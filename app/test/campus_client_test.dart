import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tokenworks_go/src/campus_client.dart';

void main() {
  test(
    'campus API uses one approved browser origin and a separate app session',
    () async {
      const sessionToken = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      const loginId = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
      const returnCode = 'ccccccccccccccccccccccccccccccccccccccccccc';
      final origin = Uri.https('tokenworks-go.ustc.edu.cn');
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final requests = <({String path, String? auth, Object? body})>[];
      var allowBrowserOrigin = false;
      server.listen((request) async {
        final path = request.uri.path;
        final data = await utf8.decoder.bind(request).join();
        requests.add((
          path: path,
          auth: request.headers.value(HttpHeaders.authorizationHeader),
          body: data.isEmpty ? null : jsonDecode(data),
        ));
        if (path.endsWith('/logout')) {
          request.response.statusCode = HttpStatus.noContent;
        } else {
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode(switch (path) {
              '/v1/campus/login' => {
                'id': loginId,
                'authorize_url': allowBrowserOrigin
                    ? '${origin.origin}/v1/campus/authorize?ticket=fixture'
                    : 'https://another.ustc.edu.cn/v1/campus/authorize',
                'expires_in': 300,
              },
              '/v1/campus/complete' => {
                'session_token': sessionToken,
                'display_name': '测试用户',
                'expires_at': '2099-01-01T00:00:00Z',
              },
              '/v1/campus/models' => {
                'status': 'ready',
                'models': ['fixture-model'],
              },
              '/v1/campus/chat' => {'content': '测试回复'},
              _ => {'error': 'unexpected-fixture-route'},
            }),
          );
        }
        await request.response.close();
      });

      await HttpOverrides.runWithHttpOverrides(() async {
        final client = CampusClient(origin);
        await expectLater(client.login(), throwsFormatException);
        allowBrowserOrigin = true;
        final flow = await client.login();
        expect(flow.authorizeUrl.origin, origin.origin);
        final session = (await client.complete(flow, returnCode))!;
        expect(session.displayName, '测试用户');
        expect((await client.models(session)).models, ['fixture-model']);
        expect(await client.ask(session, 'fixture-model', '测试问题'), '测试回复');
        await client.logout(session);
        expect(requests[2].body, {
          'id': loginId,
          'verifier': flow.verifier,
          'callback_code': returnCode,
        });
        expect(requests[3].auth, 'Bearer $sessionToken');
        expect(requests[4].body, {'model': 'fixture-model', 'prompt': '测试问题'});
        expect(requests[5].auth, 'Bearer $sessionToken');
      }, _LoopbackHttp(server.port));
    },
  );
}

// Only the fixture socket is intercepted. The tested URI still uses the
// approved HTTPS origin for authorization URL and header validation.
final class _LoopbackHttp extends HttpOverrides {
  _LoopbackHttp(this.port);
  final int port;

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)
        ..findProxy = ((_) => 'DIRECT')
        ..connectionFactory = (_, _, _) =>
            Socket.startConnect(InternetAddress.loopbackIPv4, port);
}
