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
  <a href="LICENSE"><img alt="Licença MIT" src="https://img.shields.io/badge/licen%C3%A7a-MIT-blue"></a>
</p>

<p align="center">
  <strong>Português</strong> · <a href="README.en.md">English</a>
</p>

<p align="center">
  <img src="assets/demo.png" alt="Painel do GrabIt baixando vários vídeos ao mesmo tempo" width="860">
</p>

## Por que o GrabIt?

- **Qualidade máxima, sempre.** Pega o melhor vídeo e o melhor áudio disponíveis (4K, 60 fps, HDR, som 5.1 — o que existir) e junta tudo num MKV, sem recomprimir nada. E nunca entrega um vídeo incompleto: se faltar um pedaço, o download falha e recomeça do zero.
- **Qualquer site.** Funciona com tudo o que o yt-dlp suporta: milhares de sites, playlists, canais e páginas com vídeo embutido.
- **Em lote e em paralelo.** Você entrega uma lista de links; ele baixa vários vídeos ao mesmo tempo, cada um com várias conexões.
- **Painel ao vivo.** Progresso, velocidade, tempo restante e a qualidade de cada download, sem a enxurrada de texto do yt-dlp. No fim, cada vídeo mostra o que *realmente* foi gravado (lido do arquivo com `ffprobe`).
- **Tudo dentro do arquivo.** Legendas, capa, capítulos e metadados vão embutidos no MKV.
- **Resiliente.** Falhas passageiras ganham nova tentativa automática e os erros vêm explicados em português (ou em inglês, se preferir).
- **Não baixa duas vezes.** Cada vídeo baixado entra num histórico; na próxima vez ele é pulado na hora, sem acessar o site nem mexer no arquivo — mesmo que você já o tenha movido para outra pasta.

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

Os links baixados com sucesso **saem da lista e vão para a seção `BAIXADOS`**, no fim do próprio `links.txt`, exatamente como você os escreveu (anotações incluídas). Tudo o que está nessa seção é ignorado: ela vira o seu histórico de links, e o GrabIt não perde tempo reprocessando nem listando o que já foi baixado. Os que falharam continuam em cima, prontos para a próxima vez.

```text
# comentários e linhas vazias são ignorados
https://vimeo.com/XXXXXXXXX          # este falhou e continua aqui

# ==================== BAIXADOS ====================
# Links já baixados com sucesso. O GrabIt ignora tudo daqui para baixo.
https://www.youtube.com/watch?v=XXXXXXXXXXX
https://www.youtube.com/playlist?list=XXXXXXXXXXXXXXXX
```

> Em inglês, a seção se chama `DOWNLOADED`; o GrabIt reconhece os dois nomes, então trocar de idioma não bagunça a lista.
>
> Pode editar o arquivo enquanto o GrabIt roda: ele é relido no fim, e o que você acrescentou não se perde. Quer baixar de novo algo da seção? Mova a linha para cima e rode com `-i` (veja o histórico em [Como funciona](#como-funciona)).

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
| `-r ALTURA` | resolução máxima (`720`, `1080`, `2160` ou `4k`…) | sem limite |
| `-F` | força: ignora os limites do `grabit.config` nesta execução | — |
| `-b NAVEGADOR` | usa os cookies do navegador (`firefox`, `chrome`, `brave`…) | — |
| `-p` | se o link for de um vídeo dentro de uma playlist, baixa só o vídeo | — |
| `-u` | em páginas com vários vídeos (prévias, relacionados…), baixa só o principal: o mais longo | — |
| `-a` | inclui legendas automáticas (as manuais continuam tendo prioridade) | — |
| `-s` | marca patrocínios e intros como capítulos ([SponsorBlock](https://sponsor.ajay.app)) | — |
| `-i` | ignora o histórico de baixados e confere arquivo por arquivo | — |
| `-L pt\|en` | idioma das mensagens: português ou inglês | o do sistema |
| `-h` | mostra a ajuda (`grabit -L en -h` mostra em inglês) | — |

## Configuração

Os padrões ficam no **`grabit.config`**, ao lado do `grabit.sh`. Ele é criado na primeira execução com todas as opções comentadas: para mudar uma, tire o `#` do começo da linha e edite o valor.

```ini
# grabit.config
PASTA_SAIDA=~/Vídeos/GrabIt
DOWNLOADS_SIMULTANEOS=3
COOKIES_NAVEGADOR=firefox
```

| Chave | O que faz | Padrão |
|---|---|---|
| `IDIOMA` | idioma das mensagens: `pt`, `en` ou `auto` (segue o sistema) | `auto` |
| `ARQUIVO_LINKS` | lista lida quando você roda só `grabit` | `links.txt` |
| `PASTA_SAIDA` | onde os vídeos são salvos | `./Downloads` |
| `RESOLUCAO_MAXIMA` | resolução máxima (`1080`, `2160`, `4k`…); `0` = sem limite | `0` |
| `RESOLUCAO_ALERTA` | avisa quando a melhor versão disponível fica abaixo disso; `0` = nunca | `720` |
| `DOWNLOADS_SIMULTANEOS` | vídeos ao mesmo tempo | `2` |
| `CONEXOES_POR_VIDEO` | conexões por vídeo | `4` |
| `TENTATIVAS` | tentativas por link (`1` = sem repetir) | `2` |
| `IDIOMAS_LEGENDAS` | idiomas das legendas (`all` = todas) | `pt.*,en.*` |
| `LEGENDAS_AUTOMATICAS` | `1` inclui legendas automáticas | `0` |
| `SPONSORBLOCK` | `1` marca patrocínios e intros como capítulos | `0` |
| `SEM_PLAYLIST` | `1` baixa só o vídeo quando o link também tem playlist | `0` |
| `SO_PRINCIPAL` | `1` baixa só o vídeo principal de páginas com vários vídeos (o mesmo que `-u`) | `0` |
| `COOKIES_NAVEGADOR` | navegador cujo login será usado | — |
| `USAR_HISTORICO` | `0` desliga o histórico de baixados | `1` |
| `ARQUIVO_FALHAS` | onde salvar os links que falharam | `links_falhos.txt` |

A prioridade é: **`grabit.config` < variável de ambiente < opção do comando**. Assim dá para mudar algo só uma vez sem editar o arquivo:

```bash
DOWNLOADS_SIMULTANEOS=4 grabit    # vale só nesta execução
grabit -j 4                       # idem, pela opção
grabit --config                   # mostra os valores em uso e de onde veio cada um
```

O arquivo fica fora do Git (`.gitignore`), então atualizar o GrabIt nunca mexe nas suas configurações. Para voltar aos padrões, basta apagá-lo: ele é recriado.

### Resolução máxima

Quer economizar espaço? Com `RESOLUCAO_MAXIMA=1080` o GrabIt baixa a **melhor versão até 1080p** de cada vídeo — continua escolhendo o melhor codec, fps e áudio dentro do limite. O limite vale para o lado menor da imagem, então um vídeo vertical de 1080×1920 conta como 1080p. Se um vídeo não tiver nenhuma versão dentro do limite, ele não é baixado: aparece como falha, com o aviso, e vai para o `links_falhos.txt`.

Para uma exceção, use `-F` (forçar): ele ignora os limites do `grabit.config` só naquela execução. Já o `-r` define um limite só para a execução, sem mexer no arquivo.

```bash
grabit -r 720                       # só desta vez, até 720p
grabit -F -l links_falhos.txt       # baixa os que ficaram de fora, na qualidade máxima
```

> Vídeos baixados com limite entram no histórico normalmente. Para trocar um deles por uma versão maior depois, apague o arquivo e rode com `-F -i`.

Também existem `ARQUIVO_HISTORICO` (onde fica o histórico de baixados) e `NO_COLOR` (desliga as cores), só como variáveis de ambiente.

## No fim, um resumo

<p align="center">
  <img src="assets/resumo.png" alt="Resumo final do GrabIt" width="860">
</p>

| Símbolo | Significado |
|---|---|
| ✔ | baixado agora |
| ↷ | já tinha sido baixado (pelo histórico ou porque o arquivo já estava na pasta), foi pulado |
| ✖ | falhou, com o motivo explicado logo abaixo |
| ⚠ | o vídeo está completo, mas algum detalhe falhou (ex.: converter a capa) |
| ▾ | baixado, mas a melhor versão que o site oferecia estava abaixo de `RESOLUCAO_ALERTA` (às vezes, com login, `-b`, há mais) |

Os links que falharam vão para `links_falhos.txt`, e o próprio GrabIt mostra o comando para tentar só eles de novo. Se todos derem certo na nova rodada, o arquivo é apagado sozinho.

## Como funciona

- **Formato:** `bv*+ba/b` do yt-dlp (melhor vídeo + melhor áudio) com saída em **MKV**, que aceita qualquer codec. Nada é recodificado.
- **Arquivos temporários** ficam em `Downloads/.parciais` só enquanto o GrabIt roda; o arquivo final, pronto, vai para a pasta. Um download que não terminou (<kbd>Ctrl</kbd>+<kbd>C</kbd>, erro, queda de rede) **recomeça do zero** na próxima vez, em vez de retomar os pedaços: a retomada pode deixar buracos no vídeo, e aqui a qualidade vem antes da velocidade. Os links que ainda faltavam vão para `links_falhos.txt`.
- **Novas tentativas:** erros passageiros (rede, 403, 429) voltam para o fim da fila, imitando um navegador quando o `curl-cffi` está instalado. Erros permanentes (vídeo privado, removido, 404) não são repetidos.
- **Histórico:** cada vídeo baixado é registrado em `Downloads/.grabit-historico.txt` (site + ID do vídeo). Nas próximas vezes ele é pulado antes de tudo: na maioria dos sites o GrabIt nem precisa abrir a página. Sem o histórico, o yt-dlp abriria a página de novo, baixaria a capa e reescreveria o arquivo inteiro só para concluir que ele já existe. Vídeos baixados antes do histórico existir passam por essa conferência uma única vez e já entram nele.
- **Vídeo principal (`-u`):** quando uma página tem vários vídeos, o GrabIt consulta antes a duração de cada um (pelo site ou, se ele não informar, lendo só o cabeçalho do vídeo) e baixa só o mais longo — prévias e relacionados costumam ser curtos. Links com um único vídeo não passam por essa etapa. Não use com playlists e canais: deles também sairia um vídeo só.
- **Logs:** a saída completa do yt-dlp para cada link com problema fica em `Downloads/logs/<data>/`.
- **Terminal:** o painel se adapta à largura da janela (inclusive se você redimensionar no meio), alinha títulos com emoji e caracteres asiáticos e, se a saída for redirecionada para um arquivo, troca o painel por linhas simples, sem cores.

## Dicas

- **Mantenha o yt-dlp atualizado** (`yt-dlp -U` ou `pipx upgrade yt-dlp`): os sites mudam o tempo todo. O GrabIt avisa quando a versão instalada está velha.
- **Vídeo pede login ou confirmação de idade?** Use `-b firefox` (ou o navegador em que você está logado).
- **Retomar o que falhou:** `grabit -l links_falhos.txt`.
- **Apagou um vídeo e quer baixá-lo de novo?** Rode com `-i` (ignora o histórico) ou apague a linha dele em `Downloads/.grabit-historico.txt`.

## Aviso

O GrabIt é só uma ferramenta. Baixe apenas conteúdo que você tem direito de baixar e respeite os termos de uso de cada site e a lei de direitos autorais do seu país.

## Créditos

Feito sobre o [yt-dlp](https://github.com/yt-dlp/yt-dlp) e o [FFmpeg](https://ffmpeg.org), que fazem o trabalho pesado.

## Licença

Distribuído sob a [licença MIT](LICENSE). Você pode usar, copiar, modificar e redistribuir o GrabIt à vontade, inclusive em projetos comerciais. A única condição é manter o aviso de copyright, com o crédito a **Gabriel Canela ([Canela-san](https://github.com/Canela-san))**, em todas as cópias ou partes substanciais do código.

Se o GrabIt te ajudou, um link para este repositório também é sempre bem-vindo.
