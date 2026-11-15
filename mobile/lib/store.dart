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

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    try {
      key = await _vault.read(key: 'brain_key');
    } catch (_) {
      key = null; // cofre ilegível (por exemplo, depois de restaurar um backup): pede a chave de novo
    }
  }

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
