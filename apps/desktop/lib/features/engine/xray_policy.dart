// Проверенные пакеты XTLS/Xray-core; хеши бинарников независимы от API.
const Map<String, dynamic> xrayPolicy = {
  "repository": "XTLS/Xray-core",
  "tag": "v26.7.28",
  "version": "26.7.28",
  "family": "xray",
  "label": "XRAY · VLESS",
  "allowPrerelease": true,
  "schemaVersion": 1,
  "cliContract": 3,
  "sourceRevision": "5ca6f4b7d4dc20a881d4330e498892697627ec0c",
  "minAppVersion": "0.1.1",
  "maxAppVersionExclusive": "0.2.0",
  "assets": {
    "windows-x64": "Xray-windows-64.zip",
    "linux-x64": "Xray-linux-64.zip",
    "macos-arm64": "Xray-macos-arm64-v8a.zip",
  },
  "packages": {
    "windows-x64": {
      "archiveSHA256":
          "c7172078fca4711bcd92a4774dcd1822544579c58816197575c47533317fd8d1",
      "binarySHA256":
          "1d9674327972a21afd4c906a7a72bb0856935aa9e0227c87f34f03d11a88bddf",
      "binarySize": 36904960,
      "binaryName": "xray.exe",
      "licenseName": "LICENSE",
    },
    "linux-x64": {
      "archiveSHA256":
          "8195d909f1109b8f3d99eefe401a3c451d7bf4af71f24d3815420f77e5dd2a40",
      "binarySHA256":
          "64d46afb80adea1bf97a0d467e83f4a9ac1ebd0995891e84bca3f1a1d1affb1d",
      "binarySize": 37720190,
      "binaryName": "xray",
      "licenseName": "LICENSE",
    },
    "macos-arm64": {
      "archiveSHA256":
          "9b99a351febe31b7e0c7f22deeb1577a1da0b98aaa51aec7fd17832e68cf63d6",
      "binarySHA256":
          "bd4154efa640c5b8e21f10b68afcc9177c4f1f543be3ec0485b10c499b2a4b27",
      "binarySize": 35006066,
      "binaryName": "xray",
      "licenseName": "LICENSE",
    },
  },
};
