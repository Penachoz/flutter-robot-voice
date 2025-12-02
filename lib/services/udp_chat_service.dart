import 'dart:async';
import 'dart:convert';
import 'dart:io';

class UdpChatService {
  // Debe coincidir con el puerto del servidor en el robot
  static const int chatPort = 5602;

  RawDatagramSocket? _socket;

  Future<void> init() async {
    _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
  }

  int get localPort => _socket?.port ?? 0;

  void sendChat(String robotIp, String text) {
    final sock = _socket;
    if (sock == null) return;

    final data = utf8.encode(text);
    final addr = InternetAddress(robotIp);
    sock.send(data, addr, chatPort);
  }

  void dispose() {
    _socket?.close();
    _socket = null;
  }
}
