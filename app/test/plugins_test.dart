import 'dart:convert';
import 'dart:io';

import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tokenworks_go/src/plugin_market.dart';
import 'package:tokenworks_go/src/plugins_page.dart';

import 'support/fake_dsh_carrier.dart';

void main() {
  test('downloads and parses a bounded format-1 market index', () async {
    await HttpOverrides.runWithHttpOverrides(() async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) {
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(_marketJson));
        request.response.close();
      });
      final uri = Uri.parse('http://127.0.0.1:${server.port}/index.json');
      final index = await fetchMarketIndex(uri);
      expect(index.plugins.single.name, '@example/plugin');
      expect(index.plugins.single.latest.version, '1.0.0');
      expect(index.plugins.single.latest.installTarget('@example/plugin').spec, '@example/plugin@1.0.0');
    }, _RealHttpOverrides());
  });

  testWidgets('toggles an installed bundle', (tester) async {
    final carrier = FakeDshCarrier();
    carrier.handlers['pluginManager/listBundles'] = (_) => [_bundleJson];
    carrier.handlers['pluginManager/setBundleEnabled'] = (_) => {'changed': true, 'application': 'applied', 'enabled': true};
    final client = await carrier.connect();
    addTearDown(client.close);

    await tester.pumpWidget(MaterialApp(home: PluginsPage(client: client, marketLoader: (uri) async => parseMarketIndex(_marketJson, uri))));
    await tester.pumpAndSettle();
    expect(find.text('示例插件'), findsOneWidget);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(carrier.calls['pluginManager/setBundleEnabled']?.single, {'name': '@example/plugin', 'enabled': true});
  });

  testWidgets('inspects, confirms and installs a market plugin', (tester) async {
    final carrier = FakeDshCarrier();
    carrier.handlers['pluginManager/listBundles'] = (_) => <Object?>[];
    carrier.handlers['pluginManager/inspect'] = (_) => {
      'kind': 'registry',
      'name': '@example/plugin',
      'version': '1.0.0',
      'bundle': true,
    };
    carrier.handlers['pluginManager/installBundle'] = (_) => {'changed': true, 'application': 'applied', 'bundle': '@example/plugin'};
    final client = await carrier.connect();
    addTearDown(client.close);

    await tester.pumpWidget(MaterialApp(home: PluginsPage(client: client, marketLoader: (uri) async => parseMarketIndex(_marketJson, uri))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('插件市场'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('示例插件'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('安装到当前主机'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('安装').last);
    await tester.pumpAndSettle();

    expect(carrier.calls['pluginManager/inspect']?.single, {'spec': '@example/plugin@1.0.0'});
    final install = carrier.calls['pluginManager/installBundle']!.single;
    expect(install['spec'], '@example/plugin@1.0.0');
    expect((install['options'] as Map)['enabled'], isTrue);
    expect((install['options'] as Map)['saveExact'], isTrue);
    expect(find.text('插件已安装并启用。'), findsOneWidget);
  });
}

final class _RealHttpOverrides extends HttpOverrides {}

final _bundleJson = {
  'name': '@example/plugin',
  'official': false,
  'installed': true,
  'enabled': false,
  'removable': true,
  'version': '1.0.0',
  'meta': {'title': '示例插件'},
  'rows': <Object?>[],
};

final _marketJson = {
  'format': 1,
  'metadata': {'title': '测试市场'},
  'plugins': [
    {
      'name': '@example/plugin',
      'title': '示例插件',
      'description': '用于测试安装流程',
      'versions': [
        {
          'version': '1.0.0',
          'publishTimestamp': 1767225600,
          'source': {'type': 'npm'},
        },
      ],
    },
  ],
};
