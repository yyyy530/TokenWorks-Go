import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:tokenworks_core/tokenworks_core.dart' show PkcePair;

final _sessionToken = RegExp(r'^[A-Za-z0-9_-]{43}$');
final iwanGuide = Uri.https('email.ustc.edu.cn', '/notice/iwan/');
final _modelsGateway = Uri.https('api.llm.ustc.edu.cn', '/v1/models');

Uri? configuredCampusOrigin() {
  const value = String.fromEnvironment('TOKENWORKS_CAMPUS_URL');
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.scheme != 'https' ||
      !uri.host.endsWith('.ustc.edu.cn') ||
      uri.userInfo.isNotEmpty ||
      (uri.path.isNotEmpty && uri.path != '/') ||
      uri.hasQuery ||
      uri.hasFragment) {
    return null;
  }
  return Uri.parse(uri.origin);
}

final class CampusLogin {
  const CampusLogin(this.id, this.authorizeUrl, this.verifier, this.expiresAt);

  final String id;
  final Uri authorizeUrl;
  final String verifier;
  final DateTime expiresAt;
}

final class CampusSession {
  const CampusSession(this.token, this.displayName, this.expiresAt);

  factory CampusSession.fromJson(Object? data) {
    if (data
        case {
          'session_token': final String token,
          'display_name': final String displayName,
          'expires_at': final String expires,
        }
        when _sessionToken.hasMatch(token) && displayName.trim().isNotEmpty) {
      final timestamp = DateTime.tryParse(expires);
      if (timestamp != null) {
        return CampusSession(token, displayName, timestamp);
      }
    }
    throw const FormatException('Invalid campus session');
  }

  final String token;
  final String displayName;
  final DateTime expiresAt;

  Map<String, Object?> toJson() => {
    'session_token': token,
    'display_name': displayName,
    'expires_at': expiresAt.toUtc().toIso8601String(),
  };
}

final class CampusCatalog {
  const CampusCatalog(this.status, this.models);

  factory CampusCatalog.fromJson(Object? data) {
    if (data case {
      'status': final String status,
      'models': final List<Object?> models,
    }) {
      if (models.every((entry) => entry is String && entry.trim().isNotEmpty)) {
        return CampusCatalog(
          status,
          List<String>.unmodifiable(models.cast<String>()),
        );
      }
    }
    throw const FormatException('Invalid school model catalog');
  }

  final String status;
  final List<String> models;
}

final class CampusException implements Exception {
  const CampusException(this.status);
  final int status;
}

enum CampusReachability { reachable, refused, unavailable }

final class CampusClient {
  const CampusClient(this.origin);

  final Uri origin;

  Future<CampusLogin> login() async {
    final pair = PkcePair.create();
    final data = await _json(
      '/v1/campus/login',
      method: 'POST',
      body: {'challenge': pair.challenge},
    );
    if (data
        case {
          'id': final String id,
          'authorize_url': final String browserUrl,
          'expires_in': final int timeout,
        }
        when _sessionToken.hasMatch(id) && timeout > 0 && timeout <= 300) {
      final browser = Uri.tryParse(browserUrl);
      if (browser != null &&
          browser.scheme == 'https' &&
          browser.hasAuthority &&
          browser.origin == origin.origin &&
          browser.path == '/v1/campus/authorize' &&
          browser.userInfo.isEmpty &&
          !browser.hasFragment) {
        return CampusLogin(
          id,
          browser,
          pair.verifier,
          DateTime.now().add(Duration(seconds: timeout)),
        );
      }
    }
    throw const FormatException('Invalid campus login');
  }

  Future<CampusSession?> complete(CampusLogin flow, String callbackCode) async {
    final data = await _json(
      '/v1/campus/complete',
      method: 'POST',
      body: {
        'id': flow.id,
        'verifier': flow.verifier,
        'callback_code': callbackCode,
      },
    );
    if (data case {'status': 'pending'}) return null;
    return CampusSession.fromJson(data);
  }

  Future<CampusCatalog> models(CampusSession session) async =>
      CampusCatalog.fromJson(
        await _json('/v1/campus/models', session: session),
      );

  Future<void> logout(CampusSession session) async {
    await _json('/v1/campus/logout', method: 'POST', session: session);
  }

  Future<String> ask(CampusSession session, String model, String prompt) async {
    final result = await _json(
      '/v1/campus/chat',
      method: 'POST',
      body: {'model': model, 'prompt': prompt},
      session: session,
      timeout: const Duration(seconds: 110),
    );
    if (result case {'content': final String content}
        when content.trim().isNotEmpty) {
      return content;
    }
    throw const FormatException('Invalid school model answer');
  }

  Future<Object?> _json(
    String path, {
    String method = 'GET',
    Map<String, Object?>? body,
    CampusSession? session,
    Duration timeout = const Duration(seconds: 38),
  }) async {
    final http = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    final deadline = Timer(timeout, () => http.close(force: true));
    try {
      final request = await http.openUrl(method, origin.replace(path: path));
      request.followRedirects = false;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (session != null) {
        request.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer ${session.token}',
        );
      }
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw CampusException(response.statusCode);
      }
      if (response.statusCode == 204) return null;
      if (response.headers.contentType?.mimeType != 'application/json') {
        throw const FormatException('Invalid campus response type');
      }
      final bytes = <int>[];
      await for (final chunk in response) {
        if (bytes.length + chunk.length > 256 * 1024) {
          throw const FormatException('Campus response too large');
        }
        bytes.addAll(chunk);
      }
      return jsonDecode(utf8.decode(bytes));
    } finally {
      deadline.cancel();
      http.close(force: true);
    }
  }
}

Future<CampusReachability> checkCampusGateway() async {
  final http = HttpClient()..connectionTimeout = const Duration(seconds: 6);
  try {
    final status = await (() async {
      final request = await http.getUrl(_modelsGateway);
      request.followRedirects = false;
      final response = await request.close();
      return response.statusCode;
    })().timeout(const Duration(seconds: 7));
    return switch (status) {
      200 || 401 => CampusReachability.reachable,
      403 => CampusReachability.refused,
      _ => CampusReachability.unavailable,
    };
  } on Exception {
    return CampusReachability.unavailable;
  } finally {
    http.close(force: true);
  }
}

class CampusPlatform {
  const CampusPlatform();

  static const _store = MethodChannel('tokenworks_go/campus_store');
  static const _navigation = MethodChannel('tokenworks_go/campus_navigation');

  Future<CampusSession?> read(Uri origin) async {
    final raw = await _store.invokeMethod<String>('read');
    if (raw == null) return null;
    if (jsonDecode(raw)
        case {
          'origin': final String savedOrigin,
          'session': final Object? session,
        }
        when savedOrigin == origin.origin) {
      return CampusSession.fromJson(session);
    }
    return null;
  }

  Future<void> save(Uri origin, CampusSession session) =>
      _store.invokeMethod<void>(
        'save',
        jsonEncode({'origin': origin.origin, 'session': session.toJson()}),
      );

  Future<void> clear() => _store.invokeMethod<void>('clear');

  Future<void> openBrowser(Uri url) =>
      _navigation.invokeMethod<void>('openHttps', url.toString());

  Future<bool> openVerifiedIwan() async =>
      await _navigation.invokeMethod<bool>('openIwan') ?? false;

  Future<String?> takeReturnCode(String loginId) async {
    final value = await _navigation.invokeMethod<String>('takeCampusReturn');
    final uri = value == null ? null : Uri.tryParse(value);
    if (uri == null ||
        uri.scheme != 'io.github.yyyy530.tokenworks-go' ||
        uri.authority != 'auth' ||
        uri.path != '/campus' ||
        uri.hasFragment ||
        uri.queryParametersAll['id']?.singleOrNull != loginId) {
      return null;
    }
    final code = uri.queryParametersAll['code']?.singleOrNull;
    return code != null && _sessionToken.hasMatch(code) ? code : null;
  }

  Future<void> openVpnSettings() =>
      _navigation.invokeMethod<void>('openVpnSettings');
}
