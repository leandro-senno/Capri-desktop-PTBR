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
    reply = reply.replaceAll('*', '').trim();
    return reply;
  }

  /// Manda a fala da pessoa e devolve a resposta da Capri.
  /// [note] é uma instrução extra só para esta resposta (por exemplo, o resultado de algo que ela acabou de fazer).
  Future<String> ask(String said, {String? note}) => local ? _askLocal(said, note) : _askCloud(said, note);

  /// O que ela diz quando resolve puxar conversa sozinha.
  static const String nudge =
      "(They've been quiet for a while. Say one short line to pull them back into chatting: tease them, ask about their day or what they're doing. Don't mention this note.)";

  /// O que a pessoa pediu para ela lembrar. Vai no prompt de sistema.
  List<String> facts = const [];

  /// O momento (dia, hora, bateria, clima). Vai junto da fala, para não mudar o prompt de sistema a cada minuto.
  String? moment;

  String _system(String? note) {
    final buffer = StringBuffer(character(nickname: nickname, wordiness: wordiness))
      ..write('\nA line in [Right now: ...] before their message is background about this moment. Use it only when it matters and never read it out.');
    if (facts.isNotEmpty) {
      buffer.write('\nThings they asked you to remember about them (your long-term memory):');
      for (final fact in facts) {
        buffer.write('\n- $fact');
      }
    }
    if (note != null) buffer.write('\n$note');
    return buffer.toString();
  }

  String _stamp(String said) => (moment ?? '').isEmpty ? said : '[Right now: $moment]\n$said';

  Future<String> _askLocal(String said, String? note) async {
    if (!localReady) throw BrainException(offline);
    // As últimas trocas, para a sessão do modelo recomeçar sem perder o fio.
    final recent = _history.length > 6 ? _history.sublist(_history.length - 6) : _history;
    final recap = recent.map((turn) => '${turn['role'] == 'user' ? 'User' : 'Capri'}: ${turn['content']}').join('\n');
    final limit = [160, 300, 600][wordiness.clamp(0, 2).toInt()];
    final guarded = gpu && device.onGpu == null;
    String reply;
    try {
      if (guarded) await gpuGuard?.call(true);
      reply = await device.ask(system: _system(note), said: _stamp(said), limit: limit, gpu: gpu, recap: recap);
    } on TimeoutException {
      throw BrainException('Demorei demais pensando. Tente de novo, ou use uma chave nas configurações.');
    } catch (error) {
      if (error is BrainException) rethrow;
      await device.unload();
      throw BrainException('Meu cérebro local falhou ao carregar. Feche outros apps e tente de novo, ou troque para o processador nas configurações.');
    } finally {
      if (guarded) await gpuGuard?.call(false);
    }
    reply = _clean(reply);
    if (reply.isEmpty) return declined;
    _history.add({'role': 'user', 'content': said});
    _history.add({'role': 'assistant', 'content': reply});
    _trim();
    return reply;
  }

  Future<String> _askCloud(String said, String? note) async {
    final kind = this.kind;
    final key = this.key;
    final model = this.model;
    if (kind == null || key == null || model == null || model.isEmpty) throw BrainException(offline);

    _history.add({'role': 'user', 'content': said});
    _trim();
    // Só a fala atual leva o carimbo do momento; o histórico guarda a fala limpa.
    final turns = [
      ..._history.sublist(0, _history.length - 1),
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
      _history.removeLast();
      throw BrainException('Ainda pensando... a ${companyOf(kind)} demorou demais. Tente de novo.');
    } on http.ClientException {
      _history.removeLast();
      throw BrainException('Sem conexão com a ${companyOf(kind)}. Confira a internet.');
    } finally {
      if (identical(_active, client)) _active = null;
      client.close();
    }

    if (response.statusCode != 200) {
      _history.removeLast();
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
      _history.removeLast();
      return declined;
    }
    _history.add({'role': 'assistant', 'content': reply});
    _trim();
    return reply;
  }
}
