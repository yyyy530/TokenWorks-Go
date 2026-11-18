import 'dart:convert';
import 'dart:io';

import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tokenworks_go/src/ustc_quota.dart';
import 'package:tokenworks_go/src/ustc_quota_page.dart';

const snapshotJson = {
  'version': 1,
  'source': 'tokenworks',
  'generatedAt': '2026-11-18T12:00:00Z',
  'warnings': <String>[],
  'keys': [
    {
      'provider': 'ustc-llm',
      'label': 'TokenWorks',
      'ok': true,
      'stale': false,
      'windows': [
        {
          'id': '3h',
          'state': 'active',
          'used': 12.5,
          'limit': 30,
          'resetAt': '2099-11-18T15:00:00Z',
        },
        {'id': '12h', 'state': 'resetting', 'used': null, 'limit': 70},
        {'id': '24h', 'state': 'not-configured', 'used': null, 'limit': null},
      ],
    },
  ],
};

void main() {
  test(
    'reads the published snapshot contract using the existing Host cookie',
    () async {
      await HttpOverrides.runWithHttpOverrides(() async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        var requests = 0;
        var status = HttpStatus.ok;
        String? cookieHeader;
        Uri? requested;
        server.listen((request) async {
          requests++;
          requested = request.uri;
          cookieHeader = request.headers.value(HttpHeaders.cookieHeader);
          final response = request.response..statusCode = status;
          if (status == HttpStatus.ok) {
            response.headers.contentType = ContentType.json;
            response.write(jsonEncode(snapshotJson));
          } else if (status == HttpStatus.found) {
            response.headers.set(HttpHeaders.locationHeader, '/redirected');
          }
          await response.close();
        });
        final endpoint = Uri.parse('http://127.0.0.1:${server.port}/dsh');
        final connection = DshConnection(endpoint);
        final client = DshClient(connection);
        addTearDown(client.close);

        expect(await loadUstcQuota(client), isNull);
        expect(requests, 0);

        connection.cookie = DshCookie(
          name: 'dsh-auth-test',
          value: 'fixture',
          authority: endpoint.authority,
        );
        final snapshot = (await loadUstcQuota(client))!;
        expect(requested?.path, '/dsh/plugins/dsh-ustc-quota/snapshot');
        expect(cookieHeader, 'dsh-auth-test=fixture');
        expect(snapshot.fromTokenWorks, isTrue);
        final windows = snapshot.accounts.single.windows;
        expect(windows.first.remaining, 17.5);
        expect(windows[1].state, QuotaState.resetting);
        expect(windows[1].remaining, isNull);
        expect(windows[2].remaining, isNull);

        status = HttpStatus.notFound;
        expect(await loadUstcQuota(client), isNull);

        status = HttpStatus.found;
        await expectLater(
          loadUstcQuota(client),
          throwsA(isA<DshHttpException>()),
        );
        expect(requests, 3);
      }, _FixtureHttpOverrides());
    },
  );

  testWidgets(
    'refresh shows missing login, real quotas and unsupported hosts distinctly',
    (tester) async {
      UstcQuotaSnapshot? snapshot = UstcQuotaSnapshot.fromJson({
        'version': 1,
        'source': 'tokenworks',
        'warnings': ['tokenworks-not-ready'],
        'keys': <Object?>[],
      });
      await tester.pumpWidget(
        MaterialApp(home: UstcQuotaPage(load: () async => snapshot)),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('请检查桌面登录'), findsOneWidget);
      expect(find.textContaining('剩余 0'), findsNothing);

      snapshot = UstcQuotaSnapshot.fromJson(snapshotJson);
      await tester.tap(find.text('刷新额度'));
      await tester.pumpAndSettle();
      expect(find.textContaining('17.50 / 30'), findsOneWidget);
      expect(find.textContaining('等待重置'), findsOneWidget);

      snapshot = null;
      await tester.tap(find.text('刷新额度'));
      await tester.pumpAndSettle();
      expect(find.text('当前主机未提供额度查询。'), findsOneWidget);
      expect(find.textContaining('17.50'), findsNothing);
    },
  );
}

final class _FixtureHttpOverrides extends HttpOverrides {}
