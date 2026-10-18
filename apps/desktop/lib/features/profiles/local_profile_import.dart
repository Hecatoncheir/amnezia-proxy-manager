import 'dart:async';
import 'dart:io';

import 'profile_codec.dart';

Future<List<int>> readLocalAmneziaProfile() async {
  if (!Platform.isWindows) {
    throw const ProfileProblem(
      'Локальный импорт пока доступен только в Windows.',
    );
  }
  final helper =
      '${File(Platform.resolvedExecutable).parent.path}/proxy-engine.exe';
  final process = await Process.start(helper, [
    '--import-amnezia',
  ], runInShell: false);
  try {
    final stderr = process.stderr.drain<void>();
    final bytes = <int>[];
    await for (final chunk in process.stdout.timeout(
      const Duration(seconds: 10),
    )) {
      if (bytes.length + chunk.length > maxProfileBytes) {
        throw const ProfileProblem('Профиль AmneziaVPN слишком большой.');
      }
      bytes.addAll(chunk);
    }
    final code = await process.exitCode.timeout(const Duration(seconds: 2));
    await stderr;
    if (code != 0 || bytes.isEmpty) {
      throw const ProfileProblem(
        'Не удалось получить выбранный профиль AmneziaVPN. Поддерживаются сохранённые клиентские конфигурации AWG/VLESS текущего пользователя.',
      );
    }
    return bytes;
  } finally {
    process.kill();
  }
}
