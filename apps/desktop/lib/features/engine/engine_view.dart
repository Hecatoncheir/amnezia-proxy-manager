import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'engine_manager.dart';

class EngineView extends StatefulWidget {
  const EngineView({super.key, required this.manager});
  final EngineManager manager;

  @override
  State<EngineView> createState() => _EngineViewState();
}

class _EngineViewState extends State<EngineView> {
  @override
  void initState() {
    super.initState();
    unawaited(widget.manager.check());
  }

  @override
  void dispose() {
    unawaited(widget.manager.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BlocBuilder<EngineManager, EngineState>(
    bloc: widget.manager,
    builder: (context, state) => Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ДВИЖОК AMNEZIAWG',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(_message(state)),
            if (state.status == EngineStatus.downloading) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(value: state.progress),
            ],
            if (state.status == EngineStatus.available) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: widget.manager.download,
                icon: const Icon(Icons.download_outlined),
                label: Text('Скачать движок ${state.release!.tag}'),
              ),
            ],
            if (state.status == EngineStatus.unavailable ||
                state.status == EngineStatus.failed)
              TextButton(
                onPressed: widget.manager.check,
                child: const Text('Проверить ещё раз'),
              ),
          ],
        ),
      ),
    ),
  );
}

String _message(EngineState state) => switch (state.status) {
  EngineStatus.checking =>
    'Проверяем установленный движок и совместимые выпуски…',
  EngineStatus.unavailable =>
    'В репозитории движка пока нет совместимого выпуска для этой системы.',
  EngineStatus.available =>
    state.installed == null
        ? 'Для подготовки приложения скачайте движок.'
        : 'Установлен ${state.installed!.tag}. Доступно обновление движка.',
  EngineStatus.downloading => 'Загрузка: ${(state.progress * 100).floor()}%',
  EngineStatus.ready =>
    state.offline
        ? 'Движок ${state.installed!.tag} проверен. Проверка обновлений временно недоступна.'
        : 'Движок ${state.installed!.tag} установлен и проверен.',
  EngineStatus.failed =>
    state.installed == null
        ? 'Не удалось проверить или установить движок. Повторите попытку.'
        : 'Обновление не удалось. Предыдущая версия сохранена.',
};
