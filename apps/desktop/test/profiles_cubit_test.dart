import 'dart:convert';

import 'package:amnezia_proxy_manager/features/profiles/profile_vault.dart';
import 'package:amnezia_proxy_manager/features/profiles/profiles_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/profile_fixtures.dart';

class MemoryVault implements ProfileVault {
  String? value;
  bool unavailable = false;
  @override
  Future<String?> read() async {
    if (unavailable) throw StateError('Недоступно');
    return value;
  }

  @override
  Future<void> write(String? next, {required String? expected}) async {
    if (unavailable || expected != value) {
      throw StateError('Нет доступа или конфликт');
    }
    value = next;
  }
}

void main() {
  test('Автопоиск откладывает проверку и сохранение до подключения', () async {
    final vault = MemoryVault();
    var checks = 0;
    final profiles = ProfilesCubit(
      vault: vault,
      validate: (_) async {
        checks++;
      },
    );
    addTearDown(profiles.close);
    await profiles.load();
    await profiles.discoverLocal(reader: () async => utf8.encode(testConf));
    expect(vault.value, isNull);
    expect(checks, 0);
    expect(profiles.state.message, contains('Найден профиль'));
    await profiles.importDetected();
    expect(checks, 1);
    expect(profiles.state.profiles.single.name, 'AmneziaVPN');
    await profiles.discoverLocal(
      reader: () async => throw StateError('Не читать'),
    );
    await profiles.importDetected();
    expect(checks, 1);
  });

  test('Ошибка автопоиска оставляет ручной импорт доступным', () async {
    final profiles = ProfilesCubit(
      vault: MemoryVault(),
      validate: (_) async {},
    );
    addTearDown(profiles.close);
    await profiles.load();
    await profiles.discoverLocal(
      reader: () async => throw StateError(testPrivateKey),
    );
    expect(profiles.state.message, isNot(contains(testPrivateKey)));
    await profiles.importBytes(utf8.encode(testConf), 'Вручную');
    expect(profiles.state.profiles.single.name, 'Вручную');
  });

  test(
    'Неудачная автоматическая проверка не сохраняет профиль и допускает повтор',
    () async {
      final vault = MemoryVault();
      var fail = true;
      final profiles = ProfilesCubit(
        vault: vault,
        validate: (_) async {
          if (fail) throw StateError('ошибка');
        },
      );
      addTearDown(profiles.close);
      await profiles.load();
      await profiles.discoverLocal(reader: () async => utf8.encode(testConf));
      await expectLater(profiles.importDetected(), throwsA(isA<Exception>()));
      expect(vault.value, isNull);
      fail = false;
      await profiles.importDetected();
      expect(profiles.state.selected, isNotNull);
    },
  );

  test('Импорт проверяет движком до записи, восстановление, выбор и удаление ключей', () async {
    final vault = MemoryVault();
    var checks = 0;
    ProfilesCubit manager() => ProfilesCubit(
      vault: vault,
      validate: (config) async {
        expect(config, contains(testPrivateKey));
        expect(vault.value, isNull);
        checks++;
      },
    );
    final first = manager();
    await first.load();
    await first.importBytes(utf8.encode(testConf), 'Первый');
    expect(checks, 1);
    expect(first.state.profiles.single.name, 'Первый');
    expect(first.state.message, isNot(contains(testPrivateKey)));
    final id = first.state.selected;
    await first.close();
    final restored = manager();
    await restored.load();
    expect(restored.state.selected, id);
    expect(restored.state.profiles.single.name, 'Первый');
    await restored.remove(id!);
    expect(vault.value, isNull);
    expect(restored.state.profiles, isEmpty);
    await restored.close();
  });

  test('Отказ configtest ничего не сохраняет и не раскрывает stderr', () async {
    final vault = MemoryVault();
    final manager = ProfilesCubit(
      vault: vault,
      validate: (_) async => throw StateError(testPrivateKey),
    );
    addTearDown(manager.close);
    await manager.load();
    await manager.importBytes(utf8.encode(testConf), 'Проверка');
    expect(vault.value, isNull);
    expect(manager.state.profiles, isEmpty);
    expect(manager.state.message, isNot(contains(testPrivateKey)));
  });

  test(
    'Временный профиль требует явного действия и не пишется в хранилище',
    () async {
      final vault = MemoryVault()..unavailable = true;
      final manager = ProfilesCubit(vault: vault, validate: (_) async {});
      await manager.load();
      await manager.importBytes(utf8.encode(testConf), 'Временный');
      expect(manager.state.profiles, isEmpty);
      expect(manager.state.offerTemporary, true);
      manager.useTemporary();
      expect(manager.state.profiles.single.temporary, true);
      expect(vault.value, isNull);
      await manager.remove(manager.state.selected!);
      expect(manager.state.profiles, isEmpty);
      await manager.close();
    },
  );

  test('Отмена временного импорта не добавляет профиль', () async {
    final vault = MemoryVault()..unavailable = true;
    final manager = ProfilesCubit(vault: vault, validate: (_) async {});
    addTearDown(manager.close);
    await manager.load();
    await manager.importBytes(utf8.encode(testConf), 'Отмена');
    manager.cancelTemporary();
    expect(manager.state.offerTemporary, false);
    expect(manager.state.profiles, isEmpty);
  });

  test(
    'Повреждённое хранилище и изменение другим экземпляром не перезаписываются',
    () async {
      final vault = MemoryVault()..value = 'повреждено';
      final manager = ProfilesCubit(vault: vault, validate: (_) async {});
      addTearDown(manager.close);
      await manager.load();
      await manager.importBytes(utf8.encode(testConf), 'Временный');
      expect(manager.state.offerTemporary, true);
      expect(vault.value, 'повреждено');
      final other = MemoryVault();
      final stale = ProfilesCubit(vault: other, validate: (_) async {});
      addTearDown(stale.close);
      await stale.load();
      other.value = 'изменено другим экземпляром';
      await stale.importBytes(utf8.encode(testConf), 'Конфликт');
      expect(stale.state.offerTemporary, true);
      expect(other.value, 'изменено другим экземпляром');
    },
  );
}
