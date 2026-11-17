import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// PKCE helper for the system-browser authorization-code flow.
/// The school's concrete issuer and client registration are injected by the app.
final class PkcePair {
  const PkcePair._(this.verifier, this.challenge);
  final String verifier;
  final String challenge;

  static PkcePair create({Random? random}) {
    final rng = random ?? Random.secure();
    final verifier = base64UrlEncode(
      List<int>.generate(64, (_) => rng.nextInt(256)),
    ).replaceAll('=', '');
    final challenge = base64UrlEncode(
      sha256.convert(ascii.encode(verifier)).bytes,
    ).replaceAll('=', '');
    return PkcePair._(verifier, challenge);
  }
}

final class OidcCallback {
  const OidcCallback({required this.code, required this.state});
  final String code;
  final String state;

  static OidcCallback parse(Uri uri, {required String expectedState}) {
    final state = uri.queryParameters['state'];
    _validateState(state, expectedState);
    if (uri.queryParameters.containsKey('error')) {
      throw StateError('Authorization failed: ${uri.queryParameters['error']}');
    }
    final code = uri.queryParameters['code'];
    if (code == null || code.isEmpty) {
      throw const FormatException('Missing OAuth code');
    }
    return OidcCallback(code: code, state: state!);
  }

  static void _validateState(String? state, String expectedState) {
    if (state == null || state.length != expectedState.length) {
      throw const FormatException('OAuth state mismatch');
    }
    var difference = 0;
    for (var i = 0; i < state.length; i++) {
      difference |= state.codeUnitAt(i) ^ expectedState.codeUnitAt(i);
    }
    if (difference != 0) throw const FormatException('OAuth state mismatch');
  }
}
