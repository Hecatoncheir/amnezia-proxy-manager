import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

class TrafficState {
  const TrafficState({
    this.download = 0,
    this.upload = 0,
    this.downSpeed = 0,
    this.upSpeed = 0,
    this.available = false,
  });
  final int download, upload;
  final double downSpeed, upSpeed;
  final bool available;
}

class TrafficCubit extends Cubit<TrafficState> {
  TrafficCubit(Stream<Map<String, dynamic>> events)
    : super(const TrafficState()) {
    _subscription = events.listen(_event);
    _clock.start();
  }
  late final StreamSubscription<Map<String, dynamic>> _subscription;
  final _clock = Stopwatch();
  int _lastTime = 0;

  void _event(Map<String, dynamic> event) {
    if (event['status'] == 'starting') {
      _lastTime = _clock.elapsedMicroseconds;
      emit(const TrafficState());
      return;
    }
    final data = event['traffic'];
    if (data is Map) {
      _sample(data);
      return;
    }
    if (event['status'] != 'running') {
      emit(
        TrafficState(
          download: state.download,
          upload: state.upload,
          available: state.available,
        ),
      );
    }
  }

  void _sample(Map<dynamic, dynamic> data) {
    final down = data['download'], up = data['upload'];
    if (down is! int || up is! int || down < 0 || up < 0) return;
    final now = _clock.elapsedMicroseconds;
    final seconds = (now - _lastTime) / Duration.microsecondsPerSecond;
    emit(
      TrafficState(
        download: down,
        upload: up,
        available: true,
        downSpeed: _speed(down - state.download, seconds),
        upSpeed: _speed(up - state.upload, seconds),
      ),
    );
    _lastTime = now;
  }

  double _speed(int difference, double seconds) {
    if (seconds <= 0 || difference < 0) return 0;
    return difference / seconds;
  }

  @override
  Future<void> close() async {
    await _subscription.cancel();
    await super.close();
  }
}

String formatBytes(num bytes) {
  if (bytes < 1024) return '${bytes.toStringAsFixed(0)} Б';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} КБ';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} МБ';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} ГБ';
}
