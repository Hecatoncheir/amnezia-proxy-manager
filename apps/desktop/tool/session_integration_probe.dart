import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:amnezia_proxy_manager/features/connection/connection_cubit.dart';
import 'package:amnezia_proxy_manager/features/engine/engine_manager.dart';
import 'package:amnezia_proxy_manager/features/engine/xray_policy.dart';
import 'package:amnezia_proxy_manager/features/profiles/profile_vault.dart';
import 'package:amnezia_proxy_manager/features/profiles/profiles_cubit.dart';
import 'package:amnezia_proxy_manager/features/profiles/profile_validator.dart';

import '../test/fixtures/profile_fixtures.dart';

import 'package:amnezia_proxy_manager/features/profiles/profile_codec.dart';
import 'package:amnezia_proxy_manager/features/profiles/local_profile_import.dart';

class MemoryVault implements ProfileVault {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String? next, {required String? expected}) async {
    value = next;
  }
}

Future<void> waitFor(ConnectionCubit c, bool network) async {
  final until = DateTime.now().add(const Duration(seconds: 40));
  while (DateTime.now().isBefore(until)) {
    if (c.state.status == ConnectionStatus.error) {
      throw StateError(c.state.message ?? 'error');
    }
    if (c.state.status == ConnectionStatus.running &&
        (!network || c.state.connectivity == 'verified')) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw StateError('timeout');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const output = String.fromEnvironment('M3_PROBE_OUTPUT');
  if (output.isEmpty) exit(2);
  final report = <String, Object?>{'passed': false};
  final awg = EngineManager(), xray = EngineManager(policy: xrayPolicy);
  final profiles = ProfilesCubit(
    vault: SystemProfileVault(),
    validate: EngineProfileValidator(awg, xray: xray).validate,
  );
  final connection = ConnectionCubit(profiles: profiles, awg: awg, xray: xray);
  ProfilesCubit? synthetic;
  ConnectionCubit? awgConnection;
  try {
    await profiles.load();
    if (profiles.state.requiredEngine != 'xray') {
      throw StateError('no_selected_vless');
    }
    final local = await ProfileCodec().decode(await readLocalAmneziaProfile());
    await profiles.withSelectedForConnection((family, config) async {
      report['selectedMatchesLocal'] = config == local.configuration;
    });
    profiles.lockForConnection(false);
    if (report['selectedMatchesLocal'] == false &&
        profiles.state.profiles
                .where((p) => p.id == profiles.state.selected)
                .single
                .name ==
            'AmneziaVPN') {
      await profiles.importLocal();
      report['profileRefreshed'] = true;
    }
    await connection.toggle();
    await waitFor(connection, false);
    final networkDeadline = DateTime.now().add(const Duration(seconds: 30));
    while (connection.state.connectivity == 'checking' &&
        DateTime.now().isBefore(networkDeadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    report['vlessHTTPS'] = connection.state.connectivity;
    report['profileLocked'] = profiles.state.locked;
    await connection.stop();
    report['vlessStopped'] = connection.state.status.name;
    await connection.toggle();
    await waitFor(connection, false);
    await connection.stop();
    report['vlessRestart'] = true;
    synthetic = ProfilesCubit(
      vault: MemoryVault(),
      validate: EngineProfileValidator(awg, xray: xray).validate,
    );
    await synthetic.load();
    await synthetic.importBytes(utf8.encode(testConf), 'Тестовый AWG');
    awgConnection = ConnectionCubit(profiles: synthetic, awg: awg, xray: xray);
    await awgConnection.toggle();
    await waitFor(awgConnection, false);
    report['awgListeners'] = awgConnection.state.status.name;
    await awgConnection.close();
    report['awgClosed'] = true;
    for (final port in [1080, 8080]) {
      final server = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        port,
      );
      await server.close();
    }
    report['portsReleased'] = true;
    report['passed'] = true;
  } catch (error) {
    report['errorType'] = error.runtimeType.toString();
    report['connectionStatus'] = connection.state.status.name;
    report['connectivity'] = connection.state.connectivity;
    report['message'] = connection.state.message;
  } finally {
    await connection.close();
    await awgConnection?.close();
    await profiles.close();
    await synthetic?.close();
    await awg.close();
    await xray.close();
    await File(output).writeAsString(jsonEncode(report));
  }
  exit(report['passed'] == true ? 0 : 1);
}
