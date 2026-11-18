import 'package:flutter/services.dart';

/// Encrypted key-value vault on the phone (Android Keystore, one AtomicFile
/// per key). Holds the host registry, per-host SSH/HTTPS secrets and the DSH
/// Remote account material. Keys are app-generated; the platform side rejects
/// anything outside `[A-Za-z0-9._-]`.
abstract interface class HostVault {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

final class MethodChannelHostVault implements HostVault {
  const MethodChannelHostVault();

  static const _channel = MethodChannel('tokenworks_go/host_vault');

  @override
  Future<String?> read(String key) => _channel.invokeMethod<String>('read', key);

  @override
  Future<void> write(String key, String value) =>
      _channel.invokeMethod<void>('write', {'key': key, 'value': value});

  @override
  Future<void> delete(String key) => _channel.invokeMethod<void>('delete', key);
}

/// In-memory vault for tests and previews.
final class MemoryHostVault implements HostVault {
  MemoryHostVault([Map<String, String>? initial]) : values = {...?initial};

  final Map<String, String> values;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}