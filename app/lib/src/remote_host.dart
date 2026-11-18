import 'package:dsh_remote/dsh_remote.dart';

import 'desktop_host.dart';
import 'host_manager.dart';
import 'host_registry.dart';
import 'host_vault.dart';

/// Backs the Remote account's identity, tokens and Host pins with the same
/// encrypted vault as the other host credentials.
final class VaultSecretStore implements SecretStore {
  const VaultSecretStore(this.vault);

  final HostVault vault;

  @override
  Future<String?> read(String key) => vault.read(key);

  @override
  Future<void> write(String key, String value) => vault.write(key, value);

  @override
  Future<void> delete(String key) => vault.delete(key);
}

final class RemoteHostAccess {
  RemoteHostAccess({HostVault? vault, RemoteAccount? account})
    : account = account ??
          RemoteAccount(
            secrets: VaultSecretStore(vault!),
            deviceName: 'TokenWorks-Go',
            platform: 'tokenworks-go-android',
            clientVersion: '0.1.0',
            // Relay keeps the first Android version free of a native WebRTC
            // dependency; Noise IK still encrypts the Host channel end to end.
            peerConnector: null,
          );

  final RemoteAccount account;

  Future<HostConnection> connect(
    HostEntry host, {
    required Future<bool> Function(String fingerprint) trust,
  }) async {
    try {
      final hosts = await account.listHosts();
      final remote = hosts.where((candidate) => candidate.id == host.remoteHostId).firstOrNull;
      if (remote == null) {
        throw const HostConnectionException('Remote 账号目录里找不到这台主机，请重新选择。');
      }
      final client = await account.connectHost(
        remote,
        confirmNewHost: (candidate) => trust(candidate.fingerprint ?? '指纹不可用（${candidate.id}）'),
      );
      try {
        final sessions = await client.listSessions();
        return HostConnection(client, sessions);
      } on Object {
        await client.close();
        rethrow;
      }
    } on HostConnectionException {
      rethrow;
    } on Object catch (error) {
      throw HostConnectionException(remoteError(error));
    }
  }

  Future<void> close() => account.close();
}

String remoteError(Object error) {
  final code = switch (error) {
    RemoteConnectException() => error.code,
    RemoteApiException() => error.code,
    _ => null,
  };
  return switch (code) {
    'ACCOUNT_AUTH_REQUIRED' || 'AUTH_REQUIRED' || 'AUTH_INVALID' || 'TOKEN_EXPIRED' =>
      'Remote 登录已失效，请重新登录。',
    'HOST_OFFLINE' => '这台电脑当前不在线，请在电脑上启动 DSH 和 Remote 插件后重试。',
    'HOST_NOT_TRUSTED' => '未信任这台电脑，已取消连接。',
    'PEER_IDENTITY_MISMATCH' => '电脑的身份密钥已改变。请核对后在 Remote 页重新信任。',
    'CONNECTION_REPLACED' => '这台手机已连接到另一台 Remote 主机。',
    'CONNECTION_REJECTED' => '电脑拒绝了这次 Remote 连接。',
    'HARNESS_VERSION_INCOMPATIBLE' => '电脑的 DSH 或 Remote 插件版本不兼容，请更新后重试。',
    'LOGIN_EXPIRED' => '登录已过期，请重新开始。',
    'LOGIN_CANCELLED' => '已取消登录。',
    'OAUTH_PROVIDER_UNAVAILABLE' => 'Remote 服务器当前没有可用的登录方式。',
    'RATE_LIMITED' => 'Remote 服务器请求过于频繁，请稍后重试。',
    _ => '暂时无法连接 Remote 服务，请检查网络、账号和电脑在线状态后重试。',
  };
}
