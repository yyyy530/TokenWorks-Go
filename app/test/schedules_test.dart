import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tokenworks_go/src/schedules_page.dart';

import 'support/fake_dsh_carrier.dart';

void main() {
  test('builds the official schedule_create instruction with exact arguments', () {
    final prompt = scheduleCreatePrompt(
      title: '每日报告',
      prompt: '生成报告',
      timing: const DailyTiming(time: '09:00:00', timeZone: 'Asia/Shanghai'),
    );
    expect(prompt, contains('schedule_create'));
    expect(prompt, contains('"title": "每日报告"'));
    expect(prompt, contains('"daily": {'));
    expect(prompt, contains('"time_zone": "Asia/Shanghai"'));
  });

  test('validates timing inputs at the protocol boundary', () {
    final controller = ScheduleTimingController()..everySeconds.text = '30';
    expect(() => controller.build(), throwsA(isA<FormatException>()));
    controller.everySeconds.text = '60';
    expect(controller.build(), const EveryTiming(60));
    controller
      ..setKind('cron')
      ..cron.text = 'bad';
    expect(() => controller.build(), throwsA(isA<FormatException>()));
    controller.dispose();
  });

  testWidgets('shows task details, runs now and deletes with confirmation', (tester) async {
    final carrier = FakeDshCarrier();
    carrier.handlers['schedule/catalog'] = (_) => [_dailyTask];
    carrier.handlers['schedule/history'] = (_) => {
      'records': [
        {'scheduledAt': '2026-11-18T01:00:00Z', 'deliveredAt': '2026-11-18T01:00:02Z'},
      ],
    };
    carrier.handlers['session/prompt'] = (_) => null;
    carrier.handlers['schedule/delete'] = (_) => {'deleted': true};
    final client = await carrier.connect();
    addTearDown(client.close);

    await tester.pumpWidget(MaterialApp(home: SchedulesPage(client: client)));
    await tester.pumpAndSettle();
    expect(find.text('每日报告'), findsOneWidget);
    await tester.tap(find.text('每日报告'));
    await tester.pumpAndSettle();
    expect(find.text('运行历史'), findsOneWidget);
    expect(find.textContaining('投递：'), findsOneWidget);

    await tester.tap(find.text('立即运行'));
    await tester.pumpAndSettle();
    expect(carrier.calls['session/prompt']?.single['request'], {
      'requestId': isNotNull,
      'sessionId': 'session-1',
      'mode': 'queue',
      'content': [
        {'type': 'text', 'text': '生成报告'},
      ],
      'clientTimeZone': 'Asia/Shanghai',
    });

    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除').last);
    await tester.pumpAndSettle();
    expect(carrier.calls['schedule/delete']?.single['request'], {'sessionId': 'session-1', 'id': 'task-1'});
  });

  testWidgets('creates through the current conversation instead of a fake RPC', (tester) async {
    final carrier = FakeDshCarrier();
    carrier.handlers['schedule/catalog'] = (_) => <Object?>[];
    carrier.handlers['session/prompt'] = (_) => null;
    final client = await carrier.connect();
    addTearDown(client.close);

    await tester.pumpWidget(MaterialApp(home: SchedulesPage(client: client, sessionId: 'session-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('新建'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '名称'), '每小时检查');
    await tester.enterText(find.widgetWithText(TextField, '到点发送的指令'), '检查构建状态');
    await tester.tap(find.text('交给对话创建'));
    await tester.pumpAndSettle();

    final request = carrier.calls['session/prompt']?.single['request'] as Map;
    expect(request['sessionId'], 'session-1');
    final content = request['content'] as List;
    expect((content.single['text'] as String), contains('schedule_create'));
    expect(content.single['text'], contains('每小时检查'));
    expect(content.single['text'], contains('"every_seconds": 3600'));
  });
}

final _dailyTask = {
  'id': 'task-1',
  'sessionId': 'session-1',
  'kind': 'daily',
  'title': '每日报告',
  'prompt': '生成报告',
  'time': '09:00:00',
  'timeZone': 'Asia/Shanghai',
  'status': 'active',
  'scheduledAt': '2026-11-19T01:00:00Z',
};
