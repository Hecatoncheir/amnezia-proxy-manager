import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../engine/download_ring.dart';
import 'preparation_cubit.dart';

class PreparationView extends StatelessWidget {
  const PreparationView({super.key});

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<PreparationCubit, PreparationState>(
        builder: (context, state) {
          final message = state.message;
          if (message == null) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(
              children: [
                if (state.progress != null) ...[
                  DownloadRing(progress: state.progress!),
                  const SizedBox(width: 12),
                ],
                if (state.installing) ...[
                  const SizedBox(
                    width: 48,
                    height: 48,
                    child: CircularProgressIndicator(),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Text(message, style: const TextStyle(fontSize: 12)),
                ),
              ],
            ),
          );
        },
      );
}
