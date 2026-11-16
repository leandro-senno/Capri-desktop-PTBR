import 'dart:async';
import 'dart:typed_data';

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
  bool? _loadedGpu;
  bool _vision = false;

  /// true depois que abrir uma imagem falhou neste aparelho: ela passa a usar só texto.
  bool blind = false;

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
    _loadedGpu = null;
    _vision = false;
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
  /// Com [vision], carrega também a parte do modelo que enxerga imagens (usa mais memória).
  Future<void> load({required bool gpu, bool vision = false}) async {
    final sameChip = _loadedGpu == gpu || (gpu && _loadedGpu == false);
    if (_model != null && sameChip && (_vision || !vision)) return;
    await unload();
    if (!_activated) await install();
    if (gpu) {
      try {
        _model = vision
            ? await FlutterGemma.getActiveModel(maxTokens: 4096, preferredBackend: PreferredBackend.gpu, supportImage: true, maxNumImages: 1)
            : await FlutterGemma.getActiveModel(maxTokens: 4096, preferredBackend: PreferredBackend.gpu);
        _loadedGpu = true;
        _vision = vision;
        return;
      } catch (_) {
        _model = null;
      }
    }
    _model = vision
        ? await FlutterGemma.getActiveModel(maxTokens: 4096, preferredBackend: PreferredBackend.cpu, supportImage: true, maxNumImages: 1)
        : await FlutterGemma.getActiveModel(maxTokens: 4096, preferredBackend: PreferredBackend.cpu);
    _loadedGpu = false;
    _vision = vision;
  }

  /// Responde a uma fala. Cada chamada é uma sessão nova: quem chama manda no [system] tudo que o modelo
  /// precisa saber, inclusive a conversa recente. Assim a memória não depende do estado interno do motor.
  Future<String> ask({required String system, required String said, required int limit, required bool gpu, Uint8List? image}) async {
    await load(gpu: gpu, vision: image != null);
    final chat = image == null
        ? await _model.createChat(systemInstruction: system, maxOutputTokens: limit)
        : await _model.createChat(systemInstruction: system, maxOutputTokens: limit, supportImage: true);
    try {
      await chat.addQueryChunk(image == null ? Message.text(text: said, isUser: true) : Message.withImage(text: said, imageBytes: image, isUser: true));
      final reply = StringBuffer();
      final Stream<dynamic> stream = chat.generateChatResponseAsync();
      await for (final event in stream.timeout(const Duration(seconds: 120))) {
        if (event is TextResponse) reply.write(event.token);
      }
      return reply.toString();
    } finally {
      try {
        await chat.close();
      } catch (_) {
        // versões do motor sem close(): a sessão é descartada na próxima
      }
    }
  }
}
