import 'package:dsh_client/dsh_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tokenworks_go/src/host_manager.dart';
import 'package:tokenworks_go/src/host_registry.dart';
import 'package:tokenworks_go/src/host_vault.dart';

void main() {
  test('registry round-trips all host kinds without storing secrets', () {
    final registry = HostRegistry(
      hosts: [
        HostEntry(
          id: 'https-1',
          name: '桌面',
          transport: HostTransport.https,
          endpoint: Uri.parse('https://desktop.example'),
        ),
        const HostEntry(
          id: 'ssh-1',
          name: '服务器',
          transport: HostTransport.ssh,
          ssh: SshHostSettings(
            host: 'server.example',
            username: 'ustc',
            managed: false,
            remotePort: 4099,
            workdir: '/home/ustc/work',
            trustedKeyFingerprint: 'SHA256:abc',
          ),
        ),
        const HostEntry(
          id: 'remote-1',
          name: 'Remote 电脑',
          transport: HostTransport.remote,
          remoteHostId: 'host-directory-id',
        ),
      ],
      lastActiveId: 'ssh-1',
      autoConnectLast: false,
    );

    final decoded = HostRegistry.decode(registry.encode());
    expect(decoded.hosts, hasLength(3));
    expect(decoded.hosts[0].endpoint, registry.hosts[0].endpoint);
    expect(decoded.hosts[1].ssh?.managed, isFalse);
    expect(decoded.hosts[1].ssh?.remotePort, 4099);
    expect(decoded.hosts[1].ssh?.trustedKeyFingerprint, 'SHA256:abc');
    expect(decoded.hosts[2].remoteHostId, 'host-directory-id');
    expect(decoded.lastActive?.id, 'ssh-1');
    expect(decoded.autoConnectLast, isFalse);
    expect(registry.encode(), isNot(contains('password')));
    expect(registry.encode(), isNot(contains('privateKey')));
  });

  test('registry skips malformed entries instead of losing the whole list', () {
    final registry = HostRegistry.decode(
      '{"version":1,"hosts":[{"id":"ok","name":"桌面","transport":"https","endpoint":"https://desktop.example"},{"id":"bad","name":"坏","transport":"ssh"}],"autoConnectLast":true}',
    );
    expect(registry.hosts.map((host) => host.id), ['ok']);
  });

  test('host manager persists edits, preferences and secret deletion', () async {
    final vault = MemoryHostVault();
    final manager = HostManager(vault: vault);
    const host = HostEntry(
      id: 'ssh-1',
      name: '服务器',
      transport: HostTransport.ssh,
      ssh: SshHostSettings(host: 'server.example', username: 'ustc'),
    );
    await manager.saveHost(host, secret: const {'password': 'not-in-registry'});
    await manager.setAutoConnect(false);

    expect(HostRegistry.decode(vault.values[HostRegistry.registryKey]!).hosts.single.name, '服务器');
    expect(vault.values[HostRegistry.secretKey(host.id)], contains('not-in-registry'));
    expect(HostRegistry.decode(vault.values[HostRegistry.registryKey]!).autoConnectLast, isFalse);

    await manager.removeHost(host.id);
    expect(manager.registry.hosts, isEmpty);
    expect(vault.values[HostRegistry.secretKey(host.id)], isNull);
    manager.dispose();
  });

  test('load respects disabled auto-connect', () async {
    final host = HostEntry(
      id: 'https-1',
      name: '桌面',
      transport: HostTransport.https,
      endpoint: Uri.parse('https://desktop.example'),
    );
    final registry = HostRegistry(hosts: [host], lastActiveId: host.id, autoConnectLast: false);
    final manager = HostManager(
      vault: MemoryHostVault({HostRegistry.registryKey: registry.encode()}),
      connect: (Uri endpoint, {String? launchToken, DshCookie? cookie}) {
        throw StateError('must not auto-connect');
      },
    );
    await manager.load();
    expect(manager.loaded, isTrue);
    expect(manager.busy, isFalse);
    expect(manager.client, isNull);
    manager.dispose();
  });
}
