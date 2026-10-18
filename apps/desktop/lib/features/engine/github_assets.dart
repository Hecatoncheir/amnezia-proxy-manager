import 'dart:convert';

import 'package:http/http.dart' as http;

Future<http.StreamedResponse> openGitHubAsset(
  http.Client client,
  Uri initial,
) async {
  var url = initial;
  for (var redirects = 0; redirects < 6; redirects++) {
    if (url.scheme != 'https' ||
        url.port != 443 ||
        url.userInfo.isNotEmpty ||
        !{
          'github.com',
          'api.github.com',
          'release-assets.githubusercontent.com',
          'objects.githubusercontent.com',
        }.contains(url.host)) {
      throw const FormatException('Недопустимый адрес загрузки движка');
    }
    final request = http.Request('GET', url)..followRedirects = false;
    request.headers['Accept'] = 'application/vnd.github+json';
    request.headers['Accept-Encoding'] = 'identity';
    final response = await client
        .send(request)
        .timeout(const Duration(seconds: 15));
    if (![301, 302, 303, 307, 308].contains(response.statusCode)) {
      return response;
    }
    final location = response.headers['location'];
    await response.stream.drain<void>().timeout(const Duration(seconds: 15));
    if (location == null) break;
    url = url.resolve(location);
  }
  throw const FormatException('Слишком много перенаправлений');
}

Future<List<int>> readGitHubBytes(
  http.Client client,
  Uri url,
  int limit,
) async {
  final response = await openGitHubAsset(client, url);
  if (response.statusCode != 200) {
    await response.stream.drain<void>().timeout(const Duration(seconds: 15));
    throw const FormatException('GitHub временно недоступен');
  }
  final bytes = <int>[];
  await for (final chunk in response.stream.timeout(
    const Duration(seconds: 20),
  )) {
    if (bytes.length + chunk.length > limit) {
      throw const FormatException('Превышен размер ответа');
    }
    bytes.addAll(chunk);
  }
  return bytes;
}

Future<Object?> readGitHubJson(http.Client client, Uri url, int limit) async =>
    jsonDecode(utf8.decode(await readGitHubBytes(client, url, limit)));
