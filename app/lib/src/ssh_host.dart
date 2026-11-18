import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';

import 'desktop_host.dart';
import 'host_manager.dart';
import 'host_registry.dart';

/// SSH secrets kept in the host's encrypted vault document.
final class SshSecrets {
  const SshSecrets({
    this.password,
    this.privateKey,
    this.passphrase,
    this.launchToken,
    this.managedPort,
    this.managedToken,
  });

  final String? password;
  final String? privateKey;
  final String? passphrase;
  final String? launchToken;
  final int? managedPort;
  final String? managedToken;

  factory SshSecrets.fromJson(Map<String, Object?> json) => SshSecrets(
    password: json['password'] as String?,
    privateKey: json['privateKey'] as String?,
    passphrase: json['passphrase'] as String?,
    launchToken: json['launchToken'] as String?,
    managedPort: json['managedPort'] as int?,
    managedToken: json['managedToken'] as String?,
  );

  Map<String, Object?> toJson() => {
    'password': ?password,
    'privateKey': ?privateKey,
    'passphrase': ?passphrase,
    'launchToken': ?launchToken,
    'managedPort': ?managedPort,
    'managedToken': ?managedToken,
  };

  void validateFor(SshHostSettings settings) {
    if (settings.usePrivateKey) {
      if (privateKey == null || privateKey!.trim().isEmpty) {
        throw const HostConnectionException('请导入 SSH 私钥。');
      }
    } else if (password == null || password!.isEmpty) {
      throw const HostConnectionException('请输入 SSH 密码。');
    }
    if (!settings.managed && !_validToken(launchToken)) {
      throw const HostConnectionException('请输入只连接实例的 DSH 登录令牌。');
    }
  }
}

bool _validToken(String? value) =>
    value != null && RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(value);

final class SshLaunchLink {
  const SshLaunchLink({required this.port, required this.token});

  final int port;
  final String token;
}

/// Finds the loopback launch URL printed by `dsh web`. Other console output is
/// ignored; malformed URLs and non-loopback authorities are not accepted.
SshLaunchLink? parseSshLaunchLink(String output) {
  for (final match in RegExp(r'https?://[^\s]+').allMatches(output)) {
    final raw = match.group(0)!.replaceAll(RegExp(r'''["'<>\)\],;]+$'''), '');
    final uri = Uri.tryParse(raw);
    if (uri == null) continue;
    final loopback = uri.host == '127.0.0.1' || uri.host == 'localhost' || uri.host == '::1';
    final token = uri.queryParameters['token'];
    if (loopback && uri.port > 0 && _validToken(token)) {
      return SshLaunchLink(port: uri.port, token: token!);
    }
  }
  return null;
}

/// A loopback HTTP listener that opens one SSH direct-tcpip channel per
/// connection, so the normal DSH HTTP/WebSocket client works unchanged.
final class SshTunnel {
  SshTunnel._(this.ssh, this.remotePort, this._server) {
    _server.listen(_accept);
  }

  final SSHClient ssh;
  final int remotePort;
  final ServerSocket _server;
  final _sockets = <Socket>{};
  bool _closed = false;

  static Future<SshTunnel> open(SSHClient ssh, int remotePort) async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    return SshTunnel._(ssh, remotePort, server);
  }

  Uri get endpoint => Uri.parse('http://127.0.0.1:${_server.port}');

  void _accept(Socket socket) {
    _sockets.add(socket);
    unawaited(_forward(socket));
  }

  Future<void> _forward(Socket socket) async {
    try {
      final channel = await ssh.forwardLocal(
        '127.0.0.1',
        remotePort,
        localHost: socket.remoteAddress.address,
        localPort: socket.remotePort,
      );
      socket.listen(
        channel.sink.add,
        onDone: () => unawaited(channel.sink.close()),
        onError: (_) => channel.destroy(),
        cancelOnError: true,
      );
      channel.stream.listen(
        socket.add,
        onDone: () => unawaited(socket.close()),
        onError: (_) => socket.destroy(),
        cancelOnError: true,
      );
      unawaited(channel.done.whenComplete(() => _sockets.remove(socket)));
    } on Object {
      socket.destroy();
      _sockets.remove(socket);
    }
  }

  /// Stops the local listener without closing the SSH session (used before a
  /// managed relaunch after a stale saved instance failed).
  Future<void> closeTunnel() async {
    if (_closed) return;
    _closed = true;
    await _server.close();
    for (final socket in _sockets) {
      socket.destroy();
    }
    _sockets.clear();
  }

  Future<void> close() async {
    await closeTunnel();
    await ssh.close();
  }
}

Future<HostConnection> connectSshHost(
  HostEntry host,
  Map<String, Object?> secret, {
  required Future<bool> Function(String fingerprint) trust,
}) async {
  final settings = host.ssh!;
  settings.validate();
  final credentials = SshSecrets.fromJson(secret);
  credentials.validateFor(settings);
  final socket = await SSHSocket.connect(
    settings.host,
    settings.port,
    timeout: const Duration(seconds: 15),
  );
  var trustedFingerprint = settings.trustedKeyFingerprint;
  HostConnectionException? trustError;
  final List<SSHKeyPair>? identities;
  if (settings.usePrivateKey) {
    try {
      identities = SSHKeyPair.fromPem(credentials.privateKey!, credentials.passphrase);
    } on Object {
      await socket.close();
      throw const HostConnectionException('SSH 私钥无法解析，或私钥密码不正确。');
    }
  } else {
    identities = null;
  }
  final ssh = SSHClient(
    socket,
    username: settings.username,
    identities: identities,
    onPasswordRequest: settings.usePrivateKey ? null : () => credentials.password,
    handshakeTimeout: const Duration(seconds: 15),
    authTimeout: const Duration(seconds: 15),
    onVerifyHostKey: (type, fingerprintBytes) async {
      final fingerprint = utf8.decode(fingerprintBytes);
      final saved = settings.trustedKeyFingerprint;
      if (saved == fingerprint) return true;
      if (saved != null) {
        trustError = const HostConnectionException(
          '主机密钥与已保存的指纹不一致，可能是主机重装或中间人攻击。请核对后编辑主机清除旧指纹。',
        );
        return false;
      }
      if (!await trust(fingerprint)) {
        trustError = const HostConnectionException('未信任这台主机，已取消连接。');
        return false;
      }
      trustedFingerprint = fingerprint;
      return true;
    },
  );

  HostEntry updatedHost() {
    final fingerprint = trustedFingerprint;
    if (fingerprint == null || fingerprint == settings.trustedKeyFingerprint) return host;
    return host.copyWith(ssh: settings.copyWith(trustedKeyFingerprint: fingerprint));
  }

  try {
    final managedPort = credentials.managedPort;
    final managedToken = credentials.managedToken;
    if (settings.managed && managedPort != null && _validToken(managedToken)) {
      final tunnel = await SshTunnel.open(ssh, managedPort);
      try {
        final connection = await connectLocal(tunnel.endpoint, managedToken!);
        return HostConnection(
          connection.client,
          connection.sessions,
          dispose: tunnel.close,
          updatedHost: updatedHost(),
        );
      } on Object {
        await tunnel.closeTunnel();
      }
    }

    final remotePort = settings.managed ? null : settings.remotePort;
    final launch = settings.managed ? await _launchManaged(ssh, settings) : null;
    final tunnel = await SshTunnel.open(ssh, launch?.port ?? remotePort!);
    try {
      final token = launch?.token ?? credentials.launchToken!;
      final connection = await connectLocal(tunnel.endpoint, token);
      return HostConnection(
        connection.client,
        connection.sessions,
        dispose: tunnel.close,
        updatedHost: updatedHost(),
        updatedSecret: launch == null
            ? null
            : {
                ...credentials.toJson(),
                'managedPort': launch.port,
                'managedToken': launch.token,
              },
      );
    } on Object {
      await tunnel.closeTunnel();
      rethrow;
    }
  } on Object catch (error) {
    await ssh.close();
    if (trustError case final error?) throw error;
    if (error is HostConnectionException) rethrow;
    throw HostConnectionException('SSH 连接或远端 DSH 启动失败：$error');
  }
}

Future<SshLaunchLink> _launchManaged(SSHClient ssh, SshHostSettings settings) async {
  final stamp = DateTime.now().microsecondsSinceEpoch;
  final log = '\$HOME/.tokenworks-go/dsh-$stamp.log';
  try {
    await ssh.run(
      'mkdir -p "\$HOME/.tokenworks-go"; nohup ${settings.launchCommand} --port 0 --no-open > "$log" 2>&1 &',
      runInPty: false,
    );
    for (var attempt = 0; attempt < 60; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final output = utf8.decode(await ssh.run('cat "$log" 2>/dev/null || true'), allowMalformed: true);
      final link = parseSshLaunchLink(output);
      if (link != null) return link;
    }
  } on Object catch (error) {
    throw HostConnectionException('托管启动命令执行失败：$error');
  }
  throw const HostConnectionException(
    '远端 DSH 在 30 秒内没有输出启动链接。请检查启动命令、Node/DSH 安装和远端日志。',
  );
}
