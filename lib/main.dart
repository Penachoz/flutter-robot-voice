// lib/main.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

// ====== AJUSTES POR DEFECTO ======
const String kDefaultRobotIp = '192.168.4.1';
const int    kSubPort        = 5007;  // suscripción de vídeo
const int    kCmdPort        = 5005;  // comandos
const int    kVideoPort      = 5600;  // puerto local UDP para recibir vídeo

void main() => runApp(const RobotDogApp());

class RobotDogApp extends StatelessWidget {
  const RobotDogApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RobotDog (UDP ultra-low-latency)',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // ---- IP del robot (editable en UI) ----
  final _ipCtrl = TextEditingController(text: kDefaultRobotIp);
  String get _robotIp => _ipCtrl.text.trim();
  InternetAddress? _parseIp(String s) => InternetAddress.tryParse(s.trim());

  // ---- Sockets UDP ----
  RawDatagramSocket? _txSock;   // para enviar (cmd + subscribe)
  RawDatagramSocket? _vidSock;  // bind local para vídeo
  Timer? _subTimer;

  // ---- Reensamblador de frames ----
  final _assembler = FrameAssembler();
  Uint8List? _lastJpeg;
  int _fpsCount = 0;
  DateTime _fpsT0 = DateTime.now();
  double _fps = 0;

  // ---- Voz (push-to-talk) ----
  final stt.SpeechToText _stt = stt.SpeechToText();
  bool _sttReady = false;
  bool _holding = false;
  String _partial = '';

  @override
  void initState() {
    super.initState();
    _initAll();
  }

  Future<void> _initAll() async {
    // Permisos
    await Permission.microphone.request();

    // Inicializa STT (suelta PTT si el motor se detiene o hay error)
    _sttReady = await _stt.initialize(
      onError: (e) {
        debugPrint('STT error: $e');
        _unholdAndStop();
      },
      onStatus: (s) {
        debugPrint('STT status: $s');
        if (s == 'done' || s == 'notListening') {
          _unholdAndStop();
        }
      },
    );

    // Sockets
    _txSock  = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    _vidSock = await RawDatagramSocket.bind(InternetAddress.anyIPv4, kVideoPort);
    _vidSock!.listen(_onVideoDatagram);

    // Suscripción keepalive al vídeo
    _sendSubscribe();
    _subTimer?.cancel();
    _subTimer = Timer.periodic(const Duration(seconds: 2), (_) => _sendSubscribe());

    if (mounted) setState(() {});
  }

  // Helper: suelta PTT y detiene STT seguro
  Future<void> _unholdAndStop() async {
    if (_holding) {
      _holding = false;
      if (mounted) setState(() {});
    }
    try {
      await _stt.stop();
    } catch (_) {}
  }

  void _sendSubscribe() {
    final ip = _parseIp(_robotIp) ?? _parseIp(kDefaultRobotIp);
    if (ip == null) return; // evita crash si el campo está vacío o mal
    final payload = utf8.encode('{"type":"subscribe","video_port":$kVideoPort}');
    _txSock?.send(payload, ip, kSubPort);
  }

  void _onVideoDatagram(RawSocketEvent e) {
    if (e != RawSocketEvent.read) return;
    final dg = _vidSock?.receive();
    if (dg == null) return;

    final data = dg.data;
    if (data.lengthInBytes < UdpHdr.size) return;

    final hdr = UdpHdr.tryParse(data);
    if (hdr == null) return;

    final payload = data.buffer.asUint8List(UdpHdr.size, data.lengthInBytes - UdpHdr.size);
    final complete = _assembler.push(hdr, payload);
    if (complete != null) {
      _lastJpeg = complete;
      _fpsCount++;
      final now = DateTime.now();
      final dt = now.difference(_fpsT0).inMilliseconds;
      if (dt > 1000) {
        _fps = (_fpsCount * 1000.0) / dt;
        _fpsCount = 0;
        _fpsT0 = now;
      }
      if (mounted) setState(() {});
    }
  }

  // ========= PUSH-TO-TALK =========
  Future<void> _startPTT() async {
    if (!_sttReady || _holding) return;
    _holding = true;
    _partial = '';
    if (mounted) setState(() {});

    await _stt.listen(
      localeId: 'es_CO', // ajusta si prefieres es_ES / es_MX
      listenMode: stt.ListenMode.dictation,
      partialResults: true,
      onResult: (res) async {
        final txt = (res.recognizedWords).toLowerCase().trim();
        if (txt.isEmpty) return;
        if (mounted) setState(() => _partial = txt);

        final hit = _matchFirstKeyword(txt);
        if (hit != null) {
          final kw  = hit.key;
          final cmd = hit.value;

          // 1) soltar PTT y parar STT
          await _unholdAndStop();

          // 2) feedback + envío
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('CMD: $cmd (via "$kw")')),
            );
          }
          _sendCmd(cmd);
        }
      },
    );
  }

  Future<void> _stopPTT() async {
    await _unholdAndStop();
  }

  // ---- Palabras clave -> comando (toma la PRIMERA que aparezca) ----
  static final _synFwd  = ['avanza','adelante','avance','vamos'];
  static final _synStop = ['alto','para','detente','parate','frena','stop','quieto','basta','deten'];
  static final _synL    = ['izquierda','izq'];
  static final _synR    = ['derecha','der'];
  static final _synSit  = ['sentado','siéntate','sientate'];
  static final _synStnd = ['parado','de pie','levántate','levantate','arriba'];

  MapEntry<String,String>? _matchFirstKeyword(String text) {
    final candidates = <MapEntry<String,String>>[];
    void add(List<String> keys, String cmd) {
      for (final k in keys) {
        final i = text.indexOf(k);
        if (i >= 0) candidates.add(MapEntry('$i|$k', cmd));
      }
    }
    add(_synFwd,  'FORWARD');
    add(_synStop, 'STOP');
    add(_synL,    'LEFT');
    add(_synR,    'RIGHT');
    add(_synSit,  'SIT');
    add(_synStnd, 'STAND');

    if (candidates.isEmpty) return null;
    candidates.sort((a,b){
      final ia = int.parse(a.key.split('|').first);
      final ib = int.parse(b.key.split('|').first);
      return ia.compareTo(ib);
    });
    final first = candidates.first;
    final kw = first.key.split('|')[1];
    return MapEntry(kw, first.value);
  }

  void _sendCmd(String cmd) {
    final ip = _parseIp(_robotIp) ?? _parseIp(kDefaultRobotIp);
    if (ip == null) return;
    final payload = utf8.encode(jsonEncode({"type":"cmd","value":cmd}));
    _txSock?.send(payload, ip, kCmdPort);
  }

  @override
  void dispose() {
    _subTimer?.cancel();
    _vidSock?.close();
    _txSock?.close();
    _stt.stop();
    _ipCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final img = _lastJpeg;

    return Scaffold(
      appBar: AppBar(title: const Text('RobotDog (UDP ultra-low-latency)')),
      body: Column(
        children: [
          // ---- IP del robot + Conectar ----
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ipCtrl,
                    decoration: const InputDecoration(
                      labelText: 'IP del robot',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () {
                    _sendSubscribe(); // reenvía suscripción con nueva IP
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Suscrito a ${_robotIp}:$kSubPort')),
                    );
                  },
                  child: const Text('Conectar'),
                ),
              ],
            ),
          ),

          // ---- VIDEO ----
          AspectRatio(
            aspectRatio: 16/9,
            child: Container(
              color: Colors.black,
              child: img == null
                  ? const Center(
                      child: Text('Esperando video…',
                          style: TextStyle(color: Colors.white70)))
                  : Image.memory(img, gaplessPlayback: true, fit: BoxFit.contain),
            ),
          ),

          // ---- Estado / Texto reconocido ----
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Text('FPS ~ ${_fps.toStringAsFixed(1)}'),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _partial.isEmpty
                      ? 'Mantén pulsado para hablar: avanza, alto, izquierda, derecha, sentado, parado…'
                      : _partial,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(_holding ? Icons.mic : Icons.mic_none,
                    color: _holding ? Colors.red : Colors.grey),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // ---- PUSH TO TALK ----
          GestureDetector(
            onTapDown: (_) => _startPTT(),
            onTapUp:   (_) => _stopPTT(),
            onTapCancel: () => _stopPTT(),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 22),
              decoration: BoxDecoration(
                color: _holding ? Colors.red : Colors.indigo,
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8)],
              ),
              child: Text(
                _holding ? 'Escuchando… suelta para enviar' : 'Mantén pulsado para hablar',
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ),

          const SizedBox(height: 10),

          // ---- Botones rápidos (debug) ----
          Wrap(
            spacing: 8, runSpacing: 8,
            children: [
              OutlinedButton(onPressed: ()=> _sendCmd('FORWARD'), child: const Text('FORWARD')),
              OutlinedButton(onPressed: ()=> _sendCmd('STOP'),    child: const Text('STOP')),
              OutlinedButton(onPressed: ()=> _sendCmd('LEFT'),    child: const Text('LEFT')),
              OutlinedButton(onPressed: ()=> _sendCmd('RIGHT'),   child: const Text('RIGHT')),
              OutlinedButton(onPressed: ()=> _sendCmd('SIT'),     child: const Text('SIT')),
              OutlinedButton(onPressed: ()=> _sendCmd('STAND'),   child: const Text('STAND')),
            ],
          ),

          const SizedBox(height: 10),
        ],
      ),
    );
  }
}

// =================== Reensamblado UDP (MJPEG fragmentado) ===================

class UdpHdr {
  // "MJPG" (0x4D4A5047) | seq | ts(64) | frameLen | fragIdx | fragCnt
  final int magic, seq;
  final int tsMsHi, tsMsLo;
  final int frameLen;
  final int fragIdx, fragCnt;

  static const size = 24; // 4 + 4 + 8 + 4 + 2 + 2

  UdpHdr(this.magic, this.seq, this.tsMsHi, this.tsMsLo, this.frameLen, this.fragIdx, this.fragCnt);

  static UdpHdr? tryParse(Uint8List d) {
    if (d.lengthInBytes < size) return null;
    final b = ByteData.sublistView(d);
    final magic = b.getUint32(0, Endian.big);
    if (magic != 0x4D4A5047) return null; // "MJPG"

    final seq     = b.getUint32(4, Endian.big);
    final tsHi    = b.getUint32(8, Endian.big);
    final tsLo    = b.getUint32(12, Endian.big);
    final flen    = b.getUint32(16, Endian.big);
    final fragIdx = b.getUint16(20, Endian.big);
    final fragCnt = b.getUint16(22, Endian.big);
    return UdpHdr(magic, seq, tsHi, tsLo, flen, fragIdx, fragCnt);
  }
}

class FrameAssembler {
  final _map = <int, _Pending>{};
  int _lastGoodSeq = -1;

  Uint8List? push(UdpHdr h, Uint8List payload) {
    // descarta frames demasiado viejos para evitar “goma”
    if (_lastGoodSeq != -1 && h.seq + 32 < _lastGoodSeq) return null;

    final p = _map.putIfAbsent(h.seq, () => _Pending(h.frameLen, h.fragCnt));
    p.add(h.fragIdx, payload);

    // limpieza para limitar memoria
    if (_map.length > 48) {
      final keys = _map.keys.toList()..sort();
      for (int i = 0; i < keys.length - 24; ++i) {
        _map.remove(keys[i]);
      }
    }

    if (p.isComplete) {
      _lastGoodSeq = h.seq;
      _map.remove(h.seq);
      return p.join();
    }
    return null;
  }
}

class _Pending {
  final int total;
  final int fragCnt;
  final List<Uint8List?> frags;
  int arrived = 0;

  _Pending(this.total, this.fragCnt)
      : frags = List<Uint8List?>.filled(fragCnt, null, growable: false);

  void add(int idx, Uint8List data) {
    if (idx < 0 || idx >= fragCnt) return;
    if (frags[idx] == null) {
      frags[idx] = data;
      arrived++;
    }
  }

  bool get isComplete => arrived == fragCnt;

  Uint8List join() {
    final out = Uint8List(total);
    int off = 0;
    for (final f in frags) {
      final d = f!;
      out.setRange(off, off + d.length, d);
      off += d.length;
    }
    return out;
  }
}
