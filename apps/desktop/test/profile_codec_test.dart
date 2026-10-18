import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:amnezia_proxy_manager/features/profiles/profile_codec.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/profile_fixtures.dart';

void main() {
  final codec = ProfileCodec();
  Future<ImportedProfile> decode(String value) =>
      codec.decode(utf8.encode(value));

  test('CONF с BOM, комментариями и IPv6 нормализуется', () async {
    final profile = await decode(
      '\ufeff# Тест\n${testConf.replaceAll('\n', '\r\n')}',
    );
    expect(profile.format, 'AmneziaWG');
    expect(profile.configuration, contains('AllowedIPs = 0.0.0.0/0, ::/0'));
    expect(profile.configuration, isNot(contains('Socks5')));
    expect(profile.toString(), isNot(contains(testPrivateKey)));
  });

  test('AmneziaVPN JSON и qCompress vpn:// дают тот же конфиг', () async {
    final plain = await decode(jsonEncode(exportJson()));
    final compressed = await decode(vpnUri(exportJson()));
    expect(plain.configuration, compressed.configuration);
    expect(compressed.format, 'AmneziaVPN');
  });

  test('Структурированный last_config и отдельные параметры AWG', () async {
    final profile = await decode(
      vpnUri(
        exportJson(
          last: {
            'client_ip': '10.200.200.2',
            'client_priv_key': testPrivateKey,
            'server_pub_key': testPublicKey,
            'hostName': '127.0.0.1',
            'port': 9,
            'allowed_ips': ['0.0.0.0/0'],
            'Jc': 5,
            'Jmin': 10,
            'Jmax': 50,
          },
        ),
      ),
    );
    expect(profile.configuration, contains('Jc = 5'));
    expect(profile.configuration, contains('Address = 10.200.200.2/32'));
    final extended = await decode(
      vpnUri(
        exportJson(
          last: {
            'config': testConf,
            'ContentPaddingAddition': '4-16',
            'RandomTrailers': true,
          },
        ),
      ),
    );
    expect(extended.configuration, contains('RandomTrailers = true'));
  });

  test(
    'Опасные директивы, дубликаты, env и дополнительные секции запрещены',
    () async {
      for (final addition in [
        'PostUp = command',
        'WGConfig = /tmp/secret',
        'PrivateKey = $testPrivateKey',
        'Unknown = 1',
        'PrivateKey = \$ENV',
      ]) {
        await expectLater(
          decode(testConf.replaceFirst('[Peer]', '$addition\n[Peer]')),
          throwsA(isA<ProfileProblem>()),
        );
      }
      for (final section in [
        'Socks5',
        'http',
        'TCPClientTunnel',
        'Peer',
        'Interface',
      ]) {
        await expectLater(
          decode('$testConf\n[$section]\nBindAddress = 0.0.0.0:1080'),
          throwsA(isA<ProfileProblem>()),
        );
      }
    },
  );

  test('Неверные ключи, сети и endpoint не раскрываются в ошибке', () async {
    for (final source in [
      testConf.replaceAll(testPrivateKey, 'SECRET-BAD-KEY'),
      testConf.replaceAll('127.0.0.1:9', 'example.org:65536'),
      testConf.replaceAll('10.200.200.2/32', '10.200.200.2/33'),
      testConf.replaceAll('10.200.200.1', 'dns.example.org'),
    ]) {
      try {
        await decode(source);
        fail('Профиль принят');
      } on ProfileProblem catch (error) {
        expect(error.toString(), isNot(contains(testPrivateKey)));
        expect(error.toString(), isNot(contains('SECRET-BAD-KEY')));
      }
    }
  });

  test('Другие протоколы, подписки, неоднозначные контейнеры и конфликты отклоняются', () async {
    for (final json in [
      {'api_endpoint': 'https://example.org/', 'api_key': 'secret'},
      exportJson()..['defaultContainer'] = 'amnezia-openvpn',
      exportJson(last: {'config': testConf, 'Jc': 100}),
    ]) {
      await expectLater(decode(vpnUri(json)), throwsA(isA<ProfileProblem>()));
    }
    final data = exportJson();
    (data['containers'] as List).add((data['containers'] as List).first);
    await expectLater(decode(vpnUri(data)), throwsA(isA<ProfileProblem>()));
  });

  test('Лимиты файла, распаковки, вложенности и обрезанный поток', () async {
    await expectLater(
      codec.decode(List.filled(maxProfileBytes + 1, 65)),
      throwsA(isA<ProfileProblem>()),
    );
    final header = ByteData(4)..setUint32(0, 0x7fffffff);
    await expectLater(
      decode(
        'vpn://${base64Url.encode([
          ...header.buffer.asUint8List(),
          ...zlib.encode([123, 125]),
        ])}',
      ),
      throwsA(isA<ProfileProblem>()),
    );
    header.setUint32(0, 2);
    final bomb = [
      ...header.buffer.asUint8List(),
      ...zlib.encode(List.filled(100000, 65)),
    ];
    await expectLater(
      decode('vpn://${base64Url.encode(bomb)}'),
      throwsA(isA<ProfileProblem>()),
    );
    await expectLater(
      decode('{"x":${'[' * 40}0${']' * 40}}'),
      throwsA(isA<ProfileProblem>()),
    );
    final uri = vpnUri(exportJson());
    await expectLater(
      decode(uri.substring(0, uri.length - 4)),
      throwsA(isA<ProfileProblem>()),
    );
  });
}
