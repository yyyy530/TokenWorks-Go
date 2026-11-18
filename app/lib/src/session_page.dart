import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:dsh_client/dsh_client.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'desktop_host.dart';
import 'workspace_page.dart';

final class SessionPage extends StatefulWidget {
  const SessionPage({
    required this.client,
    required this.sessionId,
    required this.title,
    super.key,
  });

  final DshClient client;
  final String sessionId;
  final String title;

  @override
  State<SessionPage> createState() => _SessionPageState();
}

final class _SessionPageState extends State<SessionPage> {
  final _composer = TextEditingController();
  final _random = Random.secure();
  final _responding = <String>{};
  ChatTranscript _transcript = ChatTranscript();
  StreamSubscription<DshEvent>? _subscription;
  SessionFollowEpoch? _epoch;
  ({String id, String text})? _pendingPrompt;
  ({String name, Uint8List bytes})? _attachment;
  String? _attachmentReceipt;
  bool _picking = false;
  bool _sending = false;
  bool _stopping = false;
  bool _loadingHistory = false;
  bool _following = false;
  String? _followError;
  String? _actionError;

  DshClient get _client => widget.client;
  String get _sessionId => widget.sessionId;

  bool get _ready =>
      _following &&
      _epoch?.isCurrent == true &&
      _client.mux.state == DshConnectionState.connected;

  @override
  void initState() {
    super.initState();
    _startWatch();
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    _composer.dispose();
    super.dispose();
  }

  void _startWatch() {
    _following = true;
    _followError = null;
    _subscription = _client
        .watch(
          _sessionId,
          options: WatchOptions(
            activate: true,
            activationAllowed: () => mounted && _following,
            includeSyncEvents: true,
          ),
        )
        .listen(
          (event) {
            if (!mounted) return;
            setState(() {
              switch (event) {
                case SessionSyncEvent():
                  _epoch = null;
                case SessionSnapshotEvent(:final followEpoch):
                  _epoch = followEpoch;
                default:
                  break;
              }
              _transcript.apply(event);
            });
          },
          onError: (Object error) {
            _finishWatch(desktopError(error));
          },
          onDone: () {
            _finishWatch(_followError ?? '会话已断开。');
          },
        );
  }

  void _finishWatch(String message) {
    if (!mounted) return;
    setState(() {
      _following = false;
      _epoch = null;
      _followError = message;
    });
  }

  void _retryWatch() {
    setState(() {
      _transcript = ChatTranscript();
      _startWatch();
    });
  }

  Future<void> _loadOlder() async {
    final transcript = _transcript;
    final epoch = _epoch;
    final oldest = transcript.oldestSeq;
    if (!_ready || _loadingHistory || oldest == null) return;
    setState(() {
      _loadingHistory = true;
      _actionError = null;
    });
    try {
      final page = await _client.history(
        _sessionId,
        throughSeq: transcript.cursor,
        beforeSeq: oldest,
        maxMessages: 100,
      );
      if (mounted && identical(epoch, _epoch) && _ready) {
        setState(() => transcript.prependHistory(page));
      }
    } on Exception catch (error) {
      if (mounted) setState(() => _actionError = desktopError(error));
    } finally {
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  String _newRequestId() {
    final bytes = List.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  Future<void> _send() async {
    if (!_ready ||
        _sending ||
        _picking ||
        (_composer.text.trim().isEmpty && _attachment == null)) {
      return;
    }
    final prompt =
        _pendingPrompt ?? (id: _newRequestId(), text: _composer.text);
    setState(() {
      _sending = true;
      _pendingPrompt = prompt;
      _actionError = null;
    });
    try {
      if (_attachment case final attachment? when _attachmentReceipt == null) {
        final receipt = await _client.uploadFile(
          _sessionId,
          attachment.bytes,
          name: attachment.name,
        );
        if (receipt.receiptId.isEmpty) {
          throw const DshProtocolException('Missing attachment receipt');
        }
        _attachmentReceipt = receipt.receiptId;
      }
      if (!mounted || !_ready) return;
      await _client.prompt(
        _sessionId,
        prompt.text,
        requestId: prompt.id,
        fileReceiptIds: [?_attachmentReceipt],
      );
      if (!mounted) return;
      _composer.clear();
      setState(() {
        _pendingPrompt = null;
        _attachment = null;
        _attachmentReceipt = null;
      });
    } on Exception catch (error) {
      if (mounted) {
        setState(() => _actionError = desktopError(error));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pickAttachment() async {
    if (_pendingPrompt != null || _picking) return;
    setState(() {
      _picking = true;
      _actionError = null;
    });
    try {
      final file = await FilePicker.pickFile();
      if (!mounted || file == null) return;
      if ((file.lengthSync() ?? 0) > maxDesktopFileBytes) {
        setState(() => _actionError = '附件上限为 10 MiB。');
        return;
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in file.readAsByteStream()) {
        if (!mounted) return;
        if (bytes.length + chunk.length > maxDesktopFileBytes) {
          setState(() => _actionError = '附件上限为 10 MiB。');
          return;
        }
        bytes.add(chunk);
      }
      if (mounted) {
        setState(
          () => _attachment = (name: file.name, bytes: bytes.takeBytes()),
        );
      }
    } on Exception {
      if (mounted) setState(() => _actionError = '无法打开选中的手机文件。');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _stop() async {
    if (!_ready || _stopping) return;
    setState(() {
      _stopping = true;
      _actionError = null;
    });
    try {
      await _client.cancel(_sessionId);
    } on Exception catch (error) {
      if (mounted) setState(() => _actionError = desktopError(error));
    } finally {
      if (mounted) setState(() => _stopping = false);
    }
  }

  Future<void> _respond(String eventId, Future<void> Function() reply) async {
    if (!_canRespond(eventId)) return;
    _responding.add(eventId);
    setState(() => _actionError = null);
    try {
      await reply();
      // The mux also broadcasts cancellation when another client answers.
      if (mounted) {
        setState(() => _transcript.apply(HostRequestCancelledEvent(eventId)));
      }
    } on Exception catch (error) {
      if (mounted) setState(() => _actionError = desktopError(error));
    } finally {
      if (mounted) setState(() => _responding.remove(eventId));
    }
  }

  bool _canRespond(String eventId) =>
      _ready &&
      !_responding.contains(eventId) &&
      _client.mux.pendingRequests.any(
        (event) => switch (event) {
          ApprovalRequestedEvent(:final request) => request.eventId == eventId,
          UserQuestionRequestedEvent(:final request) =>
            request.eventId == eventId,
          _ => false,
        },
      );

  Future<void> _answer(UserQuestionRequest request) async {
    final answers = await showDialog<List<QuestionAnswer>>(
      context: context,
      builder: (_) => _QuestionDialog(questions: request.questions),
    );
    if (!mounted ||
        answers == null ||
        !identical(_transcript.pendingQuestions[request.eventId], request)) {
      return;
    }
    await _respond(
      request.eventId,
      () => _client.answerQuestion(request, answers),
    );
  }

  @override
  Widget build(BuildContext context) {
    final transcript = _transcript;
    final notifications = [
      for (final request in transcript.pendingApprovals.values)
        _approvalCard(request),
      for (final request in transcript.pendingQuestions.values)
        _questionCard(request),
    ];
    final items = transcript.items;
    final inbox = transcript.inbox;
    return Scaffold(
      appBar: AppBar(
        title: Text(transcript.title ?? widget.title),
        actions: [
          IconButton(
            onPressed: _ready && _client.supportsEndpoint('workspaceFiles/list')
                ? () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) =>
                          WorkspacePage(client: _client, sessionId: _sessionId),
                    ),
                  )
                : null,
            icon: const Icon(Icons.folder_outlined),
            tooltip: '工作区文件',
          ),
          if (transcript.running || inbox.isNotEmpty)
            IconButton(
              onPressed: _ready && !_stopping ? _stop : null,
              icon: const Icon(Icons.stop_circle_outlined),
              tooltip: '停止当前回复',
            ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 840),
            child: Column(
              children: [
                if (!_ready) _connectionBanner(),
                Expanded(
                  child: ListView.builder(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    reverse: true,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    itemCount:
                        notifications.length +
                        inbox.length +
                        items.length +
                        (_ready && transcript.hasMoreHistory ? 1 : 0),
                    itemBuilder: (_, index) {
                      if (index < notifications.length) {
                        return notifications[notifications.length - 1 - index];
                      }
                      final messageIndex = index - notifications.length;
                      if (messageIndex < inbox.length) {
                        final prompt = inbox[inbox.length - 1 - messageIndex];
                        return _MessageCard(
                          label: '已排队',
                          text: prompt.text,
                          outgoing: true,
                        );
                      }
                      final itemIndex =
                          items.length - 1 - (messageIndex - inbox.length);
                      if (itemIndex >= 0) return _chatItem(items[itemIndex]);
                      return Center(
                        child: TextButton(
                          onPressed: _loadingHistory ? null : _loadOlder,
                          child: Text(_loadingHistory ? '加载中…' : '加载更早的消息'),
                        ),
                      );
                    },
                  ),
                ),
                if (_actionError case final error?)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      error,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                _composerBar(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _connectionBanner() {
    final unauthorized = _client.mux.state == DshConnectionState.unauthorized;
    if (unauthorized) {
      return const ListTile(title: Text('主机登录已失效，请返回首页重新连接。'));
    }
    if (_followError case final error?) {
      return ListTile(
        title: Text(error),
        trailing: TextButton(onPressed: _retryWatch, child: const Text('重连')),
      );
    }
    return const ListTile(
      leading: SizedBox.square(
        dimension: 20,
        child: CircularProgressIndicator(),
      ),
      title: Text('正在同步会话…'),
    );
  }

  Widget _composerBar() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
    child: Column(
      children: [
        if (_attachment case final attachment?)
          Align(
            alignment: Alignment.centerLeft,
            child: InputChip(
              label: Text(attachment.name, overflow: TextOverflow.ellipsis),
              onDeleted: _pendingPrompt != null || _picking
                  ? null
                  : () => setState(() => _attachment = null),
            ),
          ),
        if (_pendingPrompt != null && !_sending)
          Row(
            children: [
              const Expanded(child: Text('发送状态待确认')),
              TextButton(
                onPressed: () => setState(() {
                  _composer.clear();
                  _pendingPrompt = null;
                  _attachment = null;
                  _attachmentReceipt = null;
                  _actionError = null;
                }),
                child: const Text('清除草稿'),
              ),
            ],
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            IconButton(
              onPressed:
                  _ready &&
                      !_picking &&
                      _pendingPrompt == null &&
                      _client.supportsEndpoint('fileUploads/upload')
                  ? _pickAttachment
                  : null,
              tooltip: '添加附件',
              icon: const Icon(Icons.attach_file),
            ),
            Expanded(
              child: TextField(
                controller: _composer,
                readOnly: _pendingPrompt != null,
                minLines: 1,
                maxLines: 5,
                decoration: const InputDecoration(
                  hintText: '输入消息',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _ready && !_sending && !_picking ? _send : null,
              tooltip: _pendingPrompt == null ? '发送' : '重试发送',
              icon: Icon(_pendingPrompt == null ? Icons.send : Icons.refresh),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _approvalCard(ApprovalRequest request) {
    final tool = _transcript.items
        .whereType<ToolChatItem>()
        .where((item) => item.callId == request.callId)
        .firstOrNull;
    final enabled = _canRespond(request.eventId);
    return Card(
      key: ValueKey(request.eventId),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '审批 · ${request.toolName}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            SelectableText(request.describe('zh-CN')),
            if (tool != null && tool.arguments.isNotEmpty)
              SelectableText(tool.arguments),
            OverflowBar(
              alignment: MainAxisAlignment.end,
              spacing: 8,
              children: [
                TextButton(
                  onPressed: enabled
                      ? () => _respond(
                          request.eventId,
                          () => _client.respondApproval(
                            request,
                            ApprovalDecision.reject,
                          ),
                        )
                      : null,
                  child: const Text('拒绝'),
                ),
                FilledButton(
                  onPressed: enabled
                      ? () => _respond(
                          request.eventId,
                          () => _client.respondApproval(
                            request,
                            ApprovalDecision.allowOnce,
                          ),
                        )
                      : null,
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
    final enabled = _canRespond(request.eventId);
    return Card(
      key: ValueKey(request.eventId),
      child: ListTile(
        title: Text(request.questions.firstOrNull?.question ?? '主机请求输入'),
        trailing: Wrap(
          children: [
            TextButton(
              onPressed: enabled
                  ? () => _respond(
                      request.eventId,
                      () => _client.rejectQuestion(request),
                    )
                  : null,
              child: const Text('拒绝回答'),
            ),
            FilledButton(
              onPressed: enabled && request.questions.isNotEmpty
                  ? () => _answer(request)
                  : null,
              child: const Text('回答'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chatItem(ChatItem item) {
    final key = ValueKey(item.key);
    return switch (item) {
      UserChatItem() => _MessageCard(
        key: key,
        label: '你',
        text: [
          item.text,
          for (final file in item.files) ?file.name,
          if (item.images.isNotEmpty) '图片 × ${item.images.length}',
        ].where((text) => text.isNotEmpty).join('\n'),
        outgoing: true,
      ),
      AssistantChatItem() => _MessageCard(
        key: key,
        label: item.streaming ? '助手 · 回复中' : '助手',
        text: item.text,
      ),
      ToolChatItem() => Card(
        key: key,
        child: ExpansionTile(
          title: Text(item.name),
          subtitle: Text(switch (item.status) {
            ToolStatus.streaming => '正在生成参数',
            ToolStatus.running => '运行中',
            ToolStatus.awaitingApproval => '等待审批',
            ToolStatus.succeeded => '已完成',
            ToolStatus.failed => '失败',
            ToolStatus.denied => '未获允许',
            ToolStatus.cancelled => '已取消',
          }),
          children: [
            if (item.arguments.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(12),
                child: SelectableText(item.arguments),
              ),
            if (item.resultText.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(12),
                child: SelectableText(item.resultText),
              ),
          ],
        ),
      ),
      NoticeChatItem() => _MessageCard(
        key: key,
        label: '会话状态',
        text: item.text,
      ),
    };
  }
}

final class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.label,
    required this.text,
    this.outgoing = false,
    super.key,
  });

  final String label;
  final String text;
  final bool outgoing;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Align(
      alignment: outgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: Card(
        elevation: 0,
        color: outgoing ? colors.primaryContainer : colors.surfaceContainer,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: Theme.of(context).textTheme.labelMedium),
              if (text.isNotEmpty) SelectableText(text),
            ],
          ),
        ),
      ),
    );
  }
}

final class _QuestionDialog extends StatefulWidget {
  const _QuestionDialog({required this.questions});

  final List<UserQuestion> questions;

  @override
  State<_QuestionDialog> createState() => _QuestionDialogState();
}

final class _QuestionDialogState extends State<_QuestionDialog> {
  final _selected = <String, Set<String>>{};
  final _custom = <String, String>{};

  bool get _complete => widget.questions.every(
    (question) =>
        (_selected[question.id]?.isNotEmpty ?? false) ||
        (_custom[question.id]?.trim().isNotEmpty ?? false),
  );

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('回答主机提问'),
    scrollable: true,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final question in widget.questions) ...[
          Text(
            question.question,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          if (question.detail case final detail?) SelectableText(detail),
          for (final option in question.options)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(option.label),
              subtitle: option.description == null
                  ? null
                  : Text(option.description!),
              value: _selected[question.id]?.contains(option.label) ?? false,
              onChanged: (checked) => setState(() {
                final selected = _selected.putIfAbsent(question.id, () => {});
                if (checked == true) {
                  if (!question.multiSelect) selected.clear();
                  selected.add(option.label);
                } else {
                  selected.remove(option.label);
                }
              }),
            ),
          TextField(
            maxLines: 3,
            minLines: 1,
            decoration: InputDecoration(
              labelText: question.options.isEmpty ? '答案' : '自定义答案',
            ),
            onChanged: (text) => setState(() => _custom[question.id] = text),
          ),
          const SizedBox(height: 16),
        ],
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: _complete
            ? () => Navigator.pop(context, [
                for (final question in widget.questions)
                  QuestionAnswer(
                    question.id,
                    selected:
                        !question.multiSelect &&
                            (_custom[question.id]?.trim().isNotEmpty ?? false)
                        ? const []
                        : _selected[question.id]?.toList() ?? const [],
                    custom: switch (_custom[question.id]?.trim()) {
                      final String text when text.isNotEmpty => text,
                      _ => null,
                    },
                  ),
              ])
            : null,
        child: const Text('提交回答'),
      ),
    ],
  );
}
