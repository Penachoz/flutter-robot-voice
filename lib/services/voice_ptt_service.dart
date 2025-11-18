import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../models/commands.dart';

class VoicePttService {
  final void Function() onStateChanged;
  final void Function(String cmd, String keyword) onCommandDetected;

  final stt.SpeechToText _stt = stt.SpeechToText();
  bool _ready = false;
  bool _holding = false;
  String _partial = '';

  bool get holding => _holding;
  String get partialText => _partial;

  VoicePttService({
    required this.onStateChanged,
    required this.onCommandDetected,
  });

  Future<void> init() async {
    await Permission.microphone.request();

    _ready = await _stt.initialize(
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
  }

  Future<void> startPTT() async {
    if (!_ready || _holding) return;

    _holding = true;
    _partial = '';
    onStateChanged();

    await _stt.listen(
      localeId: 'es_CO', // puedes cambiar a es_ES / es_MX si quieres
      listenMode: stt.ListenMode.dictation,
      partialResults: true,
      onResult: (res) async {
        final txt = res.recognizedWords.toLowerCase().trim();
        if (txt.isEmpty) return;

        _partial = txt;
        onStateChanged();

        final hit = matchFirstKeyword(txt);
        if (hit != null) {
          await _unholdAndStop();
          onCommandDetected(hit.command, hit.keyword);
        }
      },
    );
  }

  Future<void> stopPTT() async {
    await _unholdAndStop();
  }

  Future<void> _unholdAndStop() async {
    if (_holding) {
      _holding = false;
      onStateChanged();
    }
    try {
      await _stt.stop();
    } catch (_) {}
  }

  void dispose() {
    _stt.stop();
  }
}
