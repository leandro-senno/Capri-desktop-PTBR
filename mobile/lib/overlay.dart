import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sprite.dart';

/// A Capri flutuando por cima dos outros apps, com as mesmas animações do app:
/// senta e levanta, fica pendurada enquanto você a segura, passeia pela tela, pisca, dança e dorme.
///
/// Gestos: toque = ela reage; dois toques = senta ou levanta; segurar e arrastar = move (pendurada);
/// segurar sem mover = dança. Para guardar, use o botão de janela dentro do app.
class FloatingCapri extends StatefulWidget {
  /// Tamanho da janela flutuante, em dp. Em pé ela ocupa a altura toda; sentada, um quadrado embaixo.
  static const double wide = 170;
  static const double tall = 250;

  const FloatingCapri({super.key});

  @override
  State<FloatingCapri> createState() => _FloatingCapriState();
}

class _FloatingCapriState extends State<FloatingCapri> {
  final CapriController _capri = CapriController()..sleepAfter = 120;
  final Random _random = Random();
  Timer? _roaming;
  Timer? _steps;
  Timer? _hold;
  Timer? _single;
  DateTime? _downAt;
  DateTime? _lastTap;
  OverlayPosition? _downPlace;
  bool _wander = true;

  @override
  void initState() {
    super.initState();
    _capri.addListener(_changed);
    _roaming = Timer.periodic(const Duration(seconds: 10), (_) => _roam());
    _readSettings();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _readSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      _wander = prefs.getBool('wander') ?? true;
      final minutes = prefs.getInt('sleep_minutes') ?? 3;
      _capri.sleepAfter = minutes * 60.0;
    } catch (_) {
      // sem as preferências, ela segue o padrão
    }
  }

  @override
  void dispose() {
    _roaming?.cancel();
    _steps?.cancel();
    _hold?.cancel();
    _single?.cancel();
    _capri.removeListener(_changed);
    _capri.dispose();
    super.dispose();
  }

  /// Largura da tela em dp (a janela flutuante só conhece o próprio tamanho).
  double get _screenWide {
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    return view.display.size.width / view.display.devicePixelRatio;
  }

  /// De vez em quando ela anda pela tela, senta ou levanta sozinha.
  void _roam() {
    if (!mounted || !_wander || !_capri.calm || _capri.sleeping || _downAt != null) return;
    final dice = _random.nextInt(100);
    if (_capri.seated) {
      if (dice < 25) _capri.stand();
      return;
    }
    if (dice < 40) {
      _walk();
    } else if (dice < 55) {
      _capri.sit();
    }
  }

  Future<void> _walk() async {
    try {
      final place = await FlutterOverlayWindow.getOverlayPosition();
      final room = _screenWide - FloatingCapri.wide;
      if (room <= 0 || !mounted || !_capri.calm) return;
      final target = _random.nextDouble() * room;
      var x = place.x.clamp(0, room).toDouble();
      final y = place.y;
      if ((target - x).abs() < 30) return;
      _capri.facingLeft = target < x;
      _capri.walking = true;
      if (!_capri.walking) return;
      _steps?.cancel();
      _steps = Timer.periodic(const Duration(milliseconds: 33), (timer) {
        final left = target - x;
        if (!mounted || !_capri.walking || left.abs() <= 3) {
          timer.cancel();
          _capri.walking = false;
          return;
        }
        x += 3 * left.sign; // 90 dp por segundo, como no app
        FlutterOverlayWindow.moveOverlay(OverlayPosition(x, y));
      });
    } catch (_) {
      _stopWalk();
    }
  }

  void _stopWalk() {
    _steps?.cancel();
    _capri.walking = false;
  }

  Future<void> _down() async {
    _downAt = DateTime.now();
    _stopWalk();
    _capri.poke();
    // Segurou: ela fica pendurada na mão, como ao arrastar no PC.
    _hold?.cancel();
    _hold = Timer(const Duration(milliseconds: 220), () => _capri.dragging = true);
    try {
      _downPlace = await FlutterOverlayWindow.getOverlayPosition();
    } catch (_) {
      _downPlace = null;
    }
  }

  Future<void> _up() async {
    final downAt = _downAt;
    _downAt = null;
    _hold?.cancel();
    if (downAt == null) return;
    final held = DateTime.now().difference(downAt);

    if (_capri.dragging) {
      _capri.dragging = false;
      var moved = true;
      try {
        final before = _downPlace;
        final after = await FlutterOverlayWindow.getOverlayPosition();
        if (before != null) moved = (after.x - before.x).abs() > 6 || (after.y - before.y).abs() > 6;
      } catch (_) {}
      if (!moved && held.inMilliseconds >= 700) _capri.dance();
      return;
    }

    // Toque rápido: espera um instante para saber se vem o segundo toque.
    final now = DateTime.now();
    final last = _lastTap;
    if (last != null && now.difference(last).inMilliseconds < 320) {
      _lastTap = null;
      _single?.cancel();
      _capri.toggleSeat();
      return;
    }
    _lastTap = now;
    _single?.cancel();
    _single = Timer(const Duration(milliseconds: 320), () {
      if (!mounted) return;
      if (_capri.sleeping) {
        _capri.poke();
      } else {
        _capri.grin();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) => _down(),
        onPointerUp: (_) => _up(),
        onPointerCancel: (_) => _up(),
        child: LayoutBuilder(
          builder: (context, box) {
            final full = box.maxHeight.isFinite ? box.maxHeight : FloatingCapri.tall;
            final across = box.maxWidth.isFinite ? box.maxWidth : FloatingCapri.wide;
            // Sentada, o quadro é quadrado: cabe na largura da janela, encostado embaixo.
            final high = _capri.reel.perch ? min(across, full) : full;
            return Align(
              alignment: Alignment.bottomCenter,
              child: CapriView(controller: _capri, height: high),
            );
          },
        ),
      ),
    );
  }
}
