import 'package:http/http.dart' as http;

import '../updates/app_updates.dart' show AppVersion;
import 'engine_release.dart';
import 'github_assets.dart';

class EngineCatalog {
  EngineCatalog(this.client, {this.policy = enginePolicy});
  final Map<String, dynamic> policy;
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
        Uri.https('api.github.com', '/repos/${policy['repository']}/releases', {
          'per_page': '10',
          'page': '$page',
        }),
        4 * 1024 * 1024,
      );
      if (data is! List) {
        throw const FormatException('Неверный список выпусков');
      }
      releases.addAll(
        data.whereType<Map>().where(
          (release) =>
              EngineRelease.isStable(release) ||
              (policy['allowPrerelease'] == true &&
                  release['tag_name'] == policy['tag'] &&
                  release['draft'] == false &&
                  release['prerelease'] == true),
        ),
      );
      if (data.length < 10 ||
          releases.any((r) => r['tag_name'] == policy['tag'])) {
        break;
      }
    }
    releases.sort(
      (a, b) =>
          AppVersion.parse(b['tag_name'])!
              .compareTo(AppVersion.parse(a['tag_name'])!),
    );
    for (final release in releases) {
      final candidate = EngineRelease.compatible(
        release,
        policy,
        applicationVersion: version,
        platform: platform,
        policy: policy,
      );
      if (candidate != null) return candidate;
    }
    return null;
  }
}
