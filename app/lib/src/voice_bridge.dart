import 'dart:async';

import 'package:flutter/services.dart';

sealed class VoiceEvent {
  const VoiceEvent();
}

final class VoiceRecognitionEvent extends VoiceEvent {
  const VoiceRecognitionEvent(this.text, {required this.isFinal});

  final String text;
  final bool isFinal;
}

final class VoiceListeningErrorEvent extends VoiceEvent {
  const VoiceListeningErrorEvent(this.code);

  final int code;
}

final class VoiceUtteranceEvent extends VoiceEvent {
  const VoiceUtteranceEvent(this.id, {required this.started});

  final String id;
  final bool started;
}

final class VoicePlaybackErrorEvent extends VoiceEvent {
  const VoicePlaybackErrorEvent(this.message);

  final String message;
}

abstract interface class VoiceBridge {
  Stream<VoiceEvent> get events;
  Future<void> startListening();
  Future<void> stopListening();
  Future<void> speak(String id, String text);
  Future<void> stopSpeaking();
  Future<void> setSpeakerphone(bool enabled);
  Future<void> shutdown();
}

final class MethodChannelVoiceBridge implements VoiceBridge {
  MethodChannelVoiceBridge() {
    _channel.setMethodCallHandler(_onCall);
  }

  static const _channel = MethodChannel('tokenworks_go/voice');
  final _events = StreamController<VoiceEvent>.broadcast();

  @override
  Stream<VoiceEvent> get events => _events.stream;

  Future<void> _onCall(MethodCall call) async {
    switch (call.method) {
      case 'recognition':
        final args = call.arguments as Map;
        _events.add(VoiceRecognitionEvent(args['text'] as String? ?? '', isFinal: args['final'] == true));
      case 'listeningError':
        _events.add(VoiceListeningErrorEvent(call.arguments as int? ?? -1));
      case 'utterance':
        final args = call.arguments as Map;
        _events.add(VoiceUtteranceEvent(args['id'] as String? ?? '', started: args['started'] == true));
      case 'playbackError':
        _events.add(VoicePlaybackErrorEvent(call.arguments as String? ?? '朗读失败'));
    }
  }

  @override
  Future<void> startListening() => _channel.invokeMethod<void>('startListening');

  @override
  Future<void> stopListening() => _channel.invokeMethod<void>('stopListening');

  @override
  Future<void> speak(String id, String text) => _channel.invokeMethod<void>('speak', {'id': id, 'text': text});

  @override
  Future<void> stopSpeaking() => _channel.invokeMethod<void>('stopSpeaking');

  @override
  Future<void> setSpeakerphone(bool enabled) => _channel.invokeMethod<void>('setSpeakerphone', enabled);

  @override
  Future<void> shutdown() async {
    await _channel.invokeMethod<void>('shutdown');
    await _events.close();
  }
}
