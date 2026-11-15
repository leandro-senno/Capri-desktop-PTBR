import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'brain.dart';
import 'look.dart';
import 'store.dart';

/// O "Mainframe" do celular: cérebro, voz e jeito dela.
class SettingsScreen extends StatefulWidget {
  final Store store;
  const SettingsScreen({super.key, required this.store});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const String freeKeyPage = 'https://build.nvidia.com/settings/api-keys';

  late final TextEditingController _key;
  late final TextEditingController _nickname;
  List<String> _models = [];
  String? _model;
  String? _note;
  bool _noteBad = false;
  bool _busy = false;
  bool _hidden = true;

  Store get _store => widget.store;

  @override
  void initState() {
    super.initState();
    _key = TextEditingController(text: _store.key ?? '');
    _nickname = TextEditingController(text: _store.nickname ?? '');
    _model = _store.model;
    if (_model != null) _models = [_model!];
    if ((_store.key ?? '').isNotEmpty) {
      _note = 'Conectada à ${Brain.companyOf(Brain.kindOf(_store.key))}.';
    }
  }

  @override
  void dispose() {
    _key.dispose();
    _nickname.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final key = _key.text.trim();
    FocusScope.of(context).unfocus();
    if (key.isEmpty) {
      await _store.saveKey(null);
      _store.model = null;
      setState(() {
        _models = [];
        _model = null;
        _note = 'Chave removida. Ela está sem cérebro.';
        _noteBad = false;
      });
      return;
    }
    final kind = Brain.kindOf(key);
    if (kind == null) {
      setState(() {
        _note = 'Essa chave não parece ser da NVIDIA (nvapi-...), OpenAI, Anthropic ou DeepSeek.';
        _noteBad = true;
      });
      return;
    }
    setState(() {
      _busy = true;
      _note = 'Conectando à ${Brain.companyOf(kind)}...';
      _noteBad = false;
    });
    try {
      final models = await Brain.listModels(key);
      final kept = _model != null && models.contains(_model) ? _model : Brain.pickModel(kind, models);
      if (kept != null && !models.contains(kept)) models.insert(0, kept);
      await _store.saveKey(key);
      _store.model = kept;
      if (!mounted) return;
      setState(() {
        _models = models;
        _model = kept;
        _busy = false;
        _note = kept == null ? 'A chave funciona, mas não encontrei modelos nela.' : 'Conectada à ${Brain.companyOf(kind)}. Modelo: $kept';
        _noteBad = kept == null;
      });
    } on BrainException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _note = error.message;
        _noteBad = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _note = 'Não consegui conectar. Confira a internet e tente de novo.';
        _noteBad = true;
      });
    }
  }

  Future<void> _open(String page) async {
    try {
      await launchUrl(Uri.parse(page), mode: LaunchMode.externalApplication);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Abra no navegador: $page')));
    }
  }

  Widget _title(String text) => Padding(
        padding: const EdgeInsets.only(top: 22, bottom: 8),
        child: Text(text, style: const TextStyle(color: Look.cyan, fontSize: 14, letterSpacing: 3)),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('MAINFRAME')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          _title('CÉREBRO'),
          const Text(
            'Ela pensa pela chave que você colar aqui. A chave da NVIDIA é grátis. A conversa passa pelos servidores do provedor da chave.',
            style: TextStyle(color: Look.dim, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _key,
            obscureText: _hidden,
            autocorrect: false,
            enableSuggestions: false,
            style: const TextStyle(fontFamily: Look.mono, color: Look.ink),
            decoration: InputDecoration(
              labelText: 'Chave (nvapi-..., sk-...)',
              suffixIcon: IconButton(icon: Icon(_hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: Look.dim), onPressed: () => setState(() => _hidden = !_hidden)),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: OutlinedButton(onPressed: () => _open(freeKeyPage), child: const Text('Chave grátis'))),
              const SizedBox(width: 10),
              Expanded(child: FilledButton(onPressed: _busy ? null : _connect, child: Text(_busy ? 'Conectando...' : 'Conectar'))),
            ],
          ),
          if (_note != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(_note!, style: TextStyle(color: _noteBad ? Look.yellow : Look.dim, fontSize: 13, height: 1.4)),
            ),
          if (_models.isNotEmpty) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _model,
              isExpanded: true,
              dropdownColor: Look.panel,
              style: const TextStyle(fontFamily: Look.mono, color: Look.ink, fontSize: 14),
              decoration: const InputDecoration(labelText: 'Modelo'),
              items: [for (final id in _models) DropdownMenuItem(value: id, child: Text(id, overflow: TextOverflow.ellipsis))],
              onChanged: (value) {
                setState(() => _model = value);
                _store.model = value;
              },
            ),
          ],
          _title('VOZ'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Ela fala as respostas'),
            subtitle: const Text('Usa a voz em português do Android', style: TextStyle(color: Look.dim, fontSize: 12)),
            value: _store.voice,
            onChanged: (value) => setState(() => _store.voice = value),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Cumprimento ao abrir'),
            subtitle: const Text('Voz original dela, em inglês', style: TextStyle(color: Look.dim, fontSize: 12)),
            value: _store.intro,
            onChanged: (value) => setState(() => _store.intro = value),
          ),
          _title('JEITO DELA'),
          TextField(
            controller: _nickname,
            maxLength: 24,
            onChanged: (value) => _store.nickname = value,
            style: const TextStyle(fontFamily: Look.mono, color: Look.ink),
            decoration: const InputDecoration(labelText: 'Como ela te chama (opcional)', counterText: ''),
          ),
          const SizedBox(height: 14),
          const Text('Tamanho das respostas', style: TextStyle(color: Look.dim, fontSize: 13)),
          const SizedBox(height: 6),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('Curtas')),
              ButtonSegment(value: 1, label: Text('Médias')),
              ButtonSegment(value: 2, label: Text('Longas')),
            ],
            selected: {_store.wordiness},
            onSelectionChanged: (picked) => setState(() => _store.wordiness = picked.first),
          ),
          const SizedBox(height: 14),
          const Text('Dorme depois de parada por', style: TextStyle(color: Look.dim, fontSize: 13)),
          const SizedBox(height: 6),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 1, label: Text('1 min')),
              ButtonSegment(value: 3, label: Text('3 min')),
              ButtonSegment(value: 10, label: Text('10 min')),
              ButtonSegment(value: 0, label: Text('Nunca')),
            ],
            selected: {_store.sleepMinutes},
            onSelectionChanged: (picked) => setState(() => _store.sleepMinutes = picked.first),
          ),
          _title('SOBRE'),
          const Text(
            'Capri para Android, versão não oficial feita por fãs e sem fins comerciais. '
            'Baseada no capri-desktop de Lachy e na tradução PT-BR de R3DPR0XY.\n\n'
            'Required Notice: Copyright 2026 Lachy (https://github.com/lachydotmcg)\n'
            'Licença: PolyForm Noncommercial 1.0.0',
            style: TextStyle(color: Look.dim, fontSize: 12, height: 1.5),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(onPressed: () => _open('https://polyformproject.org/licenses/noncommercial/1.0.0'), child: const Text('Ler a licença')),
          ),
        ],
      ),
    );
  }
}
