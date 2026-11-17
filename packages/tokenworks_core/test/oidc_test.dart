import 'dart:math';

import 'package:test/test.dart';
import 'package:tokenworks_core/tokenworks_core.dart';

void main() {
  test('PKCE verifier and S256 challenge have the required shape', () {
    final pair = PkcePair.create(random: Random(42));
    expect(pair.verifier.length, greaterThanOrEqualTo(43));
    expect(pair.challenge.length, 43);
    expect(pair.challenge, isNot(contains('=')));
    expect(pair.challenge, isNot(startsWith('pending-')));
  });

  test('accepts a callback only with the exact state', () {
    final callback = OidcCallback.parse(
      Uri.parse('tokenworksgo://auth/callback?code=abc&state=expected'),
      expectedState: 'expected',
    );
    expect(callback.code, 'abc');
  });

  test('rejects wrong state, missing code and provider errors', () {
    for (final uri in [
      Uri.parse('tokenworksgo://auth/callback?code=abc&state=wrong'),
      Uri.parse('tokenworksgo://auth/callback?state=expected'),
      Uri.parse('tokenworksgo://auth/callback?error=access_denied'),
    ]) {
      expect(
        () => OidcCallback.parse(uri, expectedState: 'expected'),
        throwsA(anyOf(isA<FormatException>(), isA<StateError>())),
      );
    }
  });
}
