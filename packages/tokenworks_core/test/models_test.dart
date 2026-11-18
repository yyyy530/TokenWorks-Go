import 'package:test/test.dart';
import 'package:tokenworks_core/tokenworks_core.dart';

void main() {
  group('WorkspaceMode', () {
    test('uses the documented preset identifiers', () {
      expect(WorkspaceMode.values.map((mode) => mode.id), <String>[
        'tw-standard', 'tw-research', 'tw-teach', 'tw-study',
      ]);
      expect(WorkspaceMode.fromId('tw-research'), WorkspaceMode.research);
    });

    test('rejects unknown ids instead of silently using standard', () {
      expect(() => WorkspaceMode.fromId('standard'), throwsFormatException);
    });
  });

  group('AccountSnapshot', () {
    test('accepts a server-provided dynamic model and quota catalog', () {
      final snapshot = AccountSnapshot(
        displayName: '测试用户',
        models: const [
          SchoolModel(
            id: 'server-model', displayName: 'Server model',
            contextWindow: 128000, maxOutput: 8192,
          ),
        ],
        quotas: [QuotaWindow(
          id: '24h', remaining: 25, limit: 100,
          resetsAt: DateTime.utc(2026, 11, 18),
        )],
        network: NetworkScope.campus,
      );
      expect(snapshot.validate, returnsNormally);
      expect(snapshot.quotas.single.fraction, .25);
    });

    test('rejects duplicate model ids and impossible quota values', () {
      const model = SchoolModel(
        id: 'duplicate', displayName: 'Duplicate',
        contextWindow: 4096, maxOutput: 1024,
      );
      final snapshot = AccountSnapshot(
        displayName: 'Test', models: const [model, model], quotas: const [],
        network: NetworkScope.unknown,
      );
      expect(snapshot.validate, throwsFormatException);
      expect(
        () => QuotaWindow(
          id: 'bad', remaining: 101, limit: 100,
          resetsAt: DateTime.utc(2026),
        ).validate(),
        throwsFormatException,
      );
    });
  });

  test('remote host must use HTTPS, except loopback development', () {
    HostProfile(
      id: 'local', displayName: 'Local', kind: HostKind.local,
      endpoint: Uri.parse('http://127.0.0.1:3080'),
    ).validate();
    expect(
      () => HostProfile(
        id: 'remote', displayName: 'Remote', kind: HostKind.remote,
        endpoint: Uri.parse('http://example.com'),
      ).validate(),
      throwsFormatException,
    );
  });

  test('rejects non-finite quotas and duplicate quota windows', () {
    for (final value in [double.nan, double.infinity]) {
      expect(
        () => QuotaWindow(
          id: 'bad', remaining: value, limit: 100,
          resetsAt: DateTime.utc(2026),
        ).validate(),
        throwsFormatException,
      );
    }
    final account = AccountSnapshot(
      displayName: 'User', models: const [],
      quotas: [
        QuotaWindow(id: '24h', remaining: 1, limit: 2, resetsAt: DateTime.utc(2026)),
        QuotaWindow(id: '24h', remaining: 1, limit: 2, resetsAt: DateTime.utc(2026)),
      ],
      network: NetworkScope.unknown,
    );
    expect(account.validate, throwsFormatException);
  });

  test('remote hosts cannot use loopback, embedded credentials or query parameters', () {
    for (final endpoint in [
      'http://127.0.0.1:3080',
      'https://user:password@example.com',
      'https://example.com?token=secret',
      'https://example.com#secret',
    ]) {
      expect(
        () => HostProfile(
          id: 'remote', displayName: 'Remote', kind: HostKind.remote,
          endpoint: Uri.parse(endpoint),
        ).validate(),
        throwsFormatException,
        reason: endpoint,
      );
    }
  });

  test('parses server data without a hardcoded model catalog', () {
    final snapshot = AccountSnapshot.fromJson({
      'displayName': 'Test',
      'models': [
        {
          'id': 'future-model', 'displayName': 'Future',
          'contextWindow': 1000000, 'maxOutput': 65536,
          'supportsImages': true, 'reasoningLevels': ['low', 'high'],
        },
      ],
      'quotas': [
        {'id': '3h', 'remaining': 1.5, 'limit': 3, 'resetsAt': '2026-11-18T00:00:00Z'},
      ],
      'network': 'campus',
    });
    expect(snapshot.models.single.id, 'future-model');
    expect(snapshot.models.single.reasoningLevels, ['low', 'high']);
    expect(snapshot.quotas.single.fraction, .5);
    expect(snapshot.network, NetworkScope.campus);
  });
}
