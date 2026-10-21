// Отдельный неизменённый sing-box; исходники и лицензия GPL-3.0 указаны в docs/TUN.md.
const Map<String, dynamic> tunPolicy = {
  'repository': 'SagerNet/sing-box',
  'tag': 'v1.14.3',
  'version': '1.14.3',
  'family': 'tun',
  'label': 'TUN · SING-BOX',
  'schemaVersion': 1,
  'cliContract': 4,
  'sourceRevision': '7054cac5124465ffdb145870d7c01885566711b1',
  'minAppVersion': '0.1.1',
  'maxAppVersionExclusive': '0.2.0',
  'assets': {
    'windows-x64': 'sing-box-1.14.3-windows-amd64.zip',
    'linux-x64': 'sing-box-1.14.3-linux-amd64.tar.gz',
    'macos-arm64': 'sing-box-1.14.3-darwin-arm64.tar.gz',
  },
  'packages': {
    'linux-x64': {
      'archiveSHA256':
          'e2bdf179c15a3652955dc44867e33ca0965c9c9b91b34267dcc5a5d639a5feee',
      'binarySHA256':
          '768d31fa7f68debc067bb4626539498a1e8751d36a7b99e1a54bee6a23815f93',
      'binarySize': 81338597,
      'binaryName': 'sing-box',
      'archiveBinaryName': 'sing-box-1.14.3-linux-amd64/sing-box',
      'licenseName': 'sing-box-1.14.3-linux-amd64/LICENSE',
    },
    'macos-arm64': {
      'archiveSHA256':
          '0360ce634a04c26a6b4fd957517987bb4f6c8950f63435ce3c5af2fcae5860c5',
      'binarySHA256':
          '28b7200074d6380006acc4f035a404c8af3dceb65dd92d7386ed92c9224e08a2',
      'binarySize': 83885298,
      'binaryName': 'sing-box',
      'archiveBinaryName': 'sing-box-1.14.3-darwin-arm64/sing-box',
      'licenseName': 'sing-box-1.14.3-darwin-arm64/LICENSE',
    },
    'windows-x64': {
      'archiveSHA256':
          'd8b86ef58936dba9230ec6a57ffa4243933f3c14ef4809828b6c553440ed1518',
      'binarySHA256':
          '5c19bb3f8c12d4e85b3d47fe63123a7624b314b58dd7a8e32f51004f1c4d2faf',
      'binarySize': 81987584,
      'binaryName': 'sing-box.exe',
      'archiveBinaryName': 'sing-box-1.14.3-windows-amd64/sing-box.exe',
      'licenseName': 'sing-box-1.14.3-windows-amd64/LICENSE',
    },
  },
};
