import 'dart:async';

import 'package:dsh_remote/dsh_remote.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'desktop_host.dart';
import 'host_manager.dart';
import 'host_registry.dart';
import 'remote_host.dart';

final class RemotePage extends StatefulWidget {
  const RemotePage({required this.manager, required this.access, super.key});

  final HostManager manager;
  final RemoteHostAccess access;

  @override
  State<RemotePage> createState() => _RemotePageState();
}

final class _RemotePageState extends State<RemotePage> {
  RemoteUser? _user;
  List<OAuthProvider> _providers = const [];
  List<RemoteHost> _hosts = const [];
  RemoteLogin? _login;
  bool _busy = true;
  String? _error;

  RemoteAccount get _account => widget.access.account;

  @override
  void initState() {
    super.initState();
    unawaited(_restore());
  }

  Future<void> _restore() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final user = await _account.currentUser();
      if (!mounted) return;
      _user = user;
      if (user == null) {
        await _loadProviders();
      } else {
        await _loadHosts();
      }
    } on Object catch (error) {
      if (mounted) setState(() => _error = remoteError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadProviders() async {
    final providers = await _account.loginProviders();
    if (mounted) setState(() => _providers = providers);
  }

  Future<void> _loadHosts() async {
    final hosts = await _account.listHosts();
    if (mounted) setState(() => _hosts = hosts);
  }

  Future<void> _startLogin(String? providerId) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final login = await _account.startLogin(providerId: providerId);
      if (!mounted) {
        login.cancel();
        return;
      }
      _login = login;
      if (!await launchUrl(login.loginUrl, mode: LaunchMode.externalApplication)) {
        throw const HostConnectionException('无法打开系统浏览器，请检查浏览器安装。');
      }
      final user = await login.result;
      if (!mounted) return;
      _login = null;
      _user = user;
      await _loadHosts();
    } on Object catch (error) {
      if (mounted) setState(() => _error = error is HostConnectionException ? error.message : remoteError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _passwordLogin() async {
    final email = TextEditingController();
    final password = TextEditingController();
    final credentials = await showDialog<({String email, String password})>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('邮箱密码登录'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: '邮箱', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: '密码', border: OutlineInputBorder())),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.of(context).pop((email: email.text.trim(), password: password.text)),
            child: const Text('登录'),
          ),
        ],
      ),
    );
    email.dispose();
    password.dispose();
    if (credentials == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      _user = await _account.loginWithPassword(credentials.email, credentials.password);
      await _loadHosts();
    } on Object catch (error) {
      if (mounted) setState(() => _error = remoteError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('退出 Remote 登录？'),
        content: const Text('会撤销这台手机的 Remote 设备凭据；电脑上的 DSH 和对话不受影响。'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('退出登录')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await _account.logout();
      if (widget.manager.activeHost?.transport == HostTransport.remote) {
        await widget.manager.disconnect();
      }
      _user = null;
      _hosts = const [];
      await _loadProviders();
    } on Object catch (error) {
      if (mounted) setState(() => _error = remoteError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connect(RemoteHost host) async {
    if (host.trust == RemoteHostTrust.keyChanged) {
      final reset = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('电脑的身份密钥已改变'),
          content: const Text('可能是电脑重装或 Remote 配置重置。只有确认这是预期变化时才重新信任。'),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('重新核对指纹')),
          ],
        ),
      );
      if (reset == true) await _account.forgetHost(host.id);
    }
    final existing = widget.manager.registry.hosts
        .where((entry) => entry.transport == HostTransport.remote && entry.remoteHostId == host.id)
        .firstOrNull;
    final entry = existing ??
        HostEntry(
          id: HostEntry.newId(),
          name: host.name,
          transport: HostTransport.remote,
          remoteHostId: host.id,
        );
    await widget.manager.connectHost(entry, trust: _trustPrompt);
    if (mounted && widget.manager.isConnected) Navigator.of(context).pop();
  }

  Future<bool> _trustPrompt(String fingerprint) async {
    final trusted = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('信任这台电脑？'),
        content: Text('请与电脑上 Remote 插件显示的身份指纹核对，一致再连接。\n\n$fingerprint'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('信任并连接')),
        ],
      ),
    );
    return trusted ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('DSH Remote'),
        actions: [
          if (_user != null)
            IconButton(onPressed: _busy ? null : _restore, tooltip: '刷新', icon: const Icon(Icons.refresh)),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (_busy) const LinearProgressIndicator(),
            if (_error case final error?)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            const Text('无需配置网络，连接端到端加密。请先在电脑的 DSH Remote 插件中登录同一账号。'),
            const SizedBox(height: 8),
            const Text('当前 Android 版本使用 Relay 中转；局域网 / P2P / TURN 直连尚未接入。'),
            const SizedBox(height: 20),
            if (_user == null) ...[
              Text('选择登录方式', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              for (final provider in _providers)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: FilledButton(
                    onPressed: _busy ? null : () => _startLogin(provider.id),
                    child: Text('使用 ${provider.displayName} 登录'),
                  ),
                ),
              OutlinedButton(onPressed: _busy ? null : _passwordLogin, child: const Text('使用邮箱密码登录')),
              if (_login case final login?) ...[
                const SizedBox(height: 12),
                const Text('请在系统浏览器中完成登录，手机会自动继续。'),
                TextButton(onPressed: () => login.cancel(), child: const Text('取消这次登录')),
              ],
            ] else ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.account_circle_outlined),
                title: Text(_user!.account),
                subtitle: Text(_user!.serverUrl.host),
                trailing: TextButton(onPressed: _busy ? null : _logout, child: const Text('退出登录')),
              ),
              const SizedBox(height: 12),
              Text('选择要连接的电脑', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              if (_hosts.isEmpty && !_busy) const Text('这个账号下还没有电脑。请先在电脑的 Remote 插件中登录。'),
              for (final host in _hosts)
                Card(
                  child: ListTile(
                    leading: Icon(Icons.computer, color: host.online ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.outline),
                    title: Text(host.name),
                    subtitle: Text('${host.online ? '在线' : '离线'} · ${switch (host.trust) {
                      RemoteHostTrust.pinned => '已信任',
                      RemoteHostTrust.unpinned => '首次连接需核对指纹',
                      RemoteHostTrust.keyChanged => '身份密钥已改变',
                      RemoteHostTrust.unknown => '身份未知',
                    }}${host.fingerprint == null ? '' : '\n${host.fingerprint}'}'),
                    isThreeLine: host.fingerprint != null,
                    enabled: host.online && !_busy,
                    onTap: () => _connect(host),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
