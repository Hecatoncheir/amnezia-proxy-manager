import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

class VpnOptions {
  const VpnOptions({this.allTraffic = false, this.killSwitch = true});
  final bool allTraffic;
  final bool killSwitch;
}

class VpnOptionsCubit extends Cubit<VpnOptions> {
  VpnOptionsCubit() : super(const VpnOptions());
  static const allTrafficKey = 'vpn-all-traffic';
  static const killSwitchKey = 'vpn-kill-switch';

  Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();
    emit(
      VpnOptions(
        allTraffic: preferences.getBool(allTrafficKey) ?? false,
        killSwitch: preferences.getBool(killSwitchKey) ?? true,
      ),
    );
  }

  Future<void> setAllTraffic(bool enabled) async {
    final preferences = await SharedPreferences.getInstance();
    if (await preferences.setBool(allTrafficKey, enabled)) {
      emit(VpnOptions(allTraffic: enabled, killSwitch: state.killSwitch));
    }
  }

  Future<void> setKillSwitch(bool enabled) async {
    final preferences = await SharedPreferences.getInstance();
    if (await preferences.setBool(killSwitchKey, enabled)) {
      emit(VpnOptions(allTraffic: state.allTraffic, killSwitch: enabled));
    }
  }
}
