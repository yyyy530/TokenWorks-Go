import 'dart:async';

import 'package:flutter/material.dart';

import 'desktop_host.dart';
import 'host_manager.dart';
import 'host_registry.dart';
import 'remote_host.dart';
import 'remote_page.dart';
import 'ssh_host_page.dart';

/// Saved-host directory and switcher. HTTPS hosts can be added here; SSH and
/// DSH Remote creation use their dedicated forms.
final class HostsPage extends StatefulWidget {
  const HostsPage({required this.manager, this.remoteAccess, super.key});

  final HostManager manager;
  final RemoteHostAccess? remoteAccess;

  @override
  State<HostsPage> createState() => _HostsPageState();
}

final class _HostsPageState extends State<HostsPage> {
  HostManager get _manager => widget.manager;

  @override
  void initState() {
    super.initState();
    _manager.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _manager.removeListener(_changed);
    super.dispose();
  }

  Future<void> _addHttps() async {
    final added = await showDialog<({Uri endpoint, String? token})>(
      context: context,
      builder: (_) => const _HttpsHostDialog(),
    );
    if (added == null || !mounted) return;
    await _manager.connectHttps(added.endpoint, launchToken: added.token);
    if (mounted && _manager.isConnected) Navigator.of(context).pop();
  }

  Future<void> _connect(HostEntry host) async {
    await _manager.connectHost(host, trust: _trustPrompt);
    if (mounted && _manager.isConnected) Navigator.of(context).pop();
  }

  void _addSsh() {
    Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => SshHostPage(manager: _manager)),
    );
  }

  void _openRemote() {
    final access = widget.remoteAccess;
    if (access == null) return;
    Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => RemotePage(manager: _manager, access: access)),
    );
  }

  Future<bool> _trustPrompt(String fingerprint) async {
    final trusted = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('信任这台主机？'),
        content: Text('首次连接这台主机。请在那台主机上核对密钥指纹，一致再信任。\n\nSHA-256：$fingerprint'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('信任并连接')),
        ],
      ),
    );
    return trusted ?? false;
  }

  Future<void> _rename(HostEntry host) async {
    if (host.transport == HostTransport.ssh) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => SshHostPage(manager: _manager, existing: host)),
      );
      return;
    }
    final controller = TextEditingController(text: host.name);
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('主机名称'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 60,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty || name == host.name) return;
    await _manager.saveHost(host.copyWith(name: name));
  }

  Future<void> _delete(HostEntry host) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('删除这台主机？'),
        content: Text('只删除手机上保存的「${host.name}」设置、密码、私钥和登录令牌，远端 DSH 和对话不受影响。'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _manager.removeHost(host.id);
  }

  @override
  Widget build(BuildContext context) {
    final manager = _manager;
    return Scaffold(
      appBar: AppBar(title: const Text('远程主机')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (manager.busy) const LinearProgressIndicator(),
                if (manager.error case final error?)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('连接上次使用的主机'),
                  subtitle: const Text('打开 App 时自动连接；关闭后可手动选择。'),
                  value: manager.registry.autoConnectLast,
                  onChanged: manager.busy ? null : (value) => unawaited(manager.setAutoConnect(value)),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: manager.busy ? null : _addHttps,
                  icon: const Icon(Icons.add),
                  label: const Text('添加 HTTPS 主机'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: manager.busy ? null : _addSsh,
                  icon: const Icon(Icons.terminal),
                  label: const Text('添加 SSH 主机'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: manager.busy || widget.remoteAccess == null ? null : _openRemote,
                  icon: const Icon(Icons.devices_other),
                  label: const Text('DSH Remote 配对'),
                ),
                const SizedBox(height: 20),
                if (manager.registry.hosts.isEmpty)
                  const Text('还没有保存的主机。')
                else
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
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(onPressed: manager.busy ? null : () => _rename(host), tooltip: '编辑', icon: const Icon(Icons.edit_outlined)),
                            IconButton(onPressed: manager.busy ? null : () => _delete(host), tooltip: '删除', icon: const Icon(Icons.delete_outline)),
                          ],
                        ),
                        selected: manager.activeHost?.id == host.id,
                        onTap: manager.busy ? null : () => _connect(host),
                      ),
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

final class _HttpsHostDialog extends StatefulWidget {
  const _HttpsHostDialog();

  @override
  State<_HttpsHostDialog> createState() => _HttpsHostDialogState();
}

final class _HttpsHostDialogState extends State<_HttpsHostDialog> {
  final _address = TextEditingController();
  final _token = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _address.dispose();
    _token.dispose();
    super.dispose();
  }

  void _submit() {
    try {
      final token = _token.text.trim();
      Navigator.of(context).pop((
        endpoint: desktopEndpoint(_address.text),
        token: token.isEmpty ? null : token,
      ));
    } on FormatException {
      setState(() => _error = '请输入有效的 HTTPS 主机地址，地址中不要包含令牌。');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('添加 HTTPS 主机'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _address,
            autofocus: true,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'HTTPS 地址',
              hintText: 'https://dsh.example.com',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _token,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: '启动令牌',
              hintText: '已有登录时可留空',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _submit(),
          ),
          if (_error case final error?)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text('令牌只用于本次登录，手机保存的是主机签发的会话 Cookie。'),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
        FilledButton(onPressed: _submit, child: const Text('保存并连接')),
      ],
    );
  }
}
