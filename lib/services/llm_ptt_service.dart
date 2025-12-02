import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

class LlmPttService {
  final VoidCallback onStateChanged;
  final void Function(String finalText) onFinalText;

  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _initialized = false;

  bool holding = false;
  String partialText = '';

  LlmPttService({
    required this.onStateChanged,
    required this.onFinalText,
  });

  Future<void> init() async {
    _initialized = await _speech.initialize(
      onStatus: (status) => debugPrint('STT status: $status'),
      onError: (err) => debugPrint('STT error: $err'),
    );
    debugPrint('STT initialized: $_initialized');
  }

  Future<void> startPTT() async {
    if (!_initialized) return;
    holding = true;
    partialText = '';
    onStateChanged();

    await _speech.listen(
      onResult: (result) {
        partialText = result.recognizedWords;
        onStateChanged();
      },
      partialResults: true,
      // si quieres forzar español:
      // localeId: 'es-ES', // o 'es-CO'
    );
  }

  Future<void> stopPTT() async {
    if (!_initialized) return;
    await _speech.stop();
    holding = false;
    onStateChanged();

    final finalText = partialText.trim();
    if (finalText.isNotEmpty) {
      onFinalText(finalText);
    }
  }

  void dispose() {
    _speech.cancel();
  }
}
