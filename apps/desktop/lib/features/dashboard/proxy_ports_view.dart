import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../settings/proxy_ports_cubit.dart';

class ProxyPortsView extends StatelessWidget {
  const ProxyPortsView({super.key, required this.cubit, required this.locked});
  final ProxyPortsCubit cubit;
  final bool locked;

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<ProxyPortsCubit, ProxyPortsState>(
        bloc: cubit,
        builder: _content,
      );

  Widget _content(BuildContext context, ProxyPortsState state) {
    if (state.loading) return const SizedBox.shrink();
    final enabled = !locked && !state.saving;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _PortField(
                label: 'SOCKS5',
                value: state.socks,
                enabled: enabled,
                onChanged: cubit.editSocks,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _PortField(
                label: 'HTTP',
                value: state.http,
                enabled: enabled,
                onChanged: cubit.editHttp,
              ),
            ),
            IconButton(
              tooltip: 'Сохранить порты',
              onPressed: enabled && state.changed ? cubit.save : null,
              icon: const Icon(Icons.check),
            ),
          ],
        ),
        if (state.error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              state.error!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 12,
              ),
            ),
          ),
      ],
    );
  }
}

class _PortField extends StatelessWidget {
  const _PortField({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });
  final String label, value;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => TextFormField(
    key: ValueKey('proxy-port-$label'),
    initialValue: value,
    enabled: enabled,
    keyboardType: TextInputType.number,
    inputFormatters: [
      FilteringTextInputFormatter.digitsOnly,
      LengthLimitingTextInputFormatter(5),
    ],
    decoration: InputDecoration(labelText: label, isDense: true),
    onChanged: onChanged,
  );
}
