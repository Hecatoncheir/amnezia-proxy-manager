// Явный нативный тест: устанавливает Xray, импортирует текущий профиль AmneziaVPN
// в рабочее защищённое хранилище и выполняет HTTPS через отдельный SOCKS5.
// Включается только отдельным запуском этого файла; секреты в отчёт не попадают.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:amnezia_proxy_manager/features/engine/engine_manager.dart';
import 'package:amnezia_proxy_manager/features/engine/engine_store.dart';
import 'package:amnezia_proxy_manager/features/engine/xray_policy.dart';
import 'package:amnezia_proxy_manager/features/profiles/local_profile_import.dart';
import 'package:amnezia_proxy_manager/features/profiles/profile_codec.dart';
import 'package:amnezia_proxy_manager/features/profiles/profile_validator.dart';
import 'package:amnezia_proxy_manager/features/profiles/profile_vault.dart';
import 'package:amnezia_proxy_manager/features/profiles/profiles_cubit.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const output = String.fromEnvironment('XRAY_PROBE_OUTPUT');
  if (output.isEmpty) exit(2);
  final awg = EngineManager(), xray = EngineManager(policy: xrayPolicy);
  final profiles = ProfilesCubit(
    vault: SystemProfileVault(),
    validate: EngineProfileValidator(awg, xray: xray).validate,
  );
  final report = <String, Object?>{'passed': false, 'phase': 'download'};
  try {
    await xray.check();
    report['catalogStatus'] = xray.state.status.name;
    if (xray.state.status == EngineStatus.available) await xray.download();
    report['downloadStatus'] = xray.state.status.name;
    if (xray.state.status != EngineStatus.ready) {
      throw StateError('Движок не готов');
    }
    report['phase'] = 'import';
    await profiles.load();
    await profiles.importLocal();
    report['importMessage'] = profiles.state.message;
    final selected = profiles.state.profiles
        .where((p) => p.id == profiles.state.selected)
        .firstOrNull;
    if (selected?.family != 'xray' || selected!.temporary) {
      throw StateError('Профиль не сохранён');
    }
    report['phase'] = 'network';
    final config = await ProfileCodec().decode(await readLocalAmneziaProfile());
    const gate = String.fromEnvironment('XRAY_PROBE_GATE');
    if (gate.isNotEmpty) {
      report['phase'] = 'waitingForDisconnect';
      await File(output).writeAsString(jsonEncode(report));
      final deadline = DateTime.now().add(const Duration(minutes: 5));
      while (!await File(gate).exists()) {
        if (DateTime.now().isAfter(deadline)) {
          throw StateError('Истёк срок ожидания');
        }
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    }
    final store = EngineStore(await xray.directory(), policy: xrayPolicy);
    final release = await store.installed('0.1.1', xray.platform);
    final helper =
        '${File(Platform.resolvedExecutable).parent.path}/proxy-engine.exe';
    final process = await Process.start(helper, [
      '--probe-xray',
      store.executable(release!).absolute.path,
      '--sha256',
      release.binary.sha256,
    ], runInShell: false);
    final stdout = process.stdout.drain<void>();
    final stderr = process.stderr.transform(utf8.decoder).join();
    process.stdin.add(utf8.encode(config.configuration));
    await process.stdin.close();
    final code = await process.exitCode.timeout(
      const Duration(seconds: 45),
      onTimeout: () {
        process.kill();
        return -1;
      },
    );
    await stdout;
    final diagnostic = await stderr;
    final marker = RegExp(r'диагностика=([a-z ,]*)').firstMatch(diagnostic);
    report['networkDiagnostic'] = marker?[1];
    report['networkExitCode'] = code;
    report['passed'] = code == 0;
    report['phase'] = 'finished';
    report['engine'] = release.tag;
    report['profiles'] = profiles.state.profiles.length;
  } catch (error) {
    report['errorType'] = error.runtimeType.toString();
  }
  final file = File(output);
  await file.parent.create(recursive: true);
  await file.writeAsString(jsonEncode(report));
  await profiles.close();
  await awg.close();
  await xray.close();
  exit(report['passed'] == true ? 0 : 1);
}
