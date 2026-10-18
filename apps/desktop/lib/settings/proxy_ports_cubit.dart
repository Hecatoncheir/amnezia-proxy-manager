import 'dart:convert';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'proxy_ports.dart';

class ProxyPortsState {
  const ProxyPortsState({
    this.socks = '1080',
    this.http = '8080',
    this.saved = const ProxyPorts(),
    this.loading = true,
    this.saving = false,
    this.error,
  });
  final String socks, http;
  final ProxyPorts saved;
  final bool loading, saving;
  final String? error;
  bool get changed => socks != '${saved.socks}' || http != '${saved.http}';
}

class ProxyPortsCubit extends Cubit<ProxyPortsState> {
  ProxyPortsCubit({this.preferences}) : super(const ProxyPortsState());
  SharedPreferences? preferences;
  static const preferenceKey = 'proxy-ports-v1';
  Future<void>? _loading;
  Future<bool>? _saving;

  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    try {
      preferences ??= await SharedPreferences.getInstance();
      final value = preferences!.getString(preferenceKey);
      if (value == null) {
        _publish(const ProxyPortsState(loading: false));
        return;
      }
      final data = jsonDecode(value) as Map;
      final ports = ProxyPorts.parse('${data['socks']}', '${data['http']}');
      _publish(
        ProxyPortsState(
          socks: '${ports.socks}',
          http: '${ports.http}',
          saved: ports,
          loading: false,
        ),
      );
    } catch (_) {
      _publish(
        const ProxyPortsState(
          loading: false,
          error: 'Не удалось прочитать порты. Используются 1080 и 8080.',
        ),
      );
    }
  }

  void editSocks(String value) => _edit(value, state.http);
  void editHttp(String value) => _edit(state.socks, value);

  void _edit(String socks, String http) {
    if (state.loading || state.saving) return;
    _publish(
      ProxyPortsState(
        socks: socks,
        http: http,
        saved: state.saved,
        loading: false,
      ),
    );
  }

  Future<ProxyPorts> forConnection() async {
    await load();
    if (!await save()) {
      throw FormatException(state.error ?? 'Дождитесь сохранения портов.');
    }
    return state.saved;
  }

  Future<bool> save() => _saving ??= _save().whenComplete(() {
    _saving = null;
  });

  Future<bool> _save() async {
    if (state.loading) return false;
    try {
      final ports = ProxyPorts.parse(state.socks, state.http);
      if (!state.changed) return true;
      await _write(ports);
      return true;
    } on FormatException catch (error) {
      _error(error.message);
    } catch (_) {
      _error('Не удалось сохранить порты. Повторите попытку.');
    }
    return false;
  }

  Future<void> _write(ProxyPorts ports) async {
    _publish(
      ProxyPortsState(
        socks: state.socks,
        http: state.http,
        saved: state.saved,
        loading: false,
        saving: true,
      ),
    );
    preferences ??= await SharedPreferences.getInstance();
    final saved = await preferences!.setString(
      preferenceKey,
      jsonEncode({'socks': ports.socks, 'http': ports.http}),
    );
    if (!saved) throw StateError('Настройки не сохранены');
    _publish(
      ProxyPortsState(
        socks: '${ports.socks}',
        http: '${ports.http}',
        saved: ports,
        loading: false,
      ),
    );
  }

  void _error(String message) => _publish(
    ProxyPortsState(
      socks: state.socks,
      http: state.http,
      saved: state.saved,
      loading: false,
      error: message,
    ),
  );

  void _publish(ProxyPortsState next) {
    if (!isClosed) emit(next);
  }
}
