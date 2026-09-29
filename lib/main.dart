import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() => runApp(const MoodClockApp());

class MoodClockApp extends StatelessWidget {
  const MoodClockApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Fold Mood Clock',
      home: MoodLightScreen(),
    );
  }
}

enum DualScreenState { checking, available, active, unavailable, unsupported }

class MoodLightScreen extends StatefulWidget {
  const MoodLightScreen({super.key});

  @override
  State<MoodLightScreen> createState() => _MoodLightScreenState();
}

class _MoodLightScreenState extends State<MoodLightScreen>
    with SingleTickerProviderStateMixin {
  static const _channel = MethodChannel('dual_screen_lab/window_area');

  late final AnimationController _animation;
  DualScreenState _dualScreenState = DualScreenState.checking;
  DateTime _now = DateTime.now();
  bool _moodMode = false;
  bool _controlsVisible = true;
  String? _message;
  Timer? _clockTimer;
  Timer? _controlsTimer;

  @override
  void initState() {
    super.initState();
    _animation = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    _channel.setMethodCallHandler(_handleNativeCall);
    _refreshStatus();
  }

  Future<void> _handleNativeCall(MethodCall call) async {
    if (call.method != 'statusChanged' || !mounted) return;
    _applyStatus(call.arguments as String?);
  }

  Future<void> _refreshStatus() async {
    try {
      final status = await _channel.invokeMethod<String>('getStatus');
      if (mounted) _applyStatus(status);
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() {
        _dualScreenState = DualScreenState.unsupported;
        _message = error.message;
      });
    }
  }

  void _applyStatus(String? status) {
    setState(() {
      _dualScreenState = switch (status) {
        'available' => DualScreenState.available,
        'active' => DualScreenState.active,
        'unavailable' => DualScreenState.unavailable,
        _ => DualScreenState.unsupported,
      };
      _message = null;
    });
  }

  Future<void> _toggleDualScreen() async {
    try {
      await _channel.invokeMethod<void>(
        _dualScreenState == DualScreenState.active ? 'stop' : 'start',
      );
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() => _message = error.message ?? '듀얼 스크린을 시작할 수 없습니다.');
    }
  }

  void _showControls() {
    _controlsTimer?.cancel();
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible && _dualScreenState == DualScreenState.active) {
      _controlsTimer = Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => _controlsVisible = false);
      });
    }
  }

  void _toggleDisplayMode() {
    _controlsTimer?.cancel();
    setState(() {
      _moodMode = !_moodMode;
      _controlsVisible = true;
    });

    if (_moodMode) {
      _controlsTimer = Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => _controlsVisible = false);
      });
    }
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _controlsTimer?.cancel();
    _channel.setMethodCallHandler(null);
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _showControls,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_moodMode)
              RepaintBoundary(
                child: AnimatedBuilder(
                  animation: _animation,
                  builder: (context, child) =>
                      CustomPaint(painter: _MoodPainter(_animation.value)),
                ),
              )
            else
              _ClockFace(now: _now),
            IgnorePointer(
              ignoring: !_controlsVisible,
              child: AnimatedOpacity(
                opacity: _controlsVisible ? 1 : 0,
                duration: const Duration(milliseconds: 450),
                child: SafeArea(
                  child: _ControlsOverlay(
                    state: _dualScreenState,
                    moodMode: _moodMode,
                    message: _message,
                    onModePressed: _toggleDisplayMode,
                    onPressed: _toggleDualScreen,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ControlsOverlay extends StatelessWidget {
  const _ControlsOverlay({
    required this.state,
    required this.moodMode,
    required this.message,
    required this.onModePressed,
    required this.onPressed,
  });

  final DualScreenState state;
  final bool moodMode;
  final String? message;
  final VoidCallback onModePressed;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final canStart =
        state == DualScreenState.available || state == DualScreenState.active;
    final label = switch (state) {
      DualScreenState.checking => '듀얼 스크린 확인 중…',
      DualScreenState.available => '듀얼 스크린 시작',
      DualScreenState.active => '듀얼 스크린 종료',
      DualScreenState.unavailable => '폴드를 펼치거나 /\\ 모양으로 세워주세요',
      DualScreenState.unsupported => '이 기기는 듀얼 스크린을 지원하지 않아요',
    };

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Spacer(),
          DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.26),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    state == DualScreenState.active
                        ? '커버에는 시계가 표시되고 있어요'
                        : moodMode
                        ? '내부 화면 · 무드 라이트'
                        : '내부 화면 · 시계',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    onPressed: onModePressed,
                    icon: Icon(
                      moodMode
                          ? Icons.schedule_rounded
                          : Icons.light_mode_rounded,
                    ),
                    label: Text(moodMode ? '시계 모드' : '무드등 모드'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.88),
                      foregroundColor: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.tonalIcon(
                    onPressed: canStart ? onPressed : null,
                    icon: Icon(
                      state == DualScreenState.active
                          ? Icons.close_fullscreen_rounded
                          : Icons.splitscreen_rounded,
                    ),
                    label: Text(label),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.88),
                      foregroundColor: Colors.black87,
                      disabledBackgroundColor: Colors.black.withValues(
                        alpha: 0.24,
                      ),
                      disabledForegroundColor: Colors.white70,
                    ),
                  ),
                  if (message != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      message!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ClockFace extends StatelessWidget {
  const _ClockFace({required this.now});

  final DateTime now;

  static const _weekdays = ['월요일', '화요일', '수요일', '목요일', '금요일', '토요일', '일요일'];

  String _twoDigits(int value) => value.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final time =
        '${_twoDigits(now.hour)}:${_twoDigits(now.minute)}:'
        '${_twoDigits(now.second)}';
    final date =
        '${now.year}년 ${now.month}월 ${now.day}일 '
        '${_weekdays[now.weekday - 1]}';

    return ColoredBox(
      color: Colors.black,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 28, 28, 170),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    time,
                    maxLines: 1,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 112,
                      height: 1,
                      fontWeight: FontWeight.w200,
                      fontFeatures: [FontFeature.tabularFigures()],
                      letterSpacing: 2,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  date,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 18,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MoodPainter extends CustomPainter {
  const _MoodPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final phase = progress * math.pi * 2;
    final hue = progress * 360;
    final pulse = (math.sin(phase * 2 - math.pi / 2) + 1) / 2;
    final brightness = 0.55 + pulse * 0.45;
    final color = HSVColor.fromAHSV(1, hue % 360, 0.72, brightness).toColor();

    canvas.drawRect(Offset.zero & size, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _MoodPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
