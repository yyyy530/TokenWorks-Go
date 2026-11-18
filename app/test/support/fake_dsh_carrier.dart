import 'dart:async';

import 'package:dsh_client/dsh_client.dart';

/// Small RPC carrier for app feature tests. Handlers receive the RPC args and
/// return the value wrapped in `RpcOk`, or a complete `RpcResult`.
final class FakeDshCarrier extends DshCarrier {
  final handlers = <String, Object? Function(Map<String, Object?> args)>{};
  final calls = <String, List<Map<String, Object?>>>{};
  late FakeMuxLink link;
  bool closed = false;

  @override
  String get kind => 'app-test';

  @override
  DshTracer? get tracer => null;

  Future<DshClient> connect() => DshClient.connectCarrier(
    this,
    muxOptions: const MuxOptions(retryCaps: [Duration(milliseconds: 50)]),
  );

  @override
  Future<RpcResult> call(
    String endpoint,
    Map<String, Object?> args, {
    Duration? timeout,
  }) async {
    calls.putIfAbsent(endpoint, () => []).add(args);
    final handler = handlers[endpoint];
    if (handler == null) {
      return RpcError(DshRemoteException('gateway/not-found', 'No fixture for $endpoint'));
    }
    final result = handler(args);
    return result is RpcResult ? result : RpcOk(result);
  }

  @override
  Future<DshMuxLink> openLink(MuxOptions options) async => link = FakeMuxLink();

  @override
  Future<void> close() async => closed = true;
}

final class FakeMuxLink extends DshMuxLink {
  late DshMuxFrameHandler _onFrame;
  late DshMuxLossHandler _onLost;
  String? _events;
  String? _follow;
  String? sessionId;

  @override
  void start({required DshMuxFrameHandler onFrame, required DshMuxLossHandler onLost}) {
    _onFrame = onFrame;
    _onLost = onLost;
  }

  @override
  void open(String streamId, String endpoint, Map<String, Object?> payload) {
    if (endpoint == r'$events') {
      _events = streamId;
      _send(_events!, {'type': 'ready', 'clientId': 'app-test'});
    } else if (endpoint == 'session/follow') {
      _follow = streamId;
      final args = payload['args'] as Map;
      sessionId = ((args['request'] as Map)['address'] as Map)['sessionId'] as String?;
      follow({
        'type': 'snapshot',
        'header': {'id': sessionId, 'version': 4, 'createdAt': 1000},
        'cursor': -1,
        'records': <Object?>[],
        'hasMore': false,
        'projections': {'values': <String, Object?>{}},
        'assistantStream': {'revision': 0},
      });
    }
  }

  void follow(Map<String, Object?> value) => _send(_follow!, value);

  void request(String event, String eventId, Map<String, Object?> request) => _send(_events!, {
    'type': 'waterfall',
    'event': event,
    'eventId': eventId,
    'agentId': sessionId,
    'request': request,
  });

  void drop() => _onLost(const DshCarrierLostException('Fixture disconnect'), null);

  void _send(String id, Map<String, Object?> value) {
    scheduleMicrotask(() => _onFrame({'type': 'item', 'streamId': id, 'value': value}));
  }

  @override
  void cancel(String streamId) {}

  @override
  void sendItem(String streamId, Object? value) {}

  @override
  void endUplink(String streamId) {}

  @override
  Future<void> close(int code, String reason) async {}
}
