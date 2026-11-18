import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/services.dart';

typedef LocalRuntimeAccess = ({Uri endpoint, String token});

final class LocalRuntimeStatus {
  const LocalRuntimeStatus(this.phase, {this.progress = 0, this.error});

  final String phase;
  final int progress;
  final String? error;

  bool get busy => switch (phase) {
    'installing' || 'starting' || 'stopping' => true,
    _ => false,
  };
}

final class LocalRuntimeChannel {
  const LocalRuntimeChannel();

  static const _channel = MethodChannel('tokenworks_go/local_runtime');

  Future<LocalRuntimeStatus> status() async {
    final data = await _channel.invokeMapMethod<String, Object?>('status');
    if (data case {
      'phase': final String phase,
      'progress': final int progress,
      'error': final String? error,
    }) {
      return LocalRuntimeStatus(phase, progress: progress, error: error);
    }
    throw const FormatException('Invalid local runtime status');
  }

  Future<void> start() => _channel.invokeMethod<void>('start');
  Future<void> stop() => _channel.invokeMethod<void>('stop');

  Future<LocalRuntimeAccess> connection() async {
    final data = await _channel.invokeMapMethod<String, String>('connect');
    if (data case {
      'endpoint': final String origin,
      'token': final String token,
    }) {
      return (endpoint: Uri.parse(origin), token: token);
    }
    throw const FormatException('Local runtime has no active connection');
  }

  Future<void> openWeb(Uri endpoint, DshCookie cookie) =>
      _channel.invokeMethod<void>('openWeb', {
        'endpoint': endpoint.toString(),
        'cookie': cookie.header,
      });
}
