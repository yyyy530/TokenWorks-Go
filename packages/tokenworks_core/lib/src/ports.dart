import 'models.dart';

abstract interface class TokenStore {
  Future<void> writeRefreshToken(String value);
  Future<String?> readRefreshToken();
  Future<void> clear();
}

abstract interface class IdentityGateway {
  Uri buildAuthorizationUri({required String state, required String codeChallenge});
  Future<void> completeSignIn(Uri callback);
  Future<void> signOut();
}

abstract interface class TokenWorksDirectory {
  Future<AccountSnapshot> loadAccount();
}

abstract interface class WorkspaceGateway {
  Stream<ConnectionStatus> watchConnection(HostProfile host);
  Future<List<SessionSummary>> listSessions(HostProfile host);
  Future<SessionSummary> createSession({
    required HostProfile host,
    required String workspace,
    required WorkspaceMode mode,
    required PermissionLevel permission,
    required SchoolModel model,
    bool fullAccessConfirmed = false,
  });
  Future<void> sendMessage(String sessionId, String text);
  Future<void> interrupt(String sessionId);
  Future<void> answerApproval(String approvalId, {required bool allowed});
}

final class IntegrationException implements Exception {
  const IntegrationException(this.code, this.message, [this.cause]);
  final String code;
  final String message;
  final Object? cause;

  @override
  String toString() => 'IntegrationException($code): $message';
}
