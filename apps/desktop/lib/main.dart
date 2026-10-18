import 'package:flutter/material.dart';

import 'theme/gruvbox.dart';

void main() => runApp(const ProxyManagerApp());

class ProxyManagerApp extends StatefulWidget {
  const ProxyManagerApp({super.key});
  @override
  State<ProxyManagerApp> createState() => _ProxyManagerAppState();
}

class _ProxyManagerAppState extends State<ProxyManagerApp> {
  bool dark = true;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Amnezia Proxy Manager',
    debugShowCheckedModeBanner: false,
    theme: gruvboxTheme(Brightness.light),
    darkTheme: gruvboxTheme(Brightness.dark),
    themeMode: dark ? ThemeMode.dark : ThemeMode.light,
    themeAnimationDuration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 240),
    home: Scaffold(
      appBar: AppBar(
        title: const Text('Amnezia Proxy Manager'),
        actions: [
          IconButton(
            tooltip: 'Переключить тему',
            onPressed: () => setState(() => dark = !dark),
            icon: AnimatedSwitcher(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 180),
              child: Icon(
                dark ? Icons.light_mode : Icons.dark_mode,
                key: ValueKey(dark),
              ),
            ),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: const [
              Text('Локальный прокси', style: TextStyle(fontSize: 28)),
              SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Не подключено • каркас приложения'),
                      SizedBox(height: 12),
                      Text('SOCKS5  127.0.0.1:1080\nHTTP  127.0.0.1:8080'),
                      SizedBox(height: 16),
                      FilledButton(onPressed: null, child: Text('Подключить')),
                      SizedBox(height: 12),
                      Text(
                        'Импорт профиля и управление движком запланированы.',
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 20),
              Text('Отдельный userspace-туннель'),
              SizedBox(height: 8),
              Text(
                'Прокси создаёт собственное подключение AmneziaWG. '
                'Он не использует активный туннель приложения AmneziaVPN. '
                'Понадобится явно экспортированный профиль. '
                'Автоматическое чтение защищённых профилей не обещается.',
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
