import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

import 'chat_screen.dart';
import 'look.dart';
import 'sprite.dart';
import 'store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = Store();
  await store.load();
  runApp(CapriApp(store: store));
}

class CapriApp extends StatelessWidget {
  final Store store;
  const CapriApp({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Capri',
      debugShowCheckedModeBanner: false,
      theme: Look.theme(),
      home: ChatScreen(store: store),
    );
  }
}

/// Ponto de entrada da janela flutuante (a Capri por cima dos outros apps).
/// O plugin flutter_overlay_window procura esta função pelo nome.
@pragma('vm:entry-point')
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(debugShowCheckedModeBanner: false, color: Colors.transparent, home: FloatingCapri()));
}

/// A Capri flutuante: arraste para mover, toque para ela reagir, toque duas vezes para guardar.
class FloatingCapri extends StatefulWidget {
  const FloatingCapri({super.key});

  @override
  State<FloatingCapri> createState() => _FloatingCapriState();
}

class _FloatingCapriState extends State<FloatingCapri> {
  final CapriController _capri = CapriController()..sleepAfter = 120;

  @override
  void dispose() {
    _capri.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (_capri.sleeping) {
            _capri.poke();
          } else {
            _capri.grin();
          }
        },
        onDoubleTap: () => FlutterOverlayWindow.closeOverlay(),
        onLongPress: _capri.dance,
        child: LayoutBuilder(
          builder: (context, box) => Center(child: CapriView(controller: _capri, height: box.maxHeight.isFinite ? box.maxHeight : 240)),
        ),
      ),
    );
  }
}
