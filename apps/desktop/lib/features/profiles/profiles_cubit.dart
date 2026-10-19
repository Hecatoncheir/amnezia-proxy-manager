import 'dart:convert';
import 'dart:math';

import 'package:flutter_bloc/flutter_bloc.dart';

import 'profile_codec.dart';
import 'local_profile_import.dart';
import 'profile_vault.dart';

class ProfileSummary {
  const ProfileSummary(this.id, this.name, this.format, this.temporary);
  final String id, name, format;
  final bool temporary;
  String get family => format == 'VLESS' ? 'xray' : 'awg';
}

class ProfilesState {
  const ProfilesState({
    this.profiles = const [],
    this.selected,
    this.busy = false,
    this.message,
    this.offerTemporary = false,
    this.requiredEngine = 'awg',
    this.locked = false,
  });
  final String requiredEngine;
  final bool locked;
  final List<ProfileSummary> profiles;
  final String? selected, message;
  final bool busy, offerTemporary;
}

class _Record {
  const _Record(
    this.id,
    this.name,
    this.format,
    this.configuration, {
    this.temporary = false,
  });
  final String id, name, format, configuration;
  final bool temporary;
  ProfileSummary get summary => ProfileSummary(id, name, format, temporary);
  Map<String, Object> json() => {
    'id': id,
    'name': name,
    'format': format,
    'configuration': configuration,
  };
  @override
  String toString() => '_Record(скрыто)';
}

class ProfilesCubit extends Cubit<ProfilesState> {
  ProfilesCubit({
    required this.vault,
    required this.validate,
    ProfileCodec? codec,
  }) : codec = codec ?? ProfileCodec(),
       super(const ProfilesState());
  final ProfileVault vault;
  final Future<void> Function(String) validate;
  final ProfileCodec codec;
  final _records = <_Record>[];
  _Record? _pending;
  String? _selected;
  String? _snapshot;
  String _requiredEngine = 'awg';
  bool _locked = false;
  bool _loaded = false, _vaultReady = false, _busy = false;
  List<int>? _detectedProfile;
  bool get hasDetectedProfile => _detectedProfile != null;

  Future<void> discoverLocal({Future<List<int>> Function()? reader}) async {
    if (!_loaded || _busy || _records.isNotEmpty || !_vaultReady) return;
    _busy = true;
    _publish(busy: true, message: 'Ищем профиль AmneziaVPN…');
    try {
      final bytes = await (reader ?? readLocalAmneziaProfile)();
      final imported = await codec.decode(bytes);
      if (isClosed) return;
      _detectedProfile = bytes;
      _requiredEngine = imported.family;
      _publish(
        message: 'Найден профиль AmneziaVPN. Нажмите кнопку подключения — движок будет скачан автоматически.',
      );
    } catch (_) {
      _publish(
        message: 'Рабочий профиль AmneziaVPN не найден. Добавьте файл или ссылку в меню «Профили».',
      );
    } finally {
      _busy = false;
    }
  }

  Future<void> importDetected() async {
    final bytes = _detectedProfile;
    if (bytes == null || _records.isNotEmpty) return;
    await importBytes(bytes, 'AmneziaVPN');
    if (_selected == null) {
      throw ProfileProblem(
        state.message ?? 'Откройте меню «Профили», чтобы завершить импорт.',
      );
    }
    _detectedProfile = null;
  }

  Future<void> load() async {
    if (_busy || _loaded) return;
    _busy = true;
    _publish(busy: true);
    try {
      final snapshot = await vault.read();
      if (isClosed) return;
      if (snapshot != null) _restore(snapshot);
      _snapshot = snapshot;
      _vaultReady = true;
      _publish();
    } catch (_) {
      _records.clear();
      _selected = null;
      _publish(
        message: 'Хранилище ключей недоступно или повреждено. Сохранённые данные не изменены.',
      );
    } finally {
      _busy = false;
      _loaded = true;
    }
  }

  void _restore(String snapshot) {
    if (utf8.encode(snapshot).length > 1024 * 1024) {
      throw const ProfileProblem('Повреждено хранилище.');
    }
    final data = jsonDecode(snapshot) as Map;
    final entries = data['profiles'] as List;
    if (data['schema'] != 1 || entries.length > 8) {
      throw const ProfileProblem('Повреждено хранилище.');
    }
    final restored = <_Record>[];
    for (final value in entries) {
      final record = value as Map;
      final id = record['id'] as String;
      final name = _name(record['name'] as String);
      final format = record['format'] as String;
      if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(id) ||
          restored.any((e) => e.id == id) ||
          !['AmneziaWG', 'AmneziaVPN', 'VLESS'].contains(format)) {
        throw const ProfileProblem('Повреждено хранилище.');
      }
      restored.add(
        _Record(
          id,
          name,
          format,
          codec.normalizeConfiguration(record['configuration'] as String),
        ),
      );
    }
    final selected = data['selected'];
    _records.addAll(restored);
    _selected = restored.any((e) => e.id == selected)
        ? selected as String
        : restored.firstOrNull?.id;
    _requiredEngine =
        restored.where((e) => e.id == _selected).firstOrNull?.format == 'VLESS'
        ? 'xray'
        : 'awg';
  }

  void lockForConnection(bool locked) {
    _locked = locked;
    _publish();
  }

  Future<void> withSelectedForConnection(
    Future<void> Function(String, String) action,
  ) async {
    if (!_loaded || _busy || _pending != null || _locked) {
      throw const ProfileProblem('Дождитесь завершения работы с профилями.');
    }
    final record = _records.where((r) => r.id == _selected).firstOrNull;
    if (record == null) {
      throw const ProfileProblem(
        'Добавьте и выберите профиль в меню «Профили».',
      );
    }
    lockForConnection(true);
    await action(record.summary.family, record.configuration);
  }

  Future<void> importLocal({Future<List<int>> Function()? reader}) async {
    if (_busy || _locked || !_loaded || _pending != null) return;
    _busy = true;
    _publish(busy: true, message: 'Читаем выбранный профиль AmneziaVPN…');
    try {
      final bytes = await (reader ?? readLocalAmneziaProfile)();
      if (isClosed) return;
      _busy = false;
      await importBytes(bytes, 'AmneziaVPN');
    } on ProfileProblem catch (error) {
      _publish(message: error.message);
    } catch (_) {
      _publish(message: 'Не удалось прочитать установленную AmneziaVPN.');
    } finally {
      _busy = false;
    }
  }

  Future<void> importBytes(List<int> bytes, String name) async {
    if (_busy || _locked || !_loaded || _pending != null) return;
    _busy = true;
    _publish(busy: true, message: 'Проверяем конфигурацию через движок…');
    try {
      if (_records.length >= 8) {
        throw const ProfileProblem('Можно сохранить не более восьми профилей.');
      }
      final title = _name(name);
      final imported = await codec.decode(bytes);
      _requiredEngine = imported.family;
      _publish(busy: true, message: 'Проверяем конфигурацию через движок…');
      await validate(imported.configuration);
      if (isClosed) return;
      final duplicate = _records
          .where((record) => record.configuration == imported.configuration)
          .firstOrNull;
      if (duplicate != null) {
        if (_vaultReady) await _persist(_records, duplicate.id);
        _selected = duplicate.id;
        _publish(message: 'Этот профиль уже импортирован и выбран.');
        return;
      }
      final random = Random.secure();
      final id = List.generate(
        16,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      final candidate = _Record(
        id,
        title,
        imported.format,
        imported.configuration,
      );
      _pending = candidate;
      if (!_vaultReady) {
        _publish(
          message: 'Хранилище ключей недоступно. Использовать профиль только в этом сеансе?',
          offerTemporary: true,
        );
        return;
      }
      try {
        await _persist([..._records, candidate], id);
      } catch (_) {
        _vaultReady = false;
        _publish(
          message: 'Хранилище не подтвердило сохранение. Использовать профиль в текущем сеансе?',
          offerTemporary: true,
        );
        return;
      }
      _records.add(candidate);
      _selected = id;
      _pending = null;
      _publish(message: 'Профиль проверен и сохранён в защищённом хранилище.');
    } on ProfileProblem catch (error) {
      _publish(message: error.message);
    } catch (_) {
      _publish(
        message: 'Не удалось импортировать профиль. Проверьте файл и установленный движок.',
      );
    } finally {
      _busy = false;
    }
  }

  void useTemporary() {
    final pending = _pending;
    if (_busy || pending == null) return;
    _records.add(
      _Record(
        pending.id,
        pending.name,
        pending.format,
        pending.configuration,
        temporary: true,
      ),
    );
    _selected = pending.id;
    _pending = null;
    _publish(message: 'Профиль доступен до закрытия приложения.');
  }

  void cancelTemporary() {
    _pending = null;
    _publish();
  }

  Future<void> select(String id) async {
    if (_busy ||
        _locked ||
        _pending != null ||
        !_records.any((e) => e.id == id)) {
      return;
    }
    _busy = true;
    try {
      if (_vaultReady) await _persist(_records, id);
      _selected = id;
      _requiredEngine = _records.firstWhere((e) => e.id == id).format == 'VLESS'
          ? 'xray'
          : 'awg';
      _publish();
    } catch (_) {
      _publish(message: 'Не удалось сохранить выбор профиля.');
    } finally {
      _busy = false;
    }
  }

  Future<void> checkSelected() async {
    if (_busy || _locked || _pending != null) return;
    final record = _records.where((e) => e.id == _selected).firstOrNull;
    if (record == null) return;
    _busy = true;
    _publish(busy: true, message: 'Проверяем конфигурацию через движок…');
    try {
      await validate(record.configuration);
      _publish(
        message:
            'Конфигурация принята движком. VPN-подключение не запускалось.',
      );
    } on ProfileProblem catch (error) {
      _publish(message: error.message);
    } catch (_) {
      _publish(message: 'Не удалось проверить конфигурацию.');
    } finally {
      _busy = false;
    }
  }

  Future<void> validateSelected() async {
    if (_busy || _pending != null) {
      throw const ProfileProblem('Дождитесь завершения импорта профиля.');
    }
    final record = _records.where((e) => e.id == _selected).firstOrNull;
    if (record == null) {
      throw const ProfileProblem('Добавьте профиль в настройках профилей.');
    }
    _busy = true;
    _publish(busy: true);
    try {
      await validate(record.configuration);
    } finally {
      _busy = false;
      _publish();
    }
  }

  Future<void> remove(String id) async {
    if (_busy || _locked || _pending != null) return;
    final record = _records.where((e) => e.id == id).firstOrNull;
    if (record == null) return;
    _busy = true;
    try {
      final remaining = _records.where((e) => e.id != id).toList();
      final selected = _selected == id ? remaining.firstOrNull?.id : _selected;
      if (!record.temporary) await _persist(remaining, selected);
      _records.remove(record);
      _selected = selected;
      _publish(message: 'Профиль удалён.');
    } catch (_) {
      _publish(
        message: 'Хранилище не подтвердило удаление. Повторите попытку.',
      );
    } finally {
      _busy = false;
    }
  }

  Future<void> _persist(List<_Record> records, String? selected) async {
    final saved = records.where((e) => !e.temporary).toList();
    final next = saved.isEmpty
        ? null
        : jsonEncode({
            'schema': 1,
            'selected': saved.any((e) => e.id == selected)
                ? selected
                : saved.first.id,
            'profiles': saved.map((e) => e.json()).toList(),
          });
    await vault.write(next, expected: _snapshot);
    _snapshot = next;
  }

  String _name(String name) {
    final result = name.trim();
    if (result.isEmpty ||
        result.length > 64 ||
        result.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
      throw const ProfileProblem(
        'Введите название профиля длиной до 64 символов.',
      );
    }
    return result;
  }

  void _publish({
    bool busy = false,
    String? message,
    bool offerTemporary = false,
  }) {
    if (!isClosed) {
      emit(
        ProfilesState(
          requiredEngine: _requiredEngine,
          locked: _locked,
          profiles: List.unmodifiable(_records.map((e) => e.summary)),
          selected: _selected,
          busy: busy,
          message: message,
          offerTemporary: offerTemporary,
        ),
      );
    }
  }

  @override
  Future<void> close() async {
    _detectedProfile = null;
    _pending = null;
    _records.clear();
    await super.close();
  }
}
