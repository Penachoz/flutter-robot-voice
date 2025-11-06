import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_vlc_player/flutter_vlc_player.dart';

const String robotIp   = '192.168.4.1';     // <-- cámbialo si tu robot usa otra
const int    robotPort = 5005;              // UDP puerto comandos
const String rtspUrl   = 'rtsp://192.168.4.1:8554/stream'; // RTSP del robot

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const RobotDogApp());
}

class RobotDogApp extends StatelessWidget {
  const RobotDogApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Robot Dog Controller',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const HomePage(),
    );
  }
}

enum ControlMode { voice, ps4 }

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  ControlMode _mode = ControlMode.voice;
  late VlcPlayerController _vlc;
  final stt.SpeechToText _stt = stt.SpeechToText();
  bool _sttAvailable = false;
  bool _listening = false;
  String _partial = '';
  RawDatagramSocket? _udp;
  Timer? _sttKeepAlive;

  @override
  void initState() {
    super.initState();
    _vlc = VlcPlayerController.network(
      rtspUrl,
      hwAcc: HwAcc.full,
      options: VlcPlayerOptions(),
    );
    _initAll();
  }

  Future<void> _initAll() async {
    await _ensurePermissions();
    await _openUdp();
    await _initSTT();
    if (mounted) setState(() {});
    // arranca en modo VOZ por defecto
    _sendMode(ControlMode.voice);
    _startVoiceLoopIfNeeded();
  }

  Future<void> _ensurePermissions() async {
    await [Permission.microphone].request();
  }

  Future<void> _openUdp() async {
    _udp?.close();
    _udp = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    _udp!.readEventsEnabled = true;
  }

  Future<void> _initSTT() async {
    _sttAvailable = await _stt.initialize(
      onStatus: (s) {
        if (s == 'done' || s == 'notListening') {
          _listening = false;
          _restartSTTIfVoiceMode();
        }
      },
      onError: (e) {
        _listening = false;
        _restartSTTIfVoiceMode(delayMs: 500);
      },
      debugLogging: false,
    );
  }

  void _restartSTTIfVoiceMode({int delayMs = 100}) {
    _sttKeepAlive?.cancel();
    if (_mode == ControlMode.voice && _sttAvailable) {
      _sttKeepAlive = Timer(Duration(milliseconds: delayMs), _startListening);
    }
  }

  void _startVoiceLoopIfNeeded() {
    if (_mode == ControlMode.voice) _startListening();
  }

  void _startListening() async {
    if (!_sttAvailable || _listening) return;
    _partial = '';
    _listening = await _stt.listen(
      localeId: 'es_CO',              // ajusta a tu acento; ej: es_ES, es_MX
      listenMode: stt.ListenMode.dictation,
      partialResults: true,
      onResult: (res) {
        final txt = (res.recognizedWords ?? '').toLowerCase().trim();
        setState(() => _partial = txt);
        if (txt.isNotEmpty) _maybeSendCommand(txt);
        // speech_to_text suele cortar a los ~60s; onStatus gatilla reintento
      },
    );
    if (!_listening) _restartSTTIfVoiceMode(delayMs: 500);
  }

  void _stopListening() {
    _stt.stop();
    _listening = false;
  }

  // --- Mapeo de palabras -> comandos ---
  static final List<String> _synFwd  = ['avanza','adelante','avance','vamos'];
  static final List<String> _synStop = ['alto','para','detente','parate','frena','stop','quieto','basta','deten'];
  static final List<String> _synL    = ['izquierda','izq'];
  static final List<String> _synR    = ['derecha','der'];
  static final List<String> _synSit  = ['sentado','siéntate','sientate'];
  static final List<String> _synStnd = ['parado','de pie','levántate','levantate','arriba'];

  void _maybeSendCommand(String text) {
    bool containsAny(List<String> keys) => keys.any((k) => text.contains(k));
    String? cmd;
    if      (containsAny(_synFwd))  cmd = 'FORWARD';
    else if (containsAny(_synStop)) cmd = 'STOP';
    else if (containsAny(_synL))    cmd = 'LEFT';
    else if (containsAny(_synR))    cmd = 'RIGHT';
    else if (containsAny(_synSit))  cmd = 'SIT';
    else if (containsAny(_synStnd)) cmd = 'STAND';

    if (cmd != null) {
      _sendCmd(cmd);
      // feedback visual rápido
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('CMD: $cmd')),
      );
    }
  }

  void _sendMode(ControlMode m) {
    _mode = m;
    final payload = jsonEncode({
      'type': 'mode',
      'value': (m == ControlMode.voice) ? 'voice' : 'ps4',
    });
    _sendUdp(payload);
    if (m == ControlMode.voice) {
      _startListening();
    } else {
      _stopListening();
    }
    setState(() {});
  }

  void _sendCmd(String value) {
    final payload = jsonEncode({'type': 'cmd', 'value': value});
    _sendUdp(payload);
  }

  void _sendUdp(String payload) {
    final data = utf8.encode(payload);
    _udp?.send(data, InternetAddress(robotIp), robotPort);
  }

  @override
  void dispose() {
    _sttKeepAlive?.cancel();
    _stopListening();
    _udp?.close();
    _vlc.dispose();
    super.dispose();
    }

  @override
  Widget build(BuildContext context) {
    final isVoice = _mode == ControlMode.voice;
    return Scaffold(
      appBar: AppBar(title: const Text('Robot Dog Controller')),
      body: Column(
        children: [
          // STREAM DE CÁMARA
          AspectRatio(
            aspectRatio: 16 / 9,
            child: VlcPlayer(
              controller: _vlc,
              aspectRatio: 16 / 9,
              placeholder: const Center(child: CircularProgressIndicator()),
            ),
          ),
          const SizedBox(height: 12),
          // BOTONES DE MODO
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FilledButton(
                onPressed: () => _sendMode(ControlMode.voice),
                style: FilledButton.styleFrom(
                  backgroundColor: isVoice ? Colors.indigo : null,
                ),
                child: const Text('Modo Voz'),
              ),
              const SizedBox(width: 12),
              FilledButton.tonal(
                onPressed: () => _sendMode(ControlMode.ps4),
                style: FilledButton.styleFrom(
                  backgroundColor: !isVoice ? Colors.indigo : null,
                ),
                child: const Text('Modo PS4'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // ESTADO DE VOZ
          if (isVoice) Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(_listening ? Icons.mic : Icons.mic_off,
                        color: _listening ? Colors.red : Colors.grey),
                    const SizedBox(width: 8),
                    Text(_listening ? 'Escuchando…' : 'No escuchando'),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _partial.isEmpty ? 'Di: avanza, alto, izquierda, derecha, sentado, parado…' : _partial,
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton(onPressed: _startListening, child: const Text('Reintentar')),
                    OutlinedButton(onPressed: _stopListening,   child: const Text('Pausar')),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
