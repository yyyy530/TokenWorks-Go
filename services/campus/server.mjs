import { createHash, randomBytes, timingSafeEqual } from 'node:crypto';
import { createServer } from 'node:http';
import { pathToFileURL } from 'node:url';

const tokenFormat = /^[A-Za-z0-9_-]{43}$/;
const verifierFormat = /^[A-Za-z0-9._~-]{43,128}$/;
const staffIdFormat = /^[A-Za-z0-9]{1,64}$/;
const authorizationLifetime = 5 * 60_000;
const sessionLifetime = 8 * 60 * 60_000;
const prefix = '/v1/campus';
const identity = 'https://id.ustc.edu.cn/cas/oauth2.0';
const platform = 'https://llm.ustc.edu.cn/api/open';
const schoolModels = 'https://api.llm.ustc.edu.cn/v1/models';
const schoolChat = 'https://api.llm.ustc.edu.cn/v1/chat/completions';

function token() {
  return randomBytes(32).toString('base64url');
}

function equalToken(value, expected) {
  return typeof value === 'string' && value.length === expected.length && tokenFormat.test(value) &&
    timingSafeEqual(Buffer.from(value), Buffer.from(expected));
}

class CampusError extends Error {
  constructor(status, code) {
    super(code);
    this.status = status;
  }
}

function configFromEnvironment(env) {
  const publicUrl = new URL(env.TWG_CAMPUS_PUBLIC_URL ?? '');
  if (publicUrl.protocol !== 'https:' || !publicUrl.hostname.endsWith('.ustc.edu.cn') ||
    publicUrl.username || publicUrl.password || publicUrl.pathname !== '/' ||
    publicUrl.search || publicUrl.hash) {
    throw new Error('TWG_CAMPUS_PUBLIC_URL must be the approved HTTPS campus origin');
  }
  const clientId = env.USTC_OAUTH_CLIENT_ID;
  const clientSecret = env.USTC_OAUTH_CLIENT_SECRET;
  if (!clientId || !clientSecret) throw new Error('USTC OAuth registration is required');
  const modelClientId = env.LLM_APP_CLIENT_ID;
  const modelClientSecret = env.LLM_APP_CLIENT_SECRET;
  if (Boolean(modelClientId) !== Boolean(modelClientSecret)) {
    throw new Error('Set both model platform application credentials');
  }
  return {
    origin: publicUrl.origin,
    clientId,
    clientSecret,
    modelClientId,
    modelClientSecret,
  };
}

function json(response, status, body) {
  response.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Cache-Control': 'no-store',
  });
  response.end(JSON.stringify(body));
}

function browserMessage(response, status, message, headers = {}, returnUrl) {
  response.writeHead(status, {
    'Content-Type': 'text/html; charset=utf-8',
    'Cache-Control': 'no-store',
    'Content-Security-Policy': "default-src 'none'; frame-ancestors 'none'",
    'Referrer-Policy': 'no-referrer',
    ...headers,
  });
  const link = returnUrl ? `<p><a href="${returnUrl}">返回 TokenWorks-Go</a></p>` : '';
  response.end(`<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>TokenWorks-Go</title><main><h1>TokenWorks-Go</h1><p>${message}</p>${link}</main></html>`);
}

async function readJson(body, maxBytes, invalid) {
  try {
    const chunks = [];
    let size = 0;
    for await (const chunk of body) {
      size += chunk.length;
      if (size > maxBytes) throw invalid;
      chunks.push(chunk);
    }
    const data = JSON.parse(Buffer.concat(chunks).toString('utf8'));
    if (!data || typeof data !== 'object' || Array.isArray(data)) throw invalid;
    return data;
  } catch {
    throw invalid;
  }
}

function oneParam(url, name) {
  const values = url.searchParams.getAll(name);
  return values.length === 1 ? values[0] : null;
}

function cookieValue(request, name) {
  const cookies = (request.headers.cookie ?? '').split(';');
  return cookies.map((cookie) => cookie.trim())
    .find((cookie) => cookie.startsWith(`${name}=`))?.slice(name.length + 1);
}

function cookieName(state) {
  return `__Host-twg-${state}`;
}

function browserCookie(state, value, age) {
  return `${cookieName(state)}=${value}; Max-Age=${age}; Path=/; Secure; HttpOnly; SameSite=Lax`;
}

function bearer(request) {
  const auth = request.headers.authorization;
  return typeof auth === 'string' && auth.startsWith('Bearer ') ? auth.slice(7) : '';
}

function form(fields) {
  return { method: 'POST', body: new URLSearchParams(fields) };
}

export function createCampusServer(config, { fetcher = fetch, now = Date.now } = {}) {
  const transactions = new Map();
  const sessions = new Map();
  const callback = `${config.origin}${prefix}/callback`;

  async function upstream(url, options, rejected = 'upstream-unavailable', timeout = 10_000) {
    let response;
    try {
      response = await fetcher(url, {
        ...options,
        redirect: 'error',
        signal: AbortSignal.timeout(timeout),
      });
    } catch {
      throw new CampusError(502, 'upstream-unavailable');
    }
    if (!response.ok || response.body == null) {
      await response.body?.cancel().catch(() => {});
      throw new CampusError(502, rejected);
    }
    return readJson(response.body, 2 * 1024 * 1024, new CampusError(502, 'invalid-upstream-data'));
  }

  async function verifyIdentity(code) {
    const grant = await upstream(`${identity}/accessToken`, form({
      grant_type: 'authorization_code',
      client_id: config.clientId,
      client_secret: config.clientSecret,
      redirect_uri: callback,
      code,
    }), 'identity-rejected');
    if (typeof grant.access_token !== 'string' || !grant.access_token ||
      !Number.isFinite(grant.expires_in) || grant.expires_in <= 0) {
      throw new CampusError(502, 'invalid-identity-grant');
    }
    const expiry = now() + Math.min(grant.expires_in * 1000, sessionLifetime);
    const profile = await upstream(`${identity}/profile`, form({ access_token: grant.access_token }));
    if (profile.active !== true || profile.client_id !== config.clientId ||
      typeof profile.id !== 'string' || !staffIdFormat.test(profile.id)) {
      throw new CampusError(403, 'identity-not-authorized');
    }
    const name = profile.attributes?.name;
    return {
      staffId: profile.id,
      displayName: typeof name === 'string' && name.trim() ? name.trim().slice(0, 80) : '中国科大用户',
      expiry,
    };
  }

  async function modelProject(staffId) {
    if (!config.modelClientId) return { status: 'model-access-unconfigured' };
    const grant = await upstream(`${platform}/oauth/token`, form({
      grant_type: 'client_credentials',
      audience: 'api',
      client_id: config.modelClientId,
      client_secret: config.modelClientSecret,
    }), 'model-application-rejected');
    if (typeof grant.access_token !== 'string' || !grant.access_token) {
      throw new CampusError(502, 'invalid-model-application-grant');
    }
    const resources = await upstream(`${platform}/v1/users/${encodeURIComponent(staffId)}/resources`, {
      headers: { Authorization: `Bearer ${grant.access_token}` },
    }, 'model-user-rejected');
    if (resources.staff_id !== staffId || !Array.isArray(resources.keys)) {
      throw new CampusError(502, 'invalid-model-resources');
    }
    const usable = new Set(resources.keys
      .filter((key) => key && key.usable === true && key.secret_available === true &&
        key.is_current_version !== false && typeof key.secret_key === 'string' && key.secret_key)
      .map((key) => key.secret_key));
    if (usable.size !== 1) {
      return { status: usable.size === 0 ? 'no-usable-key' : 'multiple-usable-keys' };
    }
    const [key] = usable;
    return { status: 'ready', key };
  }

  async function modelsFor(staffId) {
    const { status, key } = await modelProject(staffId);
    if (status !== 'ready') return { status, models: [] };
    const catalog = await upstream(schoolModels, {
      headers: { Authorization: `Bearer ${key}` },
    }, 'model-gateway-rejected');
    if (!Array.isArray(catalog.data)) throw new CampusError(502, 'invalid-model-catalog');
    const models = [...new Set(catalog.data
      .map((item) => item?.id)
      .filter((id) => typeof id === 'string' && id.trim().length > 0 && id.length <= 256))];
    return { status, models };
  }

  async function currentCatalog(session) {
    if (!session.catalog || session.catalog.until <= now()) {
      session.catalog = { until: now() + 30_000, promise: modelsFor(session.staffId) };
    }
    const request = session.catalog;
    try {
      return await request.promise;
    } catch (error) {
      if (session.catalog === request) delete session.catalog;
      throw error;
    }
  }

  function prune() {
    const current = now();
    for (const [id, flow] of transactions) {
      if (flow.expiry <= current) transactions.delete(id);
    }
    for (const [id, session] of sessions) {
      if (session.expiry <= current) sessions.delete(id);
    }
  }

  async function handle(request, response) {
    prune();
    const url = new URL(request.url, config.origin);
    const path = url.pathname;
    const method = request.method;
    if (method === 'POST' && path === `${prefix}/login`) {
      const { challenge } = await readJson(request, 8192, new CampusError(400, 'invalid-login-request'));
      if (typeof challenge !== 'string' || !tokenFormat.test(challenge)) {
        throw new CampusError(400, 'invalid-login-request');
      }
      if (transactions.size >= 256 || sessions.size >= 2048) {
        throw new CampusError(503, 'campus-busy');
      }
      const id = token();
      const flow = {
        id,
        challenge,
        ticket: token(),
        state: token(),
        browser: token(),
        expiry: now() + authorizationLifetime,
        status: 'created',
      };
      transactions.set(id, flow);
      json(response, 201, {
        id,
        authorize_url: `${config.origin}${prefix}/authorize?ticket=${flow.ticket}`,
        expires_in: authorizationLifetime / 1000,
      });
      return;
    }

    if (method === 'GET' && path === `${prefix}/authorize`) {
      const ticket = oneParam(url, 'ticket');
      const flow = [...transactions.values()].find((item) => item.ticket === ticket && item.status === 'created');
      if (!flow) {
        browserMessage(response, 400, '登录请求已失效。请返回 App 重新开始。');
        return;
      }
      flow.status = 'waiting';
      const authorize = new URL(`${identity}/authorize`);
      authorize.search = new URLSearchParams({
        response_type: 'code',
        client_id: config.clientId,
        redirect_uri: callback,
        state: flow.state,
      });
      response.writeHead(302, {
        Location: authorize.href,
        'Set-Cookie': browserCookie(flow.state, flow.browser, 300),
        'Cache-Control': 'no-store',
        'Referrer-Policy': 'no-referrer',
      }).end();
      return;
    }

    if (method === 'GET' && path === `${prefix}/callback`) {
      const state = oneParam(url, 'state');
      const flow = [...transactions.values()].find((item) => item.state === state && item.status === 'waiting');
      if (!flow || !equalToken(cookieValue(request, cookieName(state)), flow.browser)) {
        browserMessage(response, 400, '无法核对这次登录。请返回 App 重新开始。');
        return;
      }
      flow.status = 'verifying';
      const clearCookie = { 'Set-Cookie': browserCookie(flow.state, '', 0) };
      try {
        const code = oneParam(url, 'code');
        if (!code || code.length > 1024 || url.searchParams.has('error')) {
          throw new CampusError(400, 'identity-denied');
        }
        const verified = await verifyIdentity(code);
        if (flow.expiry <= now() || verified.expiry <= now() || sessions.size >= 2048) {
          throw new CampusError(400, 'identity-expired');
        }
        const session = token();
        sessions.set(session, verified);
        flow.session = session;
        flow.returnCode = token();
        flow.status = 'complete';
        const returnUrl = `io.github.yyyy530.tokenworks-go://auth/campus?id=${flow.id}&amp;code=${flow.returnCode}`;
        browserMessage(response, 200, '统一身份认证完成。', clearCookie, returnUrl);
      } catch {
        flow.status = 'failed';
        browserMessage(response, 400, '统一身份认证未完成，请返回 TokenWorks-Go 重试。', clearCookie);
      }
      return;
    }

    if (method === 'POST' && path === `${prefix}/complete`) {
      const { id, verifier, callback_code: callbackCode } =
        await readJson(request, 8192, new CampusError(400, 'invalid-login-request'));
      const flow = transactions.get(id);
      if (!flow || typeof verifier !== 'string' || !verifierFormat.test(verifier) ||
        !equalToken(createHash('sha256').update(verifier).digest('base64url'), flow.challenge)) {
        throw new CampusError(401, 'login-expired');
      }
      if (flow.status === 'failed') throw new CampusError(403, 'login-failed');
      if (flow.status !== 'complete') {
        json(response, 202, { status: 'pending' });
        return;
      }
      if (!equalToken(callbackCode, flow.returnCode)) {
        throw new CampusError(401, 'callback-required');
      }
      const session = sessions.get(flow.session);
      if (!session) throw new CampusError(401, 'login-expired');
      json(response, 200, {
        session_token: flow.session,
        display_name: session.displayName,
        expires_at: new Date(session.expiry).toISOString(),
      });
      return;
    }

    if (method === 'POST' && path === `${prefix}/logout`) {
      sessions.delete(bearer(request));
      response.writeHead(204, { 'Cache-Control': 'no-store' }).end();
      return;
    }

    if (method === 'GET' && path === `${prefix}/models`) {
      const id = bearer(request);
      const session = sessions.get(id);
      if (!session) throw new CampusError(401, 'session-expired');
      const result = await currentCatalog(session);
      if (!sessions.has(id) || session.expiry <= now()) throw new CampusError(401, 'session-expired');
      json(response, 200, result);
      return;
    }

    if (method === 'POST' && path === `${prefix}/chat`) {
      const id = bearer(request);
      const session = sessions.get(id);
      if (!session) throw new CampusError(401, 'session-expired');
      const { model, prompt } = await readJson(request, 32 * 1024, new CampusError(400, 'invalid-prompt'));
      if (typeof model !== 'string' || typeof prompt !== 'string' ||
        !prompt.trim() || prompt.length > 4000) {
        throw new CampusError(400, 'invalid-prompt');
      }
      if (session.generating) throw new CampusError(409, 'request-in-progress');
      session.generating = true;
      try {
        const catalog = await currentCatalog(session);
        if (!catalog.models.includes(model)) throw new CampusError(403, 'model-unavailable');
        const { status, key } = await modelProject(session.staffId);
        if (status !== 'ready') throw new CampusError(403, 'model-unavailable');
        if (!sessions.has(id) || session.expiry <= now()) throw new CampusError(401, 'session-expired');
        const completion = await upstream(schoolChat, {
          method: 'POST',
          headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
          body: JSON.stringify({ model, messages: [{ role: 'user', content: prompt }], stream: false }),
        }, 'model-request-rejected', 70_000);
        const content = completion.choices?.[0]?.message?.content;
        if (typeof content !== 'string' || !content.trim() || Buffer.byteLength(content) > 180_000) {
          throw new CampusError(502, 'invalid-model-result');
        }
        if (!sessions.has(id) || session.expiry <= now()) throw new CampusError(401, 'session-expired');
        json(response, 200, { content });
      } finally {
        session.generating = false;
      }
      return;
    }

    json(response, 404, { error: 'not-found' });
  }

  return createServer((request, response) => {
    handle(request, response).catch((error) => {
      if (response.headersSent) {
        response.end();
      } else if (error instanceof CampusError) {
        json(response, error.status, { error: error.message });
      } else {
        json(response, 500, { error: 'internal-error' });
      }
    });
  });
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const config = configFromEnvironment(process.env);
  const port = Number(process.env.TWG_CAMPUS_PORT ?? 8788);
  if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error('Invalid TWG_CAMPUS_PORT');
  createCampusServer(config).listen(port, '127.0.0.1', () => console.log(`Campus service listening on loopback port ${port}`));
}
