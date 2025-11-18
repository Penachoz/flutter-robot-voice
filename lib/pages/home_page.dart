import 'package:flutter/material.dart';

import '../services/udp_video_service.dart';
import '../services/udp_cmd_service.dart';
import '../services/voice_ptt_service.dart';

const String kDefaultRobotIp = '192.168.4.1';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _ipCtrl = TextEditingController(text: kDefaultRobotIp);

  late final UdpVideoService _videoService;
  late final UdpCmdService _cmdService;
  late final VoicePttService _voiceService;

  @override
  void initState() {
    super.initState();

    _videoService = UdpVideoService(
      initialRobotIp: kDefaultRobotIp,
      onFrame: _onVideoUpdated,
    );

    _cmdService = UdpCmdService();

    _voiceService = VoicePttService(
      onStateChanged: _onVoiceChanged,
      onCommandDetected: _onVoiceCommandDetected,
    );

    _initAll();
  }

  Future<void> _initAll() async {
    await _videoService.init();
    await _cmdService.init();
    await _voiceService.init();
    if (mounted) {
      setState(() {});
    }
  }

  void _onVideoUpdated() {
    if (!mounted) return;
    setState(() {});
  }

  void _onVoiceChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _onVoiceCommandDetected(String cmd, String keyword) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('CMD: $cmd (via "$keyword")')),
    );

    _cmdService.sendCmd(_ipCtrl.text, cmd);
  }

  @override
  void dispose() {
    _videoService.dispose();
    _cmdService.dispose();
    _voiceService.dispose();
    _ipCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final img      = _videoService.lastJpeg;
    final fps      = _videoService.fps;
    final holding  = _voiceService.holding;
    final partial  = _voiceService.partialText;

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
                    _videoService.updateRobotIp(_ipCtrl.text);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Suscrito a ${_ipCtrl.text.trim()}:${_videoService.subPort}',
                        ),
                      ),
                    );
                  },
                  child: const Text('Conectar'),
                ),
              ],
            ),
          ),

          // ---- VIDEO ----
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Container(
              color: Colors.black,
              child: img == null
                  ? const Center(
                      child: Text(
                        'Esperando video…',
                        style: TextStyle(color: Colors.white70),
                      ),
                    )
                  : Image.memory(
                      img,
                      gaplessPlayback: true,
                      fit: BoxFit.contain,
                    ),
            ),
          ),

          // ---- Estado / Texto reconocido ----
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Text('FPS ~ ${fps.toStringAsFixed(1)}'),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    partial.isEmpty
                        ? 'Mantén pulsado para hablar: avanza, alto, izquierda, derecha, sentado, parado…'
                        : partial,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  holding ? Icons.mic : Icons.mic_none,
                  color: holding ? Colors.red : Colors.grey,
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // ---- PUSH TO TALK ----
          GestureDetector(
            onTapDown: (_) => _voiceService.startPTT(),
            onTapUp: (_) => _voiceService.stopPTT(),
            onTapCancel: () => _voiceService.stopPTT(),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 22),
              decoration: BoxDecoration(
                color: holding ? Colors.red : Colors.indigo,
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8)],
              ),
              child: Text(
                holding
                    ? 'Escuchando… suelta para enviar'
                    : 'Mantén pulsado para hablar',
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ),

          const SizedBox(height: 10),

          // ---- Botones rápidos (debug) ----
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: () => _cmdService.sendCmd(_ipCtrl.text, 'FORWARD'),
                child: const Text('FORWARD'),
              ),
              OutlinedButton(
                onPressed: () => _cmdService.sendCmd(_ipCtrl.text, 'STOP'),
                child: const Text('STOP'),
              ),
              OutlinedButton(
                onPressed: () => _cmdService.sendCmd(_ipCtrl.text, 'LEFT'),
                child: const Text('LEFT'),
              ),
              OutlinedButton(
                onPressed: () => _cmdService.sendCmd(_ipCtrl.text, 'RIGHT'),
                child: const Text('RIGHT'),
              ),
              OutlinedButton(
                onPressed: () => _cmdService.sendCmd(_ipCtrl.text, 'SIT'),
                child: const Text('SIT'),
              ),
              OutlinedButton(
                onPressed: () => _cmdService.sendCmd(_ipCtrl.text, 'STAND'),
                child: const Text('STAND'),
              ),
            ],
          ),

          const SizedBox(height: 10),
        ],
      ),
    );
  }
}
