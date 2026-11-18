import 'dart:async';

import 'package:flutter/material.dart';

import 'campus_client.dart';

final class CampusPage extends StatefulWidget {
  const CampusPage({
    required this.client,
    this.platform = const CampusPlatform(),
    this.probe = checkCampusGateway,
    super.key,
  });

  final CampusClient? client;
  final CampusPlatform platform;
  final Future<CampusReachability> Function() probe;

  @override
  State<CampusPage> createState() => _CampusPageState();
}

final class _CampusPageState extends State<CampusPage>
    with WidgetsBindingObserver {
  CampusSession? _session;
  CampusLogin? _login;
  String? _returnCode;
  CampusCatalog? _catalog;
  CampusReachability? _reachability;
  Timer? _poll;
  String? _authMessage;
  String? _networkMessage;
  bool _busy = false;
  bool _probing = false;
  bool _probeOnReturn = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.client != null) unawaited(_restore());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (_probeOnReturn) {
      _probeOnReturn = false;
      unawaited(_probe());
    }
    if (_login != null) unawaited(_completeLogin());
  }

  Future<void> _run(Future<void> Function() operation) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _authMessage = null;
    });
    try {
      await operation();
    } on Exception {
      if (mounted) setState(() => _authMessage = '校园接入服务暂不可用，请稍后重试。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() => _run(() async {
    final saved = await widget.platform.read(widget.client!.origin);
    if (!mounted || saved == null) return;
    if (!saved.expiresAt.isAfter(DateTime.now())) {
      await widget.platform.clear();
      return;
    }
    setState(() => _session = saved);
    await _loadCatalog();
  });

  Future<void> _startLogin() => _run(() async {
    final login = await widget.client!.login();
    if (!mounted) return;
    try {
      await widget.platform.openBrowser(login.authorizeUrl);
    } on Exception {
      if (mounted) setState(() => _authMessage = '无法打开系统浏览器。');
      return;
    }
    if (!mounted) return;
    setState(() => _login = login);
    _poll = Timer.periodic(const Duration(seconds: 2), (_) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        unawaited(_completeLogin());
      }
    });
  });

  void _stopLogin() {
    _poll?.cancel();
    _poll = null;
    _login = null;
    _returnCode = null;
  }

  Future<void> _completeLogin() async {
    final login = _login;
    if (login == null || _busy) return;
    if (!login.expiresAt.isAfter(DateTime.now())) {
      setState(() {
        _stopLogin();
        _authMessage = '登录已超时，请重新打开学校登录页。';
      });
      return;
    }
    if (_returnCode == null) {
      try {
        final returned = await widget.platform.takeReturnCode(login.id);
        if (!mounted || _login != login) return;
        _returnCode ??= returned;
      } on Exception {
        if (mounted) setState(() => _authMessage = '无法读取浏览器返回的登录结果。');
        return;
      }
    }
    final code = _returnCode;
    if (code == null) return;
    await _run(() async {
      final CampusSession? session;
      try {
        session = await widget.client!.complete(login, code);
      } on CampusException catch (error) {
        if (error.status != 401 && error.status != 403) rethrow;
        if (mounted) {
          setState(() {
            _stopLogin();
            _authMessage = '这次统一身份登录未完成，请重新登录。';
          });
        }
        return;
      }
      if (!mounted || session == null) return;
      setState(() {
        _stopLogin();
        _session = session;
      });
      try {
        await widget.platform.save(widget.client!.origin, session);
      } on Exception {
        if (mounted) setState(() => _authMessage = '已登录，本次会话未能写入手机安全存储。');
      }
      if (mounted) await _loadCatalog();
    });
  }

  Future<void> _loadCatalog() async {
    final session = _session!;
    try {
      final catalog = await widget.client!.models(session);
      if (mounted) setState(() => _catalog = catalog);
    } on CampusException catch (error) {
      if (!mounted) return;
      if (error.status == 401) {
        setState(() {
          _session = null;
          _catalog = null;
          _authMessage = '校园登录已过期，请重新登录。';
        });
        await widget.platform.clear();
      } else {
        setState(() => _authMessage = '学校模型暂时无法同步，请稍后刷新。');
      }
    }
  }

  Future<void> _logout() => _run(() async {
    final session = _session!;
    await widget.platform.clear();
    if (mounted) {
      setState(() {
        _session = null;
        _catalog = null;
      });
    }
    try {
      await widget.client!.logout(session);
    } on Exception {
      if (mounted) setState(() => _authMessage = '已在本机退出，服务器会话到期后失效。');
    }
  });

  Future<void> _openNetworkSettings(Future<void> Function() open) async {
    _probeOnReturn = true;
    setState(() => _networkMessage = null);
    try {
      await open();
    } on Exception {
      _probeOnReturn = false;
      if (mounted) setState(() => _networkMessage = '无法打开，请从手机设置或浏览器操作。');
    }
  }

  Future<void> _probe() async {
    if (_probing) return;
    setState(() {
      _probing = true;
      _networkMessage = null;
    });
    try {
      final status = await widget.probe();
      if (mounted) setState(() => _reachability = status);
    } finally {
      if (mounted) setState(() => _probing = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('校园接入')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('统一身份与学校模型', style: Theme.of(context).textTheme.titleLarge),
          if (_busy) const LinearProgressIndicator(),
          const SizedBox(height: 8),
          if (widget.client == null)
            const Text('此安装包尚未配置学校批准的校园接入服务。')
          else if (_session case final session?) ...[
            Text(session.displayName),
            const SizedBox(height: 8),
            if (_catalog case final catalog?)
              _ModelCatalog(
                catalog,
                onSelect: (model) => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => _SchoolModelPage(
                      model: model,
                      ask: (prompt) =>
                          widget.client!.ask(session, model, prompt),
                    ),
                  ),
                ),
              ),
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: _busy ? null : () => _run(_loadCatalog),
                  child: const Text('刷新学校模型'),
                ),
                TextButton(
                  onPressed: _busy ? null : _logout,
                  child: const Text('退出登录'),
                ),
              ],
            ),
          ] else if (_login != null) ...[
            const Text('请在系统浏览器完成中国科大统一身份认证，再点「返回 TokenWorks-Go」。'),
            Wrap(
              children: [
                TextButton(
                  onPressed: _busy ? null : _completeLogin,
                  child: const Text('检查登录结果'),
                ),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                          _stopLogin();
                          _authMessage = null;
                        }),
                  child: const Text('取消登录'),
                ),
              ],
            ),
          ] else
            FilledButton(
              onPressed: _busy ? null : _startLogin,
              child: const Text('通过中国科大统一身份登录'),
            ),
          if (_authMessage case final message?) Text(message),
          const SizedBox(height: 24),
          Text('校园网与 iWAN', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text('校外请使用学校发布的 iWAN 客户端，客户域为 iwan.ustc。'),
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed: () => _openNetworkSettings(() async {
                  if (!await widget.platform.openVerifiedIwan()) {
                    await widget.platform.openBrowser(iwanGuide);
                  }
                }),
                child: const Text('打开 iWAN'),
              ),
              TextButton(
                onPressed: () => _openNetworkSettings(
                  () => widget.platform.openBrowser(iwanGuide),
                ),
                child: const Text('iWAN 安装与连接说明'),
              ),
              TextButton(
                onPressed: () =>
                    _openNetworkSettings(widget.platform.openVpnSettings),
                child: const Text('打开系统 VPN 设置'),
              ),
              OutlinedButton(
                onPressed: _probing ? null : _probe,
                child: const Text('检查学校模型网关'),
              ),
            ],
          ),
          if (_probing) const LinearProgressIndicator(),
          if (_networkMessage case final message?) Text(message),
          if (_reachability case final status?)
            Text(switch (status) {
              CampusReachability.reachable => '手机可访问学校模型网关。模型权限由账户授权决定。',
              CampusReachability.refused => '学校模型网关拒绝了这次检测。校外请检查 iWAN 连接。',
              CampusReachability.unavailable => '手机暂未连接到学校模型网关。',
            }),
        ],
      ),
    ),
  );
}

final class _ModelCatalog extends StatelessWidget {
  const _ModelCatalog(this.catalog, {required this.onSelect});
  final CampusCatalog catalog;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    if (catalog.models.isNotEmpty) {
      return ExpansionTile(
        title: Text('已授权模型（${catalog.models.length}）'),
        tilePadding: EdgeInsets.zero,
        children: [
          for (final model in catalog.models)
            ListTile(
              dense: true,
              title: Text(model),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => onSelect(model),
            ),
        ],
      );
    }
    return Text(switch (catalog.status) {
      'model-access-unconfigured' => '校园服务尚未开通模型平台应用授权。',
      'no-usable-key' => '模型平台尚未提供可用的账号授权。',
      'multiple-usable-keys' => '该账号有多个可用项目凭据，需要校方服务指定一个项目。',
      _ => '学校模型目录暂无可用条目。',
    });
  }
}

final class _SchoolModelPage extends StatefulWidget {
  const _SchoolModelPage({required this.model, required this.ask});

  final String model;
  final Future<String> Function(String) ask;

  @override
  State<_SchoolModelPage> createState() => _SchoolModelPageState();
}

final class _SchoolModelPageState extends State<_SchoolModelPage> {
  final _prompt = TextEditingController();
  String? _answer;
  String? _error;
  bool _waiting = false;

  @override
  void dispose() {
    _prompt.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final question = _prompt.text.trim();
    if (_waiting || question.isEmpty) return;
    setState(() {
      _waiting = true;
      _answer = null;
      _error = null;
    });
    try {
      final answer = await widget.ask(question);
      if (mounted) setState(() => _answer = answer);
    } on CampusException catch (error) {
      if (mounted) {
        setState(() {
          _error = switch (error.status) {
            401 => '登录已过期，请返回校园接入重新登录。',
            403 => '该模型当前不可用，请返回刷新学校模型。',
            409 => '上一条模型请求仍在处理。',
            _ => '学校模型暂未返回结果。',
          };
        });
      }
    } on Exception {
      if (mounted) setState(() => _error = '暂时无法联系校园接入服务。');
    } finally {
      if (mounted) setState(() => _waiting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.model)),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(
            controller: _prompt,
            readOnly: _waiting,
            decoration: const InputDecoration(
              labelText: '向学校模型提问',
              helperText: '每次提交当前问题',
            ),
            minLines: 2,
            maxLines: 6,
            maxLength: 4000,
          ),
          FilledButton(
            onPressed: _waiting ? null : _send,
            child: const Text('发送'),
          ),
          if (_waiting) const LinearProgressIndicator(),
          if (_error case final error?) Text(error),
          if (_answer case final answer?)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: SelectableText(answer),
            ),
        ],
      ),
    ),
  );
}
