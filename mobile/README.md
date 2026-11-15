# Capri para Android (Flutter)

Versão de bolso da Capri, refeita em Flutter a partir do app de Windows deste repositório. Feita para Android, pensando no Galaxy S25 FE. Uso pessoal e não comercial. Ainda não foi testada num aparelho.

## O que ela faz

- **Personagem animada** com os sprites originais: chega, pisca, dá glitch, sorri, dança, dorme e acorda, mexe a boca enquanto fala, senta na beirada com as pernas penduradas, fica pendurada quando você arrasta e passeia sozinha. Toque duas vezes para sentar ou levantar, segure para dançar, arraste para mover.
- **Conversa por texto e por voz** em português: o microfone usa o reconhecimento de fala do Android e as respostas saem pela voz pt-BR do sistema.
- **Cérebro no celular**: o Gemma 4 E2B roda dentro do aparelho (download de 2,6 GB, uma vez), sem chave e sem internet depois de baixar. É o mesmo modelo que o app de PC escolhe para máquinas médias, na versão para celular (LiteRT-LM).
- **Cérebro por chave**, como alternativa: chave grátis da NVIDIA, ou OpenAI, Anthropic e DeepSeek. A chave fica no cofre do Android.
- **Flutuar sobre outros apps**: o botão de janela na barra solta ela por cima do que estiver aberto. Arraste para mover, toque duas vezes para guardar.
- **Mainframe** (ícone do chip): chave e modelo, voz, apelido, tamanho das respostas e tempo até dormir.

## O que veio do original

| Original | Aqui |
| --- | --- |
| `assets/sprites/*.png`, `assets/voice/*.wav`, `assets/fonts/` | copiados em `mobile/assets/` |
| Quadros e velocidades das animações (`app/Capri.cs`) | `lib/sprite.dart` |
| Persona e regras dela (`app/Brain.cs`) | `lib/persona.dart`, adaptada para o celular |
| Provedores, escolha de modelo e erros (`app/Brain.cs`) | `lib/brain.dart` |
| Cores e fonte (`app/Talk.cs`) | `lib/look.dart` |

Ficaram de fora por enquanto: ela controlar o aparelho, voz da ElevenLabs e ver a tela.

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
