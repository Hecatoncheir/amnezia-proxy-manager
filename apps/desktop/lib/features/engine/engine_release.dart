import '../updates/app_updates.dart' show AppVersion;

const engineRepository = 'bropines/awg-wireproxy';
const engineSourceRevision = '02588433b6328171b594d76f3f16bd3404258a83';
const engineTag = 'v2.1.0';
const Map<String, dynamic> enginePolicy = {
  "schemaVersion": 1,
  "cliContract": 2,
  "sourceRevision": "02588433b6328171b594d76f3f16bd3404258a83",
  "minAppVersion": "0.1.1",
  "maxAppVersionExclusive": "0.2.0",
  "assets": {
    "windows-x64": "awg-wireproxy_2.1.0_windows_amd64.zip",
    "linux-x64": "awg-wireproxy_2.1.0_linux_amd64.tar.gz",
    "macos-arm64": "awg-wireproxy_2.1.0_darwin_arm64.tar.gz",
  },
  "packages": {
    "windows-x64": {
      "archiveSHA256":
          "6d86151aea7befce55ebb2a1b74e0ccaf553c4ae44f224a4e4ceb0c8362ebd40",
      "binarySHA256":
          "c5890fedddc63a97ad123e2d490edbf5fd2a0edfccbc7db99b1c53c72efcb2f3",
      "binarySize": 11687936,
    },
    "linux-x64": {
      "archiveSHA256":
          "aa05dbc67198b56417334e4aa8bfca73cd23ba946eb70e1c7205b2319d618311",
      "binarySHA256":
          "619f3e7b4aa6e9f6af38a826f30578d0e2eca9f932e93f518220884e9b7e10a6",
      "binarySize": 11370656,
    },
    "macos-arm64": {
      "archiveSHA256":
          "583f0c1d73e2510c8ca1c3200b27131d1a54f1019e036509760202da89aa5bce",
      "binarySHA256":
          "8fa5940404a06c5b1e6f51cfb4ae59c88afcdc3a9da980dc57b6a3575494bb29",
      "binarySize": 10782610,
    },
  },
};
const engineAssetNames = {
  "windows-x64": "awg-wireproxy_2.1.0_windows_amd64.zip",
  "linux-x64": "awg-wireproxy_2.1.0_linux_amd64.tar.gz",
  "macos-arm64": "awg-wireproxy_2.1.0_darwin_arm64.tar.gz",
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

  String get binaryName =>
      asset.name.endsWith('.zip') ? 'wireproxy.exe' : 'wireproxy';
  Map get package => (manifest['packages'] as Map).values.firstWhere(
    (value) => value['archiveSHA256'] == asset.sha256,
  ) as Map;
  EngineAsset get binary => EngineAsset(
    binaryName,
    asset.url,
    package['binarySize'] as int,
    package['binarySHA256'] as String,
  );

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
    if (!isStable(release) ||
        release['tag_name'] != engineTag ||
        manifest['cliContract'] != 2) {
      return null;
    }
    if (manifest['schemaVersion'] != 1 ||
        manifest['cliContract'] != 2 ||
        manifest['sourceRevision'] != engineSourceRevision) {
      return null;
    }
    final app = AppVersion.parse(applicationVersion);
    final minimum = AppVersion.parse(enginePolicy['minAppVersion'] as String);
    final maximum = AppVersion.parse(
      enginePolicy['maxAppVersionExclusive'] as String,
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
    if (asset?.sha256 != enginePolicy['packages'][platform]['archiveSHA256']) {
      return null;
    }
    return asset == null
        ? null
        : EngineRelease(
            release['tag_name'],
            engineSourceRevision,
            asset,
            enginePolicy,
          );
  }
}
