import 'models.dart';
import 'ports.dart';
import 'validation.dart';

/// Placeholder host adapter whose operations are not implemented yet.
final class TokenWorksHostAdapter implements WorkspaceGateway, TokenWorksDirectory {
  const TokenWorksHostAdapter();

  @override
  Stream<ConnectionStatus> watchConnection(HostProfile host) async* {
    throw const IntegrationException('adapter/unimplemented', '尚未接入 TokenWorks 主机桥。');
  }

  @override
  Future<List<SessionSummary>> listSessions(HostProfile host) =>
      Future<List<SessionSummary>>.error(
        const IntegrationException('adapter/unimplemented', '尚未接入 TokenWorks 主机桥。'),
      );

  @override
  Future<SessionSummary> createSession({
    required HostProfile host,
    required String workspace,
    required WorkspaceMode mode,
    required PermissionLevel permission,
    required SchoolModel model,
    bool fullAccessConfirmed = false,
  }) {
    throw UnimplementedError('Remote adapter will use DshClient bridge');
  }

  @override
  Future<void> sendMessage(String sessionId, String text) {
    throw UnimplementedError('Remote adapter will use DshClient bridge');
  }

  @override
  Future<void> interrupt(String sessionId) {
    throw UnimplementedError('Remote adapter will use DshClient bridge');
  }

  @override
  Future<void> answerApproval(String approvalId, {required bool allowed}) {
    throw UnimplementedError('Remote adapter will use DshClient bridge');
  }

  @override
  Future<AccountSnapshot> loadAccount() {
    throw UnimplementedError('Account snapshot comes from signed school config');
  }
}

/// Applies launch policy before delegating session creation.
final class PolicyEnforcingWorkspaceAdapter implements WorkspaceGateway {
  const PolicyEnforcingWorkspaceAdapter(this.inner, this.account, this.policy);

  final WorkspaceGateway inner;
  final AccountSnapshot account;
  final LaunchPolicy policy;

  @override
  Stream<ConnectionStatus> watchConnection(HostProfile host) => inner.watchConnection(host);

  @override
  Future<List<SessionSummary>> listSessions(HostProfile host) => inner.listSessions(host);

  @override
  Future<SessionSummary> createSession({
    required HostProfile host,
    required String workspace,
    required WorkspaceMode mode,
    required PermissionLevel permission,
    required SchoolModel model,
    bool fullAccessConfirmed = false,
  }) {
    policy.validateSessionLaunch(
      account: account,
      host: host,
      model: model,
      workspace: workspace,
      permission: permission,
      fullAccessConfirmed: fullAccessConfirmed,
    );
    return inner.createSession(
      host: host,
      workspace: workspace,
      mode: mode,
      permission: permission,
      model: model,
      fullAccessConfirmed: fullAccessConfirmed,
    );
  }

  @override
  Future<void> sendMessage(String sessionId, String text) => inner.sendMessage(sessionId, text);

  @override
  Future<void> interrupt(String sessionId) => inner.interrupt(sessionId);

  @override
  Future<void> answerApproval(String approvalId, {required bool allowed}) =>
      inner.answerApproval(approvalId, allowed: allowed);
}
