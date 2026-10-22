import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../tool/probe_github_client.dart';

void main() {
  test(
    'CI-токен передаётся только GitHub API, без утечки в отчёт или архивы',
    () async {
      final headers = <String, String?>{};
      final client = ProbeGitHubClient(
        token: 'test-token',
        inner: MockClient((request) async {
          headers[request.url.toString()] = request.headers['Authorization'];
          return http.Response('ok', 200);
        }),
      );
      addTearDown(client.close);
      for (final url in [
        'https://api.github.com/',
        'http://api.github.com/',
        'https://api.github.com:8443/',
        'https://github.com/',
        'https://release-assets.githubusercontent.com/',
      ]) {
        await client.get(Uri.parse(url));
      }
      expect(headers.remove('https://api.github.com/'), 'Bearer test-token');
      expect(headers.values, everyElement(isNull));
      expect(client.responses.toString(), isNot(contains('test-token')));
    },
  );
}
