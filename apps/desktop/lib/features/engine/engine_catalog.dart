import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../updates/app_updates.dart' show AppVersion;
import 'engine_release.dart';
import 'github_assets.dart';

class EngineCatalog {
  EngineCatalog(this.client);
  final http.Client client;

  Future<EngineRelease?> latestCompatible(
    String version,
    String platform,
  ) async {
    // Страницы ограничены; выбираем по SemVer, а не по дате публикации.
    final releases = <Map>[];
    for (var page = 1; page <= 5; page++) {
      final data = await readGitHubJson(
        client,
        Uri.https('api.github.com', '/repos/$engineRepository/releases', {
          'per_page': '100',
          'page': '$page',
        }),
        4 * 1024 * 1024,
      );
      if (data is! List) {
        throw const FormatException('Неверный список выпусков');
      }
      releases.addAll(data.whereType<Map>().where(EngineRelease.isStable));
      if (data.length < 100) break;
    }
    releases.sort(
      (a, b) =>
          AppVersion.parse(b['tag_name'])!
              .compareTo(AppVersion.parse(a['tag_name'])!),
    );
    for (final release in releases) {
      final manifest = await _manifest(release);
      if (manifest == null) continue;
      final candidate = EngineRelease.compatible(
        release,
        manifest,
        applicationVersion: version,
        platform: platform,
      );
      if (candidate != null) return candidate;
    }
    return null;
  }

  Future<Map?> _manifest(Map release) async {
    final assets = release['assets'];
    if (assets is! List) return null;
    final matches = assets
        .whereType<Map>()
        .where((asset) => asset['name'] == 'engine.json')
        .toList();
    if (matches.length != 1) return null;
    final asset = EngineAsset.parse(
      matches.single,
      release['tag_name'],
      'engine.json',
    );
    if (asset == null || asset.size > 16384) return null;
    final bytes = await readGitHubBytes(client, asset.url, 16384);
    if (bytes.length != asset.size ||
        sha256.convert(bytes).toString() != asset.sha256) {
      throw const FormatException('Манифест движка повреждён');
    }
    try {
      final data = jsonDecode(utf8.decode(bytes));
      return data is Map ? data : null;
    } on FormatException {
      return null;
    }
  }
}
