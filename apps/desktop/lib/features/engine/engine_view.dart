import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../theme/brand_icon.dart';

import 'engine_manager.dart';
import 'download_ring.dart';

class EngineView extends StatefulWidget {
  const EngineView({
    super.key,
    required this.manager,
    this.selector,
    this.ownsManager = true,
  });
  final Widget? selector;
  final EngineManager manager;
  final bool ownsManager;

  @override
  State<EngineView> createState() => _EngineViewState();
}

class _EngineViewState extends State<EngineView> {
  @override
  void initState() {
    super.initState();
    if (widget.ownsManager) unawaited(widget.manager.check());
  }

  @override
  void dispose() {
    if (widget.ownsManager) unawaited(widget.manager.close());
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
            Row(
              children: [
                BrandIcon(
                  BrandGlyph.engine,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child:
                      widget.selector ??
                      Text(
                        widget.manager.policy['label'] as String,
                        style: const TextStyle(
                          fontFamily: 'JetBrainsMono',
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                ),
                if (state.status == EngineStatus.ready)
                  Icon(
                    Icons.check_circle_outline,
                    color: Theme.of(context).colorScheme.primary,
                    size: 20,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (state.status != EngineStatus.downloading) Text(_message(state)),
            if (state.status == EngineStatus.downloading ||
                state.status == EngineStatus.installing) ...[
              const SizedBox(height: 12),
              Center(child: DownloadRing(progress: state.progress)),
            ],
            if (state.status == EngineStatus.available) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: widget.manager.download,
                icon: const BrandIcon(BrandGlyph.download),
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
  EngineStatus.checking => 'Проверяем движок…',
  EngineStatus.unavailable =>
    'В репозитории движка пока нет совместимого выпуска для этой системы.',
  EngineStatus.available =>
    state.installed == null
        ? 'Для подготовки приложения скачайте движок.'
        : 'Установлен ${state.installed!.tag}. Доступно обновление движка.',
  EngineStatus.downloading => 'Загрузка: ${(state.progress * 100).floor()}%',
  EngineStatus.installing =>
    'Загрузка завершена. Проверяем и устанавливаем движок…',
  EngineStatus.ready =>
    state.offline
        ? 'Движок ${state.installed!.tag} проверен. Проверка обновлений временно недоступна.'
        : 'Готов к работе · ${state.installed!.tag}',
  EngineStatus.failed =>
    state.installed == null
        ? 'Не удалось проверить или установить движок. Повторите попытку.'
        : 'Обновление не удалось. Предыдущая версия сохранена.',
};
