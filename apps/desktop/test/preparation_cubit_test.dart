import 'dart:convert';

import 'package:amnezia_proxy_manager/features/dashboard/preparation_cubit.dart';
import 'package:amnezia_proxy_manager/features/engine/engine_manager.dart';
import 'package:amnezia_proxy_manager/features/profiles/profile_vault.dart';
import 'package:amnezia_proxy_manager/features/profiles/profiles_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

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

class TestEngine extends EngineManager {
  void update(EngineState state) => emit(state);
}

void main() {
  test(
    'Показывается только нужный движок: загрузка, установка, готовность',
    () async {
      final profiles = ProfilesCubit(
        vault: MemoryVault(),
        validate: (_) async {},
      );
      final awg = TestEngine(), xray = TestEngine();
      await profiles.load();
      await profiles.importBytes(utf8.encode(testConf), 'Тест');
      final preparation = PreparationCubit(
        profiles: profiles,
        awg: awg,
        xray: xray,
      );
      addTearDown(() async {
        await preparation.close();
        await profiles.close();
        await awg.close();
        await xray.close();
      });
      xray.update(const EngineState(EngineStatus.downloading, progress: 0.8));
      await Future<void>.delayed(Duration.zero);
      expect(preparation.state.message, isNull);
      awg.update(const EngineState(EngineStatus.downloading, progress: 0.34));
      await Future<void>.delayed(Duration.zero);
      expect(preparation.state.progress, 0.34);
      awg.update(const EngineState(EngineStatus.installing));
      await Future<void>.delayed(Duration.zero);
      expect(preparation.state.installing, true);
      expect(preparation.state.progress, isNull);
      awg.update(const EngineState(EngineStatus.ready));
      await Future<void>.delayed(Duration.zero);
      expect(preparation.state.message, isNull);
    },
  );
}
