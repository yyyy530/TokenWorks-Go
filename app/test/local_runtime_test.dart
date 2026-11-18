import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tokenworks_go/src/desktop_host.dart';
import 'package:tokenworks_go/src/local_runtime_page.dart';

void main() {
  test(
    'the local runtime never sends a launch token to a remote endpoint',
    () async {
      final token = 'a' * 43;
      for (final address in [
        'http://192.0.2.1:3080',
        'https://127.0.0.1:3080',
        'http://127.0.0.1:3080/?other=1',
        'http://other@127.0.0.1:3080',
      ]) {
        await expectLater(
          connectLocal(Uri.parse(address), token),
          throwsFormatException,
        );
      }
      await expectLater(
        connectDesktop(Uri.parse('http://127.0.0.1:3080'), launchToken: token),
        throwsFormatException,
      );
    },
  );

  testWidgets('local runtime starts, opens the workspace, and stops', (
    tester,
  ) async {
    const channel = MethodChannel('tokenworks_go/local_runtime');
    final messenger = tester.binding.defaultBinaryMessenger;
    final calls = <String>[];
    var phase = 'stopped';
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      switch (call.method) {
        case 'status':
          return {'phase': phase, 'progress': 0, 'error': null};
        case 'start':
          phase = 'running';
          return null;
        case 'connect':
          return {'endpoint': 'http://127.0.0.1:3080', 'token': 'a' * 43};
        case 'stop':
          phase = 'stopped';
          return null;
        default:
          fail('Unexpected method: ${call.method}');
      }
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    await tester.pumpWidget(
      MaterialApp(
        home: LocalRuntimePage(
          workspace: (access) =>
              Scaffold(appBar: AppBar(), body: Text(access.endpoint.authority)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('启动本机引擎'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('进入本机工作区'));
    await tester.pumpAndSettle();
    expect(find.text('127.0.0.1:3080'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('停止引擎'));
    await tester.pumpAndSettle();
    expect(find.text('启动本机引擎'), findsOneWidget);
    expect(calls.where((call) => call != 'status'), [
      'start',
      'connect',
      'stop',
    ]);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
