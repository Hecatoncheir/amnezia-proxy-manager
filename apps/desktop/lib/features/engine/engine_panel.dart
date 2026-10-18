import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../profiles/profiles_cubit.dart';
import 'engine_manager.dart';
import 'engine_view.dart';

class EnginePanel extends StatefulWidget {
  const EnginePanel({
    super.key,
    required this.awg,
    required this.xray,
    required this.profiles,
    this.ownsManagers = true,
  });
  final EngineManager awg, xray;
  final bool ownsManagers;
  final ProfilesCubit profiles;
  @override
  State<EnginePanel> createState() => _EnginePanelState();
}

class _EnginePanelState extends State<EnginePanel> {
  late String _family;
  @override
  void initState() {
    super.initState();
    _family = widget.profiles.state.requiredEngine;
  }

  @override
  Widget build(BuildContext context) =>
      BlocListener<ProfilesCubit, ProfilesState>(
        bloc: widget.profiles,
        listenWhen: (before, after) =>
            before.requiredEngine != after.requiredEngine,
        listener: (_, state) => setState(() => _family = state.requiredEngine),
        child: IndexedStack(
          index: _family == 'xray' ? 1 : 0,
          children: [
            EngineView(
              manager: widget.awg,
              selector: _selector(),
              ownsManager: widget.ownsManagers,
            ),
            EngineView(
              manager: widget.xray,
              selector: _selector(),
              ownsManager: widget.ownsManagers,
            ),
          ],
        ),
      );

  Widget _selector() => DropdownButtonHideUnderline(
    child: DropdownButton<String>(
      value: _family,
      isExpanded: true,
      borderRadius: BorderRadius.circular(16),
      items: const [
        DropdownMenuItem(value: 'awg', child: Text('AmneziaWG')),
        DropdownMenuItem(value: 'xray', child: Text('VLESS · Xray')),
      ],
      onChanged: (value) {
        if (value != null) setState(() => _family = value);
      },
    ),
  );
}
