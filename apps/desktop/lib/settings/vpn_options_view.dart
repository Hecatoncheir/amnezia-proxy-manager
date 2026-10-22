import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../theme/brand_icon.dart';

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
        _switches(state, locked),
        if (state.allTraffic) ...[
          const SizedBox(height: 12),
          const Text('Скорость и объём — только для локальных прокси.'),
        ],
        if (locked) ...[
          const SizedBox(height: 12),
          const Text('Чтобы изменить режим, отключите VPN.'),
        ],
        if (_supported && connection != null) _unblock(),
      ],
    ),
  );

  Widget _switches(VpnOptions state, bool locked) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < MediaQuery.textScalerOf(context).scale(360)) {
        return Column(
          children: [
            _trafficSwitch(state, locked),
            const SizedBox(height: 8),
            _protectionSwitch(state, locked),
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _trafficSwitch(state, locked)),
          const SizedBox(width: 16),
          Expanded(child: _protectionSwitch(state, locked)),
        ],
      );
    },
  );

  Widget _trafficSwitch(VpnOptions state, bool locked) => Tooltip(
    message: _supported
        ? 'Все приложения через VPN. Для подключения нужны права администратора. Локальные прокси остаются доступны.'
        : 'Режим всего трафика недоступен на этой платформе.',
    child: SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('Весь трафик'),
      value: state.allTraffic,
      onChanged: locked || !_supported ? null : options.setAllTraffic,
    ),
  );

  Widget _protectionSwitch(VpnOptions state, bool locked) => Tooltip(
    message: 'Блокирует интернет при обрыве VPN в режиме всего трафика. Ручное отключение VPN снимает блокировку.',
    child: SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('Защита при обрыве'),
      value: state.killSwitch,
      onChanged: locked ? null : options.setKillSwitch,
    ),
  );

  Widget _unblock() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 16),
      Tooltip(
        message:
            'Снять блокировку, если после сбоя приложения интернет недоступен.',
        child: OutlinedButton.icon(
          onPressed: connection!.state.active ? null : onUnblock,
          icon: const BrandIcon(BrandGlyph.unlock),
          label: const Text('Восстановить интернет'),
        ),
      ),
    ],
  );
}
