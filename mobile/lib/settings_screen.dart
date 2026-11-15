import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'brain.dart';
import 'local_brain.dart';
import 'look.dart';
import 'store.dart';

/// O "Mainframe" do celular: cérebro, voz e jeito dela.
class SettingsScreen extends StatefulWidget {
  final Store store;
  final Brain brain;
  const SettingsScreen({super.key, required this.store, required this.brain});

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
  bool _installing = false;
  int _percent = 0;
  String? _localNote;
  bool _localBad = false;

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

  Future<void> _install() async {
    setState(() {
      _installing = true;
      _percent = 0;
      _localNote = 'Baixando o cérebro. Deixe o app aberto e use Wi-Fi.';
      _localBad = false;
    });
    try {
      await LocalBrain.install((percent) {
        if (mounted) setState(() => _percent = percent);
      });
      _store.localReady = true;
      _store.local = true;
      if (!mounted) return;
      setState(() {
        _installing = false;
        _localNote = 'Cérebro montado. Ela já pensa sozinha, sem internet.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _installing = false;
        _localNote = 'O download não terminou. Confira a internet e o espaço livre (2,6 GB) e tente de novo.';
        _localBad = true;
      });
    }
  }

  Future<void> _remove() async {
    try {
      await widget.brain.device.remove();
    } catch (_) {}
    _store.localReady = false;
    if (!mounted) return;
    setState(() {
      _localNote = 'Cérebro local apagado.';
      _localBad = false;
    });
  }

  List<Widget> _localBrain() {
    final ready = _store.localReady;
    return [
      Text(
        ready
            ? '${LocalBrain.name} montado neste celular. A conversa não sai do aparelho e funciona sem internet.'
            : 'Ela pensa dentro do celular com o ${LocalBrain.name}: grátis, sem chave e sem internet depois de baixar. O download é de 2,6 GB, uma vez só.',
        style: const TextStyle(color: Look.dim, fontSize: 13, height: 1.4),
      ),
      const SizedBox(height: 12),
      if (_installing) ...[
        LinearProgressIndicator(value: _percent > 0 ? _percent / 100 : null, color: Look.cyan, backgroundColor: Look.edge),
        const SizedBox(height: 6),
        Text('$_percent%', style: const TextStyle(color: Look.cyan, fontSize: 13)),
      ] else if (ready)
        Row(
          children: [
            const Expanded(child: Text('• PRONTO', style: TextStyle(color: Look.cyan, fontSize: 13, letterSpacing: 3))),
            OutlinedButton(onPressed: _remove, child: const Text('Apagar')),
          ],
        )
      else
        SizedBox(width: double.infinity, child: FilledButton(onPressed: _install, child: const Text('Montar o cérebro'))),
      if (_localNote != null)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(_localNote!, style: TextStyle(color: _localBad ? Look.yellow : Look.dim, fontSize: 13, height: 1.4)),
        ),
      const SizedBox(height: 14),
      const Text('Onde ela pensa', style: TextStyle(color: Look.dim, fontSize: 13)),
      const SizedBox(height: 6),
      SegmentedButton<bool>(
        segments: const [
          ButtonSegment(value: true, label: Text('Placa de vídeo')),
          ButtonSegment(value: false, label: Text('Processador')),
        ],
        selected: {_store.localGpu},
        onSelectionChanged: (picked) => setState(() => _store.localGpu = picked.first),
      ),
      const Padding(
        padding: EdgeInsets.only(top: 6),
        child: Text('A placa de vídeo responde mais rápido. Se o app fechar ou travar ao responder, troque para o processador.', style: TextStyle(color: Look.dim, fontSize: 12, height: 1.4)),
      ),
    ];
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
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('No celular')),
              ButtonSegment(value: false, label: Text('Por chave')),
            ],
            selected: {_store.local},
            onSelectionChanged: (picked) => setState(() => _store.local = picked.first),
          ),
          const SizedBox(height: 12),
          if (_store.local) ..._localBrain() else ...[
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
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Passear sozinha'),
            subtitle: const Text('Ela anda, senta e levanta por conta própria', style: TextStyle(color: Look.dim, fontSize: 12)),
            value: _store.wander,
            onChanged: (value) => setState(() => _store.wander = value),
          ),
          const SizedBox(height: 6),
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
