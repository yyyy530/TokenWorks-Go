import 'dart:async';

import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/foundation.dart';

import 'desktop_host.dart';
import 'voice_bridge.dart';

/// One voice call: system recognition becomes a normal prompt, assistant text
/// is queued to system TTS in complete sentences. Approvals always require a
/// tap; no speech event can approve a tool.
final class VoiceCallController extends ChangeNotifier {
  VoiceCallController({required this.client, required this.sessionId, required this.voice});

  final DshClient client;
  final String sessionId;
  final VoiceBridge voice;

  ChatTranscript transcript = ChatTranscript();
  String liveText = '';
  bool listening = false;
  bool speaking = false;
  bool muted = false;
  bool speakerphone = true;
  String? error;

  StreamSubscription<DshEvent>? _watchSubscription;
  StreamSubscription<VoiceEvent>? _voiceSubscription;
  SessionFollowEpoch? _epoch;
  bool _following = true;
  bool _awaitingResponse = false;
  bool _sawRunning = false;
  bool _closed = false;
  final _pendingUtterances = <String>{};
  final _consumedText = <String, int>{};
  final _suppressedItems = <String>{};
  var _utteranceSequence = 0;

  bool get ready =>
      _following && _epoch?.isCurrent == true && client.mux.state == DshConnectionState.connected;

  bool get _hasPendingInteraction =>
      transcript.pendingApprovals.isNotEmpty || transcript.pendingQuestions.isNotEmpty;

  String get status {
    if (error != null) return '通话需要处理';
    if (_hasPendingInteraction) return '等待你确认';
    if (listening) return '正在听你说…';
    if (speaking) return '正在回答…';
    if (transcript.running || _awaitingResponse) return '正在思考…';
    if (muted) return '已静音';
    return '准备聆听';
  }

  Future<void> start() async {
    _voiceSubscription = voice.events.listen(_onVoiceEvent, onError: _onVoiceError);
    _startWatch();
    await _startListening();
  }

  void _startWatch() {
    _watchSubscription = client
        .watch(
          sessionId,
          options: WatchOptions(
            activate: true,
            activationAllowed: () => !_closed && _following,
            includeSyncEvents: true,
          ),
        )
        .listen(
          _onChatEvent,
          onError: (Object err) {
            error = desktopError(err);
            _following = false;
            _awaitingResponse = false;
            notifyListeners();
          },
          onDone: () {
            if (!_closed) {
              _following = false;
              _awaitingResponse = false;
              notifyListeners();
            }
          },
        );
  }

  void _onChatEvent(DshEvent event) {
    if (_closed) return;
    switch (event) {
      case SessionSyncEvent():
        _epoch = null;
      case SessionSnapshotEvent(:final followEpoch):
        _epoch = followEpoch;
      default:
        break;
    }
    transcript.apply(event);
    if (event is SessionSnapshotEvent) {
      // History is context for the call, not something to read aloud from the top.
      for (final item in transcript.items.whereType<AssistantChatItem>()) {
        _consumedText[item.key] = item.text.length;
      }
    }
    if (transcript.running) {
      _sawRunning = true;
    } else if (_sawRunning) {
      _sawRunning = false;
      _awaitingResponse = false;
    }
    if (_hasPendingInteraction) unawaited(_stopListening());
    if (event is! SessionSnapshotEvent) _queueAssistantSpeech();
    _maybeResumeListening();
    notifyListeners();
  }

  void _onVoiceEvent(VoiceEvent event) {
    if (_closed || muted) return;
    switch (event) {
      case VoiceRecognitionEvent(:final text, :final isFinal):
        if (isFinal) {
          listening = false;
          liveText = '';
          if (text.trim().isEmpty) {
            _maybeResumeListening();
          } else {
            unawaited(_send(text.trim()));
          }
        } else {
          liveText = text;
          if (text.trim().isNotEmpty && _pendingUtterances.isNotEmpty) {
            _interruptSpeech();
          }
        }
      case VoiceListeningErrorEvent(:final code):
        listening = false;
        // "No match" and "speech timeout" just end this attempt.
        if (code != 6 && code != 7) error = '语音识别暂时不可用（错误 $code）。';
        _maybeResumeListening();
      case VoiceUtteranceEvent(:final id, :final started):
        if (!started) {
          _pendingUtterances.remove(id);
          speaking = _pendingUtterances.isNotEmpty;
          _maybeResumeListening();
        }
      case VoicePlaybackErrorEvent(:final message):
        error = message;
        _pendingUtterances.clear();
        speaking = false;
        _maybeResumeListening();
    }
    notifyListeners();
  }

  void _onVoiceError(Object err) {
    if (_closed) return;
    error = '语音通道暂时不可用。';
    listening = false;
    notifyListeners();
  }

  void _queueAssistantSpeech() {
    if (_closed || muted) return;
    for (final item in transcript.items.whereType<AssistantChatItem>()) {
      final key = item.key;
      if (_suppressedItems.contains(key)) continue;
      final full = item.text;
      var consumed = _consumedText[key] ?? 0;
      if (consumed > full.length) consumed = 0;
      final unsaid = full.substring(consumed);
      if (unsaid.trim().isEmpty) continue;
      var end = unsaid.length;
      if (item.streaming) {
        end = _lastSentenceEnd(unsaid);
        if (end <= 0) continue;
      }
      final text = unsaid.substring(0, end).trim();
      if (text.isEmpty) continue;
      _consumedText[key] = consumed + end;
      final id = 'voice-${_utteranceSequence++}';
      _pendingUtterances.add(id);
      speaking = true;
      unawaited(voice.speak(id, text));
    }
  }

  int _lastSentenceEnd(String text) {
    var end = -1;
    for (final match in RegExp(r'[。！？!?；;\n]|\. ').allMatches(text)) {
      end = match.end;
    }
    return end;
  }

  Future<void> _send(String text) async {
    await _stopListening();
    _awaitingResponse = true;
    error = null;
    notifyListeners();
    try {
      await client.prompt(sessionId, text);
    } on Exception catch (err) {
      error = desktopError(err);
      _awaitingResponse = false;
      _maybeResumeListening();
      notifyListeners();
    }
  }

  void _interruptSpeech() {
    _suppressedItems.addAll(transcript.items.whereType<AssistantChatItem>().map((item) => item.key));
    _pendingUtterances.clear();
    speaking = false;
    unawaited(voice.stopSpeaking());
  }

  /// Skips the current spoken answer without cancelling the Host's turn.
  void skipSpeech() {
    _interruptSpeech();
    _maybeResumeListening();
    notifyListeners();
  }

  Future<void> _startListening() async {
    if (_closed || muted || listening || !ready || _pendingUtterances.isNotEmpty ||
        transcript.running || _awaitingResponse || _hasPendingInteraction) {
      return;
    }
    listening = true;
    error = null;
    notifyListeners();
    try {
      await voice.startListening();
    } on Exception {
      listening = false;
      error = '无法开始语音识别，请检查麦克风权限和系统识别服务。';
      notifyListeners();
    }
  }

  Future<void> _stopListening() async {
    if (!listening) return;
    listening = false;
    liveText = '';
    try {
      await voice.stopListening();
    } on Exception {
      // The native shutdown path is idempotent; a closed recognizer is already stopped.
    }
  }

  void _maybeResumeListening() => unawaited(_startListening());

  Future<void> toggleMute() async {
    muted = !muted;
    if (muted) {
      await _stopListening();
      _interruptSpeech();
    } else {
      _maybeResumeListening();
    }
    notifyListeners();
  }

  Future<void> toggleSpeakerphone() async {
    speakerphone = !speakerphone;
    await voice.setSpeakerphone(speakerphone);
    notifyListeners();
  }

  Future<void> respond(String eventId, Future<void> Function() action) async {
    await _stopListening();
    error = null;
    notifyListeners();
    try {
      await action();
      transcript.apply(HostRequestCancelledEvent(eventId));
    } on Exception catch (err) {
      error = desktopError(err);
    } finally {
      _maybeResumeListening();
      notifyListeners();
    }
  }

  Future<void> hangUp() async {
    if (_closed) return;
    _closed = true;
    try {
      await voice.stopListening();
    } on Exception {
      // A recognizer that never started is already stopped.
    }
    listening = false;
    speaking = false;
    _pendingUtterances.clear();
    await voice.stopSpeaking();
    unawaited(_watchSubscription?.cancel());
    unawaited(_voiceSubscription?.cancel());
    await voice.shutdown();
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(hangUp());
    super.dispose();
  }
}
