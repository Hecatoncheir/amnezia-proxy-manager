import 'dart:convert';

import 'package:amnezia_proxy_manager/features/profiles/profile_codec.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> outbound(String tag, {String? via}) => {
  'tag': tag,
  'protocol': 'vless',
  'settings': {
    'vnext': [
      {
        'address': 'example.org',
        'port': 443,
        'users': [
          {
            'id': '6ba7b810-9dad-11d1-80b4-00c04fd430c8',
            'encryption': 'none',
            'flow': 'xtls-rprx-vision',
          },
        ],
      },
    ],
  },
  'streamSettings': {
    'network': 'tcp',
    'security': 'reality',
    'realitySettings': {
      'serverName': 'example.org',
      'fingerprint': 'chrome',
      'publicKey': 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
      'shortId': '1234',
    },
    if (via != null) 'sockopt': {'dialerProxy': via},
  },
};

void main() {
  final codec = ProfileCodec();
  Future<dynamic> decode(Map config) =>
      codec.decode(utf8.encode(jsonEncode(config)));
  test(
    'Цепочка VLESS сохраняется, входы/логи/прямые маршруты заменяются',
    () async {
      final profile = await decode({
        'log': {'access': '/tmp/secret.log'},
        'api': {'tag': 'api'},
        'dns': {
          'hosts': {'example.org': '127.0.0.1'},
        },
        'inbounds': [
          {'listen': '0.0.0.0', 'port': 1},
        ],
        'routing': {
          'rules': [
            {'outboundTag': 'direct'},
          ],
        },
        'outbounds': [
          outbound('main', via: 'transport'),
          outbound('transport'),
          {'tag': 'direct', 'protocol': 'freedom'},
        ],
      });
      expect(profile.family, 'xray');
      final result = jsonDecode(profile.configuration as String) as Map;
      expect((result['outbounds'] as List).length, 2);
      expect(
        result['outbounds'][0]['streamSettings']['sockopt']['dialerProxy'],
        'transport',
      );
      expect(result['log'], {'loglevel': 'none'});
      expect(result.containsKey('routing'), false);
      expect(result.containsKey('api'), false);
      expect(result.containsKey('dns'), false);
      expect(
        (result['inbounds'] as List).every((i) => i['listen'] == '127.0.0.1'),
        true,
      );
      expect(
        codec.normalizeConfiguration(profile.configuration),
        profile.configuration,
      );
    },
  );

  test(
    'Отсутствующий прокси, циклы и файловые настройки не принимаются',
    () async {
      final file = outbound('main');
      file['streamSettings']['tlsSettings'] = {
        'certificates': [
          {'certificateFile': '/secret'},
        ],
      };
      final nested = outbound('main');
      nested['streamSettings']['xhttpSettings'] = {
        'extra': {
          'downloadSettings': {'address': '127.0.0.1'},
        },
      };
      for (final outbounds in [
        [outbound('main', via: 'missing')],
        [outbound('one', via: 'two'), outbound('two', via: 'one')],
        [file],
        [nested],
        [outbound('one'), outbound('one')],
      ]) {
        await expectLater(
          decode({'outbounds': outbounds}),
          throwsA(isA<ProfileProblem>()),
        );
      }
    },
  );

  test('JSON AmneziaVPN Xray и vless:// распознаются по протоколу', () async {
    final profile = await decode({
      'defaultContainer': 'amnezia-xray',
      'containers': [
        {
          'container': 'amnezia-xray',
          'xray': {
            'last_config': jsonEncode({
              'outbounds': [outbound('proxy')],
            }),
          },
        },
      ],
      'api_config': {'vpn_key': 'SUBSCRIPTION-SECRET'},
    });
    expect(profile.format, 'VLESS');
    expect(profile.configuration, isNot(contains('SUBSCRIPTION-SECRET')));
    final uri = await codec.decode(
      utf8.encode(
        'vless://6ba7b810-9dad-11d1-80b4-00c04fd430c8@example.org:443?security=tls&type=ws&path=%2Ftest#Test',
      ),
    );
    expect(uri.family, 'xray');
    expect(
      jsonDecode(
        uri.configuration,
      )['outbounds'][0]['streamSettings']['wsSettings']['path'],
      '/test',
    );
  });
}
