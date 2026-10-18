import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../engine/engine_manager.dart';
import '../profiles/profiles_cubit.dart';

class PreparationState {
  const PreparationState({
    this.message,
    this.progress,
    this.installing = false,
  });

  final String? message;
  final double? progress;
  final bool installing;
}

/// Собирает состояние подготовки. Виджету остаётся только показать результат.
class PreparationCubit extends Cubit<PreparationState> {
  PreparationCubit({
    required this.profiles,
    required this.awg,
    required this.xray,
  }) : super(const PreparationState()) {
    _subscriptions = [
      profiles.stream.listen((_) => _update()),
      awg.stream.listen((_) => _update()),
      xray.stream.listen((_) => _update()),
    ];
    _update();
  }

  final ProfilesCubit profiles;
  final EngineManager awg, xray;
  late final List<StreamSubscription<dynamic>> _subscriptions;

  void _update() {
    if (isClosed) return;
    final engine = profiles.state.requiredEngine == 'xray' ? xray : awg;
    emit(_engineNotice(engine.state) ?? _profileNotice(profiles.state));
  }

  PreparationState? _engineNotice(EngineState engine) {
    if (engine.status == EngineStatus.downloading) {
      return PreparationState(
        message: 'Скачиваем движок…',
        progress: engine.progress,
      );
    }
    if (engine.status == EngineStatus.installing) {
      return const PreparationState(
        message: 'Проверяем и устанавливаем движок…',
        installing: true,
      );
    }
    return null;
  }

  PreparationState _profileNotice(ProfilesState profile) {
    if (profile.busy) return PreparationState(message: profile.message);
    if (profile.selected == null) {
      return PreparationState(message: profile.message);
    }
    return const PreparationState();
  }

  @override
  Future<void> close() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await super.close();
  }
}
