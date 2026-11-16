import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'brain.dart';
import 'hands.dart';
import 'local_brain.dart';
import 'look.dart';
import 'store.dart';
import 'voice.dart';

/// O "Mainframe" do celular: cérebro, voz e jeito dela.
class SettingsScreen extends StatefulWidget {
  final Store store;
  final Brain brain;
  const SettingsScreen({super.key, required this.store, required this.brain});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with WidgetsBindingObserver {
  static const String freeKeyPage = 'https://build.nvidia.com/settings/api-keys';

  late final TextEditingController _key;
  late final TextEditingController _nickname;
  List<String> _models = [];
  String? _model;
  String? _note;
  bool _noteBad = false;
  bool _busy = false;
  bool _hidden = true;
  late final TextEditingController _voiceKey;
  late final TextEditingController _city;
  bool _accessOn = false;
  bool _noticesOn = false;
  final Voice _tester = Voice();
  List<VoiceEntry> _voices = [];
  List<String> _voiceModels = [];
  String? _voiceNote;
  bool _voiceBad = false;
  bool _voiceBusy = false;
  bool _voiceHidden = true;
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
    _voiceKey = TextEditingController(text: _store.voiceKey ?? '');
    _city = TextEditingController(text: _store.city ?? '');
    WidgetsBinding.instance.addObserver(this);
    _checkAccess();
    final voiceId = _store.voiceId;
    if (voiceId != null) _voices = [VoiceEntry(voiceId, _store.voiceName ?? voiceId)];
    final voiceModel = _store.voiceModel;
    if (voiceModel != null) _voiceModels = [voiceModel];
    _tester.onProblem = (problem) {
      if (mounted) setState(() { _voiceNote = problem; _voiceBad = true; });
    };
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
    _voiceKey.dispose();
    _city.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _tester.stop();
    _tester.dispose();
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

  /// Volta das configurações do Android: confere de novo se as permissões foram dadas.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkAccess();
  }

  Future<void> _checkAccess() async {
    final access = await Hands.accessOn();
    final notices = await Hands.noticesOn();
    if (!mounted) return;
    setState(() {
      _accessOn = access;
      _noticesOn = notices;
    });
  }

  Widget _permission(String name, bool on, String about, VoidCallback open) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(name, style: const TextStyle(fontSize: 15))),
              Text(on ? '• LIGADO' : '• DESLIGADO', style: TextStyle(color: on ? Look.cyan : Look.dim, fontSize: 12, letterSpacing: 2)),
            ],
          ),
          const SizedBox(height: 4),
          Text(about, style: const TextStyle(color: Look.dim, fontSize: 12, height: 1.4)),
          const SizedBox(height: 6),
          OutlinedButton(onPressed: open, child: Text(on ? 'Abrir a permissão' : 'Ativar')),
        ],
      ),
    );
  }

  List<Widget> _eyesAndHands() {
    final facts = _store.facts;
    return [
      _permission(
        'Ver e controlar a tela',
        _accessOn,
        'Ela lê o texto da tela de outros apps ("o que tem na tela?", "resume isso") e toca, rola, digita e volta quando você pede ("clica em Entrar", "rola pra baixo", "digita oi", "volta"). Antes de tocar em comprar, pagar, enviar ou apagar, ela pergunta. Com cérebro por chave, o texto lido vai para o provedor da chave.',
        Hands.openAccessSettings,
      ),
      _permission(
        'Ler notificações',
        _noticesOn,
        'Ela guarda as últimas notificações na memória do aparelho e conta o que chegou quando você pergunta ("o que chegou?").',
        Hands.openNoticeSettings,
      ),
      const Text(
        'Se o Android disser "configuração restrita" ao ativar: toque em "Liberar configurações restritas", abra o menu de três pontos no canto da tela do app, escolha "Permitir configurações restritas" e ative de novo.',
        style: TextStyle(color: Look.dim, fontSize: 12, height: 1.4),
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton(onPressed: Hands.openAppSettings, child: const Text('Liberar configurações restritas')),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Avisar quando chegar mensagem'),
        subtitle: const Text('Ela diz de quem é, sem ler o conteúdo', style: TextStyle(color: Look.dim, fontSize: 12)),
        value: _store.announce,
        onChanged: (value) => setState(() => _store.announce = value),
      ),
      const SizedBox(height: 8),
      TextField(
        controller: _city,
        maxLength: 40,
        onChanged: (value) => _store.city = value,
        style: const TextStyle(fontFamily: Look.mono, color: Look.ink),
        decoration: const InputDecoration(labelText: 'Sua cidade, para ela saber o clima (opcional)', counterText: ''),
      ),
      const SizedBox(height: 14),
      Text(
        facts.isEmpty ? 'Memória: vazia. Diga "lembra que..." na conversa para ela guardar algo.' : 'Memória: o que você pediu para ela lembrar',
        style: const TextStyle(color: Look.dim, fontSize: 13, height: 1.4),
      ),
      for (final fact in facts)
        Row(
          children: [
            Expanded(child: Text('- $fact', style: const TextStyle(fontSize: 13, height: 1.4))),
            IconButton(
              tooltip: 'Esquecer',
              icon: const Icon(Icons.close, size: 18, color: Look.dim),
              onPressed: () => setState(() => _store.facts = _store.facts..remove(fact)),
            ),
          ],
        ),
    ];
  }

  /// Confere a chave da ElevenLabs e busca as vozes e os modelos da conta.
  Future<void> _connectVoice() async {
    final key = _voiceKey.text.trim();
    FocusScope.of(context).unfocus();
    if (key.isEmpty) {
      await _store.saveVoiceKey(null);
      setState(() {
        _voiceNote = 'Chave removida. Ela fala com a voz do Android.';
        _voiceBad = false;
      });
      return;
    }
    setState(() {
      _voiceBusy = true;
      _voiceNote = 'Conectando à ElevenLabs...';
      _voiceBad = false;
    });
    try {
      final voices = await Eleven.voices(key);
      final models = await Eleven.models(key);
      await _store.saveVoiceKey(key);
      if (voices.isNotEmpty && !voices.any((voice) => voice.id == _store.voiceId)) {
        _store.voiceId = voices.first.id;
        _store.voiceName = voices.first.name;
      }
      if (models.isNotEmpty && !models.contains(_store.voiceModel)) {
        _store.voiceModel = models.contains('eleven_v3') ? 'eleven_v3' : models.first;
      }
      if (!mounted) return;
      setState(() {
        _voices = voices;
        _voiceModels = models;
        _voiceBusy = false;
        _voiceNote = voices.isEmpty ? 'A chave funciona, mas a conta não tem vozes.' : 'Conectada. Escolha a voz e toque em Testar.';
        _voiceBad = voices.isEmpty;
      });
    } on VoiceException catch (error) {
      if (!mounted) return;
      setState(() {
        _voiceBusy = false;
        _voiceNote = error.message;
        _voiceBad = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _voiceBusy = false;
        _voiceNote = 'Não consegui conectar à ElevenLabs. Confira a internet e tente de novo.';
        _voiceBad = true;
      });
    }
  }

  void _testVoice() {
    _tester
      ..eleven = _store.eleven
      ..elevenKey = _store.voiceKey
      ..voiceId = _store.voiceId
      ..voiceModel = _store.voiceModel;
    _tester.speak('Oi, choom. Essa é a minha voz. Preem, né?');
  }

  List<Widget> _elevenVoice() {
    final voiceId = _store.voiceId;
    final voiceModel = _store.voiceModel;
    return [
      const Text(
        'Cole uma chave da ElevenLabs para ela falar com uma voz de lá. Cada resposta gasta créditos da sua conta, e o texto da resposta é enviado à ElevenLabs. Sem internet ou sem créditos, ela usa a voz do Android.',
        style: TextStyle(color: Look.dim, fontSize: 13, height: 1.4),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _voiceKey,
        obscureText: _voiceHidden,
        autocorrect: false,
        enableSuggestions: false,
        style: const TextStyle(fontFamily: Look.mono, color: Look.ink),
        decoration: InputDecoration(
          labelText: 'Chave da ElevenLabs (sk_...)',
          suffixIcon: IconButton(icon: Icon(_voiceHidden ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: Look.dim), onPressed: () => setState(() => _voiceHidden = !_voiceHidden)),
        ),
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(child: OutlinedButton(onPressed: () => _open('https://elevenlabs.io/app/developers/api-keys'), child: const Text('Criar chave'))),
          const SizedBox(width: 10),
          Expanded(child: FilledButton(onPressed: _voiceBusy ? null : _connectVoice, child: Text(_voiceBusy ? 'Conectando...' : 'Conectar'))),
        ],
      ),
      if (_voiceNote != null)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(_voiceNote!, style: TextStyle(color: _voiceBad ? Look.yellow : Look.dim, fontSize: 13, height: 1.4)),
        ),
      if (_voices.isNotEmpty) ...[
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: _voices.any((voice) => voice.id == voiceId) ? voiceId : null,
          isExpanded: true,
          dropdownColor: Look.panel,
          style: const TextStyle(fontFamily: Look.mono, color: Look.ink, fontSize: 14),
          decoration: const InputDecoration(labelText: 'Voz'),
          items: [for (final voice in _voices) DropdownMenuItem(value: voice.id, child: Text(voice.name, overflow: TextOverflow.ellipsis))],
          onChanged: (value) {
            setState(() {
              _store.voiceId = value;
              _store.voiceName = _voices.where((voice) => voice.id == value).map((voice) => voice.name).firstOrNull;
            });
          },
        ),
      ],
      if (_voiceModels.isNotEmpty) ...[
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: _voiceModels.contains(voiceModel) ? voiceModel : null,
          isExpanded: true,
          dropdownColor: Look.panel,
          style: const TextStyle(fontFamily: Look.mono, color: Look.ink, fontSize: 14),
          decoration: const InputDecoration(labelText: 'Modelo de voz'),
          items: [for (final id in _voiceModels) DropdownMenuItem(value: id, child: Text(id, overflow: TextOverflow.ellipsis))],
          onChanged: (value) => setState(() => _store.voiceModel = value),
        ),
      ],
      const SizedBox(height: 12),
    ];
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
            value: _store.voice,
            onChanged: (value) => setState(() => _store.voice = value),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Conversa contínua'),
            subtitle: const Text('Depois de responder, o microfone abre de novo sozinho', style: TextStyle(color: Look.dim, fontSize: 12)),
            value: _store.continuous,
            onChanged: (value) => setState(() => _store.continuous = value),
          ),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Voz do Android')),
              ButtonSegment(value: true, label: Text('ElevenLabs')),
            ],
            selected: {_store.eleven},
            onSelectionChanged: (picked) => setState(() => _store.eleven = picked.first),
          ),
          const SizedBox(height: 12),
          if (_store.eleven) ..._elevenVoice(),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(onPressed: _testVoice, icon: const Icon(Icons.volume_up_outlined, size: 18), label: const Text('Testar a voz')),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Cumprimento ao abrir'),
            subtitle: const Text('Voz original dela, em inglês', style: TextStyle(color: Look.dim, fontSize: 12)),
            value: _store.intro,
            onChanged: (value) => setState(() => _store.intro = value),
          ),
          _title('OLHOS E MÃOS'),
          ..._eyesAndHands(),
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
          const Text('Puxa conversa quando você some por', style: TextStyle(color: Look.dim, fontSize: 13)),
          const SizedBox(height: 6),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 10, label: Text('10 min')),
              ButtonSegment(value: 30, label: Text('30 min')),
              ButtonSegment(value: 120, label: Text('2 h')),
              ButtonSegment(value: 0, label: Text('Nunca')),
            ],
            selected: {_store.nudgeMinutes},
            onSelectionChanged: (picked) => setState(() => _store.nudgeMinutes = picked.first),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 6, bottom: 14),
            child: Text('Só com o app aberto ou com ela flutuando, e nunca entre 23h e 8h.', style: TextStyle(color: Look.dim, fontSize: 12)),
          ),
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
