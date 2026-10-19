// Нативная проверка: профиль читается в память, порты выбираются отдельно от приложения.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:amnezia_proxy_manager/features/connection/supervisor_client.dart';
import 'package:amnezia_proxy_manager/features/engine/engine_manager.dart';
import 'package:amnezia_proxy_manager/features/engine/engine_store.dart';
import 'package:amnezia_proxy_manager/features/engine/xray_policy.dart';
import 'package:amnezia_proxy_manager/features/profiles/local_profile_import.dart';
import 'package:amnezia_proxy_manager/features/profiles/profile_codec.dart';
import 'package:amnezia_proxy_manager/features/updates/app_updates.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SizedBox());
  final client = SupervisorClient();
  final report = <String, Object?>{};
  EngineManager? engine;
  Map<String, dynamic> latest = {};
  Object? traffic;
  final subscription = client.events.listen((value) {
    latest = value;
    if (value['traffic'] is Map) traffic = value['traffic'];
  });
  try {
    final profile = await ProfileCodec().decode(
      await readLocalAmneziaProfile(),
    );
    engine = profile.format == 'VLESS'
        ? EngineManager(policy: xrayPolicy)
        : EngineManager();
    await engine.ensureReady();
    final store = EngineStore(await engine.directory(), policy: engine.policy);
    final release = await store.installed(
      await installedAppVersion(),
      engine.platform,
    );
    if (release == null) throw const SessionProblem('missing_engine');
    final sockets = [
      await ServerSocket.bind('127.0.0.1', 0),
      await ServerSocket.bind('127.0.0.1', 0),
    ];
    final socks = sockets[0].port, http = sockets[1].port;
    for (final socket in sockets) {
      await socket.close();
    }
    Future<void> start() async {
      await client.start(
        family: profile.format == 'VLESS' ? 'xray' : 'awg',
        binary: store.executable(release).absolute.path,
        sha256: release.binary.sha256,
        configuration: profile.configuration,
        socksPort: socks,
        httpPort: http,
      );
      await waitFor(() => latest['connectivity'] == 'verified');
    }

    await start();
    report['httpsViaSocks'] = true;
    final web = HttpClient()..findProxy = (_) => 'PROXY 127.0.0.1:$http';
    try {
      final request = await web
          .getUrl(Uri.parse('https://example.com/'))
          .timeout(const Duration(seconds: 30));
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      report['httpsViaHTTP'] = response.statusCode;
      if (response.statusCode != 200) {
        throw const SessionProblem('http_check_failed');
      }
      await response.drain<void>();
    } finally {
      web.close(force: true);
    }
    await waitFor(() => latest['traffic'] is Map);
    await client.check();
    await waitFor(() => latest['connectivity'] == 'verified');
    await client.stop();
    report['traffic'] = traffic;
    final counters = traffic as Map;
    if ((counters['download'] as int) <= 0 ||
        (counters['upload'] as int) <= 0) {
      throw const SessionProblem('traffic_missing');
    }
    // Последнее состояние не содержит секретов; счётчики наблюдаем отдельно.
    report['stopped'] = latest['status'] == 'disconnected';
    await start();
    report['reconnected'] = true;
    await client.stop();
    report['success'] = true;
  } catch (_) {
    report['success'] = false;
  } finally {
    await client.close();
    await subscription.cancel();
    await engine?.close();
    await File(args.first).writeAsString(jsonEncode(report));
    exit(report['success'] == true ? 0 : 2);
  }
}

Future<void> waitFor(bool Function() ready) async {
  final deadline = DateTime.now().add(const Duration(seconds: 45));
  while (!ready()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Проверка не завершилась');
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}
