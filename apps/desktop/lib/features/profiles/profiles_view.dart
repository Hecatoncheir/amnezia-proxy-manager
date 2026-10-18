import 'dart:async';
import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'profile_codec.dart';
import 'profiles_cubit.dart';

class ProfilesView extends StatefulWidget {
  const ProfilesView({super.key, required this.manager});
  final ProfilesCubit manager;
  @override
  State<ProfilesView> createState() => _ProfilesViewState();
}

class _ProfilesViewState extends State<ProfilesView> {
  @override
  void initState() {
    super.initState();
    unawaited(widget.manager.load());
  }

  @override
  void dispose() {
    unawaited(widget.manager.close());
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
              extensions: ['conf', 'vpn'],
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
          'Профиль и его ключи будут удалены из хранилища приложения. Исходный файл останется у вас.',
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
            Text(
              'ПРОФИЛЬ VPN',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            if (state.profiles.isEmpty)
              const Text('Профиль не выбран')
            else ...[
              DropdownButtonFormField<String>(
                key: ValueKey(state.selected),
                initialValue: state.selected,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Профиль'),
                items: state.profiles
                    .map(
                      (profile) => DropdownMenuItem(
                        value: profile.id,
                        child: Text(
                          '${profile.name}${profile.temporary ? ' · временный' : ''}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: state.busy || state.offerTemporary
                    ? null
                    : (id) {
                        if (id != null) widget.manager.select(id);
                      },
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: state.busy || state.offerTemporary
                        ? null
                        : widget.manager.checkSelected,
                    icon: const Icon(Icons.fact_check_outlined),
                    label: const Text('Проверить'),
                  ),
                  TextButton.icon(
                    onPressed:
                        state.busy ||
                            state.offerTemporary ||
                            state.selected == null
                        ? null
                        : () => _remove(state.selected!),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Удалить'),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: state.busy || state.offerTemporary
                      ? null
                      : () => _import(false),
                  icon: const Icon(Icons.file_open_outlined),
                  label: const Text('Импорт файла'),
                ),
                TextButton(
                  onPressed: state.busy || state.offerTemporary
                      ? null
                      : () => _import(true),
                  child: const Text('Ссылка vpn://'),
                ),
              ],
            ),
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
                  labelText: 'Ссылка vpn://',
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
