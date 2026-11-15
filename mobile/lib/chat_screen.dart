import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

import 'brain.dart';
import 'look.dart';
import 'settings_screen.dart';
import 'sprite.dart';
import 'store.dart';
import 'voice.dart';

class ChatScreen extends StatefulWidget {
  final Store store;
  const ChatScreen({super.key, required this.store});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final CapriController _capri = CapriController();
  final Brain _brain = Brain();
  final Voice _voice = Voice();
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final List<Line> _lines = [];
  bool _thinking = false;
  bool _listening = false;
  bool _speaking = false;
  int _ticket = 0;

  // Onde ela está no palco: 0 = esquerda, 1 = direita.
  double _x = 0.5;
  double _stageWide = 360;
  Duration _glide = Duration.zero;
  Timer? _wander;
  Timer? _arrival;
  final Random _random = Random();

  Store get _store => widget.store;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lines.addAll(_store.lines);
    _applySettings();
    _brain.remember(_lines.map((line) => MapEntry(line.mine, line.text)));
    _voice.onStart = () {
      _speaking = true;
      _capri.talking = true;
      if (mounted) setState(() {});
    };
    _voice.onDone = () {
      _speaking = false;
      _capri.talking = false;
      if (mounted) setState(() {});
    };
    _capri.addListener(_moodChanged);
    _wander = Timer.periodic(const Duration(seconds: 9), (_) => _roam());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _greet();
      if (_store.gpuTrying) {
        // O app fechou enquanto carregava o cérebro na placa de vídeo: da próxima vez usa o processador.
        _store.localGpu = false;
        _store.setGpuTrying(false);
        _brain.gpu = false;
        _notice('A placa de vídeo travou da última vez. Troquei o cérebro para o processador.');
      }
    });
  }

  /// De vez em quando ela anda, senta ou levanta sozinha, como no PC.
  void _roam() {
    if (!mounted || !_store.wander || !_capri.calm || _capri.sleeping || _listening || _thinking || _speaking) return;
    if (MediaQuery.of(context).viewInsets.bottom > 0) return;
    final dice = _random.nextInt(100);
    if (_capri.seated) {
      if (dice < 25) _capri.stand();
      return;
    }
    if (dice < 40) {
      _walkTo(0.06 + _random.nextDouble() * 0.88);
    } else if (dice < 55) {
      _capri.sit();
    }
  }

  void _walkTo(double target) {
    final distance = (target - _x).abs() * _stageWide;
    if (distance < 24) return;
    final time = Duration(milliseconds: (distance / 90 * 1000).round());
    _capri.facingLeft = target < _x;
    _capri.walking = true;
    if (!_capri.walking) return;
    setState(() {
      _glide = time;
      _x = target;
    });
    _arrival?.cancel();
    _arrival = Timer(time, () {
      if (!mounted) return;
      _capri.walking = false;
      setState(() => _glide = Duration.zero);
    });
  }

  void _stopWalk() {
    _arrival?.cancel();
    _capri.walking = false;
    _glide = Duration.zero;
  }

  void _moodChanged() {
    if (mounted) setState(() {});
  }

  void _applySettings() {
    _brain.key = _store.key;
    _brain.model = _store.model;
    _brain.nickname = _store.nickname;
    _brain.wordiness = _store.wordiness;
    _brain.local = _store.local;
    _brain.localReady = _store.localReady;
    _brain.gpu = _store.localGpu;
    _brain.gpuGuard = _store.setGpuTrying;
    _capri.sleepAfter = _store.sleepMinutes * 60.0;
  }

  /// Cumprimento gravado do original, conforme a hora e o tempo longe.
  void _greet() {
    final now = DateTime.now();
    final last = _store.lastOpened;
    _store.touch();
    if (!_store.intro || !_store.voice) return;
    if (last != null && now.difference(last).inHours >= 48) {
      _voice.hello('miss');
    } else if (now.hour >= 22 || now.hour < 5) {
      _voice.hello('late');
    } else if (now.hour < 12 && (last == null || last.day != now.day)) {
      _voice.hello('morning');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _voice.stop();
      _voice.stopListening();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _wander?.cancel();
    _arrival?.cancel();
    _capri.removeListener(_moodChanged);
    _brain.cancel();
    _brain.device.unload();
    _voice.dispose();
    _capri.dispose();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _add(Line line) {
    setState(() => _lines.add(line));
    _store.lines = _lines;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    });
  }

  Future<void> _send([String? heard]) async {
    final said = (heard ?? _input.text).trim();
    if (said.isEmpty || _thinking) return;
    _input.clear();
    _capri.poke();
    await _voice.stop();
    _applySettings();
    _add(Line(true, said));

    if (!_brain.ready) {
      _add(const Line(false, Brain.offline, problem: true));
      return;
    }

    final ticket = ++_ticket;
    setState(() => _thinking = true);
    _capri.thinking = true;
    try {
      final reply = await _brain.ask(said);
      if (!mounted || ticket != _ticket) return;
      _capri.thinking = false;
      setState(() => _thinking = false);
      _add(Line(false, reply));
      if (_store.voice) {
        _voice.speak(reply);
      } else {
        _capri.grin();
      }
    } on BrainException catch (error) {
      if (!mounted || ticket != _ticket) return;
      _capri.thinking = false;
      setState(() => _thinking = false);
      _add(Line(false, error.message, problem: true));
    } catch (_) {
      if (!mounted || ticket != _ticket) return;
      _capri.thinking = false;
      setState(() => _thinking = false);
      _add(const Line(false, Brain.declined, problem: true));
    }
  }

  Future<void> _toggleMic() async {
    if (_listening) {
      await _voice.stopListening();
      setState(() => _listening = false);
      return;
    }
    _capri.poke();
    final started = await _voice.listen(
      onWords: (words, done) {
        if (!mounted) return;
        setState(() => _input.text = words);
        if (done && words.trim().isNotEmpty) {
          setState(() => _listening = false);
          _send(words);
        }
      },
      onStop: () {
        if (mounted) setState(() => _listening = false);
      },
    );
    if (!mounted) return;
    if (started) {
      setState(() => _listening = true);
    } else {
      _notice('Não consegui usar o microfone. Libere a permissão de microfone para a Capri nas configurações do Android.');
    }
  }

  void _notice(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text, style: const TextStyle(fontFamily: Look.mono)), backgroundColor: Look.panel));
  }

  Future<void> _float() async {
    try {
      if (await FlutterOverlayWindow.isActive()) {
        await FlutterOverlayWindow.closeOverlay();
        return;
      }
      if (!await FlutterOverlayWindow.isPermissionGranted()) {
        final granted = await FlutterOverlayWindow.requestPermission();
        if (granted != true) {
          if (mounted) _notice('Para ela flutuar, permita "Aparecer sobre outros apps" para a Capri.');
          return;
        }
      }
      await FlutterOverlayWindow.showOverlay(
        height: 300,
        width: 190,
        alignment: OverlayAlignment.centerRight,
        enableDrag: true,
        positionGravity: PositionGravity.none,
        flag: OverlayFlag.defaultFlag,
        overlayTitle: 'Capri',
        overlayContent: 'Capri está flutuando. Toque duas vezes nela para guardar.',
      );
      if (mounted) _notice('Ela está flutuando. Arraste para mover; toque duas vezes para guardar.');
    } catch (_) {
      if (mounted) _notice('Não consegui abrir a janela flutuante neste aparelho.');
    }
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => SettingsScreen(store: _store, brain: _brain)));
    if (!mounted) return;
    setState(_applySettings);
  }

  void _forget() {
    _brain.forget();
    setState(_lines.clear);
    _store.lines = _lines;
  }

  String get _status {
    if (!_brain.ready) return 'DORMENTE';
    if (_listening) return 'OUVINDO';
    if (_thinking) return _brain.local && _brain.device.onGpu == null ? 'ACORDANDO O CÉREBRO' : 'PENSANDO';
    if (_speaking) return 'FALANDO';
    if (_capri.sleeping) return 'DORMINDO';
    return 'ONLINE';
  }

  Color get _statusColor {
    if (!_brain.ready) return Look.dim;
    if (_listening) return Look.red;
    if (_thinking) return Look.yellow;
    if (_speaking) return Look.neon;
    return Look.cyan;
  }

  /// O palco: ela fica em pé na beirada da faixa de status ou senta nela, com as pernas penduradas.
  Widget _stage(double tall) {
    return LayoutBuilder(
      builder: (context, box) {
        final wide = box.maxWidth;
        _stageWide = wide;
        final perch = _capri.reel.perch;
        final high = perch ? tall * 0.84 : tall * 0.96;
        final across = high * _capri.reel.aspect;
        final strip = tall * 0.84 * 0.21; // quanto dela passa da beirada quando senta (SitY = 0.79 no original)
        final margin = tall * 0.96 * 0.625 / 2;
        final centre = margin + _x * (wide - 2 * margin);
        final left = (centre - across * (perch ? 0.45 : 0.5)).clamp(-across * 0.3, wide - across * 0.7).toDouble();
        final bottom = (perch ? strip - high * 0.21 : strip) + (_capri.dragging ? 14 : 0);
        return SizedBox(
          height: tall + strip,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: strip,
                child: Container(
                  decoration: const BoxDecoration(color: Look.panel, border: Border(top: BorderSide(color: Look.edge))),
                  alignment: _x > 0.5 ? Alignment.centerLeft : Alignment.centerRight,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Text('• $_status', style: TextStyle(color: _statusColor, fontSize: 13, letterSpacing: 3)),
                ),
              ),
              AnimatedPositioned(
                duration: _glide,
                left: left,
                bottom: bottom,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () {
                    if (_capri.sleeping) {
                      _capri.poke();
                    } else {
                      _capri.grin();
                    }
                  },
                  onDoubleTap: () {
                    _stopWalk();
                    _capri.toggleSeat();
                  },
                  onLongPress: _capri.dance,
                  onPanStart: (_) {
                    _stopWalk();
                    _capri.poke();
                    _capri.dragging = true;
                  },
                  onPanUpdate: (details) {
                    final room = wide - 2 * margin;
                    if (room <= 0) return;
                    setState(() => _x = (_x + details.delta.dx / room).clamp(0.0, 1.0).toDouble());
                  },
                  onPanEnd: (_) => _capri.dragging = false,
                  onPanCancel: () => _capri.dragging = false,
                  child: CapriView(controller: _capri, height: high),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final tall = MediaQuery.of(context).size.height;
    final keyboard = MediaQuery.of(context).viewInsets.bottom > 0;
    return Scaffold(
      appBar: AppBar(
        title: const Text('CAPRI'),
        actions: [
          IconButton(tooltip: 'Flutuar sobre outros apps', icon: const Icon(Icons.picture_in_picture_alt_outlined), onPressed: _float),
          IconButton(tooltip: 'Esquecer a conversa', icon: const Icon(Icons.delete_sweep_outlined), onPressed: _lines.isEmpty ? null : _forget),
          IconButton(tooltip: 'Configurações', icon: const Icon(Icons.memory_outlined), onPressed: _openSettings),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _stage(keyboard ? tall * 0.15 : tall * 0.30),
            Expanded(
              child: _lines.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _brain.ready
                              ? 'Fala comigo, choom.\n\nToque duas vezes nela para sentar ou levantar, segure para dançar e arraste para mover.'
                              : 'Ela ainda está sem cérebro.\nToque no chip lá em cima e monte o cérebro no celular.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Look.dim, fontSize: 15, height: 1.5),
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      itemCount: _lines.length,
                      itemBuilder: (context, index) => _Bubble(line: _lines[index]),
                    ),
            ),
            Container(
              decoration: const BoxDecoration(color: Look.panel, border: Border(top: BorderSide(color: Look.edge))),
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
              child: Row(
                children: [
                  IconButton(
                    tooltip: _listening ? 'Parar de ouvir' : 'Falar',
                    icon: Icon(_listening ? Icons.mic : Icons.mic_none, color: _listening ? Look.red : Look.cyan),
                    onPressed: _thinking ? null : _toggleMic,
                  ),
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      onTap: _capri.poke,
                      style: const TextStyle(fontFamily: Look.mono, color: Look.ink),
                      decoration: const InputDecoration(hintText: 'Diga algo para a Capri', isDense: true),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Enviar',
                    icon: const Icon(Icons.send, color: Look.cyan),
                    onPressed: _thinking ? null : () => _send(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final Line line;
  const _Bubble({required this.line});

  @override
  Widget build(BuildContext context) {
    final color = line.problem ? Look.yellow : line.mine ? Look.dim : Look.cyan;
    return Align(
      alignment: line.mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(color: Look.panel, border: Border.all(color: color.withAlpha(140)), borderRadius: BorderRadius.circular(4)),
        child: SelectableText(
          line.mine ? line.text : 'CAPRI> ${line.text}',
          style: TextStyle(color: line.mine ? Look.ink : color, fontSize: 15, height: 1.35),
        ),
      ),
    );
  }
}
