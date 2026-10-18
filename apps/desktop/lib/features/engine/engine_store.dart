import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'engine_release.dart';

class EngineStore {
  EngineStore(this.root, {Future<void> Function(File, String)? probe})
    : probe = probe ?? verifyEngineExecutable;
  final Directory root;
  final Future<void> Function(File, String) probe;

  File executable(EngineRelease release) => File(
    '${root.path}/runtimes/${release.asset.sha256}/${release.asset.name}',
  );

  Future<bool> valid(File file, EngineAsset asset) async {
    if (!await file.exists() || await file.length() != asset.size) return false;
    return (await sha256.bind(file.openRead()).first).toString() ==
        asset.sha256;
  }

  Future<EngineRelease?> installed(
    String applicationVersion,
    String platform,
  ) async {
    final receipt = File('${root.path}/active.json');
    if (!await receipt.exists()) return null;
    try {
      if (await receipt.length() > 32768) return null;
      final data = jsonDecode(await receipt.readAsString()) as Map;
      final release = EngineRelease.compatible(
        data['release'],
        data['manifest'],
        applicationVersion: applicationVersion,
        platform: platform,
      );
      if (release == null || !await valid(executable(release), release.asset)) {
        return null;
      }
      await probe(executable(release), platform);
      return release;
    } catch (_) {
      return null;
    }
  }

  Future<File> activate(
    File partial,
    EngineRelease release,
    String platform,
  ) async {
    if (!await valid(partial, release.asset)) {
      throw const FormatException('SHA-256 движка не совпадает');
    }
    if (!Platform.isWindows) {
      final result = await Process.run('/bin/chmod', ['700', partial.path]);
      if (result.exitCode != 0) {
        throw const FileSystemException('Не удалось разрешить запуск движка');
      }
    }
    await probe(partial, platform);
    final target = executable(release);
    await target.parent.create(recursive: true);
    await partial.rename(target.path);
    final active = File('${root.path}/active.json');
    if (await active.exists()) await active.copy('${root.path}/previous.json');
    final pending = File('${root.path}/active.json.pending');
    await pending.writeAsString(jsonEncode(release.receipt()), flush: true);
    await pending.rename(active.path);
    return target;
  }
}

Future<void> verifyEngineExecutable(File file, String platform) async {
  if (!await engineArchitectureMatches(file, platform)) {
    throw const FormatException('Неверная архитектура движка');
  }
  final process = await Process.start(file.path, ['-h'], runInShell: false);
  try {
    final output = await Future.wait([
      _boundedOutput(process.stdout),
      _boundedOutput(process.stderr),
    ]).timeout(const Duration(seconds: 10));
    if (await process.exitCode.timeout(const Duration(seconds: 2)) != 0) {
      throw const FormatException('Движок не поддерживает проверку CLI');
    }
    final help = output.join('\n');
    if (![
      '-config ',
      '-socks-listen ',
      '-http-listen ',
      '-dial-timeout ',
    ].every(help.contains)) {
      throw const FormatException('Несовместимый CLI движка');
    }
  } finally {
    process.kill();
  }
}

Future<String> _boundedOutput(Stream<List<int>> stream) async {
  final bytes = <int>[];
  await for (final chunk in stream) {
    if (bytes.length + chunk.length > 8192) {
      throw const FormatException('Слишком большой ответ CLI');
    }
    bytes.addAll(chunk);
  }
  return utf8.decode(bytes, allowMalformed: true);
}

Future<bool> engineArchitectureMatches(File file, String platform) async {
  final input = await file.open();
  try {
    final bytes = await input.read(64);
    if (bytes.length < 64) return false;
    final header = ByteData.sublistView(bytes);
    return switch (platform) {
      'windows-x64' => await _windowsHeader(input, header),
      'linux-x64' =>
        header.getUint32(0) == 0x7f454c46 &&
            bytes[4] == 2 &&
            bytes[5] == 1 &&
            header.getUint16(18, Endian.little) == 62,
      'macos-arm64' =>
        header.getUint32(0, Endian.little) == 0xfeedfacf &&
            header.getUint32(4, Endian.little) == 0x0100000c,
      _ => false,
    };
  } finally {
    await input.close();
  }
}

Future<bool> _windowsHeader(RandomAccessFile file, ByteData header) async {
  if (header.getUint16(0) != 0x4d5a) return false;
  final offset = header.getUint32(60, Endian.little);
  if (offset > 1024 * 1024) return false;
  await file.setPosition(offset);
  final bytes = await file.read(6);
  if (bytes.length != 6) return false;
  final pe = ByteData.sublistView(bytes);
  return pe.getUint32(0) == 0x50450000 &&
      pe.getUint16(4, Endian.little) == 0x8664;
}
