import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:amnezia_proxy_manager/features/connection/connection_cubit.dart';
import 'package:amnezia_proxy_manager/features/connection/diagnostics_cubit.dart';
import 'package:amnezia_proxy_manager/features/connection/recovery_cubit.dart';
import 'package:amnezia_proxy_manager/features/connection/traffic_cubit.dart';
import 'package:amnezia_proxy_manager/features/engine/engine_manager.dart';
import 'package:amnezia_proxy_manager/settings/proxy_ports.dart';

import 'connection_cubit_test.dart' show MemoryVault;
import 'fixtures/profile_fixtures.dart';

import 'package:amnezia_proxy_manager/features/profiles/profiles_cubit.dart';

class TestConnection extends ConnectionCubit {
  TestConnection(ProfilesCubit profiles)
    : super(profiles: profiles, awg: EngineManager(), xray: EngineManager());
  int starts = 0, stops = 0;
  final preservedStops = <bool>[];
  bool online = true;
  Completer<void>? stopGate;
  void push(ProxyConnectionState value) => emit(value);
  @override
  Future<void> toggle() async {
    starts++;
    push(
      const ProxyConnectionState(
        ConnectionStatus.running,
        connectivity: 'checking',
      ),
    );
  }

  @override
  Future<void> stop({bool preserveProtection = false}) async {
    stops++;
    preservedStops.add(preserveProtection);
    await stopGate?.future;
    push(const ProxyConnectionState(ConnectionStatus.disconnected));
  }

  @override
  Future<void> checkNetwork() async {
    push(
      ProxyConnectionState(
        ConnectionStatus.running,
        connectivity: online ? 'verified' : 'unverified',
      ),
    );
  }

  Future<void> dispose() async {
    await close();
    await awg.close();
    await xray.close();
    await profiles.close();
  }
}

Future<TestConnection> fixture() async {
  final profiles = ProfilesCubit(vault: MemoryVault(), validate: (_) async {});
  await profiles.load();
  await profiles.importBytes(utf8.encode(testConf), 'Тест');
  return TestConnection(profiles);
}

Future<ProxyPorts> freePorts() async {
  final first = await ServerSocket.bind('127.0.0.1', 0);
  final second = await ServerSocket.bind('127.0.0.1', 0);
  final ports = ProxyPorts(socks: first.port, http: second.port);
  await first.close();
  await second.close();
  return ports;
}

void main() {
  test(
    'Диагностика после обрыва не снимает уже установленную защиту',
    () async {
      final connection = await fixture();
      connection.push(
        const ProxyConnectionState(
          ConnectionStatus.error,
          code: 'engine_exited',
          internetBlocked: true,
        ),
      );
      final ports = await freePorts();
      final diagnostics = DiagnosticsCubit(
        connection: connection,
        profiles: connection.profiles,
        ports: () async => ports,
        prepare: () async {},
      );
      await diagnostics.run();
      expect(connection.preservedStops, [true]);
      await diagnostics.close();
      await connection.dispose();
    },
  );
  test(
    'После сбоя TUN защита сохраняется при повторе и снимается вручную',
    () async {
      final connection = await fixture();
      final recovery = RecoveryCubit(
        connection,
        delay: const Duration(milliseconds: 5),
      );
      await recovery.connect();
      connection.push(
        const ProxyConnectionState(
          ConnectionStatus.error,
          code: 'vpn_tun_exited',
          internetBlocked: true,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(connection.starts, 2);
      expect(connection.preservedStops, [true]);
      await recovery.stop();
      expect(connection.preservedStops, [true, false]);
      await recovery.close();
      await connection.dispose();
    },
  );
  test('Успешный HTTPS отменяет запланированный перезапуск', () async {
    final connection = await fixture();
    final recovery = RecoveryCubit(
      connection,
      delay: const Duration(milliseconds: 30),
    );
    await recovery.connect();
    for (var i = 0; i < 2; i++) {
      connection.push(
        const ProxyConnectionState(
          ConnectionStatus.running,
          connectivity: 'checking',
        ),
      );
      connection.push(
        const ProxyConnectionState(
          ConnectionStatus.running,
          connectivity: 'unverified',
        ),
      );
    }
    connection.push(
      const ProxyConnectionState(
        ConnectionStatus.running,
        connectivity: 'verified',
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(connection.starts, 1);
    expect(recovery.state.waiting, false);
    await recovery.close();
    await connection.dispose();
  });
  test(
    'Ручное отключение во время перезапуска не допускает поздний старт',
    () async {
      final connection = await fixture();
      final recovery = RecoveryCubit(
        connection,
        delay: const Duration(milliseconds: 5),
      );
      await recovery.connect();
      connection.stopGate = Completer<void>();
      connection.push(
        const ProxyConnectionState(
          ConnectionStatus.error,
          code: 'engine_exited',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final stop = recovery.stop();
      connection.stopGate!.complete();
      await stop;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(connection.starts, 1);
      await recovery.close();
      await connection.dispose();
    },
  );

  test('Диагностика не отключает уже работающий прокси', () async {
    final connection = await fixture();
    final first = await ServerSocket.bind('127.0.0.1', 0);
    final second = await ServerSocket.bind('127.0.0.1', 0);
    connection.push(
      const ProxyConnectionState(
        ConnectionStatus.running,
        connectivity: 'verified',
      ),
    );
    final diagnostics = DiagnosticsCubit(
      connection: connection,
      profiles: connection.profiles,
      ports: () async => ProxyPorts(socks: first.port, http: second.port),
      prepare: () async {},
    );
    await diagnostics.run();
    expect(
      diagnostics.state.steps.every(
        (step) => step.status == CheckStatus.passed,
      ),
      true,
    );
    expect(connection.starts, 0);
    expect(connection.stops, 0);
    expect(connection.state.status, ConnectionStatus.running);
    await first.close();
    await second.close();
    await diagnostics.close();
    await connection.dispose();
  });
  test(
    'Авария движка вызывает повтор; ручное отключение отменяет следующий',
    () async {
      final connection = await fixture();
      final recovery = RecoveryCubit(
        connection,
        delay: const Duration(milliseconds: 10),
      );
      await recovery.connect();
      connection.push(
        const ProxyConnectionState(
          ConnectionStatus.error,
          code: 'engine_exited',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(connection.starts, 2);
      connection.push(
        const ProxyConnectionState(
          ConnectionStatus.error,
          code: 'engine_exited',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await recovery.stop();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(connection.starts, 2);
      expect(recovery.state.waiting, false);
      await recovery.close();
      await connection.dispose();
    },
  );

  test(
    'Два сбоя HTTPS вызывают восстановление, ошибочный профиль — нет',
    () async {
      final connection = await fixture();
      final recovery = RecoveryCubit(
        connection,
        delay: const Duration(milliseconds: 10),
      );
      await recovery.connect();
      for (var i = 0; i < 2; i++) {
        connection.push(
          const ProxyConnectionState(
            ConnectionStatus.running,
            connectivity: 'checking',
          ),
        );
        connection.push(
          const ProxyConnectionState(
            ConnectionStatus.running,
            connectivity: 'unverified',
          ),
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(connection.starts, 2);
      connection.push(
        const ProxyConnectionState(
          ConnectionStatus.error,
          code: 'invalid_config',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(connection.starts, 2);
      await recovery.close();
      await connection.dispose();
    },
  );

  test(
    'Диагностика временно запускает прокси и убирает его после проверки',
    () async {
      final connection = await fixture();
      final ports = await freePorts();
      final diagnostics = DiagnosticsCubit(
        connection: connection,
        profiles: connection.profiles,
        ports: () async => ports,
        prepare: () async {},
      );
      await diagnostics.run();
      expect(
        diagnostics.state.steps.every(
          (step) => step.status == CheckStatus.passed,
        ),
        true,
      );
      expect(connection.starts, 1);
      expect(connection.stops, 1);
      expect(connection.state.status, ConnectionStatus.disconnected);
      expect(connection.diagnosing, false);
      await diagnostics.close();
      await connection.dispose();
    },
  );

  test('Занятый порт останавливает диагностику до запуска движка', () async {
    final connection = await fixture();
    final server = await ServerSocket.bind('127.0.0.1', 0);
    final diagnostics = DiagnosticsCubit(
      connection: connection,
      profiles: connection.profiles,
      ports: () async => ProxyPorts(socks: server.port, http: 8080),
      prepare: () async {},
    );
    await diagnostics.run();
    expect(diagnostics.state.steps[1].status, CheckStatus.failed);
    expect(connection.starts, 0);
    expect(diagnostics.state.steps[1].detail, contains('Порт занят'));
    await server.close();
    await diagnostics.close();
    await connection.dispose();
  });

  test('Ошибка HTTPS не скрывается и временная сессия завершается', () async {
    final connection = await fixture();
    connection.online = false;
    final ports = await freePorts();
    final diagnostics = DiagnosticsCubit(
      connection: connection,
      profiles: connection.profiles,
      ports: () async => ports,
      prepare: () async {},
    );
    await diagnostics.run();
    expect(diagnostics.state.steps.last.status, CheckStatus.failed);
    expect(connection.stops, 1);
    await diagnostics.close();
    await connection.dispose();
  });

  test('Трафик берётся из событий, остановка обнуляет скорость, новый сеанс — объём', () async {
    final events = StreamController<Map<String, dynamic>>();
    final traffic = TrafficCubit(events.stream);
    events.add({'status': 'starting'});
    await Future<void>.delayed(const Duration(milliseconds: 10));
    events.add({
      'status': 'running',
      'traffic': {'download': 1024, 'upload': 200},
    });
    await Future<void>.delayed(Duration.zero);
    expect(traffic.state.download, 1024);
    expect(traffic.state.downSpeed, greaterThan(0));
    events.add({'status': 'disconnected'});
    await Future<void>.delayed(Duration.zero);
    expect(traffic.state.downSpeed, 0);
    expect(traffic.state.download, 1024);
    events.add({'status': 'starting'});
    await Future<void>.delayed(Duration.zero);
    expect(traffic.state.available, false);
    expect(traffic.state.download, 0);
    await traffic.close();
    await events.close();
  });
}
