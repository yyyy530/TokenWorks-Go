import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tokenworks_go/src/voice_bridge.dart';
import 'package:tokenworks_go/src/voice_call_page.dart';

import 'support/fake_dsh_carrier.dart';

void main() {
  testWidgets('voice call sends final recognition, speaks sentences and keeps approval manual', (tester) async {
    final carrier = FakeDshCarrier();
    carrier.handlers['session/prompt'] = (_) => null;
    carrier.handlers[r'$events/result'] = (_) => null;
    final client = await carrier.connect();
    addTearDown(client.close);
    final voice = FakeVoiceBridge();

    await tester.pumpWidget(MaterialApp(home: VoiceCallPage(client: client, sessionId: 'session-1', title: '通话测试', bridge: voice)));
    await tester.pumpAndSettle();
    expect(voice.startCalls, greaterThan(0));

    carrier.link.follow({
      'type': 'snapshot',
      'header': {'id': 'session-1', 'version': 4, 'createdAt': 1000},
      'cursor': 1,
      'records': [
        {
          'type': 'event',
          'event': {
            'seq': 1,
            'time': 1001,
            'type': 'assistant/message',
            'data': {
              'turn': 1,
              'step': 1,
              'message': {
                'id': 'history-assistant',
                'role': 'assistant',
                'content': [
                  {'type': 'text', 'text': '不应朗读的历史回复。'},
                ],
              },
            },
          },
        },
      ],
      'hasMore': false,
      'projections': {'values': <String, Object?>{}},
      'assistantStream': {'revision': 0},
    });
    await tester.pumpAndSettle();
    expect(voice.spoken, isEmpty);

    voice.emit(const VoiceRecognitionEvent('你好', isFinal: false));
    await tester.pumpAndSettle();
    expect(find.text('你好'), findsOneWidget);
    voice.emit(const VoiceRecognitionEvent('你好', isFinal: true));
    await tester.pumpAndSettle();
    expect((carrier.calls['session/prompt']!.single['request'] as Map)['content'], [
      {'type': 'text', 'text': '你好'},
    ]);

    carrier.link.follow({
      'type': 'assistant-stream',
      'frame': {'type': 'start', 'attemptId': 'draft', 'revision': 1, 'turn': 1, 'step': 1},
    });
    carrier.link.follow({
      'type': 'assistant-stream',
      'frame': {
        'type': 'chunk',
        'attemptId': 'draft',
        'revision': 2,
        'index': 0,
        'chunk': {'type': 'text-delta', 'index': 0, 'text': '你好，世界。'},
      },
    });
    await tester.pumpAndSettle();
    expect(voice.spoken.map((utterance) => utterance.text), ['你好，世界。']);

    voice.emit(const VoiceRecognitionEvent('停一下', isFinal: false));
    await tester.pump();
    expect(voice.stopSpeakingCalls, greaterThan(0));

    carrier.link.request('approval/request', 'approval-1', {'toolName': 'read_file', 'reason': '读取报告'});
    await tester.pumpAndSettle();
    expect(find.text('仅允许本次'), findsOneWidget);
    await tester.tap(find.text('仅允许本次'));
    await tester.pumpAndSettle();
    expect(carrier.calls[r'$events/result']?.single['outcome'], {'kind': 'result', 'value': 'allowed-once'});

    await tester.tap(find.byIcon(Icons.call_end));
    await tester.pumpAndSettle();
    expect(voice.shutdownCalled, isTrue);
  });
}

final class FakeVoiceBridge implements VoiceBridge {
  final _events = StreamController<VoiceEvent>.broadcast();
  final spoken = <({String id, String text})>[];
  int startCalls = 0;
  int stopSpeakingCalls = 0;
  bool shutdownCalled = false;

  void emit(VoiceEvent event) => _events.add(event);

  @override
  Stream<VoiceEvent> get events => _events.stream;

  @override
  Future<void> startListening() async => startCalls++;

  @override
  Future<void> stopListening() async {}

  @override
  Future<void> speak(String id, String text) async => spoken.add((id: id, text: text));

  @override
  Future<void> stopSpeaking() async => stopSpeakingCalls++;

  @override
  Future<void> setSpeakerphone(bool enabled) async {}

  @override
  Future<void> shutdown() async => shutdownCalled = true;
}
