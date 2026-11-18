import 'dart:convert';
import 'dart:math';

/// How the phone reaches a host's DSH API.
enum HostTransport { https, ssh, remote }

/// One saved host. Secrets never live here; they are stored per host in the
/// vault under [HostRegistry.secretKey].
final class HostEntry {
  const HostEntry({
    required this.id,
    required this.name,
    required this.transport,
    this.endpoint,
    this.ssh,
    this.remoteHostId,
  });

  final String id;
  final String name;
  final HostTransport transport;

  /// HTTPS hosts only.
  final Uri? endpoint;

  /// SSH hosts only: connection settings without any secret.
  final SshHostSettings? ssh;

  /// DSH Remote hosts only: the host id in the Remote account directory.
  final String? remoteHostId;

  static String newId() {
    final random = Random.secure();
    final suffix = List.generate(6, (_) => random.nextInt(36).toRadixString(36)).join();
    return '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-$suffix';
  }

  void validate() {
    if (id.trim().isEmpty || name.trim().isEmpty) {
      throw const FormatException('Host id and name are required');
    }
    switch (transport) {
      case HostTransport.https:
        if (endpoint == null || endpoint!.scheme != 'https') {
          throw const FormatException('HTTPS host needs an https endpoint');
        }
      case HostTransport.ssh:
        if (ssh == null) throw const FormatException('SSH host needs settings');
        ssh!.validate();
      case HostTransport.remote:
        if (remoteHostId == null || remoteHostId!.isEmpty) {
          throw const FormatException('Remote host needs a directory id');
        }
    }
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'transport': transport.name,
    'endpoint': ?endpoint?.toString(),
    'ssh': ?ssh?.toJson(),
    'remoteHostId': ?remoteHostId,
  };

  static HostEntry? fromJson(Object? json) {
    if (json case {
      'id': final String id,
      'name': final String name,
      'transport': final String transport,
    }) {
      final parsed = HostTransport.values.asNameMap()[transport];
      if (parsed == null) return null;
      final endpoint = json['endpoint'];
      final ssh = SshHostSettings.fromJson(json['ssh']);
      final entry = HostEntry(
        id: id,
        name: name,
        transport: parsed,
        endpoint: endpoint is String ? Uri.tryParse(endpoint) : null,
        ssh: ssh,
        remoteHostId: json['remoteHostId'] is String ? json['remoteHostId'] as String : null,
      );
      try {
        entry.validate();
        return entry;
      } on FormatException {
        return null;
      }
    }
    return null;
  }

  HostEntry copyWith({String? name, SshHostSettings? ssh, Uri? endpoint}) => HostEntry(
    id: id,
    name: name ?? this.name,
    transport: transport,
    endpoint: endpoint ?? this.endpoint,
    ssh: ssh ?? this.ssh,
    remoteHostId: remoteHostId,
  );
}

/// SSH connection settings without secrets (password / key / token live in the
/// vault). Mirrors the upstream "添加 SSH 主机" form.
final class SshHostSettings {
  const SshHostSettings({
    required this.host,
    this.port = 22,
    required this.username,
    this.usePrivateKey = false,
    this.managed = true,
    this.launchCommand = 'dsh web',
    this.remotePort,
    this.workdir,
    this.compression = false,
    this.trustedKeyFingerprint,
  });

  final String host;
  final int port;
  final String username;

  /// Private-key login instead of password.
  final bool usePrivateKey;

  /// Managed launch ("托管启动") vs connect-only ("只连接").
  final bool managed;
  final String launchCommand;

  /// Connect-only: the remote DSH port on 127.0.0.1.
  final int? remotePort;

  /// Default working directory for new conversations.
  final String? workdir;
  final bool compression;

  /// SHA-256 host key fingerprint (base64) the user trusted; null until first
  /// trust decision.
  final String? trustedKeyFingerprint;

  void validate() {
    if (host.trim().isEmpty || username.trim().isEmpty) {
      throw const FormatException('SSH host and username are required');
    }
    if (port < 1 || port > 65535) {
      throw const FormatException('SSH port must be 1-65535');
    }
    if (managed) {
      if (launchCommand.trim().isEmpty) {
        throw const FormatException('Managed launch needs a start command');
      }
    } else {
      final port = remotePort;
      if (port == null || port < 1 || port > 65535) {
        throw const FormatException('Connect-only needs the remote DSH port');
      }
    }
  }

  Map<String, Object?> toJson() => {
    'host': host,
    'port': port,
    'username': username,
    'usePrivateKey': usePrivateKey,
    'managed': managed,
    'launchCommand': launchCommand,
    'remotePort': ?remotePort,
    'workdir': ?workdir,
    'compression': compression,
    'trustedKeyFingerprint': ?trustedKeyFingerprint,
  };

  static SshHostSettings? fromJson(Object? json) {
    if (json case {'host': final String host, 'username': final String username}) {
      final settings = SshHostSettings(
        host: host,
        port: json['port'] is int ? json['port'] as int : 22,
        username: username,
        usePrivateKey: json['usePrivateKey'] == true,
        managed: json['managed'] != false,
        launchCommand: json['launchCommand'] is String ? json['launchCommand'] as String : 'dsh web',
        remotePort: json['remotePort'] is int ? json['remotePort'] as int : null,
        workdir: json['workdir'] is String ? json['workdir'] as String : null,
        compression: json['compression'] == true,
        trustedKeyFingerprint: json['trustedKeyFingerprint'] is String
            ? json['trustedKeyFingerprint'] as String
            : null,
      );
      try {
        settings.validate();
        return settings;
      } on FormatException {
        return null;
      }
    }
    return null;
  }

  SshHostSettings copyWith({
    String? host,
    int? port,
    String? username,
    bool? usePrivateKey,
    bool? managed,
    String? launchCommand,
    int? remotePort,
    String? workdir,
    bool? compression,
    String? trustedKeyFingerprint,
  }) => SshHostSettings(
    host: host ?? this.host,
    port: port ?? this.port,
    username: username ?? this.username,
    usePrivateKey: usePrivateKey ?? this.usePrivateKey,
    managed: managed ?? this.managed,
    launchCommand: launchCommand ?? this.launchCommand,
    remotePort: remotePort ?? this.remotePort,
    workdir: workdir ?? this.workdir,
    compression: compression ?? this.compression,
    trustedKeyFingerprint: trustedKeyFingerprint ?? this.trustedKeyFingerprint,
  );
}

/// The saved host list plus switcher preferences, persisted as one vault
/// document. Per-host secrets are separate vault entries.
final class HostRegistry {
  const HostRegistry({
    this.hosts = const [],
    this.lastActiveId,
    this.autoConnectLast = true,
  });

  static const registryKey = 'registry';
  static String secretKey(String hostId) => 'secret.$hostId';

  final List<HostEntry> hosts;
  final String? lastActiveId;
  final bool autoConnectLast;

  HostEntry? get lastActive {
    for (final host in hosts) {
      if (host.id == lastActiveId) return host;
    }
    return null;
  }

  HostEntry? byId(String id) {
    for (final host in hosts) {
      if (host.id == id) return host;
    }
    return null;
  }

  HostRegistry withHost(HostEntry entry) {
    final hosts = [
      for (final host in this.hosts)
        if (host.id != entry.id) host,
      entry,
    ];
    return HostRegistry(hosts: hosts, lastActiveId: lastActiveId, autoConnectLast: autoConnectLast);
  }

  HostRegistry withoutHost(String id) => HostRegistry(
    hosts: [for (final host in hosts) if (host.id != id) host],
    lastActiveId: lastActiveId == id ? null : lastActiveId,
    autoConnectLast: autoConnectLast,
  );

  HostRegistry clearLastActive() => HostRegistry(hosts: hosts, autoConnectLast: autoConnectLast);

  HostRegistry copyWith({String? lastActiveId, bool? autoConnectLast}) => HostRegistry(
    hosts: hosts,
    lastActiveId: lastActiveId ?? this.lastActiveId,
    autoConnectLast: autoConnectLast ?? this.autoConnectLast,
  );

  String encode() => jsonEncode({
    'version': 1,
    'hosts': [for (final host in hosts) host.toJson()],
    'lastActiveId': ?lastActiveId,
    'autoConnectLast': autoConnectLast,
  });

  static HostRegistry decode(String value) {
    final json = jsonDecode(value);
    if (json case {'version': 1, 'hosts': final List<Object?> hosts}) {
      return HostRegistry(
        hosts: [for (final host in hosts) ?HostEntry.fromJson(host)],
        lastActiveId: json['lastActiveId'] is String ? json['lastActiveId'] as String : null,
        autoConnectLast: json['autoConnectLast'] != false,
      );
    }
    throw const FormatException('Invalid host registry');
  }
}