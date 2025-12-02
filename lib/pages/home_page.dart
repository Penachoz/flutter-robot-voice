import 'package:flutter/material.dart';

import '../services/udp_video_service.dart';
import '../services/udp_cmd_service.dart';
import '../services/voice_ptt_service.dart';
import '../services/udp_chat_service.dart';
import '../services/llm_ptt_service.dart';
import 'workout_page.dart';

const String kDefaultRobotIp = '192.168.86.1';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _ipCtrl = TextEditingController(text: kDefaultRobotIp);

  late final UdpVideoService _videoService;
  late final UdpCmdService _cmdService;
  late final VoicePttService _voiceService; // comandos
  late final UdpChatService _chatService; // texto para LLM
  late final LlmPttService _llmPttService; // PTT charla
  int _speedLevel = 5; // 0..10  ->  0%,10%,...,100%
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

    _chatService = UdpChatService();

    _llmPttService = LlmPttService(
      onStateChanged: _onLlmVoiceChanged,
      onFinalText: _onLlmFinalText,
    );

    _initAll();
  }

  Future<void> _initAll() async {
    await _videoService.init();
    await _cmdService.init();
    await _voiceService.init();
    await _chatService.init();
    await _llmPttService.init();
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

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('CMD: $cmd (via "$keyword")')));

    _cmdService.sendCmd(_ipCtrl.text, cmd);
  }

  void _onLlmVoiceChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _onLlmFinalText(String text) {
    if (!mounted) return;

    _chatService.sendChat(_ipCtrl.text, text);

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Enviado a Atom: "$text"')));
  }

  @override
  void dispose() {
    _videoService.dispose();
    _cmdService.dispose();
    _voiceService.dispose();
    _chatService.dispose();
    _llmPttService.dispose();
    _ipCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final img = _videoService.lastJpeg;
    final fps = _videoService.fps;
    final holding = _voiceService.holding;
    final partial = _voiceService.partialText;

    final holdingChat = _llmPttService.holding;
    final partialChat = _llmPttService.partialText;

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

          // ---- Estado / Texto reconocido (COMANDOS) ----
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Text('FPS ~ ${fps.toStringAsFixed(1)}'),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    partial.isEmpty
                        ? 'Mantén pulsado para comandos: avanza, alto, izquierda, derecha…'
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

          // ---- PUSH TO TALK COMANDOS ----
          GestureDetector(
            onTapDown: (_) => _voiceService.startPTT(),
            onTapUp: (_) => _voiceService.stopPTT(),
            onTapCancel: () => _voiceService.stopPTT(),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 22),
              decoration: BoxDecoration(
                color: holding ? Colors.red : Colors.indigo,
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 8),
                ],
              ),
              child: Text(
                holding
                    ? 'Escuchando comandos… suelta para enviar'
                    : 'Mantén pulsado para hablar (comandos)',
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // ---- Estado / Texto reconocido (CHARLA LLM) ----
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    partialChat.isEmpty
                        ? 'Habla con Atom: "cómo estás", "qué ves", etc.'
                        : partialChat,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  holdingChat ? Icons.record_voice_over : Icons.mic_none,
                  color: holdingChat ? Colors.green : Colors.grey,
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // ---- PUSH TO TALK LLM (ENVÍA TEXTO POR UDP AL ROBOT) ----
          GestureDetector(
            onTapDown: (_) => _llmPttService.startPTT(),
            onTapUp: (_) => _llmPttService.stopPTT(),
            onTapCancel: () => _llmPttService.stopPTT(),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 22),
              decoration: BoxDecoration(
                color: holdingChat ? Colors.green : Colors.teal,
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 8),
                ],
              ),
              child: Text(
                holdingChat
                    ? 'Escuchando a Atom… suelta para enviar pregunta'
                    : 'Mantén pulsado para hablar con Atom (LLM)',
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ),

          const SizedBox(height: 10),

          // ---- Botones rápidos (debug) ----
          // ---- Botones rápidos (debug) ----
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: () => _cmdService.sendCmd(_ipCtrl.text, 'I'),
                child: const Text('FORWARD (I)'),
              ),
              OutlinedButton(
                onPressed: () => _cmdService.sendCmd(_ipCtrl.text, 'K'),
                child: const Text('STOP (K)'),
              ),
              OutlinedButton(
                onPressed: () => _cmdService.sendCmd(_ipCtrl.text, 'J'),
                child: const Text('LEFT (J)'),
              ),
              OutlinedButton(
                onPressed: () => _cmdService.sendCmd(_ipCtrl.text, 'L'),
                child: const Text('RIGHT (L)'),
              ),
              OutlinedButton(
                onPressed: () => _cmdService.sendCmd(_ipCtrl.text, 'U'),
                child: const Text('TURN LEFT (U)'),
              ),
              OutlinedButton(
                onPressed: () => _cmdService.sendCmd(_ipCtrl.text, 'O'),
                child: const Text('TURN RIGHT (O)'),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // ---- Slider de velocidad (0..100 en pasos de 10) ----
          Builder(
            builder: (context) {
              final speedPercent = _speedLevel * 10; // 0,10,...,100
              return Column(
                children: [
                  Text('Velocidad: $speedPercent%'),
                  Slider(
                    value: _speedLevel.toDouble(),
                    min: 0,
                    max: 10,
                    divisions: 10, // 11 niveles
                    label: '$speedPercent%',
                    onChanged: (v) {
                      setState(() {
                        _speedLevel = v.round();
                      });
                    },
                    onChangeEnd: (v) {
                      final level = v.round();
                      final speed = level * 10; // 0-100

                      _cmdService.sendCmd(_ipCtrl.text, '$speed');

                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Speed enviada: $speed%')),
                      );
                    },
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: 10),

          FilledButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => WorkoutPage(videoService: _videoService),
                ),
              );
            },
            child: const Text('Entrena conmigo (lagartijas)'),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
