import 'dart:async';
import 'dart:typed_data';

import 'package:dsh_client/dsh_client.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tokenworks_core/tokenworks_core.dart' show WorkspaceMode;
import 'package:tokenworks_go/main.dart';
import 'package:tokenworks_go/src/desktop_host.dart';

void main() {
  testWidgets('rejects addresses that can expose credentials', (tester) async {
    final host = _Host();
    await tester.pumpWidget(
      TokenWorksGoApp(store: _Store(), connect: host.connect),
    );
    await tester.pumpAndSettle();

    for (final address in [
      'http://desktop.example',
      'https://desktop.example/?token=secret',
      'https://user@desktop.example',
    ]) {
      await tester.enterText(find.byType(TextField).first, address);
      await tester.tap(find.text('连接'));
      await tester.pumpAndSettle();
      expect(find.textContaining('请输入有效的 HTTPS'), findsOneWidget);
    }
    expect(host.endpoints, isEmpty);
  });

  testWidgets(
    'desktop flow selects model, retries prompt, handles live events and disconnects',
    (tester) async {
      final store = _Store();
      final host = _Host();
      await tester.pumpWidget(
        TokenWorksGoApp(store: store, connect: host.connect),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).first,
        'https://desktop.example/',
      );
      await tester.enterText(find.byType(TextField).last, 'test-launch-token');
      await tester.tap(find.text('连接'));
      await tester.pumpAndSettle();

      expect(host.endpoints.single.toString(), 'https://desktop.example');
      expect(store.saved?.cookie, same(host.cookie));
      expect(store.saved?.encode(), isNot(contains('test-launch-token')));
      expect(find.text('最近会话'), findsOneWidget);

      await tester.tap(find.text('新建会话'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '创建'))
            .onPressed,
        isNull,
      );
      await tester.tap(find.byType(DropdownButtonFormField<ModelInfo>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('可用模型（fixture）').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<WorkspaceMode>));
      await tester.pumpAndSettle();
      expect(find.text('教学模式'), findsNothing);
      await tester.tap(find.text('科研模式').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '/projects/report');
      await tester.tap(find.text('创建'));
      await tester.pumpAndSettle();

      expect(host.calls['session/create']?.single['request'], {
        'cwd': '/projects/report',
        'agentPreset': 'tw-research',
      });
      expect(host.calls['session/selectModel']?.single['request'], {
        'sessionId': 'new-session',
        'provider': 'fixture',
        'model': 'selected',
      });
      await tester.enterText(find.byType(TextField), '整理报告');
      await tester.tap(find.byTooltip('发送'));
      await tester.pumpAndSettle();
      expect(find.text('发送状态待确认'), findsOneWidget);
      await tester.tap(find.byTooltip('重试发送'));
      await tester.pumpAndSettle();
      final attempts = host.calls['session/prompt']!;
      expect(attempts, hasLength(2));
      expect(attempts[0], attempts[1]);

      host.link.follow({
        'type': 'assistant-stream',
        'frame': {
          'type': 'start',
          'attemptId': 'draft',
          'revision': 1,
          'turn': 1,
          'step': 1,
        },
      });
      host.link.follow({
        'type': 'assistant-stream',
        'frame': {
          'type': 'chunk',
          'attemptId': 'draft',
          'revision': 2,
          'index': 0,
          'chunk': {'type': 'text-delta', 'index': 0, 'text': '整理中'},
        },
      });
      await tester.pumpAndSettle();
      expect(find.text('整理中'), findsOneWidget);

      host.link.request('approval/request', 'approval-1', {
        'toolName': 'read_file',
        'reason': '读取报告',
      });
      await tester.pumpAndSettle();
      expect(find.text('读取报告'), findsOneWidget);
      await tester.tap(find.text('仅允许本次'));
      await tester.pumpAndSettle();
      expect(host.calls[r'$events/result']?.first['outcome'], {
        'kind': 'result',
        'value': 'allowed-once',
      });
      expect(find.text('仅允许本次'), findsNothing);

      host.link.request('user-questions/request', 'question-1', {
        'questions': [
          {'id': 'format', 'question': '输出格式？'},
        ],
      });
      await tester.pumpAndSettle();
      await tester.tap(find.text('回答'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Markdown');
      await tester.pump();
      await tester.tap(find.text('提交回答'));
      await tester.pumpAndSettle();
      expect(host.calls[r'$events/result']?.last['outcome'], {
        'kind': 'result',
        'value': {
          'answers': [
            {'id': 'format', 'selected': <String>[], 'custom': 'Markdown'},
          ],
        },
      });
      expect(find.text('输出格式？'), findsNothing);

      host.link.follow({
        'type': 'event',
        'event': {
          'seq': 0,
          'type': 'turn/start',
          'time': 500,
          'data': {'turn': 1},
        },
      });
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('停止当前回复'));
      await tester.pumpAndSettle();
      expect(host.calls['session/cancel']?.single['request'], {
        'sessionId': 'new-session',
      });

      final oldLink = host.link;
      oldLink.drop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();
      expect(host.link, isNot(same(oldLink)));
      expect(host.link.sessionId, 'new-session');

      final originalPicker = FilePickerPlatform.instance;
      final picker = _DocumentPicker();
      FilePickerPlatform.instance = picker;
      addTearDown(() => FilePickerPlatform.instance = originalPicker);
      await tester.tap(find.byTooltip('添加附件'));
      await tester.pumpAndSettle();
      expect(find.text('mobile.txt'), findsOneWidget);
      await tester.tap(find.byTooltip('发送'));
      await tester.pumpAndSettle();
      expect(host.calls['fileUploads/upload']?.single['request'], {
        'data': 'YWJj',
        'name': 'mobile.txt',
      });
      expect(
        (host.calls['session/prompt']?.last['request'] as Map)['content'],
        [
          {'type': 'file', 'receiptId': 'receipt-1'},
        ],
      );

      await tester.tap(find.byTooltip('工作区文件'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('report.txt'));
      await tester.pumpAndSettle();
      expect(find.text('报告内容'), findsOneWidget);
      expect(host.calls['workspaceFiles/read']?.single['path'], 'report.txt');
      await tester.tap(find.byTooltip('下载文件'));
      await tester.pumpAndSettle();
      expect(picker.savedName, 'report.txt');
      expect(picker.savedBytes, [97, 98, 99]);
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('断开并清除登录'));
      await tester.pumpAndSettle();
      expect(store.saved, isNull);
      expect(host.closed, isTrue);
      expect(find.text('最近会话'), findsNothing);
    },
  );

  testWidgets('restores a saved credential only for its saved endpoint', (
    tester,
  ) async {
    final host = _Host();
    final endpoint = Uri.parse('https://desktop.example');
    final store = _Store()..saved = DesktopCredentials(endpoint, host.cookie);
    await tester.pumpWidget(
      TokenWorksGoApp(store: store, connect: host.connect),
    );
    await tester.pumpAndSettle();

    expect(host.endpoints, [endpoint]);
    expect(host.restored, same(host.cookie));
    expect(find.text('最近会话'), findsOneWidget);
    await tester.tap(find.text('断开并清除登录'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(store.saved, isNull);
    expect(host.closed, isTrue);
    expect(find.text('连接桌面主机'), findsOneWidget);
  });
}

final class _Store extends DesktopStore {
  DesktopCredentials? saved;

  @override
  Future<DesktopCredentials?> read() async => saved;

  @override
  Future<void> save(DesktopCredentials credentials) async =>
      saved = credentials;

  @override
  Future<void> clear() async => saved = null;
}

final class _Host extends DshCarrier {
  final endpoints = <Uri>[];
  final calls = <String, List<Map<String, Object?>>>{};
  final cookie = const DshCookie(
    name: 'dsh-auth-test',
    value: 'v1.fake.cookie',
    authority: 'desktop.example',
  );
  DshCookie? restored;
  late _Link link;
  bool closed = false;
  int _generation = 0;

  @override
  String get kind => 'fixture';

  @override
  DshTracer? get tracer => null;

  Future<DesktopConnection> connect(
    Uri endpoint, {
    String? launchToken,
    DshCookie? cookie,
  }) async {
    endpoints.add(endpoint);
    restored = cookie;
    final client = await DshClient.connectCarrier(
      this,
      muxOptions: const MuxOptions(retryCaps: [Duration(milliseconds: 50)]),
    );
    return DesktopConnection(client, await client.listSessions(), this.cookie);
  }

  @override
  Future<RpcResult> call(
    String endpoint,
    Map<String, Object?> args, {
    Duration? timeout,
  }) async {
    final attempts = calls.putIfAbsent(endpoint, () => [])..add(args);
    if (endpoint == 'session/prompt' && attempts.length == 1) {
      throw const DshTransportException('Fixture drops the acknowledgement');
    }
    return switch (endpoint) {
      'session/list' => const RpcOk({
        'items': [
          {
            'sessionId': 'existing',
            'projections': {
              'values': {'title': '最近会话'},
            },
          },
        ],
      }),
      'session/modelCatalog' => const RpcOk({
        'groups': [
          {
            'id': 'fixture',
            'models': [
              {'id': 'selected', 'name': '可用模型'},
            ],
          },
        ],
      }),
      'agentPresets/list' => const RpcOk({
        'presets': [
          {'id': 'standard'},
          {'id': 'tw-research'},
          {'id': 'tw-teach', 'broken': 'Unavailable'},
        ],
      }),
      'session/create' => const RpcOk({
        'sessionId': 'new-session',
        'agentPreset': 'tw-research',
      }),
      'session/selectModel' => const RpcOk({
        'selected': {'provider': 'fixture', 'model': 'selected'},
      }),
      'fileUploads/upload' => const RpcOk({
        'receiptId': 'receipt-1',
        'file': {'name': 'mobile.txt'},
      }),
      'workspaceFiles/list' => const RpcOk({
        'entries': [
          {'type': 'file', 'name': 'report.txt', 'size': 3},
        ],
      }),
      'workspaceFiles/read' => const RpcOk({
        'offset': 1,
        'lines': 1,
        'text': '报告内容',
        'eof': true,
      }),
      'workspaceFiles/stat' => const RpcOk({'version': 'v1', 'bytes': 3}),
      'workspaceFiles/readBytes' => const RpcOk({
        'version': 'v1',
        'data': 'YWJj',
        'eof': true,
        'bytes': 3,
      }),
      'session/prompt' ||
      'session/cancel' ||
      r'$events/result' => const RpcOk(null),
      _ => const RpcError(
        DshRemoteException(
          'gateway/not-found',
          'Fixture does not implement this endpoint',
        ),
      ),
    };
  }

  @override
  Future<DshMuxLink> openLink(MuxOptions options) async =>
      link = _Link(++_generation);

  @override
  Future<void> close() async => closed = true;
}

final class _DocumentPicker extends FilePickerPlatform {
  String? savedName;
  Uint8List? savedBytes;

  @override
  Future<PlatformFile?> pickFile({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    dynamic Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async => _Document();

  @override
  Future<Uri?> saveFile({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    String? dialogTitle,
    String? initialDirectory,
    dynamic Function(FilePickerStatus)? onFileSaving,
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    savedName = fileName;
    savedBytes = bytes;
    return Uri.parse('content://fixture/report.txt');
  }
}

final class _Document extends PlatformFile {
  @override
  String get name => 'mobile.txt';

  @override
  Uri get uri => Uri.parse('content://fixture/mobile.txt');

  @override
  Never get xFile => throw UnsupportedError('Fixture uses byte streams');

  @override
  int lengthSync() => 3;

  @override
  Future<int> length() async => lengthSync();

  @override
  Future<Uint8List> readAsBytes() async => Uint8List.fromList([97, 98, 99]);

  @override
  Stream<Uint8List> readAsByteStream() async* {
    yield await readAsBytes();
  }
}

final class _Link extends DshMuxLink {
  _Link(this.generation);

  final int generation;
  late DshMuxFrameHandler _onFrame;
  late DshMuxLossHandler _onLost;
  late String _events;
  late String _follow;
  String? sessionId;

  @override
  void start({
    required DshMuxFrameHandler onFrame,
    required DshMuxLossHandler onLost,
  }) {
    _onFrame = onFrame;
    _onLost = onLost;
  }

  @override
  void open(String streamId, String endpoint, Map<String, Object?> payload) {
    if (endpoint == r'$events') {
      _events = streamId;
      _send(_events, {'type': 'ready', 'clientId': 'mobile-$generation'});
    } else if (endpoint == 'session/follow') {
      _follow = streamId;
      final args = payload['args'] as Map;
      sessionId =
          ((args['request'] as Map)['address'] as Map)['sessionId'] as String?;
      follow({
        'type': 'snapshot',
        'header': {'id': sessionId, 'version': 4, 'createdAt': 1000},
        'cursor': generation == 1 ? -1 : 0,
        'records': <Object?>[],
        'hasMore': false,
        'projections': {'values': <String, Object?>{}},
        'assistantStream': {'revision': 0},
      });
    }
  }

  void follow(Map<String, Object?> value) => _send(_follow, value);

  void request(String event, String eventId, Map<String, Object?> request) =>
      _send(_events, {
        'type': 'waterfall',
        'event': event,
        'eventId': eventId,
        'agentId': sessionId,
        'request': request,
      });

  void _send(String id, Map<String, Object?> value) {
    scheduleMicrotask(
      () => _onFrame({'type': 'item', 'streamId': id, 'value': value}),
    );
  }

  void drop() =>
      _onLost(const DshCarrierLostException('Fixture disconnect'), null);

  @override
  void cancel(String streamId) {}

  @override
  void sendItem(String streamId, Object? value) {}

  @override
  void endUplink(String streamId) {}

  @override
  Future<void> close(int code, String reason) async {}
}
