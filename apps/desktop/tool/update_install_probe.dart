// Используется только для испытания настоящего Setup в отдельном каталоге.
import 'dart:convert';
import 'dart:io';

import 'package:amnezia_proxy_manager/features/updates/app_updates.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/widgets.dart';

Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (arguments.isEmpty) {
    runApp(const SizedBox());
    return;
  }
  final installer = File(arguments[0]);
  final journal = File(arguments[1]);
  final directory = await installedAppDirectory();
  if (directory == null) {
    throw StateError('Проверка должна идти из установленной копии');
  }
  final package = AppPackage(
    appPackages['windows-x64']!,
    Uri.parse('https://github.com'),
    await installer.length(),
    'sha256:${await sha256.bind(installer.openRead()).first}',
  );
  final updates =
      AppUpdates(
          downloadDirectory: () async => journal.parent,
          launchInstaller: (file, args) async {
            await journal.writeAsString(
              jsonEncode({'phase': 'launch', 'directory': directory.path}),
            );
            await startAppInstaller(file, args);
          },
          closeApplication: () {
            journal.writeAsStringSync(
              jsonEncode({'phase': 'exit', 'directory': directory.path}),
            );
            exit(0);
          },
        )
        ..status = AppUpdateStatus.available
        ..downloadedPackage = installer
        ..release = AppRelease(
          'v0.2.0',
          Uri.parse('https://github.com'),
          '',
          AppVersion.parse('0.2.0')!,
          {package.name: package},
        );
  await updates.install();
  await journal.writeAsString(jsonEncode({'phase': 'failed'}));
  exit(1);
}
