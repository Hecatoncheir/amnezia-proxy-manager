// Демонстрационный запуск для README: синтетический профиль и настройки в памяти.
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_driver/driver_extension.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'package:amnezia_proxy_manager/main.dart';
import 'package:amnezia_proxy_manager/settings/window_placement.dart';
import 'package:amnezia_proxy_manager/features/engine/engine_manager.dart';
import 'package:amnezia_proxy_manager/features/engine/xray_policy.dart';
import 'package:amnezia_proxy_manager/features/profiles/profile_codec.dart';
import 'package:amnezia_proxy_manager/features/profiles/profile_validator.dart';
import 'package:amnezia_proxy_manager/features/profiles/profile_vault.dart';
import 'package:amnezia_proxy_manager/features/profiles/profiles_cubit.dart';

class _DemoVault implements ProfileVault {
  _DemoVault(this.value);
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String? next, {required String? expected}) async {
    value = next;
  }
}

Future<void> main() async {
  enableFlutterDriverExtension(
    handler: (message) async {
      final height = message == 'settings-window' ? 780.0 : 640.0;
      await windowManager.setSize(Size(640, height));
      return 'ok';
    },
  );
  // Изолируем демонстрационный запуск от настроек установленного приложения.
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  await WindowPlacement.initialize(preferenceKey: 'readme-window');
  await windowManager.setSize(const Size(640, 640));
  final awg = EngineManager(), xray = EngineManager(policy: xrayPolicy);
  final profile = await ProfileCodec().decode(
    utf8.encode(
      jsonEncode({
        'outbounds': [
          {
            'tag': 'proxy',
            'protocol': 'vless',
            'settings': {
              'vnext': [
                {
                  'address': 'example.com',
                  'port': 443,
                  'users': [
                    {
                      'id': '00000000-0000-4000-8000-000000000001',
                      'encryption': 'none',
                    },
                  ],
                },
              ],
            },
            'streamSettings': {
              'network': 'tcp',
              'security': 'tls',
              'tlsSettings': {'serverName': 'example.com'},
            },
          },
        ],
      }),
    ),
  );
  final vault = _DemoVault(
    jsonEncode({
      'schema': 1,
      'selected': '11111111111111111111111111111111',
      'profiles': [
        {
          'id': '11111111111111111111111111111111',
          'name': 'Мой профиль',
          'format': 'VLESS',
          'configuration': profile.configuration,
        },
      ],
    }),
  );
  runApp(
    ProxyManagerApp(
      engine: awg,
      xray: xray,
      profiles: ProfilesCubit(
        vault: vault,
        validate: EngineProfileValidator(awg, xray: xray).validate,
      ),
    ),
  );
}
