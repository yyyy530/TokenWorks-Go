import 'package:test/test.dart';
import 'package:tokenworks_core/tokenworks_core.dart';

void main() {
  const model = SchoolModel(
    id: 'dynamic-model', displayName: 'Dynamic model',
    contextWindow: 128000, maxOutput: 8192,
  );
  final account = AccountSnapshot(
    displayName: 'User', models: const [model], quotas: const [],
    network: NetworkScope.campus,
  );
  final local = HostProfile(
    id: 'local', displayName: 'Phone', kind: HostKind.local,
    endpoint: Uri.parse('http://127.0.0.1:3080'),
  );
  const policy = LaunchPolicy();

  test('allows a valid workspace-write local session', () {
    expect(
      () => policy.validateSessionLaunch(
        account: account, host: local, model: model,
        workspace: '/work/project', permission: PermissionLevel.workspaceWrite,
      ),
      returnsNormally,
    );
  });

  test('requires campus or tunnel only for a local host', () {
    final externalAccount = AccountSnapshot(
      displayName: account.displayName, models: account.models,
      quotas: account.quotas, network: NetworkScope.external,
    );
    expect(
      () => policy.validateSessionLaunch(
        account: externalAccount, host: local, model: model,
        workspace: '/work', permission: PermissionLevel.readOnly,
      ),
      throwsA(isA<IntegrationException>()
          .having((error) => error.code, 'code', 'network/campus-required')),
    );
  });

  test('full access requires an explicit confirmation', () {
    expect(
      () => policy.validateSessionLaunch(
        account: account, host: local, model: model,
        workspace: '/work', permission: PermissionLevel.fullAccess,
      ),
      throwsA(isA<IntegrationException>().having(
        (error) => error.code, 'code',
        'permission/explicit-confirmation-required',
      )),
    );
  });
}
