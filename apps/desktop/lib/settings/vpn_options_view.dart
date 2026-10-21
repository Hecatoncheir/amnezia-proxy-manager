import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../features/connection/connection_cubit.dart';
import 'vpn_options_cubit.dart';

class VpnOptionsView extends StatelessWidget {
  const VpnOptionsView({
    super.key,
    required this.options,
    this.connection,
    this.onUnblock,
  });
  final VpnOptionsCubit options;
  final ConnectionCubit? connection;
  final Future<void> Function()? onUnblock;
  bool get _supported =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  @override
  Widget build(BuildContext context) {
    if (connection == null) return _options(false);
    return BlocBuilder<ConnectionCubit, ProxyConnectionState>(
      bloc: connection,
      builder: (_, state) => _options(state.active || state.internetBlocked),
    );
  }

  Widget _options(bool locked) => BlocBuilder<VpnOptionsCubit, VpnOptions>(
    bloc: options,
    builder: (context, state) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _trafficSwitch(state, locked),
        const SizedBox(height: 12),
        _protectionSwitch(state, locked),
        if (state.allTraffic) ...[
          const SizedBox(height: 12),
          const Text('Счётчики скорости учитывают только локальные прокси.'),
        ],
        if (locked) ...[
          const SizedBox(height: 12),
          const Text('Чтобы изменить режим, отключите VPN.'),
        ],
        if (_supported && connection != null) _unblock(),
      ],
    ),
  );

  Widget _trafficSwitch(VpnOptions state, bool locked) => SwitchListTile(
    contentPadding: EdgeInsets.zero,
    title: const Text('Пропускать весь трафик через VPN'),
    subtitle: Text(
      _supported
          ? 'Все приложения через выбранный профиль. Локальные SOCKS5 и HTTP продолжают работать. При подключении система запросит права администратора.'
          : 'Режим всего трафика недоступен на этой платформе.',
    ),
    value: state.allTraffic,
    onChanged: locked || !_supported ? null : options.setAllTraffic,
  );

  Widget _protectionSwitch(VpnOptions state, bool locked) => SwitchListTile(
    contentPadding: EdgeInsets.zero,
    title: const Text('Блокировать интернет при обрыве VPN'),
    subtitle: const Text(
      'Действует в режиме всего трафика. Блокировка сохраняется при сбое и переподключении; ручное отключение VPN снимает её.',
    ),
    value: state.killSwitch,
    onChanged: locked ? null : options.setKillSwitch,
  );

  Widget _unblock() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 16),
      OutlinedButton.icon(
        onPressed: connection!.state.active ? null : onUnblock,
        icon: const Icon(Icons.lock_open),
        label: const Text('Снять блокировку интернета'),
      ),
      const SizedBox(height: 8),
      const Text(
        'Используйте после сбоя приложения, если интернет остался заблокирован.',
      ),
    ],
  );
}
