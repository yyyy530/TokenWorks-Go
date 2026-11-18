import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'desktop_host.dart';
import 'host_manager.dart';
import 'host_registry.dart';
import 'ssh_host.dart';

final class SshHostPage extends StatefulWidget {
  const SshHostPage({required this.manager, this.existing, super.key});

  final HostManager manager;
  final HostEntry? existing;

  @override
  State<SshHostPage> createState() => _SshHostPageState();
}

final class _SshHostPageState extends State<SshHostPage> {
  late final TextEditingController _name;
  late final TextEditingController _host;
  late final TextEditingController _port;
  late final TextEditingController _username;
  late final TextEditingController _launchCommand;
  late final TextEditingController _remotePort;
  late final TextEditingController _workdir;
  final _password = TextEditingController();
  final _privateKey = TextEditingController();
  final _passphrase = TextEditingController();
  final _launchToken = TextEditingController();

  late bool _usePrivateKey;
  late bool _managed;
  String? _trustedFingerprint;
  Map<String, Object?> _secret = const {};
  bool _secretReady = false;
  bool _busy = false;
  String? _error;
  String? _message;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _name = TextEditingController(text: existing?.name ?? '');
    _host = TextEditingController(text: existing?.ssh?.host ?? '');
    _port = TextEditingController(text: '${existing?.ssh?.port ?? 22}');
    _username = TextEditingController(text: existing?.ssh?.username ?? '');
    _launchCommand = TextEditingController(text: existing?.ssh?.launchCommand ?? 'dsh web');
    _remotePort = TextEditingController(text: existing?.ssh?.remotePort?.toString() ?? '');
    _workdir = TextEditingController(text: existing?.ssh?.workdir ?? '');
    _usePrivateKey = existing?.ssh?.usePrivateKey ?? false;
    _managed = existing?.ssh?.managed ?? true;
    _trustedFingerprint = existing?.ssh?.trustedKeyFingerprint;
    _secretReady = existing == null;
    if (existing != null) {
      unawaited(widget.manager.hostSecret(existing.id).then((value) {
        if (mounted) {
          setState(() {
            _secret = value;
            _secretReady = true;
          });
        }
      }).onError((error, stackTrace) {
        if (mounted) setState(() => _error = '无法读取已保存的 SSH 凭据。');
      }));
    }
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _host,
      _port,
      _username,
      _launchCommand,
      _remotePort,
      _workdir,
      _password,
      _privateKey,
      _passphrase,
      _launchToken,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  SshHostSettings _settings() => SshHostSettings(
    host: _host.text.trim(),
    port: int.tryParse(_port.text.trim()) ?? 0,
    username: _username.text.trim(),
    usePrivateKey: _usePrivateKey,
    managed: _managed,
    launchCommand: _launchCommand.text.trim(),
    remotePort: int.tryParse(_remotePort.text.trim()),
    workdir: _workdir.text.trim().isEmpty ? null : _workdir.text.trim(),
    compression: false,
    trustedKeyFingerprint: _trustedFingerprint,
  );

  SshSecrets _secrets() {
    final old = SshSecrets.fromJson(_secret);
    final password = _password.text;
    final privateKey = _privateKey.text;
    final passphrase = _passphrase.text;
    final launchToken = _launchToken.text.trim();
    return SshSecrets(
      password: password.isEmpty ? old.password : password,
      privateKey: privateKey.isEmpty ? old.privateKey : privateKey,
      passphrase: passphrase.isEmpty ? old.passphrase : passphrase,
      launchToken: launchToken.isEmpty ? old.launchToken : launchToken,
      managedPort: old.managedPort,
      managedToken: old.managedToken,
    );
  }

  HostEntry _entry(SshHostSettings settings) {
    final existing = widget.existing;
    final name = _name.text.trim();
    return HostEntry(
      id: existing?.id ?? HostEntry.newId(),
      name: name.isEmpty ? '${settings.username}@${settings.host}' : name,
      transport: HostTransport.ssh,
      ssh: settings,
    );
  }

  String? _validate() {
    if (!_secretReady) return '正在读取已保存的凭据，请稍候。';
    try {
      final settings = _settings();
      settings.validate();
      _secrets().validateFor(settings);
      return null;
    } on FormatException catch (error) {
      return error.message;
    } on HostConnectionException catch (error) {
      return error.message;
    }
  }

  Future<void> _importKey() async {
    final file = await FilePicker.pickFile();
    final bytes = await file?.readAsBytes();
    if (file == null || bytes == null) return;
    if (bytes.length > 1024 * 1024) {
      setState(() => _error = '私钥文件过大。');
      return;
    }
    setState(() {
      _privateKey.text = utf8.decode(bytes, allowMalformed: true);
      _usePrivateKey = true;
    });
  }

  Future<void> _test() async {
    final invalid = _validate();
    if (invalid != null) {
      setState(() => _error = invalid);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      final entry = _entry(_settings());
      final secrets = _secrets();
      final connection = await connectSshHost(entry, secrets.toJson(), trust: _trust);
      final updated = connection.updatedHost;
      final updatedSecret = connection.updatedSecret;
      await connection.close();
      if (!mounted) return;
      setState(() {
        if (updated != null) _trustedFingerprint = updated.ssh?.trustedKeyFingerprint;
        if (updatedSecret != null) _secret = updatedSecret;
        _message = '测试连接成功。托管启动的远端 DSH 会继续运行，点保存保留这台主机。';
      });
    } on Exception catch (error) {
      if (mounted) setState(() => _error = desktopError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _trust(String fingerprint) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('信任这台主机？'),
        content: Text('请在那台主机上核对 SSH 主机密钥指纹，一致再信任。\n\n$fingerprint'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('信任并连接')),
        ],
      ),
    );
    return accepted ?? false;
  }

  Future<void> _save() async {
    final invalid = _validate();
    if (invalid != null) {
      setState(() => _error = invalid);
      return;
    }
    setState(() => _busy = true);
    try {
      final settings = _settings();
      await widget.manager.saveHost(_entry(settings), secret: _secrets().toJson());
      if (mounted) Navigator.of(context).pop();
    } on Exception catch (error) {
      if (mounted) setState(() => _error = desktopError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.existing == null ? '添加 SSH 主机' : '编辑 SSH 主机')),
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
            if (_message case final message?)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(message, style: TextStyle(color: Theme.of(context).colorScheme.primary)),
              ),
            TextField(controller: _name, enabled: !_busy, decoration: const InputDecoration(labelText: '名称（可选）', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: _host, enabled: !_busy, autocorrect: false, decoration: const InputDecoration(labelText: '主机', hintText: 'server.example.com', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(flex: 2, child: TextField(controller: _username, enabled: !_busy, autocorrect: false, decoration: const InputDecoration(labelText: '用户名', border: OutlineInputBorder()))),
                const SizedBox(width: 12),
                Expanded(child: TextField(controller: _port, enabled: !_busy, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '端口', border: OutlineInputBorder()))),
              ],
            ),
            const SizedBox(height: 16),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('密码登录')),
                ButtonSegment(value: true, label: Text('私钥登录')),
              ],
              selected: {_usePrivateKey},
              onSelectionChanged: _busy ? null : (value) => setState(() => _usePrivateKey = value.single),
            ),
            const SizedBox(height: 12),
            if (!_usePrivateKey)
              TextField(
                controller: _password,
                enabled: !_busy,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: '密码',
                  helperText: widget.existing == null ? '只保存在这台手机上。' : '留空保留已保存的密码。',
                  border: const OutlineInputBorder(),
                ),
              )
            else ...[
              TextField(
                controller: _privateKey,
                enabled: !_busy,
                maxLines: 5,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: '私钥',
                  hintText: '粘贴 PEM/OpenSSH 私钥，或从文件导入',
                  helperText: widget.existing == null ? null : '留空保留已保存的私钥。',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(onPressed: _busy ? null : _importKey, icon: const Icon(Icons.upload_file), label: const Text('从文件导入')),
              const SizedBox(height: 12),
              TextField(controller: _passphrase, enabled: !_busy, obscureText: true, decoration: const InputDecoration(labelText: '私钥密码（可选）', border: OutlineInputBorder())),
            ],
            const SizedBox(height: 20),
            Text('实例管理', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('托管启动')),
                ButtonSegment(value: false, label: Text('只连接')),
              ],
              selected: {_managed},
              onSelectionChanged: _busy ? null : (value) => setState(() => _managed = value.single),
            ),
            const SizedBox(height: 8),
            Text(_managed ? '启动或复用远端 DSH；测试连接不会停止它。' : '只建立 SSH 隧道，不启动、停止或重启远端实例。'),
            const SizedBox(height: 12),
            if (_managed)
              TextField(
                controller: _launchCommand,
                enabled: !_busy,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: '启动命令',
                  helperText: '默认 dsh web；会追加 --port 0 --no-open。',
                  border: OutlineInputBorder(),
                ),
              )
            else ...[
              TextField(controller: _remotePort, enabled: !_busy, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '远端 DSH 端口', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(controller: _launchToken, enabled: !_busy, obscureText: true, autocorrect: false, decoration: InputDecoration(labelText: 'DSH 登录令牌', helperText: widget.existing == null ? null : '留空保留已保存的令牌。', border: const OutlineInputBorder())),
            ],
            const SizedBox(height: 12),
            TextField(controller: _workdir, enabled: !_busy, autocorrect: false, decoration: const InputDecoration(labelText: '工作目录（可选）', helperText: '新对话的默认目录；只连接模式请用绝对路径。', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            const Text('当前 SSH 库只支持未压缩传输（none），不提供压缩开关。'),
            if (_trustedFingerprint != null) ...[
              const SizedBox(height: 12),
              Text('已信任指纹：$_trustedFingerprint', style: Theme.of(context).textTheme.bodySmall),
              TextButton(
                onPressed: _busy ? null : () => setState(() => _trustedFingerprint = null),
                child: const Text('清除已保存指纹'),
              ),
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(child: OutlinedButton(onPressed: _busy ? null : _test, child: const Text('测试连接'))),
                const SizedBox(width: 12),
                Expanded(child: FilledButton(onPressed: _busy ? null : _save, child: const Text('保存'))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
