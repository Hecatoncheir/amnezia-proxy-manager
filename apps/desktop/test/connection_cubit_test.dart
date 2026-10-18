import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:amnezia_proxy_manager/features/connection/connection_cubit.dart';
import 'package:amnezia_proxy_manager/features/connection/supervisor_client.dart';
import 'package:amnezia_proxy_manager/features/engine/engine_manager.dart';
import 'package:amnezia_proxy_manager/features/profiles/profiles_cubit.dart';
import 'package:amnezia_proxy_manager/features/profiles/profile_vault.dart';

import 'fixtures/profile_fixtures.dart';

class MemoryVault implements ProfileVault {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String? next, {required String? expected}) async {
    value = next;
  }
}

class FakeSupervisor extends SupervisorClient {
  int starts = 0, stops = 0;
  @override
  Future<void> start({
    required String family,
    required String binary,
    required String sha256,
    required String configuration,
    int socksPort = 1080,
    int httpPort = 8080,
  }) async {
    starts++;
  }

  @override
  Future<void> stop() async {
    stops++;
  }
}

class WaitingEngine extends EngineManager {
  WaitingEngine(this.gate, Directory root) : super(directory: () async => root);
  final Future<Directory> gate;
  @override
  Future<void> ensureReady() async {
    await gate;
  }
}

void main() {
  test('Без профиля кнопка возвращает понятную ошибку', () async {
    final p = ProfilesCubit(vault: MemoryVault(), validate: (_) async {});
    await p.load();
    final awg = EngineManager(), xray = EngineManager();
    final client = FakeSupervisor();
    final c = ConnectionCubit(
      profiles: p,
      awg: awg,
      xray: xray,
      client: client,
    );
    await c.toggle();
    expect(c.state.status, ConnectionStatus.error);
    expect(client.starts, 0);
    expect(p.state.locked, false);
    await c.close();
    await p.close();
    await awg.close();
    await xray.close();
  });
  test('Отмена во время поиска runtime не запускает движок позднее', () async {
    final directory = await Directory.systemTemp.createTemp('m3-cancel');
    addTearDown(() => directory.delete(recursive: true));
    final gate = Completer<Directory>();
    final awg = WaitingEngine(gate.future, directory), xray = EngineManager();
    final p = ProfilesCubit(vault: MemoryVault(), validate: (_) async {});
    await p.load();
    await p.importBytes(utf8.encode(testConf), 'Тест');
    final client = FakeSupervisor();
    final c = ConnectionCubit(
      profiles: p,
      awg: awg,
      xray: xray,
      client: client,
    );
    final start = c.toggle();
    await Future<void>.delayed(Duration.zero);
    expect(p.state.locked, true);
    final selected = p.state.selected;
    await p.remove(selected!);
    expect(p.state.selected, selected);
    await c.stop();
    gate.complete(directory);
    await start;
    expect(client.starts, 0);
    expect(c.state.status, ConnectionStatus.disconnected);
    expect(p.state.locked, false);
    await c.close();
    await p.close();
    await awg.close();
    await xray.close();
  });
}
