import 'dart:async';
import 'dart:io';

import 'profile_codec.dart';

Future<List<int>> readLocalAmneziaProfile() async {
  final helper =
      '${File(Platform.resolvedExecutable).parent.path}/${Platform.isWindows ? 'proxy-engine.exe' : 'proxy-engine'}';
  final process = await Process.start(helper, [
    '--import-amnezia',
  ], runInShell: false);
  try {
    final stderr = process.stderr.drain<void>();
    final bytes = await _readProfileBytes(process.stdout);
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

Future<List<int>> _readProfileBytes(Stream<List<int>> output) async {
  // Первый импорт macOS может ждать два подтверждения Связки ключей.
  final timeout = Platform.isMacOS
      ? const Duration(minutes: 3)
      : const Duration(seconds: 60);
  final bytes = <int>[];
  await for (final chunk in output.timeout(timeout)) {
    if (bytes.length + chunk.length > maxProfileBytes) {
      throw const ProfileProblem('Профиль AmneziaVPN слишком большой.');
    }
    bytes.addAll(chunk);
  }
  return bytes;
}
