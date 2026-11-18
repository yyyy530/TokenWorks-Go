import 'dart:async';

import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/material.dart';

import 'voice_bridge.dart';
import 'voice_call.dart';

final class VoiceCallPage extends StatefulWidget {
  const VoiceCallPage({required this.client, required this.sessionId, required this.title, this.bridge, super.key});

  final DshClient client;
  final String sessionId;
  final String title;
  final VoiceBridge? bridge;

  @override
  State<VoiceCallPage> createState() => _VoiceCallPageState();
}

final class _VoiceCallPageState extends State<VoiceCallPage> with WidgetsBindingObserver {
  late final VoiceCallController _controller = VoiceCallController(
    client: widget.client,
    sessionId: widget.sessionId,
    voice: widget.bridge ?? MethodChannelVoiceBridge(),
  );
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller.addListener(_changed);
    unawaited(_controller.start());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      unawaited(_endCall());
    }
  }

  Future<void> _endCall() async {
    if (_closing) return;
    _closing = true;
    await _controller.hangUp();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_changed);
    unawaited(_controller.hangUp());
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final assistantText = controller.transcript.items.whereType<AssistantChatItem>().lastOrNull?.text ?? '';
    return Scaffold(
      backgroundColor: const Color(0xFF071A2C),
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Text(controller.status, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white70)),
              if (controller.error case final error?)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
              Expanded(
                child: ListView(
                  children: [
                    for (final request in controller.transcript.pendingApprovals.values) _approvalCard(request),
                    for (final request in controller.transcript.pendingQuestions.values) _questionCard(request),
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 32),
                        child: GestureDetector(
                          onTap: controller.skipSpeech,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            width: controller.speaking || controller.listening ? 156 : 136,
                            height: controller.speaking || controller.listening ? 156 : 136,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(colors: controller.speaking
                                  ? const [Color(0xFF8ED8FF), Color(0xFF1769AA)]
                                  : const [Color(0xFF70C6E8), Color(0xFF123F68)]),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF4EB4E8).withValues(alpha: controller.listening || controller.speaking ? 0.55 : 0.2),
                                  blurRadius: 36,
                                  spreadRadius: 10,
                                ),
                              ],
                            ),
                            child: Icon(controller.speaking ? Icons.graphic_eq : Icons.mic, size: 54, color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                    if (controller.liveText.isNotEmpty)
                      Text(controller.liveText, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 18)),
                    if (controller.liveText.isEmpty && assistantText.isNotEmpty)
                      Text(
                        assistantText.length > 240 ? '…${assistantText.substring(assistantText.length - 240)}' : assistantText,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70, fontSize: 16),
                      ),
                  ],
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _CallButton(
                    icon: controller.muted ? Icons.mic_off : Icons.mic,
                    label: controller.muted ? '取消静音' : '静音',
                    onPressed: controller.toggleMute,
                  ),
                  _CallButton(icon: Icons.call_end, label: '挂断', color: Colors.red, onPressed: _endCall),
                  _CallButton(
                    icon: controller.speakerphone ? Icons.volume_up : Icons.phone_in_talk,
                    label: controller.speakerphone ? '免提' : '听筒',
                    onPressed: controller.toggleSpeakerphone,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _approvalCard(ApprovalRequest request) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('审批 · ${request.toolName}', style: const TextStyle(fontWeight: FontWeight.bold)),
            Text(request.describe('zh-CN')),
            OverflowBar(
              alignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => unawaited(_controller.respond(
                    request.eventId,
                    () => widget.client.respondApproval(request, ApprovalDecision.reject),
                  )),
                  child: const Text('拒绝'),
                ),
                FilledButton(
                  onPressed: () => unawaited(_controller.respond(
                    request.eventId,
                    () => widget.client.respondApproval(request, ApprovalDecision.allowOnce),
                  )),
                  child: const Text('仅允许本次'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _questionCard(UserQuestionRequest request) {
    return Card(
      child: ListTile(
        title: Text(request.questions.firstOrNull?.question ?? '主机请求输入'),
        trailing: Wrap(
          children: [
            TextButton(onPressed: () => unawaited(_controller.respond(request.eventId, () => widget.client.rejectQuestion(request))), child: const Text('拒绝回答')),
            FilledButton(onPressed: () => _answer(request), child: const Text('回答')),
          ],
        ),
      ),
    );
  }

  Future<void> _answer(UserQuestionRequest request) async {
    final controllers = {for (final question in request.questions) question.id: TextEditingController()};
    final answers = await showDialog<List<QuestionAnswer>>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('回答主机提问'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final question in request.questions)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextField(
                  controller: controllers[question.id],
                  maxLines: 2,
                  decoration: InputDecoration(labelText: question.question, border: const OutlineInputBorder()),
                ),
              ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.of(context).pop([
              for (final question in request.questions)
                QuestionAnswer(
                  question.id,
                  custom: controllers[question.id]!.text.trim().isEmpty ? null : controllers[question.id]!.text.trim(),
                ),
            ]),
            child: const Text('提交回答'),
          ),
        ],
      ),
    );
    for (final controller in controllers.values) {
      controller.dispose();
    }
    if (answers == null) return;
    await _controller.respond(request.eventId, () => widget.client.answerQuestion(request, answers));
  }
}

final class _CallButton extends StatelessWidget {
  const _CallButton({required this.icon, required this.label, required this.onPressed, this.color});

  final IconData icon;
  final String label;
  final Future<void> Function() onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FloatingActionButton(
          heroTag: label,
          backgroundColor: color ?? const Color(0xFF24445F),
          foregroundColor: Colors.white,
          onPressed: () => unawaited(onPressed()),
          child: Icon(icon),
        ),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(color: Colors.white70)),
      ],
    );
  }
}
