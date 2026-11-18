import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import test from 'node:test';

import { createCampusServer } from './server.mjs';

const config = {
  origin: 'https://tokenworks-go.ustc.edu.cn',
  clientId: 'fixture-client',
  clientSecret: 'fixture-secret',
  modelClientId: 'fixture-model-client',
  modelClientSecret: 'fixture-model-secret',
};
const verifier = 'v'.repeat(64);
const challenge = createHash('sha256').update(verifier).digest('base64url');
const prefix = '/v1/campus';

async function fixture(t, { wrongAudience = false, multipleKeys = false } = {}) {
  const upstreamCalls = [];
  const server = createCampusServer(config, {
    async fetcher(url, options) {
      upstreamCalls.push(url);
      assert.equal(options.redirect, 'error');
      if (url.endsWith('/cas/oauth2.0/accessToken')) {
        assert.equal(options.body.get('code'), 'fixture-school-code');
        assert.equal(options.body.get('client_secret'), config.clientSecret);
        assert.equal(options.body.get('redirect_uri'), config.origin + prefix + '/callback');
        return Response.json({ access_token: 'fixture-school-token', expires_in: 3600 });
      }
      if (url.endsWith('/cas/oauth2.0/profile')) {
        assert.equal(options.body.get('access_token'), 'fixture-school-token');
        return Response.json({
          id: 'S123',
          active: true,
          client_id: wrongAudience ? 'different-client' : config.clientId,
          attributes: { name: '测试用户', gid: 'private-gid' },
        });
      }
      if (url.endsWith('/api/open/oauth/token')) {
        assert.equal(options.body.get('grant_type'), 'client_credentials');
        assert.equal(options.body.get('client_secret'), config.modelClientSecret);
        return Response.json({ access_token: 'fixture-management-token' });
      }
      if (url.endsWith('/api/open/v1/users/S123/resources')) {
        assert.equal(options.headers.Authorization, 'Bearer fixture-management-token');
        const keys = [
          { usable: false, secret_available: true, secret_key: 'ineligible-key' },
          { usable: true, secret_available: true, is_current_version: true, secret_key: 'fixture-model-key' },
        ];
        if (multipleKeys) keys.push({ usable: true, secret_available: true, secret_key: 'another-key' });
        return Response.json({ staff_id: 'S123', keys });
      }
      if (url === 'https://api.llm.ustc.edu.cn/v1/models') {
        assert.equal(options.headers.Authorization, 'Bearer fixture-model-key');
        return Response.json({ data: [{ id: 'model-a' }, { id: 'model-a' }, { id: 'model-b' }] });
      }
      if (url === 'https://api.llm.ustc.edu.cn/v1/chat/completions') {
        assert.equal(options.headers.Authorization, 'Bearer fixture-model-key');
        assert.deepEqual(JSON.parse(options.body), {
          model: 'model-b',
          messages: [{ role: 'user', content: '请回答' }],
          stream: false,
        });
        return Response.json({ choices: [{ message: { content: '学校模型回复' } }] });
      }
      assert.fail('Unexpected upstream request');
    },
  });
  t.after(() => new Promise((resolve) => server.close(resolve)));
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const origin = `http://127.0.0.1:${server.address().port}`;
  const request = (path, options) => fetch(origin + path, { redirect: 'manual', ...options });
  const post = (path, body) => request(path, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  return { request, post, upstreamCalls };
}

async function authorize({ request, post }) {
  const response = await post(prefix + '/login', { challenge });
  assert.equal(response.status, 201);
  const login = await response.json();
  const browser = new URL(login.authorize_url);
  assert.equal(browser.origin, config.origin);
  const redirect = await request(browser.pathname + browser.search);
  assert.equal(redirect.status, 302);
  assert.equal((await request(browser.pathname + browser.search)).status, 400);
  const authorize = new URL(redirect.headers.get('location'));
  assert.equal(authorize.origin, 'https://id.ustc.edu.cn');
  assert.equal(authorize.searchParams.get('client_id'), config.clientId);
  const state = authorize.searchParams.get('state');
  const cookie = redirect.headers.get('set-cookie');
  assert.match(cookie, /Secure; HttpOnly; SameSite=Lax/);
  const callback = prefix + '/callback?' + new URLSearchParams({ state, code: 'fixture-school-code' });
  const proof = { id: login.id, verifier };
  return { callback, cookie: cookie.split(';')[0], proof };
}

async function browserProof(request, callback, cookie, proof) {
  const result = await request(callback, { headers: { Cookie: cookie } });
  assert.equal(result.status, 200);
  const html = await result.text();
  const link = html.match(/href="(io\.github\.yyyy530\.tokenworks-go:[^"]+)"/)?.[1];
  assert.ok(link);
  const returnUrl = new URL(link.replace('&amp;', '&'));
  assert.equal(returnUrl.searchParams.get('id'), proof.id);
  return { ...proof, callback_code: returnUrl.searchParams.get('code') };
}

test('browser state and Android proof protect login and user-scoped model discovery', async (t) => {
  const system = await fixture(t);
  const { request, post, upstreamCalls } = system;
  const { callback, cookie, proof } = await authorize(system);

  assert.equal((await post(prefix + '/complete', proof)).status, 202);
  assert.equal((await request(callback)).status, 400);
  assert.equal((await post(prefix + '/complete', { ...proof, verifier: 'x'.repeat(64) })).status, 401);
  assert.equal(upstreamCalls.length, 0);

  const mobileProof = await browserProof(request, callback, cookie, proof);
  assert.equal((await request(callback, { headers: { Cookie: cookie } })).status, 400);
  assert.equal((await post(prefix + '/complete', proof)).status, 401);
  const completed = await post(prefix + '/complete', mobileProof);
  assert.equal(completed.status, 200);
  const session = await completed.json();
  assert.equal(session.display_name, '测试用户');
  assert.deepEqual(Object.keys(session).sort(), ['display_name', 'expires_at', 'session_token']);
  assert.deepEqual(await (await post(prefix + '/complete', mobileProof)).json(), session);

  const headers = { Authorization: `Bearer ${session.session_token}` };
  assert.equal((await request(prefix + '/models')).status, 401);
  const response = await request(prefix + '/models', { headers });
  assert.equal(response.status, 200);
  const catalog = await response.json();
  assert.deepEqual(catalog, { status: 'ready', models: ['model-a', 'model-b'] });
  assert.deepEqual(await (await request(prefix + '/models', { headers })).json(), catalog);
  assert.equal(upstreamCalls.length, 5);
  assert.equal((await request(prefix + '/logout', { method: 'POST', headers })).status, 204);
  assert.equal((await request(prefix + '/models', { headers })).status, 401);
});

test('profile for a different application cannot establish a mobile session', async (t) => {
  const system = await fixture(t, { wrongAudience: true });
  const { callback, cookie, proof } = await authorize(system);
  const rejected = await system.request(callback, { headers: { Cookie: cookie } });
  assert.equal(rejected.status, 400);
  assert.equal((await system.post(prefix + '/complete', proof)).status, 403);
});

test('multiple usable projects do not cause an automatic choice or Key disclosure', async (t) => {
  const system = await fixture(t, { multipleKeys: true });
  const { callback, cookie, proof } = await authorize(system);
  const mobileProof = await browserProof(system.request, callback, cookie, proof);
  const session = await (await system.post(prefix + '/complete', mobileProof)).json();
  const response = await system.request(prefix + '/models', {
    headers: { Authorization: `Bearer ${session.session_token}` },
  });
  assert.deepEqual(await response.json(), { status: 'multiple-usable-keys', models: [] });
  assert.equal(system.upstreamCalls.length, 4);
});

test('only an account-authorized model can answer a phone request', async (t) => {
  const system = await fixture(t);
  const { callback, cookie, proof } = await authorize(system);
  const mobileProof = await browserProof(system.request, callback, cookie, proof);
  const session = await (await system.post(prefix + '/complete', mobileProof)).json();
  const send = (model, sessionToken) => system.request(prefix + '/chat', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${sessionToken}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ model, prompt: '请回答' }),
  });
  assert.equal((await send('model-b', 'unauthorized')).status, 401);
  assert.equal((await send('model-unavailable', session.session_token)).status, 403);
  assert.equal(system.upstreamCalls.filter((url) => url.endsWith('/chat/completions')).length, 0);
  const response = await send('model-b', session.session_token);
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { content: '学校模型回复' });
});
