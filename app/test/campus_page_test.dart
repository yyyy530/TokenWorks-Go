import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tokenworks_go/src/campus_client.dart';
import 'package:tokenworks_go/src/campus_page.dart';

void main() {
  testWidgets(
    'iWAN actions remain available before campus authorization is configured',
    (tester) async {
      final calls = <MethodCall>[];
      var verifiedIwan = false;
      const channel = MethodChannel('tokenworks_go/campus_navigation');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return call.method == 'openIwan' ? verifiedIwan : null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      await tester.pumpWidget(
        MaterialApp(
          home: CampusPage(
            client: null,
            probe: () async => CampusReachability.reachable,
          ),
        ),
      );
      expect(find.textContaining('尚未配置学校批准'), findsOneWidget);
      expect(find.text('通过中国科大统一身份登录'), findsNothing);

      await tester.tap(find.text('iWAN 安装与连接说明'));
      await tester.pumpAndSettle();
      expect(calls.single.method, 'openHttps');
      expect(calls.single.arguments, iwanGuide.toString());

      await tester.tap(find.text('打开 iWAN'));
      await tester.pumpAndSettle();
      expect(calls[calls.length - 2].method, 'openIwan');
      expect(calls.last.arguments, iwanGuide.toString());

      verifiedIwan = true;
      final before = calls.length;
      await tester.tap(find.text('打开 iWAN'));
      await tester.pumpAndSettle();
      expect(calls.length, before + 1);
      expect(calls.last.method, 'openIwan');

      await tester.tap(find.text('打开系统 VPN 设置'));
      await tester.pumpAndSettle();
      expect(calls.last.method, 'openVpnSettings');

      await tester.tap(find.text('检查学校模型网关'));
      await tester.pumpAndSettle();
      expect(find.textContaining('手机可访问学校模型网关'), findsOneWidget);
    },
  );
}
