import 'dart:async';

import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/material.dart';
import 'package:tokenworks_core/tokenworks_core.dart' show WorkspaceMode;

import 'campus_client.dart';
import 'campus_page.dart';
import 'desktop_host.dart';
import 'session_page.dart';
import 'ustc_quota.dart';
import 'ustc_quota_page.dart';

final class DesktopHome extends StatefulWidget {
  const DesktopHome({required this.store, required this.connect, super.key});

  final DesktopStore store;
  final DesktopConnector connect;

  @override
  State<DesktopHome> createState() => _DesktopHomeState();
}

final class _DesktopHomeState extends State<DesktopHome> {
  final _address = TextEditingController();
  final _token = TextEditingController();
  DshClient? _client;
  DesktopCredentials? _saved;
  Uri? _endpoint;
  List<SessionSummary> _sessions = const [];
  StreamSubscription<DshConnectionState>? _statusSubscription;
  DshConnectionState _status = DshConnectionState.idle;
  String? _error;
  bool _busy = true;
  bool _remember = true;

  @override
  void initState() {
    super.initState();
    unawaited(_restore());
  }

  @override
  void dispose() {
    _address.dispose();
    _token.dispose();
    unawaited(_statusSubscription?.cancel());
    unawaited(_client?.close());
    super.dispose();
  }

  Future<void> _restore() async {
    try {
      final saved = await widget.store.read();
      if (!mounted) return;
      _saved = saved;
      if (saved != null) {
        _address.text = saved.endpoint.toString();
        await _connect(saved.endpoint, cookie: saved.cookie);
      }
    } on Exception {
      if (mounted) {
        _error = '无法读取已保存的登录信息。';
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    if (_busy) return;
    final Uri endpoint;
    try {
      endpoint = desktopEndpoint(_address.text);
    } on FormatException {
      setState(() => _error = '请输入有效的 HTTPS 主机地址，地址中不要包含令牌。');
      return;
    }
    final token = _token.text.trim();
    final saved = _saved;
    if (token.isEmpty && saved?.endpoint != endpoint) {
      setState(() => _error = '请输入桌面启动链接中的令牌。');
      return;
    }
    await _connect(
      endpoint,
      launchToken: token.isEmpty ? null : token,
      cookie: token.isEmpty ? saved?.cookie : null,
    );
  }

  Future<void> _connect(
    Uri endpoint, {
    String? launchToken,
    DshCookie? cookie,
  }) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final connection = await widget.connect(
        endpoint,
        launchToken: launchToken,
        cookie: cookie,
      );
      if (!mounted) {
        await connection.client.close();
        return;
      }
      _token.clear();
      final client = connection.client;
      _statusSubscription = client.mux.states.listen((state) {
        if (mounted && identical(_client, client)) {
          setState(() => _status = state);
        }
      });
      setState(() {
        _client = client;
        _endpoint = endpoint;
        _sessions = _visibleSessions(connection.sessions);
        _status = client.mux.state;
      });
      if (launchToken != null) {
        try {
          if (_remember) {
            final credentials = DesktopCredentials(endpoint, connection.cookie);
            await widget.store.save(credentials);
            _saved = credentials;
          } else {
            await widget.store.clear();
            _saved = null;
          }
        } on Exception {
          if (mounted) setState(() => _error = '已连接，手机上的登录存储未能更新。');
        }
      }
    } on Exception catch (error) {
      if (mounted) setState(() => _error = desktopError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.store.clear();
      _saved = null;
      unawaited(_statusSubscription?.cancel());
      _statusSubscription = null;
      await _client?.close();
      if (!mounted) return;
      setState(() {
        _client = null;
        _endpoint = null;
        _status = DshConnectionState.idle;
        _sessions = const [];
      });
    } on Exception {
      if (mounted) setState(() => _error = '未能清除手机上的登录信息，请重试。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<SessionSummary> _visibleSessions(List<SessionSummary> sessions) => [
    for (final session in sessions)
      if (!session.isSubagent && session.sessionId.isNotEmpty) session,
  ];

  Future<void> _refresh() async {
    final client = _client;
    if (_busy || client == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final sessions = await client.listSessions();
      if (mounted) setState(() => _sessions = _visibleSessions(sessions));
    } on Exception catch (error) {
      if (mounted) setState(() => _error = desktopError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openSession(DshClient client, String id, String title) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) =>
            SessionPage(client: client, sessionId: id, title: title),
      ),
    );
    if (mounted) await _refresh();
  }

  Future<void> _newSession() async {
    final client = _client!;
    setState(() {
      _busy = true;
      _error = null;
    });
    SessionCreated? created;
    String? readyId;
    var sessionTitle = '新会话';
    try {
      final availableModes = availableTokenWorksModes(client);
      final catalog = await client.listModels();
      if (!mounted) return;
      final models = {
        for (final group in catalog.groups)
          for (final model in group.models)
            if (model.id.isNotEmpty && model.provider.isNotEmpty)
              (model.provider, model.id): model,
      }.values.toList();
      if (models.isEmpty) {
        setState(() => _error = '主机没有可用模型，请先在桌面端配置。');
        return;
      }

      final modes = await availableModes;
      if (!mounted) return;
      setState(() => _busy = false);
      final selection =
          await showDialog<
            ({ModelInfo model, String? cwd, WorkspaceMode? mode})
          >(
            context: context,
            builder: (_) => _NewSessionDialog(models: models, modes: modes),
          );
      if (selection == null || !mounted) return;

      setState(() => _busy = true);
      final mode = selection.mode;
      created = await client.createSession(
        cwd: selection.cwd,
        agentPreset: mode?.id,
      );
      if (created.sessionId.isEmpty) {
        throw const DshProtocolException('Missing created session ID');
      }
      if (mode != null) {
        final applied =
            created.agentPreset ??
            (await client.projections(created.sessionId))?.agentPreset;
        if (!mounted) return;
        if (applied != mode.id) {
          setState(() => _error = '已创建空会话，但主机没有确认所选模式。');
          return;
        }
        sessionTitle = '${mode.label}会话';
      }
      final model = selection.model;
      final selected = await client.setModel(
        created.sessionId,
        provider: model.provider,
        model: model.id,
      );
      if (selected.provider != model.provider || selected.model != model.id) {
        throw const DshProtocolException('Host reported a different model');
      }
      readyId = created.sessionId;
    } on Exception catch (error) {
      if (mounted) {
        setState(() {
          _error = created != null && created.sessionId.isNotEmpty
              ? '已创建空会话，但未能确认模式或模型。请在桌面端检查。'
              : desktopError(error);
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (mounted && readyId != null) {
      await _openSession(client, readyId, sessionTitle);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('TokenWorks-Go'),
        actions: [
          IconButton(
            onPressed: () {
              final origin = configuredCampusOrigin();
              Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => CampusPage(
                    client: origin == null ? null : CampusClient(origin),
                  ),
                ),
              );
            },
            tooltip: '校园接入',
            icon: const Icon(Icons.school_outlined),
          ),
          IconButton(
            onPressed: () => showAboutDialog(
              context: context,
              applicationName: 'TokenWorks-Go',
              applicationVersion: '0.1.0',
              children: const [Text('桌面连接复用 ccch1mneyyy/dsh-Go 的 DSH 客户端。')],
            ),
            tooltip: '关于',
            icon: const Icon(Icons.info_outline),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: _busy
                      ? const LinearProgressIndicator()
                      : const SizedBox.shrink(),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  sliver: SliverList.list(
                    children: [
                      if (_error case final error?)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Text(
                            error,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      if (_client == null) ..._connectionForm(),
                      if (_client != null) ..._connectedHeader(),
                    ],
                  ),
                ),
                if (_client != null)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                    sliver: SliverList.builder(
                      itemCount: _sessions.length,
                      itemBuilder: (context, index) {
                        final client = _client!;
                        final session = _sessions[index];
                        final title = session.title ?? '无标题会话';
                        return ListTile(
                          leading: Icon(
                            session.running
                                ? Icons.sync
                                : Icons.chat_bubble_outline,
                          ),
                          title: Text(title),
                          subtitle: session.cwd == null
                              ? null
                              : Text(session.cwd!, maxLines: 1),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: _busy
                              ? null
                              : () => _openSession(
                                  client,
                                  session.sessionId,
                                  title,
                                ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _connectionForm() => [
    Text('连接桌面主机', style: Theme.of(context).textTheme.headlineSmall),
    const SizedBox(height: 8),
    const Text('填写自有 DSH 主机的 HTTPS 地址和启动令牌。'),
    const SizedBox(height: 20),
    TextField(
      controller: _address,
      enabled: !_busy,
      keyboardType: TextInputType.url,
      autocorrect: false,
      decoration: const InputDecoration(
        labelText: 'HTTPS 地址',
        hintText: 'https://dsh.example.com',
        border: OutlineInputBorder(),
      ),
    ),
    const SizedBox(height: 12),
    TextField(
      controller: _token,
      enabled: !_busy,
      obscureText: true,
      autocorrect: false,
      enableSuggestions: false,
      decoration: InputDecoration(
        labelText: '启动令牌',
        hintText: _saved == null ? '从桌面启动链接中获取' : '留空使用已保存的登录',
        border: const OutlineInputBorder(),
      ),
      onSubmitted: (_) => unawaited(_submit()),
    ),
    SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('在此手机上记住登录'),
      value: _remember,
      onChanged: _busy ? null : (value) => setState(() => _remember = value),
    ),
    FilledButton(onPressed: _busy ? null : _submit, child: const Text('连接')),
    if (_saved != null)
      TextButton(
        onPressed: _busy ? null : _disconnect,
        child: const Text('清除已保存的登录'),
      ),
  ];

  void _openQuota() {
    final client = _client;
    if (client == null) return;
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => UstcQuotaPage(load: () => loadUstcQuota(client)),
      ),
    );
  }

  List<Widget> _connectedHeader() => [
    Text(
      _endpoint!.authority,
      style: Theme.of(context).textTheme.headlineSmall,
    ),
    Text(switch (_status) {
      DshConnectionState.connected => 'DSH 已连接',
      DshConnectionState.unauthorized => '登录失效，请断开后重新连接。',
      DshConnectionState.closed => '连接已关闭',
      _ => '正在连接主机…',
    }),
    const SizedBox(height: 12),
    Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton.icon(
          onPressed: _busy || _status != DshConnectionState.connected
              ? null
              : _newSession,
          icon: const Icon(Icons.add),
          label: const Text('新建会话'),
        ),
        OutlinedButton(
          onPressed: _busy ? null : _refresh,
          child: const Text('刷新'),
        ),
        OutlinedButton(
          onPressed: _busy || _status != DshConnectionState.connected
              ? null
              : _openQuota,
          child: const Text('学校额度'),
        ),
        TextButton(
          onPressed: _busy ? null : _disconnect,
          child: const Text('断开并清除登录'),
        ),
      ],
    ),
    const SizedBox(height: 24),
    Text('桌面会话', style: Theme.of(context).textTheme.titleLarge),
    if (_sessions.isEmpty) const Text('这台主机暂无会话。'),
  ];
}

final class _NewSessionDialog extends StatefulWidget {
  const _NewSessionDialog({required this.models, required this.modes});

  final List<ModelInfo> models;
  final List<WorkspaceMode> modes;

  @override
  State<_NewSessionDialog> createState() => _NewSessionDialogState();
}

final class _NewSessionDialogState extends State<_NewSessionDialog> {
  final _cwd = TextEditingController();
  ModelInfo? _model;
  WorkspaceMode? _mode;

  @override
  void dispose() {
    _cwd.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('新建会话'),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<ModelInfo>(
            initialValue: _model,
            isExpanded: true,
            decoration: const InputDecoration(labelText: '模型'),
            items: [
              for (final model in widget.models)
                DropdownMenuItem(
                  value: model,
                  child: Text(
                    '${model.name}（${model.provider}）',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (model) => setState(() => _model = model),
          ),
          if (widget.modes.isNotEmpty) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<WorkspaceMode>(
              initialValue: _mode,
              decoration: const InputDecoration(labelText: '词元工坊模式'),
              hint: const Text('使用桌面默认模式'),
              items: [
                const DropdownMenuItem<WorkspaceMode>(child: Text('使用桌面默认模式')),
                for (final mode in widget.modes)
                  DropdownMenuItem(value: mode, child: Text('${mode.label}模式')),
              ],
              onChanged: (mode) => setState(() => _mode = mode),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _cwd,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: '桌面工作目录（可选）',
              helperText: '留空使用桌面主机的当前目录。',
              helperMaxLines: 2,
            ),
          ),
          const SizedBox(height: 12),
          const Text('会话继承桌面主机的工具权限设置。'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _model == null
              ? null
              : () {
                  final cwd = _cwd.text.trim();
                  Navigator.of(context).pop((
                    model: _model!,
                    cwd: cwd.isEmpty ? null : cwd,
                    mode: _mode,
                  ));
                },
          child: const Text('创建'),
        ),
      ],
    );
  }
}
