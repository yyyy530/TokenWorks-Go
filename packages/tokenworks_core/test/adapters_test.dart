import 'package:test/test.dart';
import 'package:tokenworks_core/tokenworks_core.dart';

final class RecordingGateway implements WorkspaceGateway {
  SchoolModel? model;
  bool? fullAccessConfirmed;
  int createCalls = 0;

  @override
  Future<SessionSummary> createSession({
    required HostProfile host,
    required String workspace,
    required WorkspaceMode mode,
    required PermissionLevel permission,
    required SchoolModel model,
    bool fullAccessConfirmed = false,
  }) async {
    createCalls++;
    this.model = model;
    this.fullAccessConfirmed = fullAccessConfirmed;
    return SessionSummary(
      id: 'session',
      title: 'Test',
      workspace: workspace,
      mode: mode,
      updatedAt: DateTime.utc(2026),
    );
  }

  @override
  Future<void> answerApproval(String approvalId, {required bool allowed}) async {}
  @override
  Future<void> interrupt(String sessionId) async {}
  @override
  Future<List<SessionSummary>> listSessions(HostProfile host) async => const [];
  @override
  Future<void> sendMessage(String sessionId, String text) async {}
  @override
  Stream<ConnectionStatus> watchConnection(HostProfile host) => const Stream.empty();
}

void main() {
  const selectedModel = SchoolModel(
    id: 'selected-model', displayName: 'Selected', contextWindow: 128000, maxOutput: 8192,
  );
  const otherModel = SchoolModel(
    id: 'other-model', displayName: 'Other', contextWindow: 64000, maxOutput: 4096,
  );
  final account = AccountSnapshot(
    displayName: 'User', models: const [selectedModel, otherModel],
    quotas: const [], network: NetworkScope.campus,
  );
  final host = HostProfile(
    id: 'local', displayName: 'Phone', kind: HostKind.local,
    endpoint: Uri.parse('http://127.0.0.1:3080'),
  );

  test('forwards the user-selected model without using the host id', () async {
    final inner = RecordingGateway();
    final adapter = PolicyEnforcingWorkspaceAdapter(inner, account, const LaunchPolicy());
    await adapter.createSession(
      host: host, workspace: '/work', mode: WorkspaceMode.research,
      permission: PermissionLevel.workspaceWrite, model: otherModel,
    );
    expect(inner.model, same(otherModel));
    expect(inner.createCalls, 1);
  });

  test('rejects an unlisted model before reaching the gateway', () {
    const unlisted = SchoolModel(
      id: 'unlisted', displayName: 'Unlisted', contextWindow: 4096, maxOutput: 1024,
    );
    final inner = RecordingGateway();
    final adapter = PolicyEnforcingWorkspaceAdapter(inner, account, const LaunchPolicy());
    expect(
      () => adapter.createSession(
        host: host, workspace: '/work', mode: WorkspaceMode.standard,
        permission: PermissionLevel.readOnly, model: unlisted,
      ),
      throwsA(isA<IntegrationException>()),
    );
    expect(inner.createCalls, 0);
  });

  test('requires confirmation for full access and forwards explicit confirmation', () async {
    final inner = RecordingGateway();
    final adapter = PolicyEnforcingWorkspaceAdapter(inner, account, const LaunchPolicy());
    expect(
      () => adapter.createSession(
        host: host, workspace: '/work', mode: WorkspaceMode.standard,
        permission: PermissionLevel.fullAccess, model: selectedModel,
      ),
      throwsA(isA<IntegrationException>()),
    );
    expect(inner.createCalls, 0);

    await adapter.createSession(
      host: host, workspace: '/work', mode: WorkspaceMode.standard,
      permission: PermissionLevel.fullAccess, model: selectedModel,
      fullAccessConfirmed: true,
    );
    expect(inner.fullAccessConfirmed, isTrue);
    expect(inner.createCalls, 1);
  });

  test('unimplemented host adapter fails explicitly, never returning fake success', () {
    const adapter = TokenWorksHostAdapter();
    expect(adapter.watchConnection(host), emitsError(isA<IntegrationException>()));
    expect(adapter.listSessions(host), throwsA(isA<IntegrationException>()));
  });
}
