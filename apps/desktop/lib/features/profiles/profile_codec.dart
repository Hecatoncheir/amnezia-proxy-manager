import 'xray_codec.dart';

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

const maxProfileBytes = 256 * 1024;
const maxConfigBytes = 65536;
const _maxJsonBytes = 512 * 1024;

class ProfileProblem implements Exception {
  const ProfileProblem(this.message);
  final String message;
  @override
  String toString() => message;
}

class ImportedProfile {
  const ImportedProfile(this.configuration, this.format);
  final String configuration, format;
  String get family => format == 'VLESS' ? 'xray' : 'awg';
  @override
  String toString() => 'ImportedProfile(скрыто)';
}

const _interfaceKeys = [
  'Address',
  'PrivateKey',
  'DNS',
  'MTU',
  'ListenPort',
  'Jc',
  'Jmin',
  'Jmax',
  'S1',
  'S2',
  'S3',
  'S4',
  'H1',
  'H2',
  'H3',
  'H4',
  'I1',
  'I2',
  'I3',
  'I4',
  'I5',
  'HeaderProtectionKey',
  'ContentPaddingAddition',
  'RekeyAfterTime',
  'RekeyTimeout',
  'RejectAfterTime',
  'KeepaliveTimeout',
  'MaxHandshakeAttempts',
  'RandomTrailers',
  'DisableCookies',
];
const _peerKeys = [
  'PublicKey',
  'PresharedKey',
  'Endpoint',
  'AllowedIPs',
  'PersistentKeepalive',
];

class ProfileCodec {
  Future<ImportedProfile> decode(List<int> bytes) async {
    try {
      if (bytes.isEmpty || bytes.length > maxProfileBytes) {
        throw const ProfileProblem('Файл пуст или превышает 256 КБ.');
      }
      final text = utf8.decode(bytes).replaceFirst('\ufeff', '').trim();
      if (text.startsWith('[') ||
          text.startsWith('#') ||
          text.startsWith(';')) {
        return ImportedProfile(normalize(text), 'AmneziaWG');
      }
      if (text.startsWith('vless://')) {
        return ImportedProfile(
          normalizeConfiguration(jsonEncode(XrayCodec().fromUri(text))),
          'VLESS',
        );
      }
      final json = text.startsWith('{') ? text : await _decodeUri(text);
      final data = _jsonObject(json);
      if (data.containsKey('outbounds')) {
        return ImportedProfile(normalizeConfiguration(json), 'VLESS');
      }
      if (data['defaultContainer'] == 'amnezia-xray') {
        final containers = data['containers'];
        if (containers is! List) {
          throw const ProfileProblem('Нет конфигурации Xray.');
        }
        final matches = containers
            .whereType<Map>()
            .where((c) => c['container'] == 'amnezia-xray')
            .toList();
        if (matches.length != 1 ||
            matches.single['xray'] is! Map ||
            matches.single['xray']['last_config'] is! String) {
          throw const ProfileProblem('Нет клиентской конфигурации Xray.');
        }
        return ImportedProfile(
          normalizeConfiguration(matches.single['xray']['last_config']),
          'VLESS',
        );
      }
      return ImportedProfile(normalize(_fromAmnezia(data)), 'AmneziaVPN');
    } on ProfileProblem {
      rethrow;
    } catch (_) {
      // Ошибки декодеров могут содержать фрагменты входа; наружу не передавать.
      throw const ProfileProblem('Повреждённый или неподдерживаемый профиль.');
    }
  }

  String normalizeConfiguration(String text) {
    if (!text.trimLeft().startsWith('{')) return normalize(text);
    try {
      final result = XrayCodec().normalize(_jsonObject(text));
      if (utf8.encode(result).length > maxConfigBytes) {
        throw const FormatException('Слишком большая конфигурация');
      }
      return result;
    } catch (_) {
      throw const ProfileProblem(
        'Неподдерживаемая или повреждённая конфигурация VLESS.',
      );
    }
  }

  String normalize(String text) {
    if (utf8.encode(text).length > maxConfigBytes || text.contains('\u0000')) {
      throw const ProfileProblem(
        'Конфигурация слишком большая или повреждена.',
      );
    }
    final sections = <String, Map<String, String>>{};
    Map<String, String>? current;
    for (final raw in const LineSplitter().convert(text)) {
      final line = raw.split(RegExp(r'[#;]')).first.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('[')) {
        final section = switch (line.toLowerCase()) {
          '[interface]' => 'Interface',
          '[peer]' => 'Peer',
          _ => '',
        };
        if (section.isEmpty || sections.containsKey(section)) {
          throw const ProfileProblem(
            'Поддерживается один Interface и один Peer без дополнительных секций.',
          );
        }
        current = <String, String>{};
        sections[section] = current;
        continue;
      }
      final equal = line.indexOf('=');
      if (current == null || equal < 1) {
        throw const ProfileProblem('Неверная структура конфигурации.');
      }
      final allowed = identical(current, sections['Interface'])
          ? _interfaceKeys
          : _peerKeys;
      final key = allowed
          .where(
            (key) =>
                key.toLowerCase() ==
                line.substring(0, equal).trim().toLowerCase(),
          )
          .firstOrNull;
      if (key == null || current.containsKey(key)) {
        throw const ProfileProblem(
          'В профиле есть неподдерживаемые или повторяющиеся параметры. Команды и файловые ссылки запрещены.',
        );
      }
      final value = line.substring(equal + 1).trim();
      if (value.isEmpty ||
          value.length > 4096 ||
          !RegExp(r'^[\x20-\x7e]+$').hasMatch(value) ||
          value.contains(r'$')) {
        throw const ProfileProblem('Недопустимое значение параметра профиля.');
      }
      current[key] = _validateValue(key, value);
    }
    final network = sections['Interface'], peer = sections['Peer'];
    if (network == null ||
        peer == null ||
        !['Address', 'PrivateKey', 'DNS'].every(network.containsKey) ||
        !['PublicKey', 'Endpoint', 'AllowedIPs'].every(peer.containsKey)) {
      throw const ProfileProblem(
        'Нужны адрес, ключи, DNS, endpoint и AllowedIPs.',
      );
    }
    final result = StringBuffer();
    for (final section in ['Interface', 'Peer']) {
      result.writeln('[$section]');
      for (final entry in sections[section]!.entries) {
        result.writeln('${entry.key} = ${entry.value}');
      }
      result.writeln();
    }
    return result.toString();
  }

  String _validateValue(String key, String value) {
    switch (key) {
      case 'PrivateKey':
      case 'PublicKey':
      case 'PresharedKey':
      case 'HeaderProtectionKey':
        if (key == 'HeaderProtectionKey' &&
            RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(value)) {
          return value;
        }
        final data = base64.decode(value);
        if (data.length != 32 ||
            base64.encode(data) != value ||
            data.every((v) => v == 0)) {
          throw const ProfileProblem(
            'Ключ должен содержать 32 байта в Base64.',
          );
        }
        return value;
      case 'Address':
      case 'AllowedIPs':
        return value
            .split(',')
            .map((part) => _prefix(part.trim(), key == 'Address'))
            .join(', ');
      case 'DNS':
        final addresses = value.split(',').map((e) => e.trim());
        if (addresses.length > 8 ||
            addresses.any((ip) => InternetAddress.tryParse(ip) == null)) {
          throw const ProfileProblem('DNS должен содержать только IP-адреса.');
        }
        return addresses.join(', ');
      case 'Endpoint':
        if (!_endpoint(value)) {
          throw const ProfileProblem('Неверный адрес или порт VPN-сервера.');
        }
        return value;
      case 'RandomTrailers':
      case 'DisableCookies':
        if (!['true', 'false'].contains(value.toLowerCase())) {
          throw const ProfileProblem('Неверный логический параметр AWG.');
        }
        return value.toLowerCase();
    }
    if (key.startsWith('I') && key.length == 2) {
      if (!RegExp(
        r'^(<(?:b 0x[0-9a-fA-F]+|r [0-9]+|rd [0-9]+|rc [0-9]+|t|c)>)+$',
      ).hasMatch(value)) {
        throw const ProfileProblem('Неверная сигнатура AWG.');
      }
    } else if (!RegExp(r'^\d{1,10}(-\d{1,10})?$').hasMatch(value)) {
      throw const ProfileProblem('Неверный числовой параметр AWG.');
    }
    return value; // Диапазоны и взаимосвязи AWG дополнительно проверяет --configtest.
  }

  String _prefix(String value, bool allowBare) {
    final parts = value.split('/');
    final ip = InternetAddress.tryParse(parts.first);
    final maximum = ip?.type == InternetAddressType.IPv4 ? 32 : 128;
    final prefix = parts.length == 2
        ? int.tryParse(parts[1])
        : (allowBare ? maximum : null);
    if (ip == null ||
        parts.length > 2 ||
        prefix == null ||
        prefix < 0 ||
        prefix > maximum) {
      throw const ProfileProblem('Неверный IP-адрес или маска сети.');
    }
    return '${ip.address}/$prefix';
  }

  bool _endpoint(String value) {
    final match = RegExp(r'^(\[[0-9a-fA-F:]+\]|[a-zA-Z0-9.-]+):(\d{1,5})$')
        .firstMatch(value);
    if (match == null) return false;
    final port = int.parse(match[2]!);
    if (port < 1 || port > 65535) return false;
    final host = match[1]!;
    if (host.startsWith('[')) {
      return InternetAddress.tryParse(host.substring(1, host.length - 1)) !=
          null;
    }
    return host.length <= 253 &&
        host
            .split('.')
            .every(
              (label) =>
                  label.isNotEmpty &&
                  label.length <= 63 &&
                  RegExp(r'^[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?$')
                      .hasMatch(label),
            );
  }

  Future<String> _decodeUri(String text) async {
    if (!text.startsWith('vpn://')) {
      throw const ProfileProblem(
        'Ожидается .conf, экспорт .vpn или ссылка vpn://.',
      );
    }
    final encoded = text.substring(6);
    if (!RegExp(r'^[a-zA-Z0-9_-]+={0,2}$').hasMatch(encoded)) {
      throw const ProfileProblem('Неверная ссылка vpn://.');
    }
    final bytes = base64Url.decode(base64Url.normalize(encoded));
    if (bytes.length < 5) {
      throw const ProfileProblem('Повреждённый экспорт AmneziaVPN.');
    }
    if (bytes.first == 123) {
      return utf8.decode(bytes); // Несжатый JSON старого экспорта.
    }
    final declared = ByteData.sublistView(bytes).getUint32(0);
    if (declared == 0 || declared > _maxJsonBytes) {
      throw const ProfileProblem(
        'Экспорт превышает допустимый размер распаковки.',
      );
    }
    final output = <int>[];
    Stream<List<int>> chunks() async* {
      for (var i = 4; i < bytes.length; i += 256) {
        yield bytes.sublist(i, (i + 256).clamp(0, bytes.length));
      }
    }

    await for (final part in zlib.decoder.bind(chunks())) {
      if (output.length + part.length > declared) {
        throw const ProfileProblem('Неверный размер распакованного экспорта.');
      }
      output.addAll(part);
    }
    if (output.length != declared) {
      throw const ProfileProblem('Экспорт повреждён или обрезан.');
    }
    return utf8.decode(output);
  }

  Map _jsonObject(String source) {
    if (utf8.encode(source).length > _maxJsonBytes) {
      throw const ProfileProblem('Экспорт слишком большой.');
    }
    var depth = 0, quoted = false, escaped = false;
    for (final char in source.codeUnits) {
      if (escaped) {
        escaped = false;
        continue;
      }
      if (quoted && char == 92) {
        escaped = true;
        continue;
      }
      if (char == 34) {
        quoted = !quoted;
        continue;
      }
      if (quoted) continue;
      if (char == 123 || char == 91) depth++;
      if (char == 125 || char == 93) depth--;
      if (depth > 32 || depth < 0) {
        throw const ProfileProblem('Неверная структура экспорта.');
      }
    }
    final value = jsonDecode(source);
    if (value is! Map) {
      throw const ProfileProblem('Ожидается экспорт AmneziaVPN.');
    }
    return value;
  }

  String _fromAmnezia(Map data) {
    if (data['defaultContainer'] != null &&
        data['defaultContainer'] != 'amnezia-awg') {
      throw const ProfileProblem(
        'Экспорт по умолчанию использует другой протокол. Выберите AmneziaWG.',
      );
    }
    final containers = data['containers'];
    if (containers is! List || containers.length > 16) {
      throw const ProfileProblem(
        'Нужен полный экспорт AmneziaWG. Подписки и ссылки API не поддерживаются.',
      );
    }
    final selected = containers
        .whereType<Map>()
        .where((c) => c['container'] == data['defaultContainer'])
        .toList();
    final candidates = selected.isNotEmpty
        ? selected
        : containers
              .whereType<Map>()
              .where((c) => c['container'] == 'amnezia-awg')
              .toList();
    if (candidates.length != 1 ||
        candidates.single['container'] != 'amnezia-awg') {
      throw const ProfileProblem(
        'Выберите экспорт одного профиля AmneziaWG. Другие протоколы не поддерживаются.',
      );
    }
    final awg = candidates.single['awg'];
    if (awg is! Map || awg['last_config'] is! String) {
      throw const ProfileProblem(
        'В экспорте отсутствует конфигурация AmneziaWG.',
      );
    }
    final last = _jsonObject(awg['last_config']);
    final config = last['config'];
    if (config is String && config.trim().isNotEmpty) {
      // Отдельные поля AWG нового экспорта должны совпасть с INI или быть добавлены.
      return _mergeAwg(config, last, data);
    }
    final host = last['hostName'] ?? data['hostName'];
    final port = last['port'] ?? awg['port'];
    if (host is! String || port == null) {
      throw const ProfileProblem('В экспорте отсутствует endpoint.');
    }
    final address = last['client_ip'];
    final allowed = last['allowed_ips'];
    if (address is! String ||
        allowed is! List ||
        allowed.any((e) => e is! String)) {
      throw const ProfileProblem('В экспорте отсутствуют адреса сети.');
    }
    final dns = [
      data['dns1'],
      data['dns2'],
    ].whereType<String>().where((e) => e.isNotEmpty).join(', ');
    final ini = StringBuffer(
      '[Interface]\nAddress = $address\nPrivateKey = ${last['client_priv_key']}\nDNS = $dns\n',
    );
    if (last['mtu'] != null) ini.writeln('MTU = ${last['mtu']}');
    ini.writeln(
      '[Peer]\nPublicKey = ${last['server_pub_key']}\nEndpoint = ${host.contains(':') ? '[$host]' : host}:$port\nAllowedIPs = ${allowed.join(', ')}',
    );
    if (last['psk_key'] is String && last['psk_key'] != '') {
      ini.writeln('PresharedKey = ${last['psk_key']}');
    }
    if (last['persistent_keep_alive'] != null) {
      ini.writeln('PersistentKeepalive = ${last['persistent_keep_alive']}');
    }
    return _mergeAwg(ini.toString(), last, data);
  }

  String _mergeAwg(String config, Map last, Map outer) {
    var result = config;
    final additions = <String>[];
    for (final key in _interfaceKeys.skip(5)) {
      final value = last[key];
      if (value == null || value == '') continue;
      if (value is! String && value is! num && value is! bool) {
        throw const ProfileProblem('Неверные параметры AWG в экспорте.');
      }
      final pattern = RegExp(
        '^${RegExp.escape(key)}\\s*=\\s*([^\\r\\n#;]*)',
        multiLine: true,
        caseSensitive: false,
      );
      final matches = pattern.allMatches(config);
      if (matches.isNotEmpty && matches.first[1]!.trim() != '$value') {
        throw const ProfileProblem(
          'Параметры AWG в тексте и экспорте не совпадают.',
        );
      }
      if (matches.isEmpty) additions.add('$key = $value');
    }
    if (!RegExp(
      r'^\s*DNS\s*=',
      multiLine: true,
      caseSensitive: false,
    ).hasMatch(config)) {
      final dns = [
        outer['dns1'],
        outer['dns2'],
      ].whereType<String>().where((e) => e.isNotEmpty).join(', ');
      if (dns.isNotEmpty) additions.add('DNS = $dns');
    }
    if (additions.isNotEmpty) {
      final section = RegExp(
        r'^\s*\[Interface\]\s*$',
        multiLine: true,
        caseSensitive: false,
      );
      if (!section.hasMatch(config)) {
        throw const ProfileProblem('В экспорте отсутствует Interface.');
      }
      result = config.replaceFirstMapped(
        section,
        (match) => '${match[0]}\n${additions.join('\n')}',
      );
    }
    return result;
  }
}
