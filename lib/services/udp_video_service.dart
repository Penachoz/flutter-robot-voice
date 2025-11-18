import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../models/frame_assembler.dart';
import '../models/udp_hdr.dart';

class UdpVideoService {
  final void Function() onFrame;

  final int _videoPort;
  final int _subPort;
  String _robotIp;

  RawDatagramSocket? _txSock;   // para subscribe
  RawDatagramSocket? _vidSock;  // para recibir vídeo
  Timer? _subTimer;

  final FrameAssembler _assembler = FrameAssembler();

  Uint8List? _lastJpeg;
  int _fpsCount = 0;
  DateTime _fpsT0 = DateTime.now();
  double _fps = 0;

  UdpVideoService({
    required this.onFrame,
    String initialRobotIp = '192.168.4.1',
    int videoPort = 5600,
    int subPort = 5007,
  })  : _robotIp = initialRobotIp,
        _videoPort = videoPort,
        _subPort = subPort;

  Uint8List? get lastJpeg => _lastJpeg;
  double get fps => _fps;
  int get videoPort => _videoPort;
  int get subPort => _subPort;

  Future<void> init() async {
    // Socket para enviar suscripciones
    _txSock = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);

    // Socket para recibir Vídeo MJPEG fragmentado
    _vidSock = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      _videoPort,
    );
    _vidSock!.listen(_onVideoDatagram);

    // Suscripción keep-alive
    _sendSubscribe();
    _subTimer?.cancel();
    _subTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _sendSubscribe(),
    );
  }

  void updateRobotIp(String ip) {
    final trimmed = ip.trim();
    if (trimmed.isEmpty) return;
    _robotIp = trimmed;
    _sendSubscribe();
  }

  void _sendSubscribe() {
    final ip = InternetAddress.tryParse(_robotIp);
    if (ip == null) return;

    final payload = utf8.encode(
      '{"type":"subscribe","video_port":$_videoPort}',
    );
    _txSock?.send(payload, ip, _subPort);
  }

  void _onVideoDatagram(RawSocketEvent e) {
    if (e != RawSocketEvent.read) return;
    final dg = _vidSock?.receive();
    if (dg == null) return;

    final data = dg.data;
    if (data.lengthInBytes < UdpHdr.size) return;

    final hdr = UdpHdr.tryParse(data);
    if (hdr == null) return;

    final payload = data.buffer.asUint8List(
      UdpHdr.size,
      data.lengthInBytes - UdpHdr.size,
    );

    final complete = _assembler.push(hdr, payload);
    if (complete != null) {
      _lastJpeg = complete;

      // FPS
      _fpsCount++;
      final now = DateTime.now();
      final dt = now.difference(_fpsT0).inMilliseconds;
      if (dt > 1000) {
        _fps = (_fpsCount * 1000.0) / dt;
        _fpsCount = 0;
        _fpsT0 = now;
      }

      onFrame();
    }
  }

  void dispose() {
    _subTimer?.cancel();
    _vidSock?.close();
    _txSock?.close();
  }
}
