import '../updates/app_updates.dart' show AppVersion;

const engineRepository = 'synacker/amnezia-proxy';
const engineSourceRevision = 'f5a7912dba8b128ae5c1a3f68a06be7c1668b908';
const engineAssetNames = {
  'windows-x64': 'awg-proxy-windows-amd64.exe',
  'linux-x64': 'awg-proxy-linux-amd64',
  'macos-arm64': 'awg-proxy-darwin-arm64',
};

class EngineAsset {
  const EngineAsset(this.name, this.url, this.size, this.sha256);
  final String name, sha256;
  final Uri url;
  final int size;

  static EngineAsset? parse(Map data, String tag, String name) {
    final size = data['size'], digest = data['digest'];
    final url = Uri.https(
      'github.com',
      '/$engineRepository/releases/download/$tag/$name',
    );
    if (data['name'] != name ||
        data['browser_download_url'] != url.toString()) {
      return null;
    }
    if (size is! int || size <= 0 || size > 128 * 1024 * 1024) return null;
    if (digest is! String ||
        !RegExp(r'^sha256:[0-9a-f]{64}$').hasMatch(digest)) {
      return null;
    }
    return EngineAsset(name, url, size, digest.substring(7));
  }
}

class EngineRelease {
  const EngineRelease(this.tag, this.revision, this.asset, this.manifest);
  final String tag, revision;
  final EngineAsset asset;
  final Map manifest;

  Map<String, Object?> receipt() => {
    'manifest': manifest,
    'release': {
      'tag_name': tag,
      'draft': false,
      'prerelease': false,
      'assets': [
        {
          'name': asset.name,
          'size': asset.size,
          'digest': 'sha256:${asset.sha256}',
          'browser_download_url': asset.url.toString(),
        },
      ],
    },
  };

  static bool isStable(Map release) {
    final tag = release['tag_name'];
    if (tag is! String || !tag.startsWith('v') || tag.trim() != tag) {
      return false;
    }
    final version = AppVersion.parse(tag);
    return release['draft'] == false &&
        release['prerelease'] == false &&
        version != null &&
        version.preview.isEmpty;
  }

  static EngineRelease? compatible(
    Map release,
    Map manifest, {
    required String applicationVersion,
    required String platform,
  }) {
    if (!isStable(release)) return null;
    if (manifest['schemaVersion'] != 1 ||
        manifest['cliContract'] != 1 ||
        manifest['sourceRevision'] != engineSourceRevision) {
      return null;
    }
    final app = AppVersion.parse(applicationVersion);
    final minimum = AppVersion.parse(
      manifest['minAppVersion']?.toString() ?? '',
    );
    final maximum = AppVersion.parse(
      manifest['maxAppVersionExclusive']?.toString() ?? '',
    );
    if (app == null || minimum == null || maximum == null) return null;
    if (minimum.compareTo(maximum) >= 0 ||
        app.compareTo(minimum) < 0 ||
        app.compareTo(maximum) >= 0) {
      return null;
    }
    final name = engineAssetNames[platform];
    if (name == null ||
        manifest['assets'] is! Map ||
        manifest['assets'][platform] != name) {
      return null;
    }
    final assets = release['assets'];
    if (assets is! List) return null;
    final matches = assets
        .whereType<Map>()
        .where((asset) => asset['name'] == name)
        .toList();
    if (matches.length != 1) return null;
    final asset = EngineAsset.parse(matches.single, release['tag_name'], name);
    return asset == null
        ? null
        : EngineRelease(
            release['tag_name'],
            engineSourceRevision,
            asset,
            manifest,
          );
  }
}
