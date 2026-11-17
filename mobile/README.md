# Capri para Android (Flutter)

Versão de bolso da Capri, refeita em Flutter a partir do app de Windows deste repositório. Feita para Android, pensando no Galaxy S25 FE. Uso pessoal e não comercial. Ainda não foi testada num aparelho.

## O que ela faz

- **Personagem animada** com os sprites originais: chega, pisca, dá glitch, sorri, dança, dorme e acorda, mexe a boca enquanto fala, senta na beirada com as pernas penduradas, fica pendurada quando você arrasta e passeia sozinha. Toque duas vezes para sentar ou levantar, segure para dançar, arraste para mover.
- **Conversa por texto e por voz** em português: o microfone usa o reconhecimento de fala do Android e as respostas saem pela voz pt-BR do sistema.
- **Cérebro no celular**: o Gemma 4 E2B roda dentro do aparelho (download de 2,6 GB, uma vez), sem chave e sem internet depois de baixar. É o mesmo modelo que o app de PC escolhe para máquinas médias, na versão para celular (LiteRT-LM).
- **Cérebro por chave**, como alternativa: chave grátis da NVIDIA, ou OpenAI, Anthropic e DeepSeek. A chave fica no cofre do Android.
- **Flutuar sobre outros apps**: o botão de janela na barra solta ela por cima do que estiver aberto, com as mesmas animações: dois toques para sentar ou levantar, segurar e arrastar para mover (ela fica pendurada), segurar parada para dançar, e ela passeia pela tela sozinha. Toque no botão de novo para guardar.
- **Voz da ElevenLabs** (opcional): com a sua chave, ela fala pela API com a voz que você escolher, e a boca acompanha o áudio como no PC. Sem chave, usa a voz pt-BR do Android.
- **Mãos**: peça "abre o WhatsApp", "abre youtube.com", "toca Linkin Park no Spotify" ou "pesquisa a previsão do tempo em São Paulo". Ela abre o app ou o link, pede a música ao Spotify, YouTube ou YouTube Music, ou pesquisa no DuckDuckGo e responde com o que achou.
- **Dia a dia**: "lembra que meu aniversário é em março" (memória de longo prazo), "me acorda às 7h30", "timer de 10 minutos", "liga para a Ana", "manda whatsapp para o João dizendo que estou chegando" (ela deixa pronto e você envia), "me leva para o aeroporto". Ela também sabe o dia, a hora, a bateria e, com a cidade preenchida, o clima.
- **Ver e controlar a tela** (com a permissão de acessibilidade): "o que tem na tela?", "resume isso", "clica em Entrar", "rola pra baixo", "digita oi", "volta". Ela lê só o texto da tela, e pergunta antes de tocar em comprar, pagar, enviar ou apagar.
- **Notificações** (com o acesso às notificações): "o que chegou?" e, se você ligar, aviso quando chega mensagem.
- **Tarefas de vários passos** (com a permissão de tela): em pedidos como "abre o YouTube e procura lofi", ela lê a tela, escolhe uma ação, executa e repete, até 6, 10 ou 16 passos conforme o nível de inteligência. O andamento aparece em amarelo e dá para parar no botão vermelho. Ela nunca toca sozinha em comprar, pagar, enviar dinheiro ou apagar.
- **Enxergar a tela**: em "o que tem na tela?" ou "olha isso", ela recebe uma foto da tela além do texto (Android 11+). Funciona com modelos que aceitam imagem; o Gemma 4 E2B local tenta e, se não conseguir no aparelho, volta a usar só o texto.
- **Assistir você jogar** (opcional): flutuando, ela olha a tela a cada 1, 3 ou 5 minutos e comenta.
- **Tocando agora e fechar apps**: "o que está tocando?" (precisa do acesso às notificações) e "fecha o Discord".
- **Nível de inteligência e ajustes dela**: idioma (português, inglês, espanhol), tamanho, volume da voz, ritmo do passeio, quanto da conversa lembra, tempo do balão, efeito de digitação e dança.
- **Conversa fluida**: ela começa a falar a primeira frase enquanto ainda pensa no resto, e numa conversa por voz você pode falar por cima para ela parar e ouvir (ou tocar no microfone).
- **Chamar a Capri**: palavra de ativação "Capri" (offline, com o reconhecedor Vosk; opcional, gasta bateria), botão "Capri" nas configurações rápidas, widget animado na tela inicial, abrir flutuando ao ligar o celular e assistente padrão (segurar o botão lateral).
- **Agenda**: "o que tenho amanhã?", "minha agenda da semana" e "marca dentista sexta às 15h" (abre o calendário preenchido para você salvar).
- **Ler e responder mensagens** (opcional): ela lê a mensagem que chegou e, se você pedir, responde pelo botão de resposta da notificação, sempre depois do seu "sim".
- **Rotinas**: "bom dia" (clima, agenda e uma música) e "modo jogo" (flutua e passa a assistir e comentar).
- **Puxa conversa**: se você some por um tempo (10 min, 30 min ou 2 h, ou nunca), ela chama, com o app aberto ou flutuando, fora do horário de 23h às 8h.
- **Conversa pela janela flutuante**: toque nela para abrir o balão. Dá para digitar ou falar pelo microfone; o botão de infinito liga a conversa contínua (o microfone abre de novo depois de cada resposta) e o de alto-falante liga o modo silencioso (ela só escreve). Quem responde é o app, então ele precisa continuar aberto ao fundo.
- **Frases livres**: pedidos como "role a página do tiktok", "próximo vídeo", "pausa", "aumenta o volume" ou "curte esse vídeo" são entendidos sem fórmula fixa; quando a frase não bate com um comando conhecido, o cérebro escolhe a ação.
- **Mainframe** (ícone do chip): chave e modelo, voz, apelido, tamanho das respostas e tempo até dormir.

## O que veio do original

| Original | Aqui |
| --- | --- |
| `assets/sprites/*.png`, `assets/voice/*.wav`, `assets/fonts/` | copiados em `mobile/assets/` |
| Quadros e velocidades das animações (`app/Capri.cs`) | `lib/sprite.dart` |
| Persona e regras dela (`app/Brain.cs`) | `lib/persona.dart`, adaptada para o celular |
| Provedores, escolha de modelo e erros (`app/Brain.cs`) | `lib/brain.dart` |
| Cores e fonte (`app/Talk.cs`) | `lib/look.dart` |

Ficaram de fora por enquanto: ela controlar o aparelho e ver a tela.

## Como gerar o APK

**Pelo GitHub (sem instalar nada):** na aba Actions do repositório, ative os workflows, abra "Android (Flutter)" e clique em "Run workflow" no branch `flutter-android`. O APK aparece em Artifacts como `capri-android`.

**No seu PC**, com o Flutter instalado, dentro da pasta `mobile/`:

```
flutter create --platforms=android --org com.leandrosenno --project-name capri .
git checkout -- .
flutter pub get
flutter build apk --release --target-platform android-arm64
```

O `flutter create` gera a pasta `android/`; o `git checkout -- .` devolve o manifesto e os ícones deste repositório por cima do que foi gerado. O APK sai em `build/app/outputs/flutter-apk/app-release.apk`.

## Licença

Required Notice: Copyright 2026 Lachy (https://github.com/lachydotmcg)

PolyForm Noncommercial License 1.0.0, a mesma do projeto original (veja `LICENSE.md` na raiz). Projeto de fãs, não oficial e sem fins comerciais.
