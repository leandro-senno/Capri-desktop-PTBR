import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// Uma tira de sprites do app original: nome do arquivo, quantidade de quadros e quadros por segundo
/// (os mesmos números de app/Capri.cs).
class Reel {
  final String name;
  final int count;
  final double fps;
  final bool loop;
  const Reel(this.name, this.count, this.fps, {this.loop = false});

  double get seconds => count / fps;

  static const idle = Reel('idle', 16, 8, loop: true);
  static const blink = Reel('blink', 4, 8);
  static const blinkGlitch = Reel('blink_glitch', 4, 8);
  static const grin = Reel('grin', 16, 8);
  static const glitch = Reel('glitch', 10, 15, loop: true);
  static const sleep = Reel('sleep', 16, 6, loop: true);
  static const wake = Reel('wake', 13, 15);
  static const dance = Reel('dance', 16, 8);
  static const arrive = Reel('arrive', 14, 15);
  static const leave = Reel('leave', 12, 15);
  static const mouth = Reel('mouth', 5, 12);

  static const all = [idle, blink, blinkGlitch, grin, glitch, sleep, wake, dance, arrive, leave, mouth];
}

/// Carrega as tiras uma vez só e guarda na memória.
class Sprites {
  static final Map<String, ui.Image> _images = {};
  static Future<void>? _loading;

  static Future<void> load() => _loading ??= _load();

  static Future<void> _load() async {
    for (final clip in Reel.all) {
      final data = await rootBundle.load('assets/sprites/${clip.name}.png');
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      _images[clip.name] = frame.image;
    }
  }

  static ui.Image? of(Reel clip) => _images[clip.name];
}

enum Mood { arriving, idle, thinking, talking, sleeping }

/// O que a Capri está fazendo. A tela muda isso e o [CapriView] desenha.
class CapriController extends ChangeNotifier {
  Reel _clip = Reel.arrive;
  double _clock = 0; // segundos dentro do clipe atual
  double _total = 0; // segundos desde que o view começou
  double _nextBlink = 4;
  double _quiet = 0; // segundos sem ninguém mexer
  bool _talking = false;
  bool _thinking = false;
  int _mouth = -1;
  double _mouthClock = 0;
  final Random _random = Random();

  /// Depois de quantos segundos parada ela dorme (0 = nunca).
  double sleepAfter = 180;

  Reel get clip => _clip;
  int get frame {
    final index = (_clock * _clip.fps).floor();
    return _clip.loop ? index % _clip.count : min(index, _clip.count - 1);
  }

  int get mouth => _mouth;
  bool get sleeping => _clip == Reel.sleep;

  Mood get mood {
    if (_clip == Reel.sleep) return Mood.sleeping;
    if (_clip == Reel.arrive) return Mood.arriving;
    if (_thinking) return Mood.thinking;
    if (_talking) return Mood.talking;
    return Mood.idle;
  }

  void _play(Reel clip) {
    _clip = clip;
    _clock = 0;
  }

  /// Alguém mexeu: acorda se estiver dormindo.
  void poke() {
    _quiet = 0;
    if (_clip == Reel.sleep) {
      _play(Reel.wake);
      notifyListeners();
    }
  }

  set thinking(bool value) {
    if (_thinking == value) return;
    _thinking = value;
    _quiet = 0;
    if (value) {
      _play(Reel.glitch);
    } else if (_clip == Reel.glitch) {
      _play(Reel.idle);
    }
    notifyListeners();
  }

  set talking(bool value) {
    if (_talking == value) return;
    _talking = value;
    _quiet = 0;
    if (value && _clip != Reel.idle) _play(Reel.idle);
    if (!value) _mouth = -1;
    notifyListeners();
  }

  void grin() {
    _quiet = 0;
    if (_talking || _thinking) return;
    _play(Reel.grin);
    notifyListeners();
  }

  void dance() {
    _quiet = 0;
    if (_talking || _thinking) return;
    _play(Reel.dance);
    notifyListeners();
  }

  /// Avança o relógio. Devolve true quando o desenho mudou.
  bool tick(double delta) {
    final beforeFrame = frame;
    final beforeClip = _clip;
    final beforeMouth = _mouth;
    _clock += delta;
    _total += delta;
    _quiet += delta;

    if (!_clip.loop && _clock >= _clip.seconds) {
      _play(_thinking ? Reel.glitch : Reel.idle);
    }

    if (_clip == Reel.idle && !_talking && !_thinking) {
      if (sleepAfter > 0 && _quiet >= sleepAfter) {
        _play(Reel.sleep);
      } else if (_total >= _nextBlink) {
        _nextBlink = _total + 3 + _random.nextDouble() * 5;
        _play(_random.nextInt(6) == 0 ? Reel.blinkGlitch : Reel.blink);
      }
    }

    if (_talking && _clip == Reel.idle) {
      _mouthClock += delta;
      if (_mouthClock >= 1 / Reel.mouth.fps) {
        _mouthClock = 0;
        // Sem o áudio para medir, a boca abre e fecha ao acaso enquanto ela fala.
        _mouth = _random.nextInt(4) == 0 ? -1 : _random.nextInt(Reel.mouth.count);
      }
    } else {
      _mouth = -1;
    }

    return frame != beforeFrame || _clip != beforeClip || _mouth != beforeMouth;
  }
}

/// Desenha a Capri animada. Os quadros têm 240 x 384, como no original.
class CapriView extends StatefulWidget {
  final CapriController controller;
  final double height;
  const CapriView({super.key, required this.controller, this.height = 320});

  @override
  State<CapriView> createState() => _CapriViewState();
}

class _CapriViewState extends State<CapriView> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    widget.controller.addListener(_changed);
    Sprites.load().then((_) {
      if (!mounted) return;
      setState(() => _ready = true);
      _ticker.start();
    });
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _onTick(Duration elapsed) {
    final delta = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    if (widget.controller.tick(delta.clamp(0, 0.25).toDouble())) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = Size(widget.height * 240 / 384, widget.height);
    if (!_ready) return SizedBox.fromSize(size: size);
    final controller = widget.controller;
    return CustomPaint(
      size: size,
      painter: _CapriPainter(
        Sprites.of(controller.clip),
        controller.clip.count,
        controller.frame,
        controller.mouth >= 0 ? Sprites.of(Reel.mouth) : null,
        controller.mouth,
      ),
    );
  }
}

class _CapriPainter extends CustomPainter {
  final ui.Image? strip;
  final int count;
  final int frame;
  final ui.Image? mouthStrip;
  final int mouth;
  _CapriPainter(this.strip, this.count, this.frame, this.mouthStrip, this.mouth);

  static final Paint _paint = Paint()..filterQuality = FilterQuality.medium;

  void _draw(Canvas canvas, Size size, ui.Image image, int cells, int cell) {
    final wide = image.width / cells;
    final source = Rect.fromLTWH(cell * wide, 0, wide, image.height.toDouble());
    canvas.drawImageRect(image, source, Offset.zero & size, _paint);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final image = strip;
    if (image == null) return;
    _draw(canvas, size, image, count, frame);
    final lips = mouthStrip;
    if (lips != null && mouth >= 0) _draw(canvas, size, lips, Reel.mouth.count, mouth);
  }

  @override
  bool shouldRepaint(_CapriPainter old) => old.strip != strip || old.frame != frame || old.mouth != mouth;
}
