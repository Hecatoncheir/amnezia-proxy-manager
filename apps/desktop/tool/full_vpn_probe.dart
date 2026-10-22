// Явная нативная проверка полного VPN с текущим профилем AmneziaVPN.
// В отчёт попадают только состояния и результаты; профиль остаётся в памяти.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:amnezia_proxy_manager/features/connection/supervisor_client.dart';
import 'package:amnezia_proxy_manager/features/engine/engine_manager.dart';
import 'package:amnezia_proxy_manager/features/engine/engine_store.dart';
import 'package:amnezia_proxy_manager/features/engine/tun_policy.dart';
import 'package:amnezia_proxy_manager/features/engine/xray_policy.dart';
import 'package:amnezia_proxy_manager/features/profiles/local_profile_import.dart';
import 'package:amnezia_proxy_manager/features/profiles/profile_codec.dart';
import 'package:amnezia_proxy_manager/features/updates/app_updates.dart';

Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SizedBox());
  final result = await FullVpnProbe().run();
  await File(arguments.single).writeAsString(jsonEncode(result));
  exit(result['success'] == true ? 0 : 2);
}

class FullVpnProbe {
  final client = SupervisorClient();
  final tun = EngineManager(policy: tunPolicy);
  final report = <String, Object?>{'success': false};
  Map<String, dynamic> state = {};
  late final EngineManager backend;
  late final String family, configuration;
  late final (String, String) backendFile, tunFile;

  Future<Map<String, Object?>> run() async {
    final events = client.events.listen((value) => state = value);
    try {
      await _prepare();
      await _cycle();
      report['firstConnection'] = true;
      await _cycle();
      report['reconnected'] = true;
      await _https();
      report['internetRestored'] = true;
      report['success'] = true;
    } catch (error) {
      report['error'] = _safeError(error);
      report['stateCode'] = state['code'];
    } finally {
      await _cleanup();
      await events.cancel();
      await tun.close();
    }
    return report;
  }

  String _safeError(Object error) {
    if (error is SessionProblem) return error.code;
    return error.runtimeType.toString();
  }

  Future<void> _prepare() async {
    final profile = await ProfileCodec().decode(
      await readLocalAmneziaProfile(),
    );
    family = profile.format == 'VLESS' ? 'xray' : 'awg';
    configuration = profile.configuration;
    backend = family == 'xray'
        ? EngineManager(policy: xrayPolicy)
        : EngineManager();
    try {
      backendFile = await _runtime(backend);
      tunFile = await _runtime(tun);
    } finally {
      await backend.close();
    }
    report['family'] = family;
    report['prepared'] = true;
  }

  Future<(String, String)> _runtime(EngineManager manager) async {
    await manager.ensureReady();
    final store = EngineStore(
      await manager.directory(),
      policy: manager.policy,
    );
    final release = await store.installed(
      await installedAppVersion(),
      manager.platform,
    );
    if (release == null) throw const SessionProblem('missing_engine');
    return (store.executable(release).absolute.path, release.binary.sha256);
  }

  Future<void> _cycle() async {
    final socks = await _freePort();
    final http = await _freePort();
    await client.start(
      family: family,
      binary: backendFile.$1,
      sha256: backendFile.$2,
      configuration: configuration,
      socksPort: socks,
      httpPort: http,
      allTraffic: true,
      tunBinary: tunFile.$1,
    );
    await _waitForNetwork();
    await _verifyTunnel();
    await client.stop();
    if (state['status'] != 'disconnected' ||
        state['internetBlocked'] != false) {
      throw const SessionProblem('stop_failed');
    }
    report['stoppedAndUnblocked'] = true;
  }

  Future<int> _freePort() async {
    final socket = await ServerSocket.bind('127.0.0.1', 0);
    final port = socket.port;
    await socket.close();
    return port;
  }

  Future<void> _waitForNetwork() async {
    final deadline = DateTime.now().add(const Duration(seconds: 45));
    while (state['connectivity'] != 'verified') {
      if (state['status'] == 'error') throw const SessionProblem('vpn_failed');
      if (DateTime.now().isAfter(deadline)) throw TimeoutException('VPN');
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  Future<void> _verifyTunnel() async {
    if (state['internetBlocked'] != true) {
      throw const SessionProblem('protection_missing');
    }
    final route = await Process.run('/sbin/route', ['-n', 'get', '1.1.1.1']);
    if (!RegExp(r'interface:\s+utun233\b').hasMatch(route.stdout.toString())) {
      throw const SessionProblem('tun_route_missing');
    }
    report['routeViaTun'] = true;
    await _https();
    report['httpsWithoutProxy'] = 200;
    report['protectionEnabled'] = true;
  }

  Future<void> _https() async {
    final web = HttpClient()..findProxy = (_) => 'DIRECT';
    try {
      final request = await web
          .getUrl(Uri.parse('https://example.com/'))
          .timeout(const Duration(seconds: 20));
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      if (response.statusCode != 200) {
        throw const SessionProblem('https_failed');
      }
      await response.drain<void>().timeout(const Duration(seconds: 20));
    } finally {
      web.close(force: true);
    }
  }

  Future<void> _cleanup() async {
    try {
      await client.stop();
      await client.close();
    } catch (_) {
      report['success'] = false;
      report['cleanupFailed'] = true;
    }
  }
}
