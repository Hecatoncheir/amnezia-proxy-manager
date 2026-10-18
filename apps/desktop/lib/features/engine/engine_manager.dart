import 'dart:io';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../updates/app_updates.dart'
    show installedAppPlatform, installedAppVersion, AppVersion;
import 'engine_catalog.dart';
import 'engine_release.dart';
import 'engine_store.dart';
import 'github_assets.dart';

enum EngineStatus {
  checking,
  unavailable,
  available,
  downloading,
  ready,
  failed,
}

class EngineState {
  const EngineState(
    this.status, {
    this.release,
    this.installed,
    this.progress = 0,
    this.offline = false,
  });
  final EngineStatus status;
  final EngineRelease? release, installed;
  final double progress;
  final bool offline;
}

class EngineManager extends Cubit<EngineState> {
  EngineManager({
    http.Client? client,
    String? platform,
    Future<String> Function()? readVersion,
    Future<Directory> Function()? directory,
    this.probe,
  }) : client = client ?? http.Client(),
       platform = platform ?? installedAppPlatform(),
       readVersion = readVersion ?? installedAppVersion,
       directory = directory ?? _engineDirectory,
       super(const EngineState(EngineStatus.checking));
  final http.Client client;
  final String platform;
  final Future<String> Function() readVersion;
  final Future<Directory> Function() directory;
  final Future<void> Function(File, String)? probe;
  bool _busy = false;
  EngineStore? _store;

  Future<void> check() async {
    if (_busy || isClosed) return;
    _busy = true;
    EngineRelease? installed;
    _publish(const EngineState(EngineStatus.checking));
    try {
      final version = await readVersion();
      _store = EngineStore(await directory(), probe: probe);
      installed = await _store!.installed(version, platform);
      final release = await EngineCatalog(client)
          .latestCompatible(version, platform);
      final newer = _newer(release, installed);
      var status = installed != null
          ? EngineStatus.ready
          : EngineStatus.unavailable;
      if (newer) status = EngineStatus.available;
      _publish(EngineState(status, release: release, installed: installed));
    } catch (_) {
      _publish(
        EngineState(
          installed != null ? EngineStatus.ready : EngineStatus.failed,
          installed: installed,
          offline: true,
        ),
      );
    } finally {
      _busy = false;
    }
  }

  Future<void> download() async {
    final release = state.release, installed = state.installed;
    final store = _store;
    if (_busy ||
        isClosed ||
        release == null ||
        store == null ||
        state.status != EngineStatus.available) {
      return;
    }
    _busy = true;
    _publish(
      EngineState(
        EngineStatus.downloading,
        release: release,
        installed: installed,
      ),
    );
    File? partial;
    RandomAccessFile? installationLock;
    try {
      await store.root.create(recursive: true);
      installationLock = await File('${store.root.path}/install.lock')
          .open(mode: FileMode.append);
      await installationLock.lock(FileLock.exclusive);
      partial = File('${store.root.path}/${release.asset.sha256}.part');
      final response = await openGitHubAsset(client, release.asset.url);
      if (response.statusCode != 200) {
        throw const FormatException('Не удалось скачать движок');
      }
      if (response.contentLength != null &&
          response.contentLength != release.asset.size) {
        throw const FormatException('Неверный размер движка');
      }
      final writer = partial.openWrite();
      var received = 0;
      try {
        await for (final chunk in response.stream.timeout(
          const Duration(seconds: 30),
        )) {
          if (isClosed || received + chunk.length > release.asset.size) {
            throw const FormatException('Загрузка прервана');
          }
          writer.add(chunk);
          received += chunk.length;
          _publish(
            EngineState(
              EngineStatus.downloading,
              release: release,
              installed: installed,
              progress: received / release.asset.size,
            ),
          );
        }
      } finally {
        await writer.close();
      }
      if (isClosed) return;
      await store.activate(partial, release, platform);
      _publish(
        EngineState(EngineStatus.ready, installed: release, release: release),
      );
    } catch (_) {
      _publish(
        EngineState(
          EngineStatus.failed,
          installed: installed,
          release: release,
        ),
      );
    } finally {
      try {
        if (partial != null && await partial.exists()) await partial.delete();
      } on FileSystemException {
        // Незавершённый файл не активирован; его можно заменить при повторе.
      }
      _busy = false;
      await installationLock?.close();
    }
  }

  void _publish(EngineState next) {
    if (!isClosed) emit(next);
  }

  @override
  Future<void> close() async {
    client.close();
    await super.close();
  }
}

bool _newer(EngineRelease? release, EngineRelease? installed) {
  if (release == null) return false;
  if (installed == null) return true;
  return AppVersion.parse(release.tag)!
          .compareTo(AppVersion.parse(installed.tag)!) >
      0;
}

Future<Directory> _engineDirectory() async =>
    Directory('${(await getApplicationSupportDirectory()).path}/engines');
