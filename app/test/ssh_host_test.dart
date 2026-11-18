import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tokenworks_go/src/host_manager.dart';
import 'package:tokenworks_go/src/desktop_host.dart';
import 'package:tokenworks_go/src/host_registry.dart';
import 'package:tokenworks_go/src/host_vault.dart';
import 'package:tokenworks_go/src/ssh_host.dart';
import 'package:tokenworks_go/src/ssh_host_page.dart';

void main() {
  test('parses a loopback DSH launch link from noisy output', () {
    final token = 'a' * 43;
    final link = parseSshLaunchLink(
      'DSH starting\nOpen http://127.0.0.1:43821/?token=$token to continue\nready',
    );
    expect(link?.port, 43821);
    expect(link?.token, token);
  });

  test('rejects external, malformed and non-token launch URLs', () {
    final token = 'a' * 43;
    expect(parseSshLaunchLink('https://example.com:443/?token=$token'), isNull);
    expect(parseSshLaunchLink('http://127.0.0.1:8080/?token=short'), isNull);
    expect(parseSshLaunchLink('not a URL'), isNull);
  });

  test('validates secrets against the selected instance mode', () {
    const settings = SshHostSettings(host: 'server.example', username: 'ustc', managed: false, remotePort: 8080);
    expect(() => const SshSecrets(password: 'pw').validateFor(settings), throwsA(isA<HostConnectionException>()));
    expect(
      () => SshSecrets(password: 'pw', launchToken: 'a' * 43).validateFor(settings),
      returnsNormally,
    );
    const keySettings = SshHostSettings(host: 'server.example', username: 'ustc', usePrivateKey: true);
    expect(() => const SshSecrets().validateFor(keySettings), throwsA(isA<HostConnectionException>()));
  });

  testWidgets('saves an SSH host and keeps secrets out of the registry', (tester) async {
    final vault = MemoryHostVault();
    final manager = HostManager(vault: vault);
    await tester.pumpWidget(MaterialApp(home: SshHostPage(manager: manager)));

    await tester.enterText(find.widgetWithText(TextField, '主机'), 'server.example');
    await tester.enterText(find.widgetWithText(TextField, '用户名'), 'ustc');
    await tester.enterText(find.widgetWithText(TextField, '密码'), 'secret-password');
    await tester.scrollUntilVisible(find.text('保存'), 300, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final registry = HostRegistry.decode(vault.values[HostRegistry.registryKey]!);
    final host = registry.hosts.single;
    expect(host.transport, HostTransport.ssh);
    expect(host.ssh?.host, 'server.example');
    expect(registry.encode(), isNot(contains('secret-password')));
    expect(vault.values[HostRegistry.secretKey(host.id)], contains('secret-password'));
    manager.dispose();
  });
}
