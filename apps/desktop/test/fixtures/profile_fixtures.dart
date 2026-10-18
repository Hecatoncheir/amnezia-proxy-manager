// Только публичные синтетические ключи; не использовать для настоящего VPN.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

const testPrivateKey = 'uCTIK+56CPyCvwJxmU5dBfuyJvPuSXAq1FzHdnIxe1Q=';
const testPublicKey = 'QP+A67Z2UBrMgvNIdHv8gPel5URWNLS4B3ZQ2hQIZlg=';
const testConf =
    '''[Interface]
Address = 10.200.200.2/32
PrivateKey = $testPrivateKey
DNS = 10.200.200.1
Jc = 5
Jmin = 10
Jmax = 50
S1 = 20
S2 = 30
H1 = 100000-200000
H2 = 300000-400000
H3 = 500000-600000
H4 = 700000-800000
[Peer]
PublicKey = $testPublicKey
Endpoint = 127.0.0.1:9
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
''';

Map<String, Object> exportJson({Map<String, Object>? last}) => {
  'defaultContainer': 'amnezia-awg',
  'dns1': '10.200.200.1',
  'containers': [
    {
      'container': 'amnezia-awg',
      'awg': {
        'last_config': jsonEncode(last ?? {'config': testConf}),
      },
    },
  ],
};

String vpnUri(Map data) {
  final json = utf8.encode(jsonEncode(data));
  final header = ByteData(4)..setUint32(0, json.length);
  return 'vpn://${base64Url.encode([...header.buffer.asUint8List(), ...zlib.encode(json)]).replaceAll('=', '')}';
}
