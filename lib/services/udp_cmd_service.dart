import 'dart:convert';
import 'dart:io';

class UdpCmdService {
  final int cmdPort;
  RawDatagramSocket? _txSock;

  UdpCmdService({this.cmdPort = 5005});

  Future<void> init() async {
    _txSock = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
  }

  void sendCmd(String robotIpText, String cmd) {
    final ip = InternetAddress.tryParse(robotIpText.trim());
    if (ip == null) return;

    final payload = utf8.encode(
      jsonEncode({"type": "cmd", "value": cmd}),
    );
    _txSock?.send(payload, ip, cmdPort);
  }

  void dispose() {
    _txSock?.close();
  }
}
