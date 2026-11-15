import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// Uma tira de sprites do app original: nome do arquivo, quantidade de quadros e quadros por segundo
/// (os mesmos números de app/Capri.cs). As tiras "perch" (sentada) têm quadros de 384 px; as outras, 240 px.
class Reel {
  final String name;
  final int count;
  final double fps;
  final bool loop;
  final bool perch;
  const Reel(this.name, this.count, this.fps, {this.loop = false, this.perch = false});

  double get seconds => count / fps;

  /// Largura do quadro em relação à altura (384 px).
  double get aspect => (perch ? 384 : 240) / 384;

  static const idle = Reel('idle', 16, 8, loop: true);
  static const blink = Reel('blink', 4, 8);
  static const blinkGlitch = Reel('blink_glitch', 4, 8);
  static const grin = Reel('grin', 16, 8);
  static const glitch = Reel('glitch', 10, 15, loop: true);
  static const dangle = Reel('dangle', 24, 10, loop: true);
  static const sleep = Reel('sleep', 16, 6, loop: true);
  static const wake = Reel('wake', 13, 15);
  static const walk = Reel('walk', 12, 12, loop: true);
  static const dance = Reel('dance', 16, 8);
  static const arrive = Reel('arrive', 14, 15);
  static const leave = Reel('leave', 12, 15);
  static const mouth = Reel('mouth', 5, 12);

  static const perched = Reel('perch', 16, 8, loop: true, perch: true);
  static const perchBlink = Reel('perch_blink', 4, 8, perch: true);
  static const perchBlinkGlitch = Reel('perch_blink_glitch', 4, 8, perch: true);
  static const perchGlitch = Reel('perch_glitch', 10, 15, loop: true, perch: true);
  static const perchDance = Reel('perch_dance', 16, 8, perch: true);
  static const perchArrive = Reel('perch_arrive', 14, 15, perch: true);
  static const perchLeave = Reel('perch_leave', 12, 15, perch: true);

  /// As que precisam estar prontas antes de ela aparecer.
  static const first = [arrive, idle, blink, mouth];

  static const rest = [
    blinkGlitch, grin, glitch, dangle, sleep, wake, walk, dance, leave,
    perched, perchBlink, perchBlinkGlitch, perchGlitch, perchDance, perchArrive, perchLeave,
  ];
}

/// Carrega as tiras uma vez só e guarda na memória.
class Sprites {
  static final Map<String, ui.Image> _images = {};
  static Future<void>? _loading;

  /// Termina quando as primeiras tiras estão prontas; as outras continuam carregando ao fundo.
  static Future<void> load() => _loading ??= _load();

  static Future<void> _one(Reel reel) async {
    final data = await rootBundle.load('assets/sprites/${reel.name}.png');
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    _images[reel.name] = frame.image;
  }

  static Future<void> _others() async {
    for (final reel in Reel.rest) {
      try {
        await _one(reel);
      } catch (_) {
        // uma tira que falhar só deixa de aparecer
      }
    }
  }

  static Future<void> _load() async {
    for (final reel in Reel.first) {
      await _one(reel);
    }
    _others();
  }

  static ui.Image? of(Reel reel) => _images[reel.name];
  static bool has(Reel reel) => _images.containsKey(reel.name);
}

/// O que a Capri está fazendo. A tela muda isso e o [CapriView] desenha.
class CapriController extends ChangeNotifier {
  Reel _reel = Reel.arrive;
  final List<Reel> _queue = [];
  double _clock = 0; // segundos dentro da tira atual
  double _total = 0; // segundos desde o começo
  double _nextBlink = 4;
  double _quiet = 0; // segundos sem ninguém mexer
  bool _seated = false;
  bool _dragging = false;
  bool _walking = false;
  bool _talking = false;
  bool _thinking = false;
  int _mouth = -1;
  double _mouthClock = 0;
  double _talkClock = 0;
  List<int>? _shapes;
  final Random _random = Random();

  /// Depois de quantos segundos parada ela dorme (0 = nunca).
  double sleepAfter = 180;

  /// Virada para a esquerda (quando anda para lá).
  bool facingLeft = false;

  Reel get reel => _reel;
  int get frame {
    final index = (_clock * _reel.fps).floor();
    return _reel.loop ? index % _reel.count : min(index, _reel.count - 1);
  }

  int get mouth => _mouth;
  bool get sleeping => _reel == Reel.sleep;
  bool get seated => _seated;
  bool get dragging => _dragging;
  bool get walking => _walking;

  /// Livre para passear ou mudar de pose sozinha.
  bool get calm => !_dragging && !_walking && !_talking && !_thinking && _queue.isEmpty && (_reel == Reel.idle || _reel == Reel.perched);

  /// A tira em que ela fica parada no estado atual.
  Reel get _base {
    if (_dragging) return Reel.dangle;
    if (_walking) return Reel.walk;
    if (_thinking) return _seated ? Reel.perchGlitch : Reel.glitch;
    return _seated ? Reel.perched : Reel.idle;
  }

  void _play(Reel reel) {
    // Tira ainda carregando: pula para a pose parada em vez de sumir.
    if (Sprites.has(reel) || !Sprites.has(_base)) {
      _reel = reel;
    } else {
      _queue.clear();
      _reel = _base;
    }
    _clock = 0;
  }

  void _refresh() {
    if (_reel.loop) _play(_base);
  }

  /// Alguém mexeu: acorda se estiver dormindo.
  void poke() {
    _quiet = 0;
    if (_reel == Reel.sleep) {
      _play(Reel.wake);
      notifyListeners();
    }
  }

  set thinking(bool value) {
    if (_thinking == value) return;
    _thinking = value;
    _quiet = 0;
    if (_reel == Reel.sleep) {
      _play(Reel.wake);
    } else {
      _refresh();
    }
    notifyListeners();
  }

  set talking(bool value) {
    if (_talking == value) return;
    _talking = value;
    _quiet = 0;
    _talkClock = 0;
    if (!value) {
      _mouth = -1;
      _shapes = null;
    }
    if (_reel == Reel.sleep) _play(Reel.wake);
    notifyListeners();
  }

  /// As formas da boca medidas no áudio (12 por segundo), para ela falar em sincronia com a voz.
  void lipSync(List<int> shapes) {
    _shapes = shapes.isEmpty ? null : shapes;
    _talkClock = 0;
  }

  set dragging(bool value) {
    if (_dragging == value) return;
    _dragging = value;
    _quiet = 0;
    _queue.clear();
    if (value) {
      _seated = false;
      _walking = false;
    }
    _play(_base);
    notifyListeners();
  }

  set walking(bool value) {
    if (_walking == value || (value && (_seated || _dragging))) return;
    _walking = value;
    _refresh();
    notifyListeners();
  }

  /// Senta na beirada (como nas janelas do PC) ou levanta.
  void sit() {
    if (_seated || _dragging || _walking) return;
    _quiet = 0;
    _seated = true;
    _queue
      ..clear()
      ..add(Reel.perchArrive);
    _play(Reel.leave);
    notifyListeners();
  }

  void stand() {
    if (!_seated || _dragging) return;
    _quiet = 0;
    _seated = false;
    _queue
      ..clear()
      ..add(Reel.arrive);
    _play(Reel.perchLeave);
    notifyListeners();
  }

  void toggleSeat() => _seated ? stand() : sit();

  void grin() {
    _quiet = 0;
    if (!calm) return;
    _play(_seated ? Reel.perchBlinkGlitch : Reel.grin);
    notifyListeners();
  }

  void dance() {
    _quiet = 0;
    if (!calm) return;
    _play(_seated ? Reel.perchDance : Reel.dance);
    notifyListeners();
  }

  /// Avança o relógio. Devolve true quando o desenho mudou.
  bool tick(double delta) {
    final beforeFrame = frame;
    final beforeReel = _reel;
    final beforeMouth = _mouth;
    _clock += delta;
    _total += delta;
    _quiet += delta;

    if (!_reel.loop && _clock >= _reel.seconds) {
      _play(_queue.isNotEmpty ? _queue.removeAt(0) : _base);
    }

    if (calm) {
      if (!_seated && sleepAfter > 0 && _quiet >= sleepAfter) {
        _play(Reel.sleep);
      } else if (_total >= _nextBlink) {
        _nextBlink = _total + 3 + _random.nextDouble() * 5;
        final odd = _random.nextInt(6) == 0;
        if (_seated) {
          _play(odd ? Reel.perchBlinkGlitch : Reel.perchBlink);
        } else {
          _play(odd ? Reel.blinkGlitch : Reel.blink);
        }
      }
    }

    if (_talking) _talkClock += delta;
    final shapes = _shapes;
    if (_talking && _reel == Reel.idle && shapes != null) {
      final index = (_talkClock * Reel.mouth.fps).floor();
      _mouth = index < shapes.length ? shapes[index].clamp(-1, Reel.mouth.count - 1).toInt() : -1;
    } else if (_talking && _reel == Reel.idle) {
      _mouthClock += delta;
      if (_mouthClock >= 1 / Reel.mouth.fps) {
        _mouthClock = 0;
        // Sem o áudio para medir, a boca abre e fecha ao acaso enquanto ela fala.
        _mouth = _random.nextInt(4) == 0 ? -1 : _random.nextInt(Reel.mouth.count);
      }
    } else {
      _mouth = -1;
    }

    // Quem monta a tela em volta dela (palco, janela flutuante) precisa saber quando a pose muda.
    if (_reel != beforeReel) notifyListeners();
    return frame != beforeFrame || _reel != beforeReel || _mouth != beforeMouth;
  }
}

/// Desenha a Capri animada. [height] é a altura do quadro; a largura segue a tira atual.
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
    final controller = widget.controller;
    final size = Size(widget.height * controller.reel.aspect, widget.height);
    if (!_ready) return SizedBox.fromSize(size: size);
    final paint = CustomPaint(
      size: size,
      painter: _CapriPainter(
        Sprites.of(controller.reel),
        controller.reel.count,
        controller.frame,
        controller.mouth >= 0 ? Sprites.of(Reel.mouth) : null,
        controller.mouth,
      ),
    );
    if (!controller.facingLeft) return paint;
    return Transform.flip(flipX: true, child: paint);
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
