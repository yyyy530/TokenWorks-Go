import 'dart:async';

import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/material.dart';
import 'package:tokenworks_core/tokenworks_core.dart' show WorkspaceMode;

import 'campus_client.dart';
import 'campus_page.dart';
import 'desktop_host.dart';
import 'host_manager.dart';
import 'host_registry.dart';
import 'host_vault.dart';
import 'hosts_page.dart';
import 'local_runtime.dart';
import 'local_runtime_page.dart';
import 'plugins_page.dart';
import 'remote_host.dart';
import 'schedules_page.dart';
import 'session_page.dart';
import 'ustc_quota.dart';
import 'ustc_quota_page.dart';

final class DesktopHome extends StatefulWidget {
  const DesktopHome({required this.manager, this.remoteAccess, super.key});

  final HostManager manager;
  final RemoteHostAccess? remoteAccess;

  @override
  State<DesktopHome> createState() => _DesktopHomeState();
}

final class _DesktopHomeState extends State<DesktopHome> {
  final _address = TextEditingController();
  final _token = TextEditingController();
  bool _remember = true;

  HostManager get _manager => widget.manager;

  @override
  void initState() {
    super.initState();
    _manager.addListener(_onManagerChanged);
    if (!_manager.loaded) unawaited(_manager.load());
  }

  void _onManagerChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _manager.removeListener(_onManagerChanged);
    _address.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final Uri endpoint;
    try {
      endpoint = desktopEndpoint(_address.text);
    } on FormatException {
      setState(() => _manager.error = '请输入有效的 HTTPS 主机地址，地址中不要包含令牌。');
      return;
    }
    final token = _token.text.trim();
    await _manager.connectHttps(
      endpoint,
      launchToken: token.isEmpty ? null : token,
      remember: _remember,
    );
    if (mounted && _manager.isConnected) _token.clear();
  }

  Future<void> _openSession(DshClient client, String id, String title) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => SessionPage(client: client, sessionId: id, title: title),
      ),
    );
    if (mounted) await _manager.refresh();
  }

  Future<void> _newSession() async {
    final client = _manager.client!;
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
        setState(() => _manager.error = _manager.isLocal
            ? '本机没有可用模型，请打开「配置本机模型」添加模型提供商。'
            : '主机没有可用模型，请先在桌面端配置。');
        return;
      }

      final modes = await availableModes;
      if (!mounted) return;
      final selection = await showDialog<({ModelInfo model, String? cwd, WorkspaceMode? mode})>(
        context: context,
        builder: (_) => _NewSessionDialog(models: models, modes: modes),
      );
      if (selection == null || !mounted) return;

      final mode = selection.mode;
      created = await client.createSession(cwd: selection.cwd, agentPreset: mode?.id);
      if (created.sessionId.isEmpty) {
        throw const DshProtocolException('Missing created session ID');
      }
      if (mode != null) {
        final applied = created.agentPreset ?? (await client.projections(created.sessionId))?.agentPreset;
        if (!mounted) return;
        if (applied != mode.id) {
          setState(() => _manager.error = '已创建空会话，但主机没有确认所选模式。');
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
        setState(() => _manager.error = created != null && created.sessionId.isNotEmpty
            ? '已创建空会话，但未能确认模式或模型。请在桌面端检查。'
            : desktopError(error));
      }
    }
    if (mounted && readyId != null) {
      await _openSession(client, readyId, sessionTitle);
    }
  }

  void _openHosts() {
    Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => HostsPage(manager: _manager, remoteAccess: widget.remoteAccess)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final manager = _manager;
    final client = manager.client;
    return Scaffold(
      appBar: AppBar(
        title: Text(manager.isLocal ? '本机工作区' : 'TokenWorks-Go'),
        actions: [
          if (!manager.isLocal) ...[
            IconButton(
              onPressed: _openHosts,
              tooltip: '主机管理',
              icon: const Icon(Icons.dns_outlined),
            ),
            IconButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => LocalRuntimePage(
                    workspace: (access) => DesktopHome(
                      manager: HostManager(vault: MemoryHostVault(), localAccess: access),
                    ),
                  ),
                ),
              ),
              tooltip: '本机运行',
              icon: const Icon(Icons.phone_android),
            ),
          ],
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
              children: const [Text('客户端与 Linux 运行时基于 ccch1mneyyy/dsh-Go。')],
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
                  child: manager.busy ? const LinearProgressIndicator() : const SizedBox.shrink(),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  sliver: SliverList.list(
                    children: [
                      if (manager.error case final error?)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Text(
                            error,
                            style: TextStyle(color: Theme.of(context).colorScheme.error),
                          ),
                        ),
                      if (client == null && manager.isLocal)
                        OutlinedButton(
                          onPressed: manager.busy
                              ? null
                              : () => _manager.connectLocalEngine(_manager.localAccess!),
                          child: const Text('重连本机引擎'),
                        ),
                      if (client == null && !manager.isLocal) ..._disconnectedBody(),
                      if (client != null) ..._connectedHeader(),
                    ],
                  ),
                ),
                if (client != null)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                    sliver: SliverList.builder(
                      itemCount: manager.sessions.length,
                      itemBuilder: (context, index) {
                        final session = manager.sessions[index];
                        final title = session.title ?? '无标题会话';
                        return ListTile(
                          leading: Icon(session.running ? Icons.sync : Icons.chat_bubble_outline),
                          title: Text(title),
                          subtitle: session.cwd == null ? null : Text(session.cwd!, maxLines: 1),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: manager.busy
                              ? null
                              : () => _openSession(client, session.sessionId, title),
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

  List<Widget> _disconnectedBody() {
    final manager = _manager;
    if (manager.registry.hosts.isEmpty) return _connectionForm();
    return [
      Text('选择主机', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 8),
      const Text('点一台主机连接，或在主机管理里添加 SSH 主机与 DSH Remote。'),
      const SizedBox(height: 12),
      for (final host in manager.registry.hosts)
        Card(
          child: ListTile(
            leading: Icon(switch (host.transport) {
              HostTransport.https => Icons.cloud_outlined,
              HostTransport.ssh => Icons.terminal,
              HostTransport.remote => Icons.devices_other,
            }),
            title: Text(host.name),
            subtitle: Text(switch (host.transport) {
              HostTransport.https => host.endpoint?.authority ?? '',
              HostTransport.ssh => '${host.ssh?.username}@${host.ssh?.host}:${host.ssh?.port}',
              HostTransport.remote => 'DSH Remote',
            }),
            trailing: const Icon(Icons.chevron_right),
            onTap: manager.busy ? null : () => _manager.connectHost(host, trust: _trustPrompt),
          ),
        ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: manager.busy ? null : _openHosts,
        icon: const Icon(Icons.add),
        label: const Text('添加或管理主机'),
      ),
    ];
  }

  Future<bool> _trustPrompt(String fingerprint) async {
    final trusted = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('信任这台主机？'),
        content: Text('首次连接这台主机。请在那台主机上核对密钥指纹，一致再信任。\n\nSHA-256：$fingerprint'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('信任并连接'),
          ),
        ],
      ),
    );
    return trusted ?? false;
  }

  List<Widget> _connectionForm() => [
    Text('连接桌面主机', style: Theme.of(context).textTheme.headlineSmall),
    const SizedBox(height: 8),
    const Text('填写自有 DSH 主机的 HTTPS 地址和启动令牌。'),
    const SizedBox(height: 20),
    TextField(
      controller: _address,
      enabled: !_manager.busy,
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
      enabled: !_manager.busy,
      obscureText: true,
      autocorrect: false,
      enableSuggestions: false,
      decoration: const InputDecoration(
        labelText: '启动令牌',
        hintText: '从桌面启动链接中获取',
        border: OutlineInputBorder(),
      ),
      onSubmitted: (_) => unawaited(_submit()),
    ),
    SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('在此手机上记住登录'),
      value: _remember,
      onChanged: _manager.busy ? null : (value) => setState(() => _remember = value),
    ),
    FilledButton(onPressed: _manager.busy ? null : _submit, child: const Text('连接')),
    const SizedBox(height: 12),
    OutlinedButton.icon(
      onPressed: _manager.busy ? null : _openHosts,
      icon: const Icon(Icons.add),
      label: const Text('添加 SSH 主机或 DSH Remote'),
    ),
  ];

  void _openQuota() {
    final client = _manager.client;
    if (client == null) return;
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => UstcQuotaPage(load: () => loadUstcQuota(client)),
      ),
    );
  }

  void _openSchedules() {
    final client = _manager.client;
    if (client == null) return;
    Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => SchedulesPage(client: client)),
    );
  }

  void _openPlugins() {
    final client = _manager.client;
    if (client == null) return;
    Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => PluginsPage(client: client)),
    );
  }

  Future<void> _openLocalSettings() async {
    final access = _manager.localAccess;
    final cookie = _manager.client?.connection.cookie;
    if (access == null || cookie == null) return;
    try {
      await const LocalRuntimeChannel().openWeb(access.endpoint, cookie);
    } on Exception {
      if (mounted) setState(() => _manager.error = '本机引擎设置暂时无法打开。');
    }
  }

  List<Widget> _connectedHeader() {
    final manager = _manager;
    final title = manager.isLocal ? '本机 DSH' : manager.activeHost?.name ?? '主机';
    return [
      Text(title, style: Theme.of(context).textTheme.headlineSmall),
      Text(switch (manager.status) {
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
            onPressed: manager.busy || manager.status != DshConnectionState.connected ? null : _newSession,
            icon: const Icon(Icons.add),
            label: const Text('新建会话'),
          ),
          OutlinedButton(onPressed: manager.busy ? null : _manager.refresh, child: const Text('刷新')),
          OutlinedButton(
            onPressed: manager.busy || manager.status != DshConnectionState.connected ? null : _openSchedules,
            child: const Text('自动化任务'),
          ),
          OutlinedButton(
            onPressed: manager.busy || manager.status != DshConnectionState.connected ? null : _openPlugins,
            child: const Text('插件'),
          ),
          if (!manager.isLocal) ...[
            OutlinedButton(
              onPressed: manager.busy || manager.status != DshConnectionState.connected ? null : _openQuota,
              child: const Text('学校额度'),
            ),
            OutlinedButton(onPressed: manager.busy ? null : _openHosts, child: const Text('切换主机')),
            TextButton(
              onPressed: manager.busy ? null : () => _manager.disconnect(clearLogin: true),
              child: const Text('断开并清除登录'),
            ),
          ] else
            OutlinedButton(
              onPressed: manager.busy || manager.status != DshConnectionState.connected ? null : _openLocalSettings,
              child: const Text('配置本机模型'),
            ),
        ],
      ),
      const SizedBox(height: 24),
      Text(manager.isLocal ? '本机会话' : '桌面会话', style: Theme.of(context).textTheme.titleLarge),
      if (manager.sessions.isEmpty) const Text('这台主机暂无会话。'),
    ];
  }
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
                  child: Text('${model.name}（${model.provider}）', overflow: TextOverflow.ellipsis),
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
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
        FilledButton(
          onPressed: _model == null
              ? null
              : () {
                  final cwd = _cwd.text.trim();
                  Navigator.of(context).pop((model: _model!, cwd: cwd.isEmpty ? null : cwd, mode: _mode));
                },
          child: const Text('创建'),
        ),
      ],
    );
  }
}
