import 'dart:typed_data';
import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;

class PushupState {
  final int count;
  final String stage;      // 'up' / 'down'
  final String feedback;   // texto tipo "Nice!", "Go lower!"
  final List<Offset> keypoints;
  final int imageWidth;
  final int imageHeight;

  PushupState({
    required this.count,
    required this.stage,
    required this.feedback,
    required this.keypoints,
    required this.imageWidth,
    required this.imageHeight,
  });
}

class PushupCounterService {
  Interpreter? _interpreter;
  bool _busy = false;

  int _count = 0;
  String _stage = 'up';
  String _feedback = 'Loading model...';

  // Info del modelo
  late List<int> _inputShape;   // [1, H, W, 3]
  late TensorType _inputType;   // float32 / float16 / uint8 / int8
  late int _inputHeight;
  late int _inputWidth;

  bool get isReady => _interpreter != null;
  String get debugFeedback => _feedback;

  Future<void> init() async {
    try {
      final options = InterpreterOptions()..threads = 2;

      _interpreter = await Interpreter.fromAsset(
        'assets/models/lite-model_movenet_singlepose_lightning_tflite_float16_4.tflite',
        options: options,
      );

      final inputTensor = _interpreter!.getInputTensor(0);
      _inputShape  = inputTensor.shape;     // ej: [1,192,192,3]
      _inputType   = inputTensor.type;
      _inputHeight = _inputShape[1];
      _inputWidth  = _inputShape[2];

      print('[Pushup] MoveNet cargado OK');
      print('[Pushup] inputShape = $_inputShape');
      print('[Pushup] inputType  = $_inputType');

      final outputShape = _interpreter!.getOutputTensor(0).shape;
      print('[Pushup] outputShape = $outputShape');

      _feedback = 'Ready!';
    } catch (e, st) {
      print('[Pushup] ERROR cargando MoveNet: $e');
      print(st);
      _feedback = 'Error cargando modelo: $e';
      rethrow;
    }
  }

  void dispose() {
    _interpreter?.close();
  }

  double _angle(Offset a, Offset b, Offset c) {
    final ab = math.atan2(a.dy - b.dy, a.dx - b.dx);
    final cb = math.atan2(c.dy - b.dy, c.dx - b.dx);
    var angle = (cb - ab) * 180.0 / math.pi;
    angle = angle.abs();
    if (angle > 180.0) angle = 360.0 - angle;
    return angle;
  }

  Object _buildInput(img.Image resized) {
    if (_inputType == TensorType.float32 ||
        _inputType == TensorType.float16) {
      return [
        List.generate(
          _inputHeight,
          (y) => List.generate(
            _inputWidth,
            (x) {
              final img.Pixel p = resized.getPixel(x, y);
              final r = p.r / 255.0;
              final g = p.g / 255.0;
              final b = p.b / 255.0;
              return [r, g, b];
            },
          ),
        ),
      ];
    }

    if (_inputType == TensorType.uint8 || _inputType == TensorType.int8) {
      return [
        List.generate(
          _inputHeight,
          (y) => List.generate(
            _inputWidth,
            (x) {
              final img.Pixel p = resized.getPixel(x, y);
              return [p.r, p.g, p.b];
            },
          ),
        ),
      ];
    }

    throw Exception('Tipo de tensor no soportado: $_inputType');
  }

  Future<PushupState?> processFrame(Uint8List jpeg) async {
    if (_interpreter == null) {
      // Modelo no cargado aún
      return PushupState(
        count: _count,
        stage: _stage,
        feedback: _feedback,
        keypoints: const [],
        imageWidth: 640,
        imageHeight: 480,
      );
    }

    if (_busy) return null;
    _busy = true;

    try {
      final img.Image? image = img.decodeJpg(jpeg);
      if (image == null) {
        print('[Pushup] decodeJpg devolvió null');
        return null;
      }

      final resized = img.copyResize(
        image,
        width: _inputWidth,
        height: _inputHeight,
      );

      final Object input = _buildInput(resized);

      final output =
          List.filled(1 * 1 * 17 * 3, 0.0).reshape([1, 1, 17, 3]);

      _interpreter!.run(input, output);

      final keypoints = <Offset>[];

      for (int i = 0; i < 17; i++) {
        final yNorm = output[0][0][i][0] as double;
        final xNorm = output[0][0][i][1] as double;
        final score = output[0][0][i][2] as double;

        if (score > 0.5) {
          final x = xNorm * image.width;
          final y = yNorm * image.height;
          keypoints.add(Offset(x, y));
        } else {
          keypoints.add(Offset.zero);
        }
      }

      const leftShoulder = 5;
      const leftElbow    = 7;
      const leftWrist    = 9;

      final ls = keypoints[leftShoulder];
      final le = keypoints[leftElbow];
      final lw = keypoints[leftWrist];

      if (ls != Offset.zero && le != Offset.zero && lw != Offset.zero) {
        final angle = _angle(ls, le, lw);

        if (angle > 160) {
          if (_stage == 'down') {
            _count++;
            _feedback = 'Nice!';
            print('[Pushup] Conteo = $_count');
          }
          _stage = 'up';
        } else if (angle < 90) {
          if (_stage == 'up') {
            _feedback = 'Go lower!';
          }
          _stage = 'down';
        } else {
          _feedback = 'Mantén el movimiento...';
        }
      } else {
        _feedback =
            'Asegúrate de que hombro, codo y muñeca se vean (lado de la cámara).';
      }

      return PushupState(
        count: _count,
        stage: _stage,
        feedback: _feedback,
        keypoints: keypoints,
        imageWidth: image.width,
        imageHeight: image.height,
      );
    } catch (e, st) {
      print('[Pushup] ERROR en processFrame: $e');
      print(st);
      _feedback = 'Error procesando frame: $e';

      return PushupState(
        count: _count,
        stage: _stage,
        feedback: _feedback,
        keypoints: const [],
        imageWidth: 0,
        imageHeight: 0,
      );
    } finally {
      _busy = false;
    }
  }

  void reset() {
    _count = 0;
    _stage = 'up';
    _feedback = 'Counter reset.';
  }
}
