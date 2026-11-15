import 'dart:isolate';
import 'dart:ui';

/// Fio entre o app e a janela flutuante. Cada um roda no seu próprio isolado; os dois se acham por nome.
///
/// Da janela para o app: {type: 'ask', text}.
/// Do app para a janela: {type: 'thinking'}, {type: 'reply', text}, {type: 'talking', on}, {type: 'shapes', shapes}.
class Link {
  static const String app = 'capri_app';
  static const String floating = 'capri_floating';

  /// Começa a receber mensagens com esse nome. Feche a porta devolvida ao terminar.
  static ReceivePort listen(String name, void Function(Map<dynamic, dynamic> message) onMessage) {
    final port = ReceivePort();
    IsolateNameServer.removePortNameMapping(name);
    IsolateNameServer.registerPortWithName(port.sendPort, name);
    port.listen((message) {
      if (message is Map) onMessage(message);
    });
    return port;
  }

  static void close(String name, ReceivePort? port) {
    IsolateNameServer.removePortNameMapping(name);
    port?.close();
  }

  /// Devolve false quando o outro lado não está aberto.
  static bool send(String name, Map<String, Object?> message) {
    final port = IsolateNameServer.lookupPortByName(name);
    if (port == null) return false;
    port.send(message);
    return true;
  }
}
