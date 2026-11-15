import 'dart:async';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'link.dart';
import 'look.dart';
import 'sprite.dart';

/// A Capri flutuando por cima dos outros apps, com as mesmas animações do app:
/// senta e levanta, fica pendurada enquanto você a segura, passeia pela tela, pisca, dança e dorme.
///
/// Gestos: toque = abre ou fecha a conversa; dois toques = senta ou levanta; segurar e arrastar = move
/// (pendurada); segurar sem mover = dança. Para guardar, use o botão de janela dentro do app.
///
/// A conversa daqui é respondida pelo app (é lá que ficam o cérebro e a voz), pelo fio de [Link].
class FloatingCapri extends StatefulWidget {
  /// Tamanho da janela flutuante, em dp. Em pé ela ocupa a altura toda; sentada, um quadrado embaixo.
  static const double wide = 170;
  static const double tall = 250;

  /// Com a conversa aberta a janela cresce: mais larga e com este espaço extra em cima dela.
  static const double chatWide = 300;
  static const double chatExtra = 190;

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

  // Conversa pela janela flutuante.
  final TextEditingController _input = TextEditingController();
  ReceivePort? _port;
  Timer? _ack;
  bool _open = false;
  bool _waiting = false;
  String _reply = 'Fala comigo, choom.';
  static const String _asleep = 'Abra o app da Capri uma vez e deixe ele aberto ao fundo: é lá que eu penso.';

  @override
  void initState() {
    super.initState();
    _capri.addListener(_changed);
    _roaming = Timer.periodic(const Duration(seconds: 10), (_) => _roam());
    _port = Link.listen(Link.floating, _heard);
    _readSettings();
  }

  /// Mensagens do app: ela está pensando, respondeu, começou ou parou de falar.
  void _heard(Map<dynamic, dynamic> message) {
    if (!mounted) return;
    switch (message['type']) {
      case 'thinking':
        _ack?.cancel();
        _capri.thinking = true;
        setState(() => _waiting = true);
      case 'reply':
        _ack?.cancel();
        _capri.thinking = false;
        final text = message['text'];
        setState(() {
          _waiting = false;
          if (text is String) _reply = text;
        });
        if (!_open) _toggleChat();
      case 'talking':
        _capri.talking = message['on'] == true;
      case 'shapes':
        final shapes = message['shapes'];
        if (shapes is List) _capri.lipSync(shapes.whereType<int>().toList());
    }
  }

  void _ask() {
    final text = _input.text.trim();
    if (text.isEmpty || _waiting) return;
    _input.clear();
    _capri.poke();
    if (!Link.send(Link.app, {'type': 'ask', 'text': text})) {
      setState(() => _reply = _asleep);
      return;
    }
    setState(() => _waiting = true);
    // Se o app não avisar que começou a pensar, é porque foi fechado.
    _ack?.cancel();
    _ack = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      _capri.thinking = false;
      setState(() {
        _waiting = false;
        _reply = _asleep;
      });
    });
  }

  /// Abre ou fecha a conversa: a janela cresce para caber o balão e o campo de texto, e passa a aceitar teclado.
  Future<void> _toggleChat() async {
    final open = !_open;
    _stopWalk();
    try {
      final place = await FlutterOverlayWindow.getOverlayPosition();
      if (open) {
        final x = place.x.clamp(0, max(0.0, _screenWide - FloatingCapri.chatWide)).toDouble();
        final y = max(0.0, place.y - FloatingCapri.chatExtra);
        await FlutterOverlayWindow.moveOverlay(OverlayPosition(x, y));
        await FlutterOverlayWindow.resizeOverlay(FloatingCapri.chatWide.round(), (FloatingCapri.tall + FloatingCapri.chatExtra).round(), true);
        await FlutterOverlayWindow.updateFlag(OverlayFlag.focusPointer);
      } else {
        await FlutterOverlayWindow.updateFlag(OverlayFlag.defaultFlag);
        await FlutterOverlayWindow.resizeOverlay(FloatingCapri.wide.round(), FloatingCapri.tall.round(), true);
        await FlutterOverlayWindow.moveOverlay(OverlayPosition(place.x, place.y + FloatingCapri.chatExtra));
      }
    } catch (_) {
      // se a janela não puder crescer neste aparelho, a conversa abre no espaço que houver
    }
    if (mounted) setState(() => _open = open);
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
    _ack?.cancel();
    Link.close(Link.floating, _port);
    _input.dispose();
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
    if (!mounted || !_wander || _open || !_capri.calm || _capri.sleeping || _downAt != null) return;
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
        _toggleChat();
      }
    });
  }

  Widget _chat() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
      child: Column(
        children: [
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(color: Look.panel, border: Border.all(color: Look.cyan.withAlpha(160)), borderRadius: BorderRadius.circular(4)),
              child: SingleChildScrollView(
                child: Text(
                  _waiting ? 'CAPRI> ...' : 'CAPRI> $_reply',
                  style: const TextStyle(fontFamily: Look.mono, color: Look.cyan, fontSize: 14, height: 1.3),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 44,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _ask(),
                    style: const TextStyle(fontFamily: Look.mono, color: Look.ink, fontSize: 14),
                    decoration: const InputDecoration(hintText: 'Diga algo', isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10)),
                  ),
                ),
                IconButton(tooltip: 'Enviar', icon: const Icon(Icons.send, color: Look.cyan, size: 20), onPressed: _waiting ? null : _ask),
                IconButton(tooltip: 'Fechar a conversa', icon: const Icon(Icons.close, color: Look.dim, size: 20), onPressed: _toggleChat),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Só a área dela responde aos gestos; o balão e o campo de texto ficam livres para tocar e digitar.
    final capri = SizedBox(
      width: FloatingCapri.wide,
      height: FloatingCapri.tall,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) => _down(),
        onPointerUp: (_) => _up(),
        onPointerCancel: (_) => _up(),
        child: Align(
          alignment: Alignment.bottomCenter,
          // Sentada, o quadro é quadrado: cabe na largura da janela, encostado embaixo.
          child: CapriView(controller: _capri, height: _capri.reel.perch ? FloatingCapri.wide : FloatingCapri.tall),
        ),
      ),
    );
    return Material(
      color: Colors.transparent,
      child: _open
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _chat()),
                capri,
              ],
            )
          : Align(alignment: Alignment.bottomLeft, child: capri),
    );
  }
}
