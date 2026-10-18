import 'dart:async';
import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'profile_codec.dart';
import 'profiles_cubit.dart';

class ProfilesView extends StatefulWidget {
  const ProfilesView({
    super.key,
    required this.manager,
    this.ownsManager = true,
  });
  final ProfilesCubit manager;
  final bool ownsManager;
  @override
  State<ProfilesView> createState() => _ProfilesViewState();
}

class _ProfilesViewState extends State<ProfilesView> {
  @override
  void initState() {
    super.initState();
    if (widget.ownsManager) unawaited(widget.manager.load());
  }

  @override
  void dispose() {
    if (widget.ownsManager) unawaited(widget.manager.close());
    super.dispose();
  }

  Future<void> _import(bool link) async {
    final input = await showDialog<_ImportInput>(
      context: context,
      builder: (_) => _ImportDialog(
        link: link,
        number: widget.manager.state.profiles.length + 1,
      ),
    );
    if (input == null || !mounted) return;
    try {
      List<int> bytes = utf8.encode(input.link ?? '');
      if (!link) {
        final file = await openFile(
          acceptedTypeGroups: [
            const XTypeGroup(
              label: 'Профили AmneziaWG и AmneziaVPN',
              extensions: ['conf', 'vpn', 'json'],
            ),
          ],
        );
        if (file == null) return;
        if (await file.length() > maxProfileBytes) {
          throw const ProfileProblem('Файл превышает 256 КБ.');
        }
        bytes = [];
        await for (final part in file.openRead()) {
          if (bytes.length + part.length > maxProfileBytes) {
            throw const ProfileProblem('Файл превышает 256 КБ.');
          }
          bytes.addAll(part);
        }
      }
      if (!mounted) return;
      await widget.manager.importBytes(bytes, input.name);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is ProfileProblem
                ? error.message
                : 'Не удалось прочитать выбранный файл.',
          ),
        ),
      );
    }
  }

  Future<void> _remove(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить профиль?'),
        content: const Text(
          'Копия профиля и ключей будет удалена только из этого менеджера. Профиль в AmneziaVPN и исходный файл останутся.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) await widget.manager.remove(id);
  }

  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<ProfilesCubit, ProfilesState>(
    bloc: widget.manager,
    builder: (context, state) => Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'ПРОФИЛЬ',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Добавить профиль',
                  enabled:
                      !state.busy && !state.locked && !state.offerTemporary,
                  onSelected: (action) {
                    if (action == 'local') {
                      widget.manager.importLocal();
                    } else {
                      _import(action == 'link');
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'local',
                      child: ListTile(
                        leading: Icon(Icons.move_to_inbox_outlined),
                        title: Text('Из AmneziaVPN'),
                        subtitle: Text('Выбранный профиль на этом компьютере'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'file',
                      child: ListTile(
                        leading: Icon(Icons.file_open_outlined),
                        title: Text('Из файла'),
                        subtitle: Text('.conf, .vpn, .json'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'link',
                      child: ListTile(
                        leading: Icon(Icons.link),
                        title: Text('По ссылке'),
                        subtitle: Text('vpn:// или vless://'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 4,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.add,
                          size: 20,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Добавить',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (state.profiles.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('Добавьте профиль для подключения'),
              )
            else ...[
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      key: ValueKey(state.selected),
                      initialValue: state.selected,
                      isExpanded: true,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(
                          Icons.vpn_key_outlined,
                          size: 20,
                        ),
                        filled: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      items: state.profiles
                          .map(
                            (profile) => DropdownMenuItem(
                              value: profile.id,
                              child: Text(
                                profile.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged:
                          state.busy || state.locked || state.offerTemporary
                          ? null
                          : (id) {
                              if (id != null) widget.manager.select(id);
                            },
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Действия с профилем',
                    enabled:
                        !state.busy &&
                        !state.locked &&
                        !state.offerTemporary &&
                        state.selected != null,
                    icon: const Icon(Icons.more_vert),
                    onSelected: (action) {
                      if (action == 'check') {
                        widget.manager.checkSelected();
                      } else {
                        _remove(state.selected!);
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'check',
                        child: ListTile(
                          leading: Icon(Icons.fact_check_outlined),
                          title: Text('Проверить'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      PopupMenuItem(
                        value: 'remove',
                        child: ListTile(
                          leading: Icon(Icons.delete_outline),
                          title: Text('Удалить из менеджера'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              for (final profile in state.profiles.where(
                (p) => p.id == state.selected,
              ))
                Text(
                  '${profile.family == 'xray' ? 'VLESS' : 'AmneziaWG'} · ${profile.temporary ? 'Только в этом сеансе' : 'Ключи защищены'}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
            if (state.busy)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: LinearProgressIndicator(),
              ),
            if (state.message != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  state.message!,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            if (state.offerTemporary)
              Wrap(
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: widget.manager.useTemporary,
                    child: const Text('Только в этом сеансе'),
                  ),
                  TextButton(
                    onPressed: widget.manager.cancelTemporary,
                    child: const Text('Отмена'),
                  ),
                ],
              ),
          ],
        ),
      ),
    ),
  );
}

class _ImportInput {
  const _ImportInput(this.name, this.link);
  final String name;
  final String? link;
}

class _ImportDialog extends StatefulWidget {
  const _ImportDialog({required this.link, required this.number});
  final bool link;
  final int number;
  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<_ImportDialog> {
  late final _name = TextEditingController(text: 'Профиль ${widget.number}');
  final _link = TextEditingController();
  @override
  void dispose() {
    _name.dispose();
    _link.clear();
    _link.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Импорт профиля'),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              maxLength: 64,
              decoration: const InputDecoration(labelText: 'Название'),
            ),
            if (widget.link)
              TextField(
                controller: _link,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                maxLength: maxProfileBytes,
                decoration: const InputDecoration(
                  labelText: 'Ссылка vpn:// или vless://',
                  counterText: '',
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Отмена'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(
          context,
          _ImportInput(_name.text, widget.link ? _link.text : null),
        ),
        child: Text(widget.link ? 'Импортировать' : 'Выбрать файл'),
      ),
    ],
  );
}
