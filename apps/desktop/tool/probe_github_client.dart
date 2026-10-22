// Только для нативных CI-проверок. Токен не передаётся на хосты архивов.
import 'package:http/http.dart' as http;

class ProbeGitHubClient extends http.BaseClient {
  ProbeGitHubClient({required this.token, http.Client? inner})
    : inner = inner ?? http.Client();

  final String token;
  final http.Client inner;
  final responses = <Map<String, Object>>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (_isAPI(request.url) && token.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $token';
      request.followRedirects = false;
    }
    final response = await inner.send(request);
    responses.add({'host': request.url.host, 'status': response.statusCode});
    return response;
  }

  bool _isAPI(Uri url) =>
      url.scheme == 'https' &&
      url.host == 'api.github.com' &&
      url.port == 443 &&
      url.userInfo.isEmpty;

  @override
  void close() => inner.close();
}
