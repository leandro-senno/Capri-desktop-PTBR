import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Voz e ouvidos no Android: a voz pt-BR do sistema fala e o reconhecimento do sistema escuta.
/// (No Windows o fork usa a voz pt-BR do Windows do mesmo jeito.)
class Voice {
  final FlutterTts _tts = FlutterTts();
  final SpeechToText _ears = SpeechToText();
  final AudioPlayer _player = AudioPlayer();
  bool _earsReady = false;
  bool _ttsReady = false;

  void Function()? onStart;
  void Function()? onDone;

  Future<void> _prepare() async {
    if (_ttsReady) return;
    _ttsReady = true;
    try {
      await _tts.setLanguage('pt-BR');
      await _tts.setSpeechRate(0.52);
      await _tts.setPitch(1.25);
      _tts.setStartHandler(() => onStart?.call());
      _tts.setCompletionHandler(() => onDone?.call());
      _tts.setCancelHandler(() => onDone?.call());
      _tts.setErrorHandler((_) => onDone?.call());
    } catch (_) {
      // sem voz instalada: ela só escreve
    }
  }

  /// Tags de glitch como [SIGNAL CORRUPTED] aparecem no texto mas não são lidas, como no original.
  static String spoken(String text) => text.replaceAll(RegExp(r'\[[^\]]*\]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

  Future<void> speak(String text) async {
    final words = spoken(text);
    if (words.isEmpty) {
      onDone?.call();
      return;
    }
    await _prepare();
    try {
      await _tts.stop();
      await _tts.speak(words);
    } catch (_) {
      onDone?.call();
    }
  }

  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }

  /// Toca um dos cumprimentos gravados do original (hello-morning, hello-late, hello-miss).
  Future<void> hello(String name) async {
    try {
      await _player.play(AssetSource('voice/hello-$name.wav'));
    } catch (_) {}
  }

  bool get listening => _ears.isListening;

  /// Começa a ouvir. Devolve false se o microfone ou o reconhecimento não estiverem disponíveis.
  Future<bool> listen({required void Function(String words, bool done) onWords, required void Function() onStop}) async {
    try {
      if (!_earsReady) {
        _earsReady = await _ears.initialize(
          onStatus: (status) {
            if (status == 'done' || status == 'notListening') onStop();
          },
          onError: (_) => onStop(),
        );
      }
      if (!_earsReady) return false;
      await stop();
      await _ears.listen(
        onResult: (SpeechRecognitionResult result) => onWords(result.recognizedWords, result.finalResult),
        localeId: 'pt_BR',
        listenOptions: SpeechListenOptions(partialResults: true, cancelOnError: true),
        pauseFor: const Duration(seconds: 3),
        listenFor: const Duration(seconds: 30),
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
    _tts.stop();
  }
}
