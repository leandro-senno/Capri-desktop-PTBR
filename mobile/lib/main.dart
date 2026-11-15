import 'package:flutter/material.dart';

import 'chat_screen.dart';
import 'look.dart';
import 'overlay.dart';
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
  runApp(MaterialApp(debugShowCheckedModeBanner: false, color: Colors.transparent, theme: Look.theme(), home: const FloatingCapri()));
}
