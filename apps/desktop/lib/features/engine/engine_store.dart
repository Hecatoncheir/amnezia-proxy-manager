import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:archive/archive.dart';

import 'engine_release.dart';

class EngineStore {
  EngineStore(
    this.root, {
    Future<void> Function(File, String)? probe,
    this.policy = enginePolicy,
  }) : probe =
           probe ??
           ((file, platform) =>
               verifyEngineExecutable(file, platform, policy: policy));
  final Map<String, dynamic> policy;
  final Directory root;
  final Future<void> Function(File, String) probe;

  File executable(EngineRelease release) => File(
    '${root.path}/runtimes/${release.asset.sha256}/${release.binaryName}',
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
        policy: policy,
      );
      if (release == null ||
          !await valid(executable(release), release.binary)) {
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
    final bytes = await partial.readAsBytes();
    final unpacked = release.asset.name.endsWith('.zip')
        ? ZipDecoder().decodeBytes(bytes)
        : TarDecoder().decodeBytes(await _gunzip(bytes));
    final matches = unpacked.files
        .where(
          (entry) =>
              entry.name ==
              (release.package['archiveBinaryName'] ?? release.binaryName),
        )
        .toList();
    final licenses = unpacked.files
        .where(
          (entry) =>
              entry.name == (release.package['licenseName'] ?? 'LICENSE'),
        )
        .toList();
    if (matches.length != 1 ||
        !matches.single.isFile ||
        matches.single.isSymbolicLink ||
        matches.single.size != release.binary.size ||
        licenses.length != 1 ||
        !licenses.single.isFile ||
        licenses.single.size > 65536) {
      throw const FormatException('Неверное содержимое архива движка');
    }
    final extracted = File('${partial.path}.exe');
    try {
      await extracted.writeAsBytes(matches.single.content, flush: true);
      if (!await valid(extracted, release.binary)) {
        throw const FormatException('SHA-256 исполняемого файла не совпадает');
      }
      return await _activateExecutable(
        extracted,
        release,
        platform,
        licenses.single.content,
      );
    } finally {
      if (await extracted.exists()) await extracted.delete();
    }
  }

  Future<File> _activateExecutable(
    File partial,
    EngineRelease release,
    String platform,
    List<int> license,
  ) async {
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
    await File('${target.parent.path}/LICENSE')
        .writeAsBytes(license, flush: true);
    final active = File('${root.path}/active.json');
    if (await active.exists()) await active.copy('${root.path}/previous.json');
    final pending = File('${root.path}/active.json.pending');
    await pending.writeAsString(jsonEncode(release.receipt()), flush: true);
    await pending.rename(active.path);
    return target;
  }
}

Future<void> verifyEngineExecutable(
  File file,
  String platform, {
  Map<String, dynamic> policy = enginePolicy,
}) async {
  if (policy['family'] == 'tun') {
    await _verifyTun(file, platform, policy);
    return;
  }
  if (policy['family'] == 'xray') {
    if (!await engineArchitectureMatches(file, platform)) {
      throw const FormatException('Неверная архитектура Xray');
    }
    final result = await Process.run(file.path, [
      'version',
    ], runInShell: false).timeout(const Duration(seconds: 10));
    if (result.exitCode != 0 ||
        !result.stdout.toString().startsWith('Xray ${policy['version']} ')) {
      throw const FormatException('Несовместимая версия Xray');
    }
    return;
  }
  if (!await engineArchitectureMatches(file, platform)) {
    throw const FormatException('Неверная архитектура движка');
  }
  final process = await Process.start(
    file.path,
    ['--help'],
    runInShell: false,
    environment: {'WIREPROXY_ADMIN': '', 'WIREPROXY_ADMIN_TOKEN': ''},
  );
  try {
    final output = await Future.wait([
      _boundedOutput(process.stdout),
      _boundedOutput(process.stderr),
    ]).timeout(const Duration(seconds: 10));
    if (await process.exitCode.timeout(const Duration(seconds: 2)) != 0) {
      throw const FormatException('Движок не поддерживает проверку CLI');
    }
    final help = output.join('\n');
    if (!['--config ', '--configtest', '--version'].every(help.contains)) {
      throw const FormatException('Несовместимый CLI движка');
    }
    final version = await Process.run(file.path, [
      '--version',
    ], runInShell: false).timeout(const Duration(seconds: 10));
    if (version.exitCode != 0 ||
        version.stdout.toString().trim() != 'wireproxy, version 2.1.0') {
      throw const FormatException('Несовместимая версия движка');
    }
  } finally {
    process.kill();
  }
}

Future<void> _verifyTun(
  File file,
  String platform,
  Map<String, dynamic> policy,
) async {
  if (!await engineArchitectureMatches(file, platform)) {
    throw const FormatException('Неверная архитектура TUN');
  }
  final result = await Process.run(file.path, [
    'version',
  ], runInShell: false).timeout(const Duration(seconds: 10));
  if (result.exitCode != 0 ||
      !result.stdout.toString().startsWith(
        'sing-box version ${policy['version']}\n',
      )) {
    throw const FormatException('Несовместимая версия TUN');
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

Future<List<int>> _gunzip(List<int> bytes) async {
  final result = BytesBuilder(copy: false);
  await for (final chunk in gzip.decoder.bind(Stream.value(bytes))) {
    if (result.length + chunk.length > 256 * 1024 * 1024) {
      throw const FormatException('Архив движка слишком большой');
    }
    result.add(chunk);
  }
  return result.takeBytes();
}
