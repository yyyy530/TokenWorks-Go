import 'dart:async';
import 'dart:convert';

import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/foundation.dart';

import 'desktop_host.dart';
import 'host_registry.dart';
import 'host_vault.dart';
import 'local_runtime.dart';

/// A live host connection plus any transport-specific cleanup (SSH tunnel).
final class HostConnection {
  const HostConnection(
    this.client,
    this.sessions, {
    this.cookie,
    this.dispose,
    this.updatedHost,
    this.updatedSecret,
  });

  final DshClient client;
  final List<SessionSummary> sessions;
  final DshCookie? cookie;
  final Future<void> Function()? dispose;
  final HostEntry? updatedHost;
  final Map<String, Object?>? updatedSecret;

  Future<void> close() async {
    await client.close();
    await dispose?.call();
  }
}

/// SSH connector injected by the SSH feature; [secret] is the host's vault
/// document, [trust] asks the user to confirm an unknown host key fingerprint.
typedef SshHostConnector =
    Future<HostConnection> Function(
      HostEntry host,
      Map<String, Object?> secret, {
      required Future<bool> Function(String fingerprint) trust,
    });

/// DSH Remote connector injected by the Remote feature.
typedef RemoteHostConnector =
    Future<HostConnection> Function(
      HostEntry host, {
      required Future<bool> Function(String fingerprint) trust,
    });

/// Single owner of the saved hosts and the active host connection.
final class HostManager extends ChangeNotifier {
  HostManager({
    required this.vault,
    this.connect = connectDesktop,
    this.sshConnect,
    this.remoteConnect,
    this.legacyStore,
    this.localAccess,
  });

  final HostVault vault;
  final DesktopConnector connect;
  final SshHostConnector? sshConnect;
  final RemoteHostConnector? remoteConnect;
  final DesktopStore? legacyStore;

  /// When set, this manager drives the on-phone engine instead of saved hosts.
  final LocalRuntimeAccess? localAccess;

  bool get isLocal => localAccess != null;

  HostRegistry registry = const HostRegistry();
  HostEntry? activeHost;
  DshClient? client;
  List<SessionSummary> sessions = const [];
  DshConnectionState status = DshConnectionState.idle;
  bool busy = true;
  String? error;
  bool loaded = false;

  StreamSubscription<DshConnectionState>? _statusSubscription;
  HostConnection? _connection;
  int _connectGeneration = 0;

  bool get isConnected => client != null;

  Future<void> load() async {
    if (localAccess case final access?) {
      await connectLocalEngine(access);
      return;
    }
    try {
      final stored = await vault.read(HostRegistry.registryKey);
      if (stored != null) {
        registry = HostRegistry.decode(stored);
      } else {
        await _migrateLegacy();
      }
    } on Exception {
      error = '无法读取已保存的主机列表。';
    }
    loaded = true;
    busy = false;
    notifyListeners();
    final last = registry.lastActive;
    if (registry.autoConnectLast && last != null) {
      await connectHost(last);
    } else {
      notifyListeners();
    }
  }

  /// Connects the on-phone engine; not a saved host, no registry writes.
  Future<void> connectLocalEngine(LocalRuntimeAccess access) async {
    final generation = ++_connectGeneration;
    busy = true;
    error = null;
    notifyListeners();
    HostConnection? connection;
    try {
      final local = await connectLocal(access.endpoint, access.token);
      connection = HostConnection(local.client, local.sessions);
      if (generation != _connectGeneration) {
        await connection.close();
        return;
      }
      await _teardownActive();
      final client = connection.client;
      _connection = connection;
      _statusSubscription = client.mux.states.listen((state) {
        if (identical(client, this.client)) {
          status = state;
          notifyListeners();
        }
      });
      activeHost = null;
      this.client = client;
      sessions = _visibleSessions(connection.sessions);
      status = client.mux.state;
    } on Exception catch (err) {
      await connection?.close();
      if (generation == _connectGeneration) error = desktopError(err);
    } finally {
      if (generation == _connectGeneration) {
        busy = false;
        loaded = true;
        notifyListeners();
      }
    }
  }

  Future<void> _migrateLegacy() async {
    final store = legacyStore;
    if (store == null) return;
    final DesktopCredentials? legacy;
    try {
      legacy = await store.read();
    } on Exception {
      return;
    }
    if (legacy == null) return;
    final host = HostEntry(
      id: HostEntry.newId(),
      name: legacy.endpoint.host,
      transport: HostTransport.https,
      endpoint: legacy.endpoint,
    );
    registry = HostRegistry(hosts: [host], lastActiveId: host.id);
    await vault.write(HostRegistry.registryKey, registry.encode());
    await vault.write(HostRegistry.secretKey(host.id), legacy.encode());
    await store.clear();
  }

  /// Connects an HTTPS host from the quick form, saving it when [remember].
  Future<void> connectHttps(
    Uri endpoint, {
    String? launchToken,
    bool remember = true,
  }) async {
    final existing = _httpsHostFor(endpoint);
    final host =
        existing ??
        HostEntry(
          id: HostEntry.newId(),
          name: endpoint.host,
          transport: HostTransport.https,
          endpoint: endpoint,
        );
    await _connect(
      host,
      launchToken: launchToken,
      remember: remember,
      persistHost: existing == null || remember,
    );
  }

  HostEntry? _httpsHostFor(Uri endpoint) {
    for (final host in registry.hosts) {
      if (host.transport == HostTransport.https && host.endpoint == endpoint) {
        return host;
      }
    }
    return null;
  }

  Future<void> connectHost(
    HostEntry host, {
    String? launchToken,
    Future<bool> Function(String fingerprint)? trust,
  }) async {
    await _connect(host, launchToken: launchToken, trust: trust);
  }

  Future<void> _connect(
    HostEntry host, {
    String? launchToken,
    bool remember = true,
    bool persistHost = true,
    Future<bool> Function(String fingerprint)? trust,
  }) async {
    if (busy && loaded) return;
    final generation = ++_connectGeneration;
    busy = true;
    error = null;
    notifyListeners();
    HostConnection? connection;
    try {
      final secret = await _readSecret(host.id);
      connection = switch (host.transport) {
        HostTransport.https => await _connectHttps(
          host,
          secret,
          launchToken: launchToken,
        ),
        HostTransport.ssh => await _connectSsh(host, secret, trust),
        HostTransport.remote => await _connectRemote(host, trust),
      };
      if (generation != _connectGeneration) {
        await connection.close();
        return;
      }
      await _teardownActive();
      final client = connection.client;
      _connection = connection;
      _statusSubscription = client.mux.states.listen((state) {
        if (identical(client, this.client)) {
          status = state;
          notifyListeners();
        }
      });
      final effectiveHost = connection.updatedHost ?? host;
      activeHost = effectiveHost;
      this.client = client;
      sessions = _visibleSessions(connection.sessions);
      status = client.mux.state;
      registry = registry.copyWith(lastActiveId: effectiveHost.id);
      if (persistHost) registry = registry.withHost(effectiveHost);
      await _persistRegistry();
      final updatedSecret = connection.updatedSecret;
      if (updatedSecret != null) {
        await vault.write(
          HostRegistry.secretKey(effectiveHost.id),
          jsonEncode(updatedSecret),
        );
      }
      final cookie = connection.cookie;
      if (host.transport == HostTransport.https &&
          launchToken != null &&
          cookie != null) {
        if (remember) {
          await vault.write(
            HostRegistry.secretKey(host.id),
            DesktopCredentials(host.endpoint!, cookie).encode(),
          );
        } else {
          await vault.delete(HostRegistry.secretKey(host.id));
        }
      }
    } on Exception catch (err) {
      await connection?.close();
      if (generation == _connectGeneration) error = desktopError(err);
    } finally {
      if (generation == _connectGeneration) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<HostConnection> _connectHttps(
    HostEntry host,
    Map<String, Object?> secret, {
    String? launchToken,
  }) async {
    DshCookie? cookie;
    if (launchToken == null && secret.isNotEmpty) {
      cookie = DesktopCredentials.decode(jsonEncode(secret)).cookie;
    }
    final connection = await connect(
      host.endpoint!,
      launchToken: launchToken,
      cookie: cookie,
    );
    return HostConnection(
      connection.client,
      connection.sessions,
      cookie: connection.cookie,
    );
  }

  Future<HostConnection> _connectSsh(
    HostEntry host,
    Map<String, Object?> secret,
    Future<bool> Function(String fingerprint)? trust,
  ) async {
    final connector = sshConnect;
    if (connector == null) {
      throw const FormatException('SSH 连接尚未可用。');
    }
    return connector(host, secret, trust: trust ?? (_) async => false);
  }

  Future<HostConnection> _connectRemote(
    HostEntry host,
    Future<bool> Function(String fingerprint)? trust,
  ) async {
    final connector = remoteConnect;
    if (connector == null) {
      throw const FormatException('DSH Remote 尚未可用。');
    }
    return connector(host, trust: trust ?? (_) async => false);
  }

  Future<Map<String, Object?>> hostSecret(String hostId) => _readSecret(hostId);

  Future<Map<String, Object?>> _readSecret(String hostId) async {
    final value = await vault.read(HostRegistry.secretKey(hostId));
    if (value == null) return const {};
    final json = jsonDecode(value);
    return json is Map<String, Object?> ? json : const {};
  }

  Future<void> _persistRegistry() =>
      vault.write(HostRegistry.registryKey, registry.encode());

  Future<void> _teardownActive() async {
    unawaited(_statusSubscription?.cancel());
    _statusSubscription = null;
    await _connection?.close();
    _connection = null;
  }

  /// Closes the active connection. [clearLogin] also removes the host's saved
  /// secret; the host entry stays in the list for reconnection.
  Future<void> disconnect({bool clearLogin = false}) async {
    if (busy && loaded) return;
    busy = true;
    error = null;
    notifyListeners();
    final host = activeHost;
    try {
      await _teardownActive();
      if (clearLogin && host != null) {
        await vault.delete(HostRegistry.secretKey(host.id));
        registry = registry.clearLastActive();
        await _persistRegistry();
      }
      activeHost = null;
      client = null;
      sessions = const [];
      status = DshConnectionState.idle;
    } on Exception {
      error = '未能清除手机上的登录信息，请重试。';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> removeHost(String id) async {
    if (activeHost?.id == id) await disconnect();
    registry = registry.withoutHost(id);
    await _persistRegistry();
    await vault.delete(HostRegistry.secretKey(id));
    notifyListeners();
  }

  /// Adds or edits a host from the management page. [secret] replaces the
  /// host's vault document when provided.
  Future<void> saveHost(HostEntry host, {Map<String, Object?>? secret}) async {
    host.validate();
    registry = registry.withHost(host);
    await _persistRegistry();
    if (secret != null) {
      await vault.write(HostRegistry.secretKey(host.id), jsonEncode(secret));
    }
    if (activeHost?.id == host.id) activeHost = host;
    notifyListeners();
  }

  Future<void> setAutoConnect(bool value) async {
    registry = registry.copyWith(autoConnectLast: value);
    await _persistRegistry();
    notifyListeners();
  }

  Future<void> refresh() async {
    final client = this.client;
    if (busy || client == null) return;
    busy = true;
    error = null;
    notifyListeners();
    try {
      sessions = _visibleSessions(await client.listSessions());
    } on Exception catch (err) {
      error = desktopError(err);
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  List<SessionSummary> _visibleSessions(List<SessionSummary> sessions) => [
    for (final session in sessions)
      if (!session.isSubagent && session.sessionId.isNotEmpty) session,
  ];

  @override
  void dispose() {
    unawaited(_statusSubscription?.cancel());
    unawaited(_connection?.close());
    super.dispose();
  }
}