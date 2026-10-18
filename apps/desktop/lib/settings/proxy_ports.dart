class ProxyPorts {
  const ProxyPorts({this.socks = 1080, this.http = 8080});
  final int socks, http;

  static ProxyPorts parse(String socks, String http) {
    final socksPort = _port(socks);
    final httpPort = _port(http);
    if (socksPort == httpPort) {
      throw const FormatException('Для SOCKS5 и HTTP нужны разные порты.');
    }
    return ProxyPorts(socks: socksPort, http: httpPort);
  }

  static int _port(String text) {
    final value = int.tryParse(text);
    if (value == null || value < 1 || value > 65535) {
      throw const FormatException('Укажите порт от 1 до 65535.');
    }
    return value;
  }
}
