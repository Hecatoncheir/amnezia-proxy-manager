import 'dart:io';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:amnezia_proxy_manager/features/connection/supervisor_client.dart';

String dartExecutable() {
  var directory = File(Platform.resolvedExecutable).parent;
  while (true) {
    final candidate = File(
      '${directory.path}/dart-sdk/bin/dart${Platform.isWindows ? '.exe' : ''}',
    );
    if (candidate.existsSync()) return candidate.path;
    if (directory.parent.path == directory.path) {
      throw StateError('Dart SDK недоступен');
    }
    directory = directory.parent;
  }
}

void main() {
  test('Отмена во время запуска IPC не допускает поздний start', () async {
    final gate = Completer<void>();
    final c = SupervisorClient(
      launchProcess: () async {
        await gate.future;
        return Process.start(dartExecutable(), [
          'test/fixtures/supervisor_fixture.dart',
        ]);
      },
    );
    addTearDown(c.close);
    final statuses = <String>[];
    final subscription = c.events.listen(
      (event) => statuses.add(event['status'] as String),
    );
    addTearDown(subscription.cancel);
    final starting = c.start(
      family: 'xray',
      binary: 'unused',
      sha256: 'unused',
      configuration: 'test',
    );
    await Future<void>.delayed(Duration.zero);
    final stopping = c.stop();
    gate.complete();
    await Future.wait([starting, stopping]);
    expect(statuses, isNot(contains('running')));
  });

  test(
    'IPC передаёт режим VPN, защиту по умолчанию и сохранение при повторе',
    () async {
      final c = SupervisorClient(
        launchProcess: () => Process.start(dartExecutable(), [
          'test/fixtures/supervisor_fixture.dart',
        ]),
      );
      addTearDown(c.close);
      await c.start(
        family: 'xray',
        binary: 'unused',
        sha256: 'unused',
        configuration: 'vpn_parameters',
        allTraffic: true,
        tunBinary: 'tun',
      );
      await c.stop(preserveProtection: true);
      await c.stop();
    },
  );
  SupervisorClient client() => SupervisorClient(
    launchProcess: () => Process.start(dartExecutable(), [
      'test/fixtures/supervisor_fixture.dart',
    ], runInShell: false),
  );
  Future<void> start(SupervisorClient c, String config) => c.start(
    family: 'xray',
    binary: 'unused',
    sha256: 'unused',
    configuration: config,
  );
  test('Выбранные порты передаются в IPC', () async {
    final c = client();
    addTearDown(c.close);
    await c.start(
      family: 'xray',
      binary: 'unused',
      sha256: 'unused',
      configuration: 'custom_ports',
      socksPort: 19080,
      httpPort: 19081,
    );
    await c.stop();
  });
  test(
    'IPC согласует протокол, получает события и повторно запускает сессию',
    () async {
      final c = client();
      addTearDown(c.close);
      final events = <String>[];
      final sub = c.events.listen((e) => events.add(e['status'] as String));
      addTearDown(sub.cancel);
      await start(c, 'test');
      await c.stop();
      await start(c, 'test');
      await c.stop();
      expect(events, ['running', 'disconnected', 'running', 'disconnected']);
    },
  );
  test('После аварии supervisor можно подключиться заново', () async {
    final c = client();
    addTearDown(c.close);
    await expectLater(start(c, 'crash'), throwsA(isA<SessionProblem>()));
    await start(c, 'test');
    await c.stop();
  });
  for (final invalid in ['bad_version', 'oversized']) {
    test('IPC отклоняет $invalid без вывода конфигурации', () async {
      final c = client();
      addTearDown(c.close);
      await expectLater(start(c, invalid), throwsA(isA<SessionProblem>()));
    });
  }
}
