import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../engine/engine_manager.dart';
import '../engine/engine_store.dart';
import '../updates/app_updates.dart' show installedAppVersion;
import 'profile_codec.dart';

class EngineProfileValidator {
  EngineProfileValidator(this.engine, {this.xray, String? supervisor})
    : supervisor =
          supervisor ??
          '${File(Platform.resolvedExecutable).parent.path}/${Platform.isWindows ? 'proxy-engine.exe' : 'proxy-engine'}';
  final EngineManager engine;
  final EngineManager? xray;
  final String supervisor;

  Future<void> validate(String core) async {
    final isXray = core.trimLeft().startsWith('{');
    final runtime = isXray ? xray : engine;
    if (runtime == null) throw const ProfileProblem('Движок Xray недоступен.');
    try {
      await runtime.ensureReady();
    } catch (_) {
      throw const ProfileProblem(
        'Не удалось скачать или проверить движок. Проверьте доступ к GitHub и повторите попытку в меню «Движки».',
      );
    }
    final store = EngineStore(
      await runtime.directory(),
      policy: runtime.policy,
    );
    final installed = await store.installed(
      await installedAppVersion(),
      runtime.platform,
    );
    if (installed == null) {
      throw ProfileProblem(
        isXray
            ? 'Сначала скачайте движок Xray, затем повторите импорт.'
            : 'Сначала установите движок AmneziaWG.',
      );
    }
    if (!await File(supervisor).exists()) {
      throw const ProfileProblem(
        'Не найден компонент проверки профилей. Переустановите приложение.',
      );
    }
    final config = isXray
        ? core
        : '$core\n[Socks5]\nBindAddress = 127.0.0.1:1080\n\n[http]\nBindAddress = 127.0.0.1:8080\n';
    final process = await Process.start(supervisor, [
      isXray ? '--validate-xray' : '--validate-config',
      store.executable(installed).absolute.path,
      '--sha256',
      installed.binary.sha256,
    ], runInShell: false);
    try {
      // Вывод полностью отбрасывается: upstream может включить ключ в ошибку.
      final stdout = process.stdout.drain<void>();
      final stderr = process.stderr.drain<void>();
      process.stdin.add(utf8.encode(config));
      await process.stdin.close();
      final code = await process.exitCode.timeout(const Duration(seconds: 18));
      await Future.wait([stdout, stderr]).timeout(const Duration(seconds: 2));
      if (code != 0) {
        throw const ProfileProblem(
          'Движок отклонил конфигурацию. Проверьте параметры экспорта.',
        );
      }
    } on TimeoutException {
      throw const ProfileProblem('Движок не ответил на проверку конфигурации.');
    } finally {
      process.kill();
    }
  }
}
