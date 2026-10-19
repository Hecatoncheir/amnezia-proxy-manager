import 'dart:async';
import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'profile_codec.dart';
import 'profiles_cubit.dart';

class ProfileEditor extends Cubit<String> {
  ProfileEditor() : super('');
  void open(String action) => emit(action);
}

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
  final _editor = ProfileEditor();
  final _name = TextEditingController();
  final _link = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.ownsManager) unawaited(widget.manager.load());
  }

  @override
  void dispose() {
    unawaited(_editor.close());
    _name.dispose();
    _link.clear();
    _link.dispose();
    if (widget.ownsManager) unawaited(widget.manager.close());
    super.dispose();
  }

  Future<List<int>?> _file() async {
    final file = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(
          label: 'Профили AmneziaWG и AmneziaVPN',
          extensions: ['conf', 'vpn', 'json'],
        ),
      ],
    );
    if (file == null) return null;
    if (await file.length() > maxProfileBytes) {
      throw const ProfileProblem('Файл превышает 256 КБ.');
    }
    final bytes = <int>[];
    await for (final part in file.openRead()) {
      if (bytes.length + part.length > maxProfileBytes) {
        throw const ProfileProblem('Файл превышает 256 КБ.');
      }
      bytes.addAll(part);
    }
    return bytes;
  }

  Future<void> _import() async {
    try {
      final bytes = await _input();
      if (bytes == null || !mounted) return;
      final name = _profileName();
      await widget.manager.importBytes(bytes, name);
      if (!mounted) return;
      _link.clear();
      _editor.open('');
    } catch (error) {
      _importError(error);
    }
  }

  Future<List<int>?> _input() async =>
      _editor.state == 'link' ? utf8.encode(_link.text) : await _file();
  String _profileName() => _name.text.trim().isEmpty
      ? 'Профиль ${widget.manager.state.profiles.length + 1}'
      : _name.text;
  void _importError(Object error) {
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

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<ProfilesCubit, ProfilesState>(
        bloc: widget.manager,
        builder: (context, state) => BlocBuilder<ProfileEditor, String>(
          bloc: _editor,
          builder: (context, action) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Выберите профиль для подключения. Ключи хранятся отдельно от интерфейса.',
              ),
              const SizedBox(height: 16),
              ..._profileCards(state),
              _actions(state),
              if (action.startsWith('delete:'))
                _confirmDelete(action.substring(7), state),
              const SizedBox(height: 24),
              Text(
                'Добавить профиль',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              _importActions(state),
              if (action == 'file' || action == 'link')
                _importForm(action, state),
              ..._messages(state),
            ],
          ),
        ),
      );

  Widget _importActions(ProfilesState state) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      OutlinedButton.icon(
        onPressed: _enabled(state) ? () => widget.manager.importLocal() : null,
        icon: const Icon(Icons.move_to_inbox_outlined),
        label: const Text('Из AmneziaVPN'),
      ),
      OutlinedButton.icon(
        onPressed: _enabled(state) ? () => _editor.open('file') : null,
        icon: const Icon(Icons.file_open_outlined),
        label: const Text('Из файла'),
      ),
      OutlinedButton.icon(
        onPressed: _enabled(state) ? () => _editor.open('link') : null,
        icon: const Icon(Icons.link),
        label: const Text('По ссылке'),
      ),
    ],
  );

  List<Widget> _profileCards(ProfilesState state) => [
    for (final profile in state.profiles) _profileCard(profile, state),
    if (state.profiles.isEmpty)
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Text('Профилей пока нет. Добавьте первый ниже.'),
      ),
  ];

  Widget _profileCard(ProfileSummary profile, ProfilesState state) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: ListTile(
      leading: Icon(
        profile.id == state.selected
            ? Icons.check_circle
            : Icons.circle_outlined,
      ),
      title: Text(profile.name),
      subtitle: Text(
        '${profile.family == 'xray' ? 'VLESS' : 'AmneziaWG'} · ${profile.temporary ? 'В памяти' : 'Ключи защищены'}',
      ),
      selected: profile.id == state.selected,
      enabled: !state.busy && !state.locked,
      onTap: () {
        _editor.open('');
        widget.manager.select(profile.id);
      },
    ),
  );

  List<Widget> _messages(ProfilesState state) => [
    if (state.busy)
      const Padding(
        padding: EdgeInsets.only(top: 16),
        child: LinearProgressIndicator(),
      ),
    if (state.message != null)
      Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Text(state.message!),
      ),
    if (state.offerTemporary)
      Wrap(
        spacing: 8,
        runSpacing: 8,
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
  ];

  bool _enabled(ProfilesState state) =>
      !state.busy && !state.locked && !state.offerTemporary;

  Widget _actions(ProfilesState state) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      TextButton.icon(
        onPressed: _enabled(state) && state.selected != null
            ? widget.manager.checkSelected
            : null,
        icon: const Icon(Icons.fact_check_outlined),
        label: const Text('Проверить профиль'),
      ),
      TextButton.icon(
        onPressed: _enabled(state) && state.selected != null
            ? () => _editor.open('delete:${state.selected}')
            : null,
        icon: const Icon(Icons.delete_outline),
        label: const Text('Удалить из менеджера'),
      ),
    ],
  );

  Widget _confirmDelete(String id, ProfilesState state) => Card(
    margin: const EdgeInsets.only(top: 12),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Удалить копию профиля из менеджера? Профиль в AmneziaVPN и исходный файл останутся.',
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              TextButton(
                onPressed: _enabled(state)
                    ? () async {
                        await widget.manager.remove(id);
                        _editor.open('');
                      }
                    : null,
                child: const Text('Удалить'),
              ),
              TextButton(
                onPressed: () => _editor.open(''),
                child: const Text('Отмена'),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _importForm(String action, ProfilesState state) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: Column(
      children: [
        TextField(
          controller: _name,
          maxLength: 64,
          decoration: const InputDecoration(labelText: 'Название профиля'),
        ),
        if (action == 'link')
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
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton(
              onPressed: _enabled(state) ? _import : null,
              child: Text(action == 'link' ? 'Импортировать' : 'Выбрать файл'),
            ),
            TextButton(
              onPressed: () {
                _link.clear();
                _editor.open('');
              },
              child: const Text('Отмена'),
            ),
          ],
        ),
      ],
    ),
  );
}
