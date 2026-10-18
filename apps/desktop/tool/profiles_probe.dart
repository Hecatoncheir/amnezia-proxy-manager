// Нативная проверка системного хранилища на синтетических профилях.
import 'dart:convert';
import 'dart:io';

import 'package:amnezia_proxy_manager/features/engine/engine_manager.dart';
import 'package:amnezia_proxy_manager/features/profiles/profile_validator.dart';
import 'package:amnezia_proxy_manager/features/profiles/profile_vault.dart';
import 'package:amnezia_proxy_manager/features/profiles/profiles_cubit.dart';
import 'package:flutter/widgets.dart';

import '../test/fixtures/profile_fixtures.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const phase = String.fromEnvironment(
    'PROFILE_PROBE_PHASE',
    defaultValue: 'write',
  );
  const output = String.fromEnvironment('PROFILE_PROBE_OUTPUT');
  if (output.isEmpty) exit(2);
  final engine = EngineManager();
  final vault = SystemProfileVault(key: 'amnezia_m2_native_probe_v1');
  final profiles = ProfilesCubit(
    vault: vault,
    validate: EngineProfileValidator(engine).validate,
  );
  var passed = false;
  try {
    await profiles.load();
    if (phase == 'write') {
      if (await vault.read() != null) {
        throw StateError('Тестовое хранилище уже занято');
      }
      await profiles.importBytes(utf8.encode(testConf), 'Тест CONF');
      await profiles.importBytes(utf8.encode(vpnUri(exportJson())), 'Тест VPN');
      passed =
          profiles.state.profiles.length == 2 && !profiles.state.offerTemporary;
    } else {
      passed =
          profiles.state.profiles.length == 2 &&
          profiles.state.profiles.last.id == profiles.state.selected;
      await profiles.checkSelected();
      passed =
          passed &&
          profiles.state.message ==
              'Конфигурация принята движком. VPN-подключение не запускалось.';
      for (final profile in [...profiles.state.profiles]) {
        await profiles.remove(profile.id);
      }
      passed =
          passed &&
          await vault.read() == null &&
          profiles.state.profiles.isEmpty;
    }
  } catch (_) {
    passed = false;
  }
  final result = File(output);
  await result.parent.create(recursive: true);
  await result.writeAsString(
    jsonEncode({
      'passed': passed,
      'phase': phase,
      'profiles': profiles.state.profiles.length,
      'message': profiles.state.message,
    }),
  );
  await profiles.close();
  await engine.close();
  exit(passed ? 0 : 1);
}
