import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_updates.dart';
import '../engine/download_ring.dart';

class UpdatesView extends StatefulWidget {
  const UpdatesView({super.key, this.controller});
  final AppUpdates? controller;

  @override
  State<UpdatesView> createState() => _UpdatesViewState();
}

class _UpdatesViewState extends State<UpdatesView> {
  late final updates = widget.controller ?? AppUpdates();
  bool installedCopy = false;

  @override
  void initState() {
    super.initState();
    unawaited(initialize());
  }

  Future<void> initialize() async {
    await updates.initialize();
    try {
      final directory = await updates.installationDirectory();
      if (mounted) setState(() => installedCopy = directory != null);
    } catch (_) {
      // Переносимая копия обновляется вручную через страницу выпуска.
    }
  }

  @override
  void dispose() {
    if (widget.controller == null) unawaited(updates.close());
    super.dispose();
  }

  Future<void> open(Uri uri) async {
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    } catch (_) {
      // Ошибка открытия показывается внутри приложения.
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось открыть файл или страницу.')),
      );
    }
  }

  bool _confirmInstall = false;
  Future<void> install() async {
    setState(() => _confirmInstall = true);
  }

  String get message => switch (updates.status) {
    AppUpdateStatus.idle => 'Проверка выполняется по запросу.',
    AppUpdateStatus.checking => 'Проверяем новые версии…',
    AppUpdateStatus.current => 'Установлена актуальная версия.',
    AppUpdateStatus.available => 'Доступна версия ${updates.release!.tag}',
    AppUpdateStatus.empty => 'Выпуски с установщиками пока недоступны.',
    AppUpdateStatus.failed =>
      'Не удалось проверить обновления. Повторите позже.',
  };

  @override
  Widget build(BuildContext context) => BlocBuilder<AppUpdates, AppUpdateState>(
    bloc: updates,
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Обновления', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text('Версия: ${updates.installed.isEmpty ? '—' : updates.installed}'),
        const SizedBox(height: 8),
        Text(message),
        const SizedBox(height: 12),
        actions(),
        ..._installPrompt(),
        ..._downloadProgress(),
        ..._downloadErrors(),
        ..._downloadedInfo(),
        ..._releaseNotes(),
      ],
    ),
  );

  Widget actions() {
    final busy =
        updates.downloading ||
        updates.installing ||
        updates.status == AppUpdateStatus.checking;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton(
          onPressed: busy ? null : updates.check,
          child: const Text('Проверить обновления'),
        ),
        ..._downloadButtons(busy),
        ..._installButtons(busy),
        ..._macPackageButtons(busy),
        ..._folderButtons(busy),
        ..._releaseButtons(busy),
      ],
    );
  }

  List<Widget> _installPrompt() => [
    if (_confirmInstall) ...[
      const SizedBox(height: 16),
      const Text(
        'Приложение закроется. Установщик обновит его и запустит снова.',
      ),
      Wrap(
        spacing: 8,
        children: [
          FilledButton(
            onPressed: updates.installing
                ? null
                : () async {
                    setState(() => _confirmInstall = false);
                    await updates.install();
                  },
            child: const Text('Подтвердить установку'),
          ),
          TextButton(
            onPressed: () => setState(() => _confirmInstall = false),
            child: const Text('Отмена'),
          ),
        ],
      ),
    ],
  ];

  List<Widget> _downloadProgress() => [
    if (updates.downloading) ...[
      const SizedBox(height: 12),
      DownloadRing(
        progress: updates.downloadedBytes / updates.package!.size,
        label: 'Скачивание обновления',
      ),
    ],
  ];

  List<Widget> _downloadErrors() => [
    if (updates.downloadFailed)
      const Text('Не удалось скачать или проверить файл. Повторите загрузку.'),
    if (updates.installFailed)
      const Text(
        'Не удалось запустить установщик. Приложение остаётся открытым.',
      ),
  ];

  List<Widget> _downloadedInfo() {
    final package = updates.downloadedPackage;
    if (package == null) return [];
    return [
      const Text('Пакет загружен. Размер и SHA-256 проверены.'),
      if (Platform.isLinux)
        SelectableText(
          'Закройте приложение и установите обновление командой:\n'
          'sh "${package.path}"',
        ),
      if (Platform.isMacOS)
        const Text(
          'Откройте DMG, закройте приложение и перенесите новую копию в Applications.',
        ),
      if (Platform.isWindows && !installedCopy)
        const Text(
          'Это переносимая копия. Для установки запустите скачанный Setup вручную.',
        ),
    ];
  }

  List<Widget> _releaseNotes() => [
    if (updates.release != null)
      ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: const Text('Изменения версии'),
        children: [SelectableText(updates.release!.notes)],
      ),
  ];

  List<Widget> _downloadButtons(bool busy) => [
    if (updates.status == AppUpdateStatus.available && updates.package != null)
      OutlinedButton(
        onPressed: busy || updates.downloadedPackage != null
            ? null
            : updates.download,
        child: const Text('Скачать обновление'),
      ),
  ];

  List<Widget> _installButtons(bool busy) => [
    if (updates.downloadedPackage != null && installedCopy)
      FilledButton(
        onPressed: busy ? null : install,
        child: const Text('Установить и перезапустить'),
      ),
  ];

  List<Widget> _macPackageButtons(bool busy) => [
    if (updates.downloadedPackage != null && Platform.isMacOS)
      OutlinedButton(
        onPressed: busy ? null : () => open(updates.downloadedPackage!.uri),
        child: const Text('Открыть пакет'),
      ),
  ];

  List<Widget> _folderButtons(bool busy) => [
    if (updates.downloadedPackage != null &&
        !installedCopy &&
        !Platform.isMacOS)
      OutlinedButton(
        onPressed: busy
            ? null
            : () => open(updates.downloadedPackage!.parent.uri),
        child: const Text('Папка загрузки'),
      ),
  ];

  List<Widget> _releaseButtons(bool busy) => [
    if (updates.release != null)
      TextButton(
        onPressed: () => open(updates.release!.url),
        child: const Text('Страница выпуска'),
      ),
  ];
}
