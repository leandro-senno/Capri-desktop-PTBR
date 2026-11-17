import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Erro da ElevenLabs, já numa frase pronta para mostrar.
class VoiceException implements Exception {
  final String message;
  final int status;
  VoiceException(this.message, [this.status = 0]);
  @override
  String toString() => message;
}

class VoiceEntry {
  final String id;
  final String name;
  const VoiceEntry(this.id, this.name);
}

/// A voz da ElevenLabs pela API, portada de app/Voice.cs: mesmas rotas, mesmo formato de áudio
/// e a mesma conta da boca a partir do volume do áudio.
class Eleven {
  static const String host = 'https://api.elevenlabs.io';

  static String explain(int status, String body) {
    if (status == 401) return 'A ElevenLabs não aceitou essa chave. Confira a chave.';
    if (status == 402 || body.contains('quota') || body.contains('credits')) return 'Os créditos da ElevenLabs acabaram. Ela volta a falar com a voz do Android.';
    if (status == 403 || RegExp(r'permission|not allowed|forbidden|unauthori[sz]ed', caseSensitive: false).hasMatch(body)) {
      return 'A chave não tem permissão. Crie uma chave nova na ElevenLabs com "Restrict key" desligado.';
    }
    if (status == 404 || body.contains('voice_not_found')) return 'Essa voz não existe na sua conta da ElevenLabs. Escolha outra.';
    if (status == 429) return 'Pedidos demais para a ElevenLabs. Espere um pouco.';
    if (status >= 500) return 'Os servidores da ElevenLabs falharam. Tente de novo.';
    if (body.contains('not available for model')) return 'Essa voz não funciona com esse modelo. Escolha outro modelo de voz.';
    return 'A ElevenLabs respondeu com o erro $status.';
  }

  static Future<http.Response> _send(Future<http.Response> request) async {
    final http.Response response;
    try {
      response = await request.timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw VoiceException('A ElevenLabs demorou demais para responder.');
    } on http.ClientException {
      throw VoiceException('Sem conexão com a ElevenLabs. Confira a internet.');
    }
    if (response.statusCode != 200) throw VoiceException(explain(response.statusCode, response.body), response.statusCode);
    return response;
  }

  /// As vozes da conta: as suas primeiro, depois as prontas, em ordem alfabética.
  static Future<List<VoiceEntry>> voices(String key) async {
    final mine = <VoiceEntry>[];
    final premade = <VoiceEntry>[];
    String? next;
    for (var page = 0; page < 10; page++) {
      final path = '/v2/voices?page_size=100${next == null ? '' : '&next_page_token=${Uri.encodeQueryComponent(next)}'}';
      final response = await _send(http.get(Uri.parse('$host$path'), headers: {'xi-api-key': key}));
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      final found = decoded is Map ? decoded['voices'] : null;
      if (found is List) {
        for (final voice in found) {
          if (voice is Map && voice['voice_id'] is String) {
            final entry = VoiceEntry(voice['voice_id'] as String, (voice['name'] as String?) ?? voice['voice_id'] as String);
            (voice['category'] == 'premade' ? premade : mine).add(entry);
          }
        }
      }
      final more = decoded is Map && decoded['has_more'] == true;
      final token = decoded is Map ? decoded['next_page_token'] : null;
      if (!more || token is! String || token.isEmpty) break;
      next = token;
    }
    int byName(VoiceEntry a, VoiceEntry b) => a.name.toLowerCase().compareTo(b.name.toLowerCase());
    mine.sort(byName);
    premade.sort(byName);
    return [...mine, ...premade];
  }

  /// Os modelos de voz que a chave pode usar.
  static Future<List<String>> models(String key) async {
    try {
      final response = await _send(http.get(Uri.parse('$host/v1/models'), headers: {'xi-api-key': key}));
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      final ids = <String>[];
      if (decoded is List) {
        for (final model in decoded) {
          if (model is Map && model['can_do_text_to_speech'] == true && model['model_id'] is String) ids.add(model['model_id'] as String);
        }
      }
      return ids;
    } on VoiceException catch (error) {
      if (error.status == 401) rethrow;
      return [];
    } on FormatException {
      return [];
    }
  }

  /// Pede a fala em WAV de 24 kHz, como o original.
  static Future<Uint8List> speak({required String key, required String voiceId, String? model, required String text}) async {
    final body = <String, Object>{'text': text};
    if (model != null && model.isNotEmpty) body['model_id'] = model;
    final response = await _send(http.post(
      Uri.parse('$host/v1/text-to-speech/${Uri.encodeComponent(voiceId)}?output_format=wav_24000'),
      headers: {'xi-api-key': key, 'Content-Type': 'application/json'},
      body: jsonEncode(body),
    ));
    return response.bodyBytes;
  }

  /// A forma da boca a cada instante (-1 fechada, 0 a 4 cada vez mais aberta), medida pelo volume
  /// do áudio. É a mesma conta de Voice.Mouths no original.
  static List<int> mouths(Uint8List wav, double perSecond) {
    final data = ByteData.sublistView(wav);
    var rate = 24000;
    var channels = 1;
    var start = -1;
    var length = 0;
    var at = 12;
    while (at + 8 <= wav.length) {
      final id = String.fromCharCodes(wav.sublist(at, at + 4));
      final size = data.getUint32(at + 4, Endian.little);
      if (id == 'fmt ' && at + 16 <= wav.length) {
        channels = max(1, data.getUint16(at + 10, Endian.little));
        rate = data.getUint32(at + 12, Endian.little);
      } else if (id == 'data') {
        start = at + 8;
        length = min(size, wav.length - start);
        break;
      }
      at += 8 + size + (size.isOdd ? 1 : 0);
    }
    if (start < 0 || rate <= 0) return const [];
    final frames = length ~/ (2 * channels);
    final step = max(1, (rate / perSecond).floor());
    final count = frames ~/ step;
    final levels = List<double>.filled(count, 0);
    for (var i = 0; i < count; i++) {
      var sum = 0.0;
      for (var j = i * step; j < (i + 1) * step; j++) {
        final sample = data.getInt16(start + j * 2 * channels, Endian.little).toDouble();
        sum += sample * sample;
      }
      levels[i] = sqrt(sum / step) / 32768.0;
    }
    final loudest = levels.fold<double>(0, max);
    final quiet = max(0.004, loudest * 0.08);
    final talking = levels.where((level) => level > quiet).toList()..sort();
    double cut(double q) => talking.isEmpty ? 1 : talking[min(talking.length - 1, (q * talking.length).floor())];
    final low = cut(0.35), mid = cut(0.7), high = cut(0.97);
    return [
      for (var i = 0; i < count; i++)
        levels[i] <= quiet
            ? -1
            : levels[i] < low
                ? (i % 3 == 0 ? 0 : 1)
                : levels[i] < mid
                    ? (i.isOdd ? 2 : 1)
                    : levels[i] < high
                        ? 3
                        : 4,
    ];
  }
}

/// Voz e ouvidos no Android. A voz pode ser a da ElevenLabs (pela API) ou a pt-BR do sistema;
/// os ouvidos são o reconhecimento de fala do sistema.
class Voice {
  final FlutterTts _tts = FlutterTts();
  final SpeechToText _ears = SpeechToText();
  final AudioPlayer _player = AudioPlayer();
  final AudioPlayer _speech = AudioPlayer();
  bool _earsReady = false;
  bool _ttsReady = false;
  int _ticket = 0;

  /// ElevenLabs: com chave e voz escolhidas, ela fala por lá.
  bool eleven = false;
  String? elevenKey;
  String? voiceId;
  String? voiceModel;

  /// Idioma em que ela fala e ouve (pt, en ou es) e volume da voz, de 0 a 1.
  String language = 'pt';
  double volume = 1;

  static const Map<String, String> _speakIn = {'pt': 'pt-BR', 'en': 'en-US', 'es': 'es-ES'};
  static const Map<String, String> _hearIn = {'pt': 'pt_BR', 'en': 'en_US', 'es': 'es_ES'};

  void Function()? onStart;
  void Function()? onDone;

  /// As formas da boca para a fala que vai começar (só com a ElevenLabs).
  void Function(List<int> shapes)? onShapes;

  /// A ElevenLabs falhou e ela usou a voz do Android: a frase explica o motivo.
  void Function(String problem)? onProblem;

  bool get elevenReady => eleven && (elevenKey ?? '').isNotEmpty && (voiceId ?? '').isNotEmpty;

  Future<void> _prepare() async {
    if (_ttsReady) return;
    _ttsReady = true;
    try {
      await _tts.setLanguage('pt-BR');
      await _tts.setSpeechRate(0.52);
      await _tts.setPitch(1.25);
      // Cada frase espera terminar antes da próxima; o fim da fala inteira é avisado pela fila.
      await _tts.awaitSpeakCompletion(true);
    } catch (_) {
      // sem voz instalada: ela só escreve
    }
  }

  /// Tags de glitch como [SIGNAL CORRUPTED] aparecem no texto mas não são lidas, como no original.
  static String spoken(String text) => text.replaceAll(RegExp(r'\[[^\]]*\]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

  // ------------------------------------------------------------ fala em fila
  // As frases entram com add() assim que o cérebro termina cada uma, e saem uma depois da outra.
  // Com a ElevenLabs, o áudio de cada frase já é pedido na hora em que ela entra na fila.

  final List<Future<_Piece?>> _queue = [];
  bool _pumping = false;
  bool _closed = true;
  bool _talking = false;
  int _finishedTicket = -1;
  Completer<void> _hush = Completer<void>();
  final StringBuffer _said = StringBuffer();

  /// Está falando (ou com frases na fila).
  bool get talking => _talking || _queue.isNotEmpty;

  /// Começa uma fala nova, que vai receber frases com [add] e termina com [end].
  void begin() {
    _ticket++;
    _queue.clear();
    _closed = false;
    _talking = false;
    _said.clear();
    if (_hush.isCompleted) _hush = Completer<void>();
  }

  /// Junta uma frase à fala atual.
  void add(String sentence) {
    final words = spoken(sentence);
    if (words.isEmpty || _closed) return;
    _said.write(' $words');
    _queue.add(_fetch(words, _ticket));
    _pump();
  }

  /// Não vêm mais frases: quando a fila acabar, avisa [onDone].
  void end() {
    _closed = true;
    if (!_pumping && _queue.isEmpty) _finish();
  }

  /// Fala um texto inteiro de uma vez.
  Future<void> speak(String text) async {
    await stop(quietly: true);
    begin();
    add(text);
    end();
  }

  Future<_Piece?> _fetch(String words, int ticket) async {
    if (!elevenReady) return _Piece(words, null);
    try {
      final wav = await Eleven.speak(key: elevenKey!, voiceId: voiceId!, model: voiceModel, text: words);
      return _Piece(words, wav);
    } on VoiceException catch (error) {
      if (ticket == _ticket) onProblem?.call(error.message);
    } catch (_) {
      if (ticket == _ticket) onProblem?.call('Não consegui tocar a voz da ElevenLabs. Usei a voz do Android.');
    }
    return _Piece(words, null);
  }

  Future<void> _pump() async {
    if (_pumping) return;
    _pumping = true;
    while (_queue.isNotEmpty) {
      final ticket = _ticket;
      final piece = await _queue.removeAt(0);
      if (ticket != _ticket || piece == null) continue;
      await _play(piece);
    }
    _pumping = false;
    if (_closed) _finish();
  }

  Future<void> _play(_Piece piece) async {
    if (!_talking) {
      _talking = true;
      onStart?.call();
    }
    final hush = _hush.future;
    final wav = piece.wav;
    if (wav != null) {
      onShapes?.call(Eleven.mouths(wav, 12));
      final done = Completer<void>();
      final listening = _speech.onPlayerComplete.listen((_) {
        if (!done.isCompleted) done.complete();
      });
      try {
        await _speech.setVolume(volume);
        await _speech.play(BytesSource(wav, mimeType: 'audio/wav'));
        await Future.any([done.future, hush]).timeout(const Duration(seconds: 60));
      } catch (_) {
        // áudio que não tocou: segue para a próxima frase
      } finally {
        await listening.cancel();
      }
      return;
    }
    await _prepare();
    try {
      await _tts.setLanguage(_speakIn[language] ?? 'pt-BR');
      await _tts.setVolume(volume);
      final talk = _tts.speak(piece.words);
      await Future.any([talk, hush]).timeout(Duration(milliseconds: 5000 + piece.words.length * 120));
    } catch (_) {
      // voz do sistema travou ou demorou: segue
    }
  }

  void _finish() {
    if (_finishedTicket == _ticket) return;
    _finishedTicket = _ticket;
    _talking = false;
    onDone?.call();
  }

  Future<void> _quiet() async {
    if (!_hush.isCompleted) _hush.complete();
    try {
      await _speech.stop();
    } catch (_) {}
    try {
      await _tts.stop();
    } catch (_) {}
  }

  /// Para de falar na hora. Com [quietly], não avisa [onDone] (uma fala nova vai começar em seguida).
  Future<void> stop({bool quietly = false}) async {
    _ticket++;
    _queue.clear();
    _closed = true;
    await _quiet();
    _hush = Completer<void>();
    _finishedTicket = _ticket;
    _talking = false;
    if (!quietly) onDone?.call();
  }

  static String _fold(String text) {
    const from = 'áàâãäéèêëíìîïóòôõöúùûüç';
    const to = 'aaaaaeeeeiiiiooooouuuuc';
    final buffer = StringBuffer();
    for (final rune in text.toLowerCase().runes) {
      final letter = String.fromCharCode(rune);
      final at = from.indexOf(letter);
      buffer.write(at >= 0 ? to[at] : letter);
    }
    return buffer.toString().replaceAll(RegExp(r'[^a-z0-9 ]'), ' ');
  }

  static const Set<String> _halt = {'para', 'pare', 'espera', 'pera', 'perai', 'chega', 'calma', 'capri', 'stop', 'silencio', 'cala'};

  /// O microfone ouviu a própria voz dela (eco) ou foi você falando por cima?
  /// É eco quando quase todas as palavras ouvidas estão no que ela está dizendo.
  bool isEcho(String heard) {
    final mine = _fold(_said.toString()).split(' ').where((word) => word.length >= 2).toSet();
    final theirs = _fold(heard).split(' ').where((word) => word.length >= 2).toList();
    if (theirs.any((word) => _halt.contains(word) && !mine.contains(word))) return false;
    if (theirs.length < 3) return true;
    final strange = theirs.where((word) => !mine.contains(word)).length;
    return strange / theirs.length < 0.5;
  }

  /// Toca um dos cumprimentos gravados do original (hello-morning, hello-late, hello-miss).
  Future<void> hello(String name) async {
    try {
      await _player.setVolume(volume);
      await _player.play(AssetSource('voice/hello-$name.wav'));
    } catch (_) {}
  }

  bool get listening => _ears.isListening;

  /// Começa a ouvir. Devolve false se o microfone ou o reconhecimento não estiverem disponíveis.
  /// O aviso de "parou de ouvir" da escuta atual. O reconhecimento é iniciado uma vez só,
  /// então o aviso fica aqui e é trocado a cada escuta, para nunca chegar a uma escuta antiga.
  void Function()? _stopped;

  /// Com [keepTalking], ouve sem parar a fala dela (para você poder interromper).
  Future<bool> listen({required void Function(String words, bool done) onWords, required void Function() onStop, bool keepTalking = false}) async {
    try {
      if (!_earsReady) {
        _earsReady = await _ears.initialize(
          onStatus: (status) {
            if (status == 'done' || status == 'notListening') _stopped?.call();
          },
          onError: (_) => _stopped?.call(),
        );
      }
      if (!_earsReady) return false;
      if (!keepTalking) await stop();
      _stopped = onStop;
      await _ears.listen(
        onResult: (SpeechRecognitionResult result) => onWords(result.recognizedWords, result.finalResult),
        localeId: _hearIn[language] ?? 'pt_BR',
        listenOptions: SpeechListenOptions(partialResults: true, cancelOnError: true),
        // Depois de 1,8 s de silêncio ela entende que você terminou de falar.
        pauseFor: const Duration(milliseconds: 1800),
        listenFor: const Duration(seconds: 45),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> stopListening() async {
    try {
      await _ears.stop();
    } catch (_) {}
  }

  void dispose() {
    _player.dispose();
    _speech.dispose();
    _tts.stop();
  }
}

class _Piece {
  final String words;
  final Uint8List? wav;
  const _Piece(this.words, this.wav);
}
