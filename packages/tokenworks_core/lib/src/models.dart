import 'package:meta/meta.dart';

enum WorkspaceMode {
  standard('tw-standard', '标准'),
  research('tw-research', '科研'),
  teaching('tw-teach', '教学'),
  study('tw-study', '学习');

  const WorkspaceMode(this.id, this.label);
  final String id;
  final String label;

  static WorkspaceMode fromId(String id) => values.firstWhere(
        (mode) => mode.id == id,
        orElse: () => throw FormatException('Unknown TokenWorks mode: $id'),
      );
}

enum HostKind { local, remote }

enum NetworkScope { campus, tunnel, external, unknown }

enum PermissionLevel { readOnly, workspaceWrite, fullAccess }

enum ConnectionStatus { disconnected, connecting, connected, failed }

enum AuthStatus { signedOut, awaitingCallback, authenticated, expired }

@immutable
final class SchoolModel {
  const SchoolModel({
    required this.id,
    required this.displayName,
    required this.contextWindow,
    required this.maxOutput,
    this.supportsImages = false,
    this.reasoningLevels = const <String>[],
    this.audience,
  });

  final String id;
  final String displayName;
  final int contextWindow;
  final int maxOutput;
  final bool supportsImages;
  final List<String> reasoningLevels;
  final String? audience;

  void validate() {
    if (id.trim().isEmpty) throw const FormatException('Model id is empty');
    if (contextWindow <= 0 || maxOutput <= 0) {
      throw const FormatException('Model token limits must be positive');
    }
    if (maxOutput > contextWindow) {
      throw const FormatException('maxOutput exceeds contextWindow');
    }
  }

  static SchoolModel fromJson(Map<String, Object?> json) {
    final model = SchoolModel(
      id: json['id'] as String,
      displayName: json['displayName'] as String? ?? json['id']! as String,
      contextWindow: json['contextWindow'] as int,
      maxOutput: json['maxOutput'] as int,
      supportsImages: json['supportsImages'] as bool? ?? false,
      reasoningLevels: List<String>.unmodifiable(
        (json['reasoningLevels'] as List<Object?>? ?? const <Object?>[])
            .map((level) => level as String),
      ),
      audience: json['audience'] as String?,
    );
    model.validate();
    return model;
  }
}

@immutable
final class QuotaWindow {
  const QuotaWindow({
    required this.id,
    required this.remaining,
    required this.limit,
    required this.resetsAt,
  });

  final String id;
  final double remaining;
  final double limit;
  final DateTime resetsAt;

  double get fraction => limit <= 0 ? 0 : (remaining / limit).clamp(0, 1);
  bool get isLow => fraction <= .2;

  void validate() {
    if (!remaining.isFinite || !limit.isFinite ||
        remaining < 0 || limit <= 0 || remaining > limit) {
      throw const FormatException('Invalid quota values');
    }
  }
}

@immutable
final class HostProfile {
  const HostProfile({
    required this.id,
    required this.displayName,
    required this.kind,
    required this.endpoint,
    this.campusNetwork = NetworkScope.unknown,
  });

  final String id;
  final String displayName;
  final HostKind kind;
  final Uri endpoint;
  final NetworkScope campusNetwork;

  void validate() {
    if (id.trim().isEmpty || displayName.trim().isEmpty) {
      throw const FormatException('Host id and name are required');
    }
    if (!endpoint.hasScheme || endpoint.host.isEmpty) {
      throw const FormatException('Host endpoint must be absolute');
    }
    final isLoopback =
        endpoint.host == '127.0.0.1' || endpoint.host == 'localhost' || endpoint.host == '::1';
    if (endpoint.scheme != 'https' && !isLoopback) {
      throw const FormatException('Remote hosts require HTTPS');
    }
    if (kind == HostKind.remote && isLoopback) {
      throw const FormatException('A remote host cannot use a phone-loopback endpoint');
    }
    if (endpoint.userInfo.isNotEmpty || endpoint.hasQuery || endpoint.hasFragment) {
      throw const FormatException('Host endpoint cannot contain credentials, query or fragment');
    }
    final normalizedPath = endpoint.path;
    if (normalizedPath.isNotEmpty && normalizedPath != '/' &&
        (normalizedPath.contains('..') || normalizedPath.endsWith('/'))) {
      throw const FormatException('Host endpoint must be an origin or normalized path prefix');
    }
  }
}

@immutable
final class SessionSummary {
  const SessionSummary({
    required this.id,
    required this.title,
    required this.workspace,
    required this.mode,
    required this.updatedAt,
    this.isRunning = false,
    this.needsAttention = false,
  });

  final String id;
  final String title;
  final String workspace;
  final WorkspaceMode mode;
  final DateTime updatedAt;
  final bool isRunning;
  final bool needsAttention;
}

@immutable
final class AccountSnapshot {
  const AccountSnapshot({
    required this.displayName,
    required this.models,
    required this.quotas,
    required this.network,
  });

  final String displayName;
  final List<SchoolModel> models;
  final List<QuotaWindow> quotas;
  final NetworkScope network;

  void validate() {
    for (final model in models) {
      model.validate();
    }
    for (final quota in quotas) {
      quota.validate();
    }
    final ids = models.map((model) => model.id).toSet();
    if (ids.length != models.length) {
      throw const FormatException('Duplicate model ids');
    }
    final quotaIds = quotas.map((quota) => quota.id).toSet();
    if (quotaIds.length != quotas.length) {
      throw const FormatException('Duplicate quota window ids');
    }
  }

  static AccountSnapshot fromJson(Map<String, Object?> json) {
    final snapshot = AccountSnapshot(
      displayName: json['displayName'] as String,
      models: List<SchoolModel>.unmodifiable(
        (json['models'] as List<Object?>? ?? const <Object?>[])
            .map((model) => SchoolModel.fromJson((model as Map).cast<String, Object?>())),
      ),
      quotas: List<QuotaWindow>.unmodifiable(
        (json['quotas'] as List<Object?>? ?? const <Object?>[]).map((item) {
          final quota = (item as Map).cast<String, Object?>();
          final resetsAt = DateTime.tryParse(quota['resetsAt'] as String? ?? '');
          if (resetsAt == null) throw const FormatException('Invalid quota reset time');
          return QuotaWindow(
            id: quota['id'] as String,
            remaining: quota['remaining'] as double,
            limit: quota['limit'] as double,
            resetsAt: resetsAt,
          );
        }),
      ),
      network: NetworkScope.values.asNameMap()[json['network']] ?? NetworkScope.unknown,
    );
    snapshot.validate();
    return snapshot;
  }
}
