import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Uma fala da conversa.
class Line {
  final bool mine;
  final String text;
  final bool problem;
  const Line(this.mine, this.text, {this.problem = false});

  Map<String, Object> toJson() => {'mine': mine, 'text': text};

  static Line? fromJson(Object? json) {
    if (json is Map && json['mine'] is bool && json['text'] is String) return Line(json['mine'] as bool, json['text'] as String);
    return null;
  }
}

/// Preferências no aparelho. A chave fica no cofre do Android (Keystore), como o original usa o DPAPI do Windows.
class Store {
  static const _vault = FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true));
  late final SharedPreferences _prefs;

  String? key;
  String? voiceKey;

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    try {
      key = await _vault.read(key: 'brain_key');
      voiceKey = await _vault.read(key: 'voice_key');
    } catch (_) {
      key = null; // cofre ilegível (por exemplo, depois de restaurar um backup): pede a chave de novo
      voiceKey = null;
    }
  }

  Future<void> saveVoiceKey(String? value) async {
    voiceKey = value;
    try {
      if (value == null || value.isEmpty) {
        await _vault.delete(key: 'voice_key');
      } else {
        await _vault.write(key: 'voice_key', value: value);
      }
    } catch (_) {
      // sem cofre, a chave vale só até fechar o app
    }
  }

  /// Falar pela ElevenLabs (true) ou pela voz do Android (false).
  bool get eleven => _prefs.getBool('eleven') ?? false;
  set eleven(bool value) => _prefs.setBool('eleven', value);

  String? get voiceId => _prefs.getString('voice_id');
  set voiceId(String? value) => value == null || value.isEmpty ? _prefs.remove('voice_id') : _prefs.setString('voice_id', value);

  String? get voiceName => _prefs.getString('voice_name');
  set voiceName(String? value) => value == null || value.isEmpty ? _prefs.remove('voice_name') : _prefs.setString('voice_name', value);

  String? get voiceModel => _prefs.getString('voice_model');
  set voiceModel(String? value) => value == null || value.isEmpty ? _prefs.remove('voice_model') : _prefs.setString('voice_model', value);

  Future<void> saveKey(String? value) async {
    key = value;
    try {
      if (value == null || value.isEmpty) {
        await _vault.delete(key: 'brain_key');
      } else {
        await _vault.write(key: 'brain_key', value: value);
      }
    } catch (_) {
      // sem cofre, a chave vale só até fechar o app
    }
  }

  String? get model => _prefs.getString('model');
  set model(String? value) => value == null ? _prefs.remove('model') : _prefs.setString('model', value);

  String? get nickname => _prefs.getString('nickname');
  set nickname(String? value) => value == null || value.trim().isEmpty ? _prefs.remove('nickname') : _prefs.setString('nickname', value.trim());

  /// 0 = curtas, 1 = mais longas, 2 = longas (como REPLIES no Mainframe).
  int get wordiness => _prefs.getInt('wordiness') ?? 0;
  set wordiness(int value) => _prefs.setInt('wordiness', value);

  bool get voice => _prefs.getBool('voice') ?? true;
  set voice(bool value) => _prefs.setBool('voice', value);

  bool get intro => _prefs.getBool('intro') ?? true;
  set intro(bool value) => _prefs.setBool('intro', value);

  /// Cérebro no celular (true) ou por chave (false). Quem já tinha uma chave continua nela.
  bool get local => _prefs.getBool('local') ?? (key == null || key!.isEmpty);
  set local(bool value) => _prefs.setBool('local', value);

  /// O modelo local já foi baixado.
  bool get localReady => _prefs.getBool('local_ready') ?? false;
  set localReady(bool value) => _prefs.setBool('local_ready', value);

  /// Usar a placa de vídeo do celular para o cérebro local.
  bool get localGpu => _prefs.getBool('local_gpu') ?? true;
  set localGpu(bool value) => _prefs.setBool('local_gpu', value);

  /// Ficou true se o app fechou no meio de carregar o modelo na placa de vídeo.
  bool get gpuTrying => _prefs.getBool('gpu_trying') ?? false;
  Future<void> setGpuTrying(bool value) => _prefs.setBool('gpu_trying', value);

  /// De quantos em quantos minutos de silêncio ela puxa conversa (0 = nunca).
  int get nudgeMinutes => _prefs.getInt('nudge_minutes') ?? 30;
  set nudgeMinutes(int value) => _prefs.setInt('nudge_minutes', value);

  /// O que a pessoa pediu para ela lembrar (memória de longo prazo).
  List<String> get facts => _prefs.getStringList('facts') ?? [];
  set facts(List<String> value) => _prefs.setStringList('facts', value);

  void addFact(String fact) {
    final all = facts..remove(fact);
    all.add(fact);
    facts = all.length > 40 ? all.sublist(all.length - 40) : all;
  }

  /// A cidade da pessoa, para ela saber o clima.
  String? get city => _prefs.getString('city');
  set city(String? value) => value == null || value.trim().isEmpty ? _prefs.remove('city') : _prefs.setString('city', value.trim());

  /// Avisar na conversa quando chega uma mensagem (precisa do acesso às notificações).
  bool get announce => _prefs.getBool('announce') ?? false;
  set announce(bool value) => _prefs.setBool('announce', value);

  /// Ela passeia e senta sozinha.
  bool get wander => _prefs.getBool('wander') ?? true;
  set wander(bool value) => _prefs.setBool('wander', value);

  /// Minutos parada até dormir (0 = nunca).
  int get sleepMinutes => _prefs.getInt('sleep_minutes') ?? 3;
  set sleepMinutes(int value) => _prefs.setInt('sleep_minutes', value);

  DateTime? get lastOpened {
    final at = _prefs.getInt('last_opened');
    return at == null ? null : DateTime.fromMillisecondsSinceEpoch(at);
  }

  void touch() => _prefs.setInt('last_opened', DateTime.now().millisecondsSinceEpoch);

  List<Line> get lines {
    final saved = _prefs.getString('lines');
    if (saved == null) return [];
    try {
      final decoded = jsonDecode(saved);
      if (decoded is! List) return [];
      return decoded.map(Line.fromJson).whereType<Line>().toList();
    } on FormatException {
      return [];
    }
  }

  set lines(List<Line> value) {
    final kept = value.where((line) => !line.problem).toList();
    final recent = kept.length > 60 ? kept.sublist(kept.length - 60) : kept;
    _prefs.setString('lines', jsonEncode(recent.map((line) => line.toJson()).toList()));
  }
}
