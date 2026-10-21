import 'dart:async';
import 'dart:convert';
import 'dart:io';

class SessionProblem implements Exception {
  const SessionProblem(this.code);
  final String code;
  @override
  String toString() => 'SessionProblem($code)';
}

/// Конфигурация передаётся только через stdin. Вывод движков сюда не поступает.
class SupervisorClient {
  SupervisorClient({String? executable, this.launchProcess})
    : executable =
          executable ??
          '${File(Platform.resolvedExecutable).parent.path}/${Platform.isWindows ? 'proxy-engine.exe' : 'proxy-engine'}';
  final String executable;
  final Future<Process> Function()? launchProcess;
  final _events = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get events => _events.stream;
  final _pending = <String, Completer<Map<String, dynamic>>>{};
  final _line = <int>[];
  Process? _process;
  Future<void>? _launching, _closing;
  var _next = 0;
  var _dead = false;
  var _supportsPorts = false;
  var _supportsVpn = false;
  var _elevated = false;
  var _protection = false;
  String? _launchFailure;
  var _operation = 0;

  Future<void> _launch() async {
    try {
      await _spawn();
    } catch (_) {
      _fail();
      throw SessionProblem(_launchFailure ?? 'ipc_failed');
    }
  }

  Future<void> _spawn() async {
    _launchFailure = null;
    if (_dead) throw const SessionProblem('ipc_failed');
    final process =
        await (launchProcess?.call() ??
            Process.start(executable, [
              _elevated ? '--ipc-admin' : '--ipc',
            ], runInShell: false));
    _process = process;
    unawaited(process.stderr.drain<void>());
    process.stdout.listen(
      (bytes) {
        if (_process == process) _read(bytes);
      },
      onError: (_) => _fail(process),
      onDone: () => _fail(process),
    );
    unawaited(process.exitCode.then((_) => _fail(process)));
    final hello = await _request('hello');
    final capabilities = hello['capabilities'];
    if (capabilities is! List ||
        !capabilities.contains('start') ||
        !capabilities.contains('stop')) {
      _fail();
      throw const SessionProblem('protocol_mismatch');
    }
    _supportsPorts = capabilities.contains('custom_ports');
    _supportsVpn =
        capabilities.contains('full_vpn') &&
        capabilities.contains('kill_switch');
    _protection = hello['internetBlocked'] == true;
  }

  void _read(List<int> bytes) {
    try {
      for (final byte in bytes) {
        if (byte == 10) {
          final message =
              jsonDecode(utf8.decode(_line)) as Map<String, dynamic>;
          _line.clear();
          if (message['version'] != 1) throw const FormatException();
          if (message['event'] == 'state') {
            _readLaunchFailure(message['state'] as Map);
            _events.add(Map<String, dynamic>.from(message['state'] as Map));
          } else {
            final completer = _pending.remove(message['requestId']);
            if (completer == null) throw const FormatException();
            if (message['ok'] == true) {
              completer.complete(message);
            } else {
              const codes = {
                'already_running',
                'invalid_config',
                'unsupported_engine',
                'stop_timeout',
                'invalid_ports',
                'not_running',
                'vpn_platform_unsupported',
                'vpn_admin_required',
                'vpn_runtime_missing',
                'vpn_unblock_failed',
              };
              completer.completeError(
                SessionProblem(
                  codes.contains(message['code'])
                      ? message['code'] as String
                      : 'ipc_failed',
                ),
              );
            }
          }
        } else {
          if (_line.length >= 8192) throw const FormatException();
          _line.add(byte);
        }
      }
    } catch (_) {
      _fail();
    }
  }

  void _readLaunchFailure(Map state) {
    const codes = {
      'vpn_elevation_denied',
      'vpn_elevation_failed',
      'vpn_already_running',
      'vpn_authorization_unavailable',
    };
    if (codes.contains(state['code'])) _launchFailure = state['code'] as String;
  }

  void _fail([Process? expected]) {
    if (expected != null && expected != _process) return;
    if (_dead) return;
    _dead = true;
    _process?.kill();
    for (final value in _pending.values) {
      value.completeError(const SessionProblem('ipc_failed'));
    }
    _pending.clear();
    _line.clear();
    if (_closing == null && !_events.isClosed) {
      _events.add({
        'status': 'error',
        'code': _launchFailure ?? 'ipc_failed',
        'internetBlocked': _protection,
      });
    }
  }

  Future<Map<String, dynamic>> _request(
    String method, [
    Map<String, Object?> arguments = const {},
  ]) async {
    if (_dead || _process == null) throw const SessionProblem('ipc_failed');
    final id = '${++_next}';
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    try {
      final message = jsonEncode({
        'version': 1,
        'requestId': id,
        'method': method,
        ...arguments,
      });
      if (utf8.encode(message).length > 500 * 1024) {
        throw const SessionProblem('invalid_config');
      }
      _process!.stdin.writeln(message);
      await _process!.stdin.flush();
      return await completer.future.timeout(
        Duration(seconds: method == 'hello' && _elevated ? 100 : 20),
      );
    } catch (_) {
      _pending.remove(id);
      _fail();
      rethrow;
    }
  }

  Future<void> start({
    required String family,
    required String binary,
    required String sha256,
    required String configuration,
    int socksPort = 1080,
    int httpPort = 8080,
    bool allTraffic = false,
    bool killSwitch = true,
    String? tunBinary,
  }) async {
    if (_closing != null) throw const SessionProblem('ipc_failed');
    final operation = ++_operation;
    await _selectPrivilege(allTraffic);
    if (operation != _operation) return;
    if (_dead) {
      _process = null;
      _dead = false;
      _launching = null;
    }
    await (_launching ??= _launch());
    if (operation != _operation) return;
    if (allTraffic && !_supportsVpn) {
      throw const SessionProblem('vpn_unsupported');
    }
    if (!_supportsPorts && (socksPort != 1080 || httpPort != 8080)) {
      throw const SessionProblem('unsupported_ports');
    }
    _protection = allTraffic && killSwitch;
    await _request('start', {
      'family': family,
      'binary': binary,
      'sha256': sha256,
      'configuration': configuration,
      'socksPort': socksPort,
      'httpPort': httpPort,
      'allTraffic': allTraffic,
      'killSwitch': killSwitch,
      'tunBinary': tunBinary,
    });
  }

  Future<void> _selectPrivilege(bool elevated) async {
    if (_elevated == elevated) return;
    if (_process != null && !_dead) await _stopRequest(false);
    await _process?.stdin.close();
    _process = null;
    _dead = false;
    _launching = null;
    _elevated = elevated;
  }

  Future<void> check() async {
    await _request('check');
  }

  Future<void> stop({bool preserveProtection = false}) async {
    ++_operation;
    await _stopRequest(preserveProtection);
  }

  Future<void> _stopRequest(bool preserveProtection) async {
    if (_launching != null) await _launching;
    if (_process == null || _dead) return;
    await _request('stop', {'preserveProtection': preserveProtection});
    if (!preserveProtection) _protection = false;
  }

  Future<void> unblock() async {
    ++_operation;
    await _selectPrivilege(true);
    if (_dead) {
      _process = null;
      _dead = false;
      _launching = null;
    }
    await (_launching ??= _launch());
    await stop();
  }

  Future<void> abort() async {
    _fail();
    try {
      await _process?.exitCode.timeout(const Duration(seconds: 3));
    } catch (_) {}
  }

  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    try {
      if (_protection && _dead) {
        await unblock();
      } else {
        await stop();
      }
    } catch (_) {
      /* После сбоя закрываем канал и Job Object. */
    }
    try {
      await _process?.stdin.close();
      await _process?.exitCode.timeout(const Duration(seconds: 3));
    } catch (_) {
      _process?.kill();
    }
    _fail();
    await _events.close();
  }
}
