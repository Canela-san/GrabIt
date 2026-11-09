# Contribuindo

*[English below](#contributing-in-english)*

Obrigado pelo interesse. Relatos de bugs, ideias e correções são bem-vindos, em português ou em inglês.

## Relatar um problema

Use o modelo de issue e cole a saída do `grabit diagnostico`: ela traz as versões, o sistema e o fim do último log, com links e cookies apagados. Confira o que vai colar, porque a issue é pública. Falhas de segurança vão em particular, como diz o [SECURITY.md](SECURITY.md).

## Como o projeto é feito

- O GrabIt é **um script Bash só**, o `grabit.sh`, e é distribuído assim: um arquivo, sem etapa de montagem. Ele precisa rodar no **Bash 4.4** ou mais novo, no Linux e no macOS.
- Toda mensagem mostrada a quem usa existe **em português e em inglês**, com a mesma chave em `idioma_pt` e em `idioma_en`. Os testes conferem que as duas línguas têm as mesmas chaves.
- Os comentários explicam o **porquê**, em português. O que o código faz, ele mesmo diz.
- Mudou algo para quem usa? Escreva no `CHANGELOG.md`, na seção da próxima versão, do ponto de vista de quem usa.

## Antes de enviar

```bash
bash testes/rodar.sh              # todos os testes: precisa de yt-dlp, ffmpeg e python3
bash testes/rodar.sh --rapido     # só os que não baixam nada
shellcheck -s bash -S warning grabit.sh testes/rodar.sh packaging/apt/*.sh
```

Os testes completos sobem um servidor local com vídeos gerados pelo FFmpeg, e um yt-dlp e um navegador de mentira: nada sai da máquina. `GRABIT_TESTES_J` limita quantos grupos rodam ao mesmo tempo. Um teste novo vai na seção do assunto, em `testes/rodar.sh`.

A CI roda tudo isso no Ubuntu e no macOS, com o Bash 4.4 e no WSL, a cada envio e uma vez por semana com o yt-dlp mais novo.

## Versões

Só o dono do projeto publica versões. Uma versão nova é `GRABIT_VERSAO` no script, uma seção `## X.Y.Z` no `CHANGELOG.md` e a etiqueta `vX.Y.Z`. A CI testa, publica, assina e atualiza o apt e o Homebrew.

---

## Contributing in English

Thanks for your interest. Bug reports, ideas and fixes are welcome, in Portuguese or English.

- **Reporting a problem:** use the issue template and paste the output of `grabit diagnostic` (versions, system and the end of the last log, with links and cookies removed). Check it first: issues are public. Security issues go privately, see [SECURITY.md](SECURITY.md).
- **How it's built:** GrabIt is a single Bash script, `grabit.sh`, shipped as is. It must run on Bash 4.4 or newer, on Linux and macOS. Every user-facing message exists in Portuguese and English, with the same key in `idioma_pt` and `idioma_en`. Comments explain the why, in Portuguese. User-facing changes go in `CHANGELOG.md`.
- **Before sending:** `bash testes/rodar.sh` (or `--rapido` for the quick ones) and `shellcheck -s bash -S warning grabit.sh testes/rodar.sh packaging/apt/*.sh`. The full tests run against a local server with generated videos: nothing leaves your machine.
