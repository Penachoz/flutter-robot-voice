import 'package:flutter/material.dart';

import '../services/udp_video_service.dart';
import '../services/pushup_counter.dart';
import '../widgets/pose_painter.dart';

class WorkoutPage extends StatefulWidget {
  final UdpVideoService videoService;

  const WorkoutPage({super.key, required this.videoService});

  @override
  State<WorkoutPage> createState() => _WorkoutPageState();
}

class _WorkoutPageState extends State<WorkoutPage> {
  late final PushupCounterService _pushupService;
  PushupState? _state;
  int _frameSkip = 0;

  @override
  void initState() {
    super.initState();
    _pushupService = PushupCounterService();
    _init();
  }

  Future<void> _init() async {
    await _pushupService.init();
    _loop();
  }

  void _loop() async {
    while (mounted) {
      final jpeg = widget.videoService.lastJpeg;
      if (jpeg != null) {
        if (_frameSkip++ % 3 == 0) {
          final st = await _pushupService.processFrame(jpeg);
          if (st != null && mounted) {
            setState(() => _state = st);
          }
        }
      }
      await Future.delayed(const Duration(milliseconds: 50));
    }
  }

  @override
  void dispose() {
    _pushupService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final imgBytes = widget.videoService.lastJpeg;
    final count    = _state?.count ?? 0;
    final stage    = _state?.stage ?? '-';
    final feedback =
        _state?.feedback ?? _pushupService.debugFeedback;

    final imageWidth  = _state?.imageWidth  ?? 640;
    final imageHeight = _state?.imageHeight ?? 480;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Entrena conmigo (lagartijas)'),
      ),
      body: Column(
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: imgBytes == null
                ? const Center(child: Text('Esperando video…'))
                : FittedBox(
                    fit: BoxFit.contain,
                    child: SizedBox(
                      width: imageWidth.toDouble(),
                      height: imageHeight.toDouble(),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.memory(
                            imgBytes,
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                          ),
                          if (_state != null)
                            CustomPaint(
                              painter: PosePainter(
                                keypoints: _state!.keypoints,
                                imageWidth: imageWidth,
                                imageHeight: imageHeight,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 8),
          Text('Count', style: Theme.of(context).textTheme.titleLarge),
          Text('$count', style: const TextStyle(fontSize: 48)),
          const SizedBox(height: 8),
          Text('Stage: $stage', style: const TextStyle(fontSize: 24)),
          const SizedBox(height: 8),
          Text(feedback),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () {
              _pushupService.reset();
              setState(() => _state = null);
            },
            child: const Text('Reset'),
          ),
        ],
      ),
    );
  }
}
