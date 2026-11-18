import 'package:dsh_remote/dsh_remote.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tokenworks_go/src/host_vault.dart';
import 'package:tokenworks_go/src/remote_host.dart';

void main() {
  test('vault secret store round-trips Remote account keys', () async {
    final vault = MemoryHostVault();
    final store = VaultSecretStore(vault);
    const key = 'dsh_remote.v1.scope.identity';
    await store.write(key, '{"private":"secret"}');
    expect(await store.read(key), '{"private":"secret"}');
    expect(vault.values[key], contains('secret'));
    await store.delete(key);
    expect(await store.read(key), isNull);
  });

  test('maps Remote failures to actionable Chinese messages', () {
    expect(
      remoteError(const RemoteConnectException(RemoteFailure('HOST_OFFLINE', 'offline', retryable: true))),
      contains('不在线'),
    );
    expect(
      remoteError(const RemoteConnectException(RemoteFailure('HOST_NOT_TRUSTED', 'no', retryable: false))),
      contains('未信任'),
    );
    expect(remoteError(StateError('other')), contains('暂时无法连接'));
  });

  test('Remote access uses the official server and relay-only first version', () async {
    final access = RemoteHostAccess(vault: MemoryHostVault());
    expect(access.account.serverUrl.toString(), 'https://dsh.r2049.cn');
    expect(access.account.peerConnector, isNull);
    await access.close();
  });
}
