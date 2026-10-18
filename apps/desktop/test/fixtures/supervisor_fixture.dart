import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  await for (final line
      in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    final request = jsonDecode(line) as Map;
    final response = <String, Object?>{
      'version': 1,
      'requestId': request['requestId'],
      'ok': true,
    };
    if (request['method'] == 'hello') {
      response['capabilities'] = ['start', 'stop', 'status', 'custom_ports'];
    }
    if (request['method'] == 'start') {
      if (request['configuration'] == 'custom_ports') {
        response['ok'] =
            request['socksPort'] == 19080 && request['httpPort'] == 19081;
        response['code'] = 'invalid_ports';
      }
      if (request['configuration'] == 'crash') exit(7);
      if (request['configuration'] == 'bad_version') response['version'] = 2;
      if (request['configuration'] == 'oversized') {
        response['padding'] = 'a' * 9000;
      }
      stdout.writeln(
        jsonEncode({
          'version': 1,
          'event': 'state',
          'state': {'status': 'running', 'connectivity': 'verified'},
        }),
      );
    }
    if (request['method'] == 'stop') {
      stdout.writeln(
        jsonEncode({
          'version': 1,
          'event': 'state',
          'state': {'status': 'disconnected'},
        }),
      );
    }
    stdout.writeln(jsonEncode(response));
  }
}
