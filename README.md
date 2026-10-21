<p align="center">
  <img src="assets/logo.png" alt="GrabIt" width="200">
</p>

<h1 align="center">GrabIt</h1>

<p align="center">
  <strong>Baixe vídeos de qualquer site, em lote, sempre na qualidade máxima.</strong><br>
  Um único script Bash sobre o <a href="https://github.com/yt-dlp/yt-dlp">yt-dlp</a>, com painel ao vivo no terminal.
</p>

<p align="center">
  <img alt="Bash 4.4+" src="https://img.shields.io/badge/bash-4.4%2B-4EAA25?logo=gnubash&logoColor=white">
  <img alt="Motor: yt-dlp" src="https://img.shields.io/badge/motor-yt--dlp-red">
  <img alt="Linux e macOS" src="https://img.shields.io/badge/plataforma-Linux%20%7C%20macOS-informational">
</p>

<p align="center">
  <img src="assets/demo.png" alt="Painel do GrabIt baixando vários vídeos ao mesmo tempo" width="860">
</p>

## Por que o GrabIt?

- **Qualidade máxima, sempre.** Pega o melhor vídeo e o melhor áudio disponíveis (4K, 60 fps, HDR, som 5.1 — o que existir) e junta tudo num MKV, sem recomprimir nada.
- **Qualquer site.** Funciona com tudo o que o yt-dlp suporta: milhares de sites, playlists, canais e páginas com vídeo embutido.
- **Em lote e em paralelo.** Você entrega uma lista de links; ele baixa vários vídeos ao mesmo tempo, cada um com várias conexões.
- **Painel ao vivo.** Progresso, velocidade, tempo restante e a qualidade de cada download, sem a enxurrada de texto do yt-dlp. No fim, cada vídeo mostra o que *realmente* foi gravado (lido do arquivo com `ffprobe`).
- **Tudo dentro do arquivo.** Legendas, capa, capítulos e metadados vão embutidos no MKV.
- **Resiliente.** Falhas passageiras ganham nova tentativa automática, downloads interrompidos são retomados de onde pararam e os erros vêm explicados em português.
- **Não baixa duas vezes.** O que já existe na pasta é reconhecido e pulado.

## Instalação

### 1. Dependências

| Programa | Para quê | Como instalar |
|---|---|---|
| [yt-dlp](https://github.com/yt-dlp/yt-dlp) | o motor dos downloads | `pipx install "yt-dlp[default,curl-cffi]"` |
| [FFmpeg](https://ffmpeg.org) | juntar vídeo e áudio, gerar o MKV, tratar capas | `sudo apt install ffmpeg` · `brew install ffmpeg` |
| [Deno](https://deno.com) *(recomendado)* | exigido pelo YouTube para liberar as melhores resoluções | veja o site |
| Bash 4.4+ | rodar o script | já vem no Linux · no macOS: `brew install bash` |

> O `curl-cffi` permite imitar um navegador quando um site bloqueia downloads automáticos. É opcional, mas recomendado.

### 2. GrabIt

```bash
git clone https://github.com/Canela-san/GrabIt.git
cd GrabIt
chmod +x grabit.sh
```

Para usar o comando `grabit` em qualquer pasta (e atualizar com um simples `git pull`):

```bash
mkdir -p ~/.local/bin
ln -s "$PWD/grabit.sh" ~/.local/bin/grabit
```

## Uso

Crie um `links.txt` com um link por linha:

```text
# comentários e linhas vazias são ignorados
https://www.youtube.com/watch?v=XXXXXXXXXXX
https://vimeo.com/XXXXXXXXX          # dá para anotar no fim da linha
https://www.youtube.com/playlist?list=XXXXXXXXXXXXXXXX
```

E rode na mesma pasta:

```bash
grabit
```

Mais exemplos:

```bash
grabit https://youtu.be/XXXXXXXXXXX          # links direto no comando
grabit -l cursos.txt -o ~/Vídeos/Cursos      # outra lista, outra pasta
grabit -j 4 -c 8                             # 4 vídeos por vez, 8 conexões cada
grabit -b firefox                            # usa o login do navegador (vídeos restritos)
cat lista.txt | grabit -l -                  # lê os links da entrada padrão
```

### Opções

| Opção | O que faz | Padrão |
|---|---|---|
| `-l ARQUIVO` | arquivo com os links (`-` = entrada padrão) | `links.txt` |
| `-o PASTA` | pasta onde os vídeos são salvos | `./Downloads` |
| `-j N` | downloads simultâneos | `2` |
| `-c N` | conexões (fragmentos) por vídeo | `4` |
| `-b NAVEGADOR` | usa os cookies do navegador (`firefox`, `chrome`, `brave`…) | — |
| `-p` | se o link for de um vídeo dentro de uma playlist, baixa só o vídeo | — |
| `-a` | inclui legendas automáticas (as manuais continuam tendo prioridade) | — |
| `-s` | marca patrocínios e intros como capítulos ([SponsorBlock](https://sponsor.ajay.app)) | — |
| `-h` | mostra a ajuda | — |

Algumas configurações também podem vir de variáveis de ambiente:

| Variável | O que faz | Padrão |
|---|---|---|
| `IDIOMAS_LEGENDAS` | idiomas das legendas (`all` = todas) | `pt.*,en.*` |
| `TENTATIVAS` | tentativas por link (`1` = sem repetir) | `2` |
| `ARQUIVO_FALHAS` | onde salvar os links que falharam | `links_falhos.txt` |
| `NO_COLOR` | desliga as cores | — |

```bash
IDIOMAS_LEGENDAS=all TENTATIVAS=3 grabit
```

## No fim, um resumo

<p align="center">
  <img src="assets/resumo.png" alt="Resumo final do GrabIt" width="860">
</p>

| Símbolo | Significado |
|---|---|
| ✔ | baixado agora |
| ↷ | já existia na pasta, foi pulado |
| ✖ | falhou, com o motivo explicado logo abaixo |
| ⚠ | o vídeo está completo, mas algum detalhe falhou (ex.: converter a capa) |

Os links que falharam vão para `links_falhos.txt`, e o próprio GrabIt mostra o comando para tentar só eles de novo. Se todos derem certo na nova rodada, o arquivo é apagado sozinho.

## Como funciona

- **Formato:** `bv*+ba/b` do yt-dlp (melhor vídeo + melhor áudio) com saída em **MKV**, que aceita qualquer codec. Nada é recodificado.
- **Arquivos parciais** ficam em `Downloads/.parciais` e só o arquivo final pronto vai para a pasta. Cancelou com <kbd>Ctrl</kbd>+<kbd>C</kbd>? É só rodar de novo: o download continua de onde parou, e os links que ainda faltavam também vão para `links_falhos.txt`.
- **Novas tentativas:** erros passageiros (rede, 403, 429) voltam para o fim da fila, imitando um navegador quando o `curl-cffi` está instalado. Erros permanentes (vídeo privado, removido, 404) não são repetidos.
- **Logs:** a saída completa do yt-dlp para cada link com problema fica em `Downloads/logs/<data>/`.
- **Terminal:** o painel se adapta à largura da janela (inclusive se você redimensionar no meio), alinha títulos com emoji e caracteres asiáticos e, se a saída for redirecionada para um arquivo, troca o painel por linhas simples, sem cores.

## Dicas

- **Mantenha o yt-dlp atualizado** (`yt-dlp -U` ou `pipx upgrade yt-dlp`): os sites mudam o tempo todo. O GrabIt avisa quando a versão instalada está velha.
- **Vídeo pede login ou confirmação de idade?** Use `-b firefox` (ou o navegador em que você está logado).
- **Retomar o que falhou:** `grabit -l links_falhos.txt`.

## Aviso

O GrabIt é só uma ferramenta. Baixe apenas conteúdo que você tem direito de baixar e respeite os termos de uso de cada site e a lei de direitos autorais do seu país.

## Créditos

Feito sobre o [yt-dlp](https://github.com/yt-dlp/yt-dlp) e o [FFmpeg](https://ffmpeg.org), que fazem o trabalho pesado.
