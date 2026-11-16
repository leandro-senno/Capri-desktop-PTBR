import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'local_brain.dart';
import 'persona.dart';

/// Erro que já vem numa frase pronta para mostrar na conversa.
class BrainException implements Exception {
  final String message;
  BrainException(this.message);
  @override
  String toString() => message;
}

/// O cérebro por chave, portado de app/Brain.cs: a chave diz qual é o provedor.
class Brain {
  static const String nvidia = 'https://integrate.api.nvidia.com';
  static const String openAi = 'https://api.openai.com';
  static const String anthropic = 'https://api.anthropic.com';
  static const String deepSeek = 'https://api.deepseek.com';

  /// Modelos da NVIDIA que o app original tenta primeiro, na ordem.
  static const List<String> nvidiaPicks = [
    'nvidia/nemotron-3.5-super-vl-120b-a12b',
    'nvidia/nemotron-3.5-bolt-e4b',
    'openai/gpt-oss-20b',
    'meta/llama-3.2-11b-vision-instruct',
  ];

  static const String offline =
      'Meu cérebro está offline. Toque no chip lá em cima e monte o cérebro no celular, ou conecte uma chave grátis da NVIDIA.';
  static const String declined = '[SIGNAL CORRUPTED] Perdi essa na estática. Me pergunta outra coisa?';

  String? key;
  String? model;
  String? nickname;
  int wordiness = 0;

  /// Quantas trocas ela lembra (no original: Recall = 8).
  int recall = 8;

  /// true = o cérebro roda no próprio celular; false = cérebro por chave.
  bool local = true;

  /// O modelo local já foi baixado.
  bool localReady = false;

  /// Tentar a placa de vídeo do celular (mais rápido) antes do processador.
  bool gpu = true;

  /// Avisado antes (true) e depois (false) de carregar o modelo na placa de vídeo, para o app
  /// lembrar da tentativa se o aparelho travar no meio.
  Future<void> Function(bool trying)? gpuGuard;

  final LocalBrain device = LocalBrain();

  final List<Map<String, String>> _history = [];
  http.Client? _active;

  static String? kindOf(String? key) {
    if (key == null || key.isEmpty) return null;
    if (key.startsWith('sk-ant-')) return 'anthropic';
    if (key.startsWith('nvapi-')) return 'nvidia';
    if (RegExp(r'^sk-[0-9a-f]{32}$').hasMatch(key)) return 'deepseek';
    return key.startsWith('sk-') ? 'openai' : null;
  }

  String? get kind => kindOf(key);
  bool get ready => local ? localReady : kind != null && (model ?? '').isNotEmpty;

  static String companyOf(String? kind) {
    switch (kind) {
      case 'anthropic':
        return 'Anthropic';
      case 'deepseek':
        return 'DeepSeek';
      case 'nvidia':
        return 'NVIDIA';
      case 'openai':
        return 'OpenAI';
      default:
        return '';
    }
  }

  static String _base(String kind) {
    switch (kind) {
      case 'anthropic':
        return anthropic;
      case 'deepseek':
        return deepSeek;
      case 'nvidia':
        return nvidia;
      default:
        return openAi;
    }
  }

  static Map<String, String> _headers(String kind, String key) {
    if (kind == 'anthropic') {
      return {'x-api-key': key, 'anthropic-version': '2023-06-01', 'content-type': 'application/json'};
    }
    return {'Authorization': 'Bearer $key', 'Content-Type': 'application/json', 'Accept': 'application/json'};
  }

  void forget() => _history.clear();

  /// Recoloca a conversa salva na memória dela.
  void remember(Iterable<MapEntry<bool, String>> turns) {
    _history.clear();
    for (final turn in turns) {
      _history.add({'role': turn.key ? 'user' : 'assistant', 'content': turn.value});
    }
    _trim();
  }

  void _trim() {
    while (_history.length > recall * 2) {
      _history.removeAt(0);
    }
    // A conversa enviada sempre começa por uma fala da pessoa.
    while (_history.isNotEmpty && _history.first['role'] != 'user') {
      _history.removeAt(0);
    }
  }

  void cancel() {
    _active?.close();
    _active = null;
  }

  static String _explain(int status, String kind) {
    if (status == 401 || status == 403) return 'Essa chave não foi aceita pela ${companyOf(kind)}. Confira a chave nas configurações.';
    if (status == 404 || status == 400) return 'Esse modelo não está disponível na sua chave. Escolha outro nas configurações.';
    if (status == 429) return 'Pedidos demais. Espere um minuto e tente de novo.';
    if (status >= 500) return 'Os servidores da ${companyOf(kind)} falharam. Tente de novo ou escolha outro modelo.';
    return 'A ${companyOf(kind)} respondeu com o erro $status.';
  }

  /// Lista os modelos que a chave pode usar.
  static Future<List<String>> listModels(String key) async {
    final kind = kindOf(key);
    if (kind == null) throw BrainException('Essa chave não parece ser da NVIDIA, OpenAI, Anthropic ou DeepSeek.');
    final http.Response response;
    try {
      response = await http
          .get(Uri.parse('${_base(kind)}/v1/models${kind == 'anthropic' ? '?limit=100' : ''}'), headers: _headers(kind, key))
          .timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw BrainException('A ${companyOf(kind)} demorou demais para responder.');
    } on http.ClientException {
      throw BrainException('Sem conexão com a ${companyOf(kind)}. Confira a internet.');
    }
    if (response.statusCode != 200) throw BrainException(_explain(response.statusCode, kind));
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    final data = decoded is Map ? decoded['data'] : null;
    final ids = <String>[];
    if (data is List) {
      for (final item in data) {
        if (item is Map && item['id'] is String) ids.add(item['id'] as String);
      }
    }
    if (kind == 'openai') {
      ids.removeWhere((id) => !(id.startsWith('gpt-') || id.startsWith('o')) || id.contains('audio') || id.contains('image') || id.contains('realtime') || id.contains('tts') || id.contains('transcribe'));
    }
    ids.sort();
    return ids;
  }

  /// Escolhe o modelo inicial, como o original faz.
  static String? pickModel(String kind, List<String> models) {
    if (kind == 'nvidia') {
      for (final pick in nvidiaPicks) {
        if (models.contains(pick)) return pick;
      }
      return nvidiaPicks.first;
    }
    if (models.isEmpty) return null;
    if (kind == 'anthropic') {
      for (final family in ['haiku', 'sonnet']) {
        final found = models.where((id) => id.contains(family)).toList();
        if (found.isNotEmpty) return found.last;
      }
      return models.first;
    }
    if (kind == 'deepseek') return models.contains('deepseek-flash') ? 'deepseek-flash' : models.first;
    for (final id in models) {
      if (id.startsWith('gpt-') && id.endsWith('-mini')) return id;
    }
    return models.first;
  }

  static String _clean(String text) {
    var reply = text.replaceAll(RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false), '');
    final open = reply.toLowerCase().lastIndexOf('</think>');
    if (open >= 0) reply = reply.substring(open + 8);
    reply = reply.replaceAll('*', '');
    // O modelo às vezes repete o carimbo do momento ou começa a fala com o próprio nome: isso sai.
    reply = reply.replaceAll(RegExp(r'\[(?:Right now|Background)[^\]]*\]', caseSensitive: false), '');
    reply = reply.trim();
    final label = RegExp(r'^(?:capri|you|assistant|model)\s*[:>\-–—]+\s*', caseSensitive: false);
    while (label.hasMatch(reply)) {
      reply = reply.replaceFirst(label, '').trim();
    }
    // Se ele inventar a fala seguinte da pessoa, corta ali.
    final next = RegExp(r'\n\s*(?:they|user|usu[aá]rio)\s*:', caseSensitive: false).firstMatch(reply);
    if (next != null) reply = reply.substring(0, next.start).trim();
    return reply;
  }

  /// Manda a fala da pessoa e devolve a resposta da Capri.
  /// [note] é uma instrução extra só para esta resposta (por exemplo, o resultado de algo que ela acabou de fazer).
  /// Com [hidden], a fala não é da pessoa (é um empurrão do app) e não entra na memória da conversa.
  Future<String> ask(String said, {String? note, bool hidden = false}) => local ? _askLocal(said, note, hidden) : _askCloud(said, note, hidden);

  /// O que ela diz quando resolve puxar conversa sozinha.
  static const String nudge =
      "(They've been quiet for a while. Say one short line to pull them back into chatting: tease them, ask about their day or what they're doing. Don't mention this note.)";

  /// O que a pessoa pediu para ela lembrar. Vai no prompt de sistema.
  List<String> facts = const [];

  /// O momento (dia, hora, bateria, clima). Só é preenchido quando a pessoa pergunta por isso.
  String? moment;

  String _system(String? note) {
    final buffer = StringBuffer(character(nickname: nickname, wordiness: wordiness))
      ..write('\nNever start a reply with your name or any label, and never mention the battery, the time, the date or the weather unless they ask about it.');
    if (facts.isNotEmpty) {
      buffer.write('\nThings they asked you to remember about them (your long-term memory):');
      for (final fact in facts) {
        buffer.write('\n- $fact');
      }
    }
    if (note != null) buffer.write('\n$note');
    return buffer.toString();
  }

  String _stamp(String said) => (moment ?? '').isEmpty ? said : '[Background, because they are asking about it: $moment]\n$said';

  /// A conversa até aqui, em texto. O modelo local não guarda nada entre uma fala e outra:
  /// cada resposta recebe a conversa recente de novo, e é isso que faz ela lembrar do que acabou de dizer.
  String _transcript() {
    if (_history.isEmpty) return '';
    final lines = _history.map((turn) => '${turn['role'] == 'user' ? 'They said' : 'You said'}: ${turn['content']}').join('\n');
    return '\n\nThe conversation so far, oldest first:\n$lines\n\nTheir next message continues this conversation. If you just asked or offered something, their message is the answer to it. Reply with your words only.';
  }

  Future<String> _local(String system, String said, int limit) async {
    if (!localReady) throw BrainException(offline);
    final guarded = gpu && device.onGpu == null;
    try {
      if (guarded) await gpuGuard?.call(true);
      return await device.ask(system: system, said: said, limit: limit, gpu: gpu);
    } on TimeoutException {
      throw BrainException('Demorei demais pensando. Tente de novo, ou use uma chave nas configurações.');
    } catch (error) {
      if (error is BrainException) rethrow;
      await device.unload();
      throw BrainException('Meu cérebro local falhou ao carregar. Feche outros apps e tente de novo, ou troque para o processador nas configurações.');
    } finally {
      if (guarded) await gpuGuard?.call(false);
    }
  }

  Future<String> _askLocal(String said, String? note, bool hidden) async {
    final limit = [160, 300, 600][wordiness.clamp(0, 2).toInt()];
    final reply = _clean(await _local(_system(note) + _transcript(), _stamp(said), limit));
    if (reply.isEmpty) return declined;
    if (!hidden) _history.add({'role': 'user', 'content': said});
    _history.add({'role': 'assistant', 'content': reply});
    _trim();
    return reply;
  }

  /// Como o cérebro transforma um pedido em frase livre em ações no celular.
  static const String _router =
      "You turn a request written in Brazilian Portuguese into actions for an assistant that controls the user's Android phone. "
      'Reply ONLY with action lines, one per line, at most 3 lines, with no other text. The actions are:\n'
      'open <app name>\ntap <exact text of something on screen>\ntype <text>\nscroll down\nscroll up\nback\nhome\nrecents\n'
      'play <song or artist>\npause\nresume\nnext\nprevious\nvolume up\nvolume down\nsearch <what to look up on the web>\nread screen\nnone\n'
      'Rules: "scroll down" shows what comes next (the next video, post or part of the page). If they name an app to act in, put "open <app>" first. '
      'For "tap", prefer a text from the list of things on screen. Use "read screen" when they ask what is on the screen. '
      'Reply "none" when the message is conversation, a question for you, or you are not sure.';

  /// Pergunta ao cérebro quais ações o pedido quer. Devolve as linhas de ação (vazio = é só conversa).
  Future<List<String>> route(String said, List<String> onScreen) async {
    if (!ready) return const [];
    final system = onScreen.isEmpty ? _router : '$_router\nThings on screen now: ${onScreen.join('; ')}';
    String answer;
    try {
      answer = local ? await _local(system, said, 60) : await _once(system, said, 80);
    } catch (_) {
      return const [];
    }
    final known = RegExp(r'^(?:open|tap|type|scroll|back|home|recents|play|pause|resume|next|previous|volume|search|read)\b', caseSensitive: false);
    final actions = <String>[];
    for (final raw in _clean(answer).split('\n')) {
      final line = raw.replaceFirst(RegExp(r'^[\s\-\d.)`]+'), '').replaceAll('`', '').trim();
      if (line.toLowerCase() == 'none') return const [];
      if (known.hasMatch(line) && actions.length < 3) actions.add(line);
    }
    return actions;
  }

  /// Uma pergunta avulsa ao cérebro por chave, sem persona nem memória.
  Future<String> _once(String system, String said, int limit) async {
    final kind = this.kind;
    final key = this.key;
    final model = this.model;
    if (kind == null || key == null || model == null) return '';
    final Uri address;
    final Map<String, Object?> body;
    final turns = [
      {'role': 'user', 'content': said},
    ];
    if (kind == 'anthropic') {
      address = Uri.parse('$anthropic/v1/messages');
      body = {'model': model, 'max_tokens': limit, 'system': system, 'messages': turns};
    } else {
      address = Uri.parse('${_base(kind)}/v1/chat/completions');
      body = {
        'model': model,
        'messages': [
          {'role': 'system', 'content': system},
          ...turns,
        ],
        'stream': false,
      };
      if (kind != 'openai') {
        body['max_tokens'] = limit;
        body['temperature'] = 0;
      }
    }
    final response = await http.post(address, headers: _headers(kind, key), body: jsonEncode(body)).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) return '';
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (kind == 'anthropic') {
      final content = decoded['content'];
      return content is List ? content.whereType<Map>().where((part) => part['type'] == 'text').map((part) => '${part['text']}').join() : '';
    }
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) return '';
    final message = choices.first['message'];
    final content = message is Map ? message['content'] : null;
    return content is String ? content : '';
  }

  Future<String> _askCloud(String said, String? note, bool hidden) async {
    final kind = this.kind;
    final key = this.key;
    final model = this.model;
    if (kind == null || key == null || model == null || model.isEmpty) throw BrainException(offline);

    // A memória da conversa só muda quando a resposta chega; a fala atual leva o carimbo do momento, se houver.
    final turns = [
      ..._history,
      {'role': 'user', 'content': _stamp(said)},
    ];
    final system = _system(note);
    final limit = [512, 800, 1400][wordiness.clamp(0, 2).toInt()];

    final Uri address;
    final Map<String, Object?> body;
    if (kind == 'anthropic') {
      address = Uri.parse('$anthropic/v1/messages');
      body = {'model': model, 'max_tokens': limit, 'system': system, 'messages': turns};
    } else {
      address = Uri.parse('${_base(kind)}/v1/chat/completions');
      body = {
        'model': model,
        'messages': [
          {'role': 'system', 'content': system},
          ...turns,
        ],
        'stream': false,
      };
      // Os modelos novos da OpenAI recusam max_tokens e temperature; os outros aceitam.
      if (kind != 'openai') {
        body['max_tokens'] = limit;
        body['temperature'] = 0.85;
      }
    }

    final client = http.Client();
    _active = client;
    final http.Response response;
    try {
      response = await client.post(address, headers: _headers(kind, key), body: jsonEncode(body)).timeout(const Duration(seconds: 60));
    } on TimeoutException {
      throw BrainException('Ainda pensando... a ${companyOf(kind)} demorou demais. Tente de novo.');
    } on http.ClientException {
      throw BrainException('Sem conexão com a ${companyOf(kind)}. Confira a internet.');
    } finally {
      if (identical(_active, client)) _active = null;
      client.close();
    }

    if (response.statusCode != 200) {
      throw BrainException(_explain(response.statusCode, kind));
    }

    String reply = '';
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (kind == 'anthropic') {
        final content = decoded['content'];
        if (content is List) {
          for (final part in content) {
            if (part is Map && part['type'] == 'text' && part['text'] is String) reply += part['text'] as String;
          }
        }
      } else {
        final choices = decoded['choices'];
        if (choices is List && choices.isNotEmpty) {
          final message = choices.first['message'];
          final content = message is Map ? message['content'] : null;
          if (content is String) {
            reply = content;
          } else if (content is List) {
            for (final part in content) {
              if (part is Map && part['text'] is String) reply += part['text'] as String;
            }
          }
        }
      }
    } on FormatException {
      reply = '';
    }

    reply = _clean(reply);
    if (reply.isEmpty) {
      return declined;
    }
    if (!hidden) _history.add({'role': 'user', 'content': said});
    _history.add({'role': 'assistant', 'content': reply});
    _trim();
    return reply;
  }
}
