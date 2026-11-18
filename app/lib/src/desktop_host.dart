import 'dart:async';
import 'dart:convert';

import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/services.dart';
import 'package:tokenworks_core/tokenworks_core.dart'
    show HostKind, HostProfile, WorkspaceMode;

const maxDesktopFileBytes = 10 * 1024 * 1024;

final class DesktopCredentials {
  const DesktopCredentials(this.endpoint, this.cookie);

  factory DesktopCredentials.decode(String value) {
    if (jsonDecode(value) case {
      'endpoint': final String address,
      'cookie': final Map<String, Object?> fields,
    }) {
      final cookie = DshCookie.fromJson(fields);
      if (cookie.name.isNotEmpty && cookie.value.isNotEmpty) {
        return DesktopCredentials(desktopEndpoint(address), cookie);
      }
    }
    throw const FormatException('Invalid saved desktop login');
  }

  final Uri endpoint;
  final DshCookie cookie;

  String encode() =>
      jsonEncode({'endpoint': endpoint.toString(), 'cookie': cookie.toJson()});
}

Uri desktopEndpoint(String input) {
  final uri = Uri.parse(input.trim());
  if (uri.scheme != 'https') {
    throw const FormatException('请输入主机的 HTTPS 地址。');
  }
  final endpoint = uri.path == '/' ? uri.replace(path: '') : uri;
  HostProfile(
    id: endpoint.toString(),
    displayName: endpoint.host,
    kind: HostKind.remote,
    endpoint: endpoint,
  ).validate();
  return endpoint;
}

class DesktopStore {
  const DesktopStore();

  static const _channel = MethodChannel('tokenworks_go/desktop_store');

  Future<DesktopCredentials?> read() async {
    final value = await _channel.invokeMethod<String>('read');
    return value == null ? null : DesktopCredentials.decode(value);
  }

  Future<void> save(DesktopCredentials credentials) =>
      _channel.invokeMethod<void>('save', credentials.encode());

  Future<void> clear() => _channel.invokeMethod<void>('clear');
}

typedef DesktopConnector = Future<DesktopConnection> Function(
  Uri endpoint, {
  String? launchToken,
  DshCookie? cookie,
});

final class DesktopConnection {
  const DesktopConnection(this.client, this.sessions, this.cookie);

  final DshClient client;
  final List<SessionSummary> sessions;
  final DshCookie cookie;
}

Future<DesktopConnection> connectDesktop(
  Uri endpoint, {
  String? launchToken,
  DshCookie? cookie,
}) async {
  final connection = DshConnection(
    desktopEndpoint(endpoint.toString()),
    requestTimeout: const Duration(seconds: 20),
  );
  final client = DshClient(connection);
  try {
    if (launchToken != null) {
      await connection.login(launchToken);
    } else {
      if (cookie == null ||
          cookie.name.isEmpty ||
          cookie.value.isEmpty ||
          cookie.authority != connection.authority ||
          cookie.isExpiredAt(DateTime.now())) {
        throw const DshHttpException(401, 'Saved login expired');
      }
      connection.cookie = cookie;
    }
    // Check a real RPC before starting the reconnecting live stream.
    final sessions = await client.listSessions();
    await client.mux.ready(timeout: const Duration(seconds: 12));
    return DesktopConnection(client, sessions, connection.cookie!);
  } on Object {
    await client.close();
    rethrow;
  }
}

Future<List<WorkspaceMode>> availableTokenWorksModes(DshClient client) async {
  if (!client.supportsEndpoint('agentPresets/list')) return const [];
  try {
    final presets = await client.listAgentPresets().timeout(
      const Duration(seconds: 4),
    );
    final available = {
      for (final preset in presets)
        if (preset.broken == null) preset.id,
    };
    return [
      for (final mode in WorkspaceMode.values)
        if (available.contains(mode.id)) mode,
    ];
  } on DshException {
    return const [];
  } on TimeoutException {
    return const [];
  }
}

String desktopError(Object error) => switch (error) {
  DshHttpException(statusCode: 401) => '主机登录已失效，请使用新的启动令牌连接。',
  DshHttpException(statusCode: 403) => '主机拒绝了连接，请检查主机名和反向代理配置。',
  DshRemoteException(code: 'session/writer-held') => '会话正在由另一进程写入。',
  DshRemoteException(code: 'session/model-unavailable') => '主机当前无法使用该模型。',
  DshRemoteException(code: 'session/not-found') => '主机上找不到该会话。',
  DshRemoteException() => '主机拒绝了操作，请检查会话状态后重试。',
  DshProtocolException() => '主机响应与 DSH 协议不兼容。',
  DshTransportException() ||
  DshCarrierLostException() ||
  TimeoutException() => '暂时无法连接主机，请检查网络、HTTPS 证书和主机运行状态。',
  _ => '操作失败，请检查主机连接后重试。',
};
