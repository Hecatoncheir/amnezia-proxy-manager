import 'package:flutter_bloc/flutter_bloc.dart';

import 'app_tray.dart';
import 'window_placement.dart';

class TrayState {
  const TrayState({this.ready = false, this.hidden = false, this.message});
  final bool ready, hidden;
  final String? message;
}

class TrayCubit extends Cubit<TrayState> {
  TrayCubit({
    AppTray? tray,
    Future<void> Function()? showWindow,
    Future<void> Function()? hideWindow,
    Future<void> Function()? exitApplication,
  }) : tray = tray ?? NativeAppTray(),
       showWindow = showWindow ?? WindowPlacement.show,
       hideWindow = hideWindow ?? WindowPlacement.hide,
       exitApplication = exitApplication ?? WindowPlacement.quit,
       super(const TrayState());
  final AppTray tray;
  final Future<void> Function() showWindow, hideWindow, exitApplication;

  Future<void> start({bool hidden = false}) async {
    try {
      final ready = await tray.create(
        open: open,
        hide: hide,
        exit: exitApplication,
      );
      emit(TrayState(ready: ready));
      if (!ready) tray.dispose();
      if (hidden && ready) {
        await hide();
        return;
      }
      await open();
    } catch (_) {
      tray.dispose();
      emit(
        const TrayState(message: 'Трей недоступен. Окно приложения открыто.'),
      );
      await showWindow();
    }
  }

  Future<void> open() async {
    await showWindow();
    if (!isClosed) emit(TrayState(ready: state.ready));
  }

  Future<void> hide() async {
    if (!state.ready) return;
    await hideWindow();
    if (!isClosed) emit(const TrayState(ready: true, hidden: true));
  }

  Future<bool> minimizeIfEnabled(bool enabled) async {
    if (!enabled || !state.ready) return false;
    if (state.hidden) return true;
    try {
      await hide();
    } catch (_) {
      await open();
      if (!isClosed) {
        emit(
          TrayState(
            ready: state.ready,
            message: 'Не удалось свернуть в трей. Окно оставлено открытым.',
          ),
        );
      }
    }
    return true;
  }

  @override
  Future<void> close() async {
    tray.dispose();
    await super.close();
  }
}
