import 'dart:convert';

import 'package:dsh_client/dsh_client.dart';

Future<UstcQuotaSnapshot?> loadUstcQuota(DshClient client) async {
  final carrier = client.carrier;
  if (carrier is! DshHttpCarrier || !carrier.connection.hasCookie) return null;

  final response = await carrier.connection.getBounded(
    '/plugins/dsh-ustc-quota/snapshot',
    maxBytes: 128 * 1024,
    autoUncompress: true,
    timeout: const Duration(seconds: 10),
  );
  if (response.statusCode == 404) return null;
  if (response.statusCode != 200) {
    throw DshHttpException(response.statusCode, 'Quota snapshot unavailable');
  }
  if (response.contentType != 'application/json') {
    throw const FormatException('Quota snapshot must be JSON');
  }
  return UstcQuotaSnapshot.fromJson(jsonDecode(response.text));
}

final class UstcQuotaSnapshot {
  const UstcQuotaSnapshot._(
    this.fromTokenWorks,
    this.waitingForLogin,
    this.generatedAt,
    this.accounts,
  );

  factory UstcQuotaSnapshot.fromJson(Object? json) {
    if (json case {'version': 1, 'keys': final List<Object?> accounts}) {
      final data = json as Map;
      final fromTokenWorks = data['source'] == 'tokenworks';
      final warnings = data['warnings'];
      return UstcQuotaSnapshot._(
        fromTokenWorks,
        fromTokenWorks &&
            warnings is List &&
            warnings.contains('tokenworks-not-ready'),
        _date(data['generatedAt']),
        List.unmodifiable(accounts.map(UstcQuotaAccount.fromJson)),
      );
    }
    throw const FormatException('Unsupported quota snapshot version');
  }

  final bool fromTokenWorks;
  final bool waitingForLogin;
  final DateTime? generatedAt;
  final List<UstcQuotaAccount> accounts;
}

final class UstcQuotaAccount {
  const UstcQuotaAccount._(
    this.label,
    this.available,
    this.stale,
    this.windows,
  );

  factory UstcQuotaAccount.fromJson(Object? json) {
    if (json case {
      'provider': final String provider,
      'windows': final List<Object?> windows,
    }) {
      final data = json as Map;
      final label = data['label'];
      return UstcQuotaAccount._(
        label is String && label.trim().isNotEmpty ? label : provider,
        data['ok'] == true,
        data['stale'] == true,
        List.unmodifiable(windows.map(UstcQuotaWindow.fromJson)),
      );
    }
    throw const FormatException('Invalid quota account');
  }

  final String label;
  final bool available;
  final bool stale;
  final List<UstcQuotaWindow> windows;
}

enum QuotaState { active, stale, resetting, unknown }

final class UstcQuotaWindow {
  const UstcQuotaWindow._(
    this.label,
    this.state,
    this.used,
    this.limit,
    this.resetsAt,
  );

  factory UstcQuotaWindow.fromJson(Object? json) {
    if (json case {'id': final String id}) {
      final data = json as Map;
      final state = switch (data['state']) {
        'active' => QuotaState.active,
        'stale' => QuotaState.stale,
        'resetting' => QuotaState.resetting,
        _ => QuotaState.unknown,
      };
      final hasUsage = state == QuotaState.active || state == QuotaState.stale;
      final limit = _nonnegative(data['limit']);
      return UstcQuotaWindow._(
        id,
        state,
        hasUsage ? _nonnegative(data['used']) : null,
        limit != null && limit > 0 ? limit : null,
        _date(data['resetAt']),
      );
    }
    throw const FormatException('Invalid quota window');
  }

  final String label;
  final QuotaState state;
  final double? used;
  final double? limit;
  final DateTime? resetsAt;

  double? get usedFraction {
    if (used == null || limit == null) return null;
    return (used! / limit!).clamp(0.0, 1.0);
  }

  double? get remaining {
    if (used == null || limit == null) return null;
    return (limit! - used!).clamp(0.0, limit!);
  }
}

DateTime? _date(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;

double? _nonnegative(Object? value) {
  if (value is! num) return null;
  final number = value.toDouble();
  return number.isFinite && number >= 0 ? number : null;
}
