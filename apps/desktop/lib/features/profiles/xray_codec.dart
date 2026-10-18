import 'dart:convert';

/// Создаёт отдельную конфигурацию прокси, исключая настройки файлов, API,
/// входящих туннелей и прямой маршрутизации исходного приложения.
class XrayCodec {
  String normalize(Map source, {int socksPort = 1080, int httpPort = 8080}) {
    final original = source['outbounds'];
    if (original is! List || original.isEmpty || original.length > 16) {
      throw const FormatException('Нет исходящих подключений VLESS');
    }
    final outbounds = <Map<String, dynamic>>[];
    for (final value in original) {
      if (value is! Map) throw const FormatException('Неверное подключение');
      if (value['protocol'] == 'dns' ||
          value['protocol'] == 'freedom' ||
          value['protocol'] == 'blackhole') {
        continue;
      }
      if (value['protocol'] != 'vless') {
        throw const FormatException('Поддерживается только VLESS');
      }
      outbounds.add(_outbound(value, outbounds.length));
    }
    if (outbounds.isEmpty) throw const FormatException('Нет VLESS');
    final tags = outbounds.map((o) => o['tag'] as String).toSet();
    if (tags.length != outbounds.length) {
      throw const FormatException('Повторяющиеся теги');
    }
    for (final outbound in outbounds) {
      final visited = <String>{};
      Map current = outbound;
      while (true) {
        if (!visited.add(current['tag'] as String)) {
          throw const FormatException('Цикл прокси');
        }
        final next =
            (current['streamSettings']?['sockopt'] as Map?)?['dialerProxy'];
        if (next == null) break;
        if (!tags.contains(next)) {
          throw const FormatException('Отсутствует промежуточный прокси');
        }
        current = outbounds.firstWhere((o) => o['tag'] == next);
      }
    }
    return jsonEncode({
      'log': {'loglevel': 'none'},
      'inbounds': [
        {
          'tag': 'manager-socks',
          'listen': '127.0.0.1',
          'port': socksPort,
          'protocol': 'socks',
          'settings': {'auth': 'noauth', 'udp': false},
        },
        {
          'tag': 'manager-http',
          'listen': '127.0.0.1',
          'port': httpPort,
          'protocol': 'http',
          'settings': {},
        },
      ],
      'outbounds': outbounds,
    });
  }

  Map<String, dynamic> _outbound(Map source, int index) {
    final tag = source['tag'] ?? 'vless-$index';
    if (tag is! String || !RegExp(r'^[a-zA-Z0-9_.-]{1,64}$').hasMatch(tag)) {
      throw const FormatException('Неверный тег');
    }
    final settings = source['settings'];
    final servers = settings is Map ? settings['vnext'] : null;
    if (servers is! List || servers.length != 1 || servers.single is! Map) {
      throw const FormatException('Неверный сервер VLESS');
    }
    final server = servers.single as Map;
    final host = server['address'],
        port = server['port'],
        users = server['users'];
    if (host is! String ||
        host.isEmpty ||
        host.length > 253 ||
        !RegExp(r'^[a-zA-Z0-9.:-]+$').hasMatch(host) ||
        port is! int ||
        port < 1 ||
        port > 65535 ||
        users is! List ||
        users.isEmpty ||
        users.length > 8) {
      throw const FormatException('Неверный адрес VLESS');
    }
    final safeUsers = users.map((value) {
      if (value is! Map ||
          value['id'] is! String ||
          (value['id'] as String).isEmpty) {
        throw const FormatException('Нет ID VLESS');
      }
      return _fields(value, const {
        'id',
        'encryption',
        'flow',
        'level',
      }, ignoreUnknown: true);
    }).toList();
    final result = <String, dynamic>{
      'tag': tag,
      'protocol': 'vless',
      'settings': {
        'vnext': [
          {'address': host, 'port': port, 'users': safeUsers},
        ],
      },
    };
    final stream = source['streamSettings'];
    if (stream is! Map) throw const FormatException('Не задан транспорт VLESS');
    result['streamSettings'] = _stream(stream);
    if (source['mux'] is Map) {
      result['mux'] = _fields(source['mux'], const {
        'enabled',
        'concurrency',
        'xudpConcurrency',
        'xudpProxyUDP443',
      });
    }
    return result;
  }

  Map<String, dynamic> _stream(Map source) {
    final network = source['network'] ?? 'tcp';
    final security = source['security'] ?? 'none';
    if (![
          'tcp',
          'raw',
          'xhttp',
          'splithttp',
          'ws',
          'grpc',
          'httpupgrade',
          'kcp',
        ].contains(network) ||
        !['none', 'tls', 'reality'].contains(security)) {
      throw const FormatException('Неподдерживаемый транспорт');
    }
    final result = <String, dynamic>{'network': network, 'security': security};
    const fields = {
      'realitySettings': {
        'serverName',
        'fingerprint',
        'publicKey',
        'password',
        'shortId',
        'spiderX',
        'mldsa65Verify',
      },
      'tlsSettings': {
        'serverName',
        'fingerprint',
        'alpn',
        'allowInsecure',
        'minVersion',
        'maxVersion',
        'pinnedPeerCertSha256',
        'echConfigList',
      },
      'sockopt': {'dialerProxy', 'domainStrategy', 'tcpFastOpen', 'tcpNoDelay'},
      'xhttpSettings': {'path', 'host', 'mode', 'headers', 'xmux', 'extra'},
      'splithttpSettings': {'path', 'host', 'mode', 'headers', 'xmux', 'extra'},
      'wsSettings': {
        'path',
        'host',
        'headers',
        'maxEarlyData',
        'earlyDataHeaderName',
        'acceptProxyProtocol',
      },
      'grpcSettings': {
        'serviceName',
        'multiMode',
        'idle_timeout',
        'health_check_timeout',
        'permit_without_stream',
        'initial_windows_size',
      },
      'httpupgradeSettings': {'path', 'host', 'headers'},
      'kcpSettings': {
        'mtu',
        'tti',
        'uplinkCapacity',
        'downlinkCapacity',
        'congestion',
        'readBufferSize',
        'writeBufferSize',
        'header',
        'seed',
      },
      'tcpSettings': {'header'},
      'rawSettings': {'header'},
    };
    for (final entry in source.entries) {
      if (entry.key == 'network' || entry.key == 'security') continue;
      final allowed = fields[entry.key];
      if (allowed == null || entry.value is! Map) {
        throw const FormatException('Неподдерживаемые параметры транспорта');
      }
      final map = entry.value as Map;
      if (map['allowInsecure'] == true || map['acceptProxyProtocol'] == true) {
        throw const FormatException('Небезопасные параметры транспорта');
      }
      result[entry.key as String] = _fields(map, allowed);
    }
    return result;
  }

  Map<String, dynamic> _fields(
    Map source,
    Set<String> allowed, {
    bool ignoreUnknown = false,
  }) {
    final result = <String, dynamic>{};
    for (final entry in source.entries) {
      if (!allowed.contains(entry.key)) {
        if (ignoreUnknown) continue;
        throw const FormatException('Неподдерживаемый параметр');
      }
      _checkTree(entry.value, 0);
      result[entry.key as String] = entry.value;
    }
    return result;
  }

  void _checkTree(Object? value, int depth) {
    if (depth > 8) throw const FormatException('Слишком сложный транспорт');
    if (value is String) {
      if (value.length > 4096 || value.contains(RegExp(r'[\x00-\x1f]'))) {
        throw const FormatException('Неверная строка');
      }
    } else if (value is List) {
      if (value.length > 64) {
        throw const FormatException('Слишком большой список');
      }
      for (final item in value) {
        _checkTree(item, depth + 1);
      }
    } else if (value is Map) {
      if (value.length > 64) {
        throw const FormatException('Слишком большой объект');
      }
      for (final entry in value.entries) {
        if (entry.key is! String ||
            RegExp(
              r'file|certificate|keylog|dialerproxy|sockopt|proxysettings|downloadsettings',
              caseSensitive: false,
            ).hasMatch(entry.key as String)) {
          throw const FormatException(
            'Файлы и вложенные сетевые настройки запрещены',
          );
        }
        _checkTree(entry.value, depth + 1);
      }
    } else if (value != null && value is! num && value is! bool) {
      throw const FormatException('Неверный тип значения');
    }
  }

  Map fromUri(String text) {
    final uri = Uri.parse(text);
    if (uri.scheme != 'vless' ||
        uri.host.isEmpty ||
        !uri.hasPort ||
        uri.userInfo.isEmpty) {
      throw const FormatException('Неверная ссылка VLESS');
    }
    final q = uri.queryParameters;
    const allowedQuery = {
      'security',
      'type',
      'sni',
      'fp',
      'pbk',
      'sid',
      'spx',
      'alpn',
      'serviceName',
      'path',
      'host',
      'mode',
      'encryption',
      'flow',
    };
    if (q.keys.any((key) => !allowedQuery.contains(key))) {
      throw const FormatException('Неподдерживаемые параметры ссылки VLESS');
    }
    if (uri.queryParametersAll.values.any((v) => v.length != 1)) {
      throw const FormatException('Повторяющиеся параметры');
    }
    final security = q['security'] ?? 'none';
    final stream = <String, dynamic>{
      'network': q['type'] ?? 'tcp',
      'security': security,
    };
    if (security == 'reality') {
      stream['realitySettings'] = {
        'serverName': q['sni'] ?? '',
        'fingerprint': q['fp'] ?? 'chrome',
        'publicKey': q['pbk'] ?? '',
        'shortId': q['sid'] ?? '',
        if (q['spx'] != null) 'spiderX': q['spx'],
      };
    }
    if (security == 'tls') {
      stream['tlsSettings'] = {
        'serverName': q['sni'] ?? uri.host,
        if (q['fp'] != null) 'fingerprint': q['fp'],
        if (q['alpn'] != null) 'alpn': q['alpn']!.split(','),
      };
    }
    final transport = {
      'ws': 'wsSettings',
      'xhttp': 'xhttpSettings',
      'grpc': 'grpcSettings',
      'httpupgrade': 'httpupgradeSettings',
    }[stream['network']];
    if (transport != null) {
      stream[transport] = stream['network'] == 'grpc'
          ? {'serviceName': q['serviceName'] ?? ''}
          : {
              'path': q['path'] ?? '/',
              if (q['host'] != null) 'host': q['host'],
              if (q['mode'] != null) 'mode': q['mode'],
            };
    }
    return {
      'outbounds': [
        {
          'protocol': 'vless',
          'settings': {
            'vnext': [
              {
                'address': uri.host,
                'port': uri.port,
                'users': [
                  {
                    'id': Uri.decodeComponent(uri.userInfo),
                    'encryption': q['encryption'] ?? 'none',
                    if (q['flow'] != null) 'flow': q['flow'],
                  },
                ],
              },
            ],
          },
          'streamSettings': stream,
        },
      ],
    };
  }
}
