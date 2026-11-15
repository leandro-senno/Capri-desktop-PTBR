import 'dart:async';

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';

/// O cérebro que roda dentro do celular: Gemma 4 E2B, o mesmo modelo que o app de PC escolhe para
/// máquinas médias, na versão feita para celular (LiteRT-LM). Depois de baixado, funciona sem internet.
class LocalBrain {
  static const String name = 'Gemma 4 E2B';
  static const String file = 'gemma-4-E2B-it.litertlm';
  static const String url = 'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/$file';

  /// Tamanho do download, em bytes (2,6 GB).
  static const int size = 2588147712;

  static bool _started = false;
  static bool _activated = false;

  dynamic _model;
  dynamic _chat;
  bool? _loadedGpu;
  String? _system;
  int _limit = 0;
  int _turns = 0;

  /// Em qual processador o modelo foi carregado (null = ainda não carregou).
  bool? get onGpu => _loadedGpu;

  static Future<void> _start() async {
    if (_started) return;
    await FlutterGemma.initialize(inferenceEngines: const [LiteRtLmEngine()]);
    _started = true;
  }

  static Future<bool> installed() async {
    try {
      await _start();
      return await FlutterGemma.isModelInstalled(file);
    } catch (_) {
      return false;
    }
  }

  /// Baixa o modelo (ou só confirma, se já estiver no aparelho) e o deixa como o modelo ativo.
  static Future<void> install([void Function(int percent)? onProgress]) async {
    await _start();
    await FlutterGemma.installModel(modelType: ModelType.gemma4, fileType: ModelFileType.litertlm)
        .fromNetwork(url)
        .withProgress((progress) => onProgress?.call(progress))
        .install();
    _activated = true;
  }

  Future<void> unload() async {
    final model = _model;
    _model = null;
    _chat = null;
    _loadedGpu = null;
    _system = null;
    _turns = 0;
    try {
      await model?.close();
    } catch (_) {}
  }

  Future<void> remove() async {
    await unload();
    await _start();
    await FlutterGemma.uninstallModel(file);
    _activated = false;
  }

  /// Carrega o modelo na memória. Tenta a placa de vídeo quando [gpu] é true e cai para o processador se falhar.
  Future<void> load({required bool gpu}) async {
    if (_model != null && (_loadedGpu == gpu || (gpu && _loadedGpu == false))) return;
    await unload();
    if (!_activated) await install();
    if (gpu) {
      try {
        _model = await FlutterGemma.getActiveModel(maxTokens: 4096, preferredBackend: PreferredBackend.gpu);
        _loadedGpu = true;
        return;
      } catch (_) {
        _model = null;
      }
    }
    _model = await FlutterGemma.getActiveModel(maxTokens: 4096, preferredBackend: PreferredBackend.cpu);
    _loadedGpu = false;
  }

  /// Responde à fala. [recap] são as últimas trocas, usadas quando a sessão precisa recomeçar.
  Future<String> ask({required String system, required String said, required int limit, required bool gpu, String recap = ''}) async {
    await load(gpu: gpu);
    // A janela do modelo é curta: a cada 8 trocas a sessão recomeça, levando um resumo das últimas falas.
    if (_chat == null || _system != system || _limit != limit || _turns >= 8) {
      _chat = await _model.createChat(
        systemInstruction: recap.isEmpty ? system : '$system\n\nThe conversation so far:\n$recap',
        maxOutputTokens: limit,
      );
      _system = system;
      _limit = limit;
      _turns = 0;
    }
    _turns++;
    await _chat.addQueryChunk(Message.text(text: said, isUser: true));
    final reply = StringBuffer();
    final Stream<dynamic> stream = _chat.generateChatResponseAsync();
    await for (final event in stream.timeout(const Duration(seconds: 120))) {
      if (event is TextResponse) reply.write(event.token);
    }
    return reply.toString();
  }
}
