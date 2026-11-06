#!/usr/bin/env bash
# ==============================================================================
#  GrabIt (grabit.sh)  —  yt-dlp em lote · máxima qualidade · terminal limpo
#  https://github.com/Canela-san/GrabIt
#  Copyright (c) 2026 Gabriel Canela (Canela-san) · Licença MIT (veja LICENSE)
#  SPDX-License-Identifier: MIT
#
#  Ajuda: grabit -h  ·  Help in English: grabit -L en -h
# ==============================================================================

if [ -z "${BASH_VERSION:-}" ] || [ "${BASH_VERSINFO[0]}" -lt 4 ] ||
   { [ "${BASH_VERSINFO[0]}" -eq 4 ] && [ "${BASH_VERSINFO[1]}" -lt 4 ]; }; then
  echo "O GrabIt precisa do Bash 4.4 ou superior (execute com: bash grabit.sh)." >&2
  echo "GrabIt needs Bash 4.4 or newer (run it with: bash grabit.sh)." >&2
  echo "macOS: brew install bash" >&2
  exit 1
fi

set -uo pipefail
shopt -s extglob

PATH_ORIGINAL=$PATH

# O idioma do sistema é lido antes de forçar o UTF-8 logo abaixo
LOCALE_ORIGINAL=${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}

# Garante UTF-8 (necessário para os símbolos e para medir a largura do texto). Quem
# responde é o próprio Bash: "é" tem que contar 1 caractere, não 2 bytes. (Perguntar ao
# programa "locale" engana: com um LANG que não existe no sistema e um LC_CTYPE válido,
# ele diz UTF-8, mas o Bash fica no locale C.)
utf8_teste="é"
if (( ${#utf8_teste} != 1 )); then
  for loc in C.UTF-8 C.utf8 en_US.UTF-8 pt_BR.UTF-8 UTF-8; do
    export LC_ALL=$loc 2>/dev/null
    (( ${#utf8_teste} == 1 )) && break
    unset LC_ALL
  done
fi
unset utf8_teste loc
export PYTHONUNBUFFERED=1 PYTHONIOENCODING=utf-8

# Modo auxiliar da verificação completa (-v): o yt-dlp chama o GrabIt assim depois de
# cada vídeo (--exec). O ffmpeg decodifica o arquivo inteiro e qualquer erro reprova o
# vídeo: ele é guardado com outro nome (para não contar como "já baixado") e, com o
# código 86, o yt-dlp não o registra no histórico. O painel lê as linhas @@V@@.
if [[ ${1:-} == --verificar-arquivo ]]; then
  sufixo=$2 arq=$3 dur=${4%%.*}
  [[ $dur =~ ^[1-9][0-9]*$ ]] || dur=$(ffprobe -v error -show_entries format=duration -of csv=p=0 -- "$arq" 2>/dev/null)
  dur=${dur%%.*}; [[ $dur =~ ^[0-9]+$ ]] || dur=0
  ruim="${arq%.*}${sufixo}.${arq##*.}"
  erros=$(mktemp) || exit 1
  # Ctrl+C chega a todos os processos: um ffmpeg interrompido (ou reclamando do cano
  # fechado) não pode ser confundido com um arquivo com defeito.
  trap 'rm -f -- "$erros"; exit 130' INT TERM HUP
  ffmpeg -nostdin -hide_banner -v error -i "$arq" -map '0:v?' -map '0:a?' \
         -f null -progress pipe:1 -nostats - 2>"$erros" |
    while IFS='=' read -r k v; do
      [[ $k == out_time_us && $v =~ ^[0-9]+$ ]] && printf '@@V@@%d\x1f%d\n' $(( v / 1000000 )) "$dur"
    done
  (( PIPESTATUS[0] == 255 )) && { rm -f -- "$erros"; exit 130; }   # o ffmpeg recebeu um sinal
  if [[ -s $erros ]]; then
    printf '@@V@@ERRO %s\n' "$(head -c 400 "$erros" | tr '\r\n' '  ' | sed -E 's/\[[^]]* @ 0x[0-9a-f]+\] //g')"
    rm -f -- "$erros"; mv -f -- "$arq" "$ruim"
    exit 86
  fi
  rm -f -- "$erros" "$ruim"                   # passou: some a cópia ruim de uma tentativa anterior
  exit 0
fi

# Modo auxiliar do -m (Jellyfin/Plex/Kodi): o yt-dlp chama o GrabIt assim depois de cada
# vídeo. Lê os metadados que o próprio yt-dlp gravou no arquivo e escreve, ao lado dele,
# o .nfo do episódio (e o tvshow.nfo do canal, se ainda não existir).
if [[ ${1:-} == --nfo ]]; then
  arq=$2; base=${arq%.*}; serie_dir=${arq%/*}; serie_dir=${serie_dir%/*}; serie=${serie_dir##*/}
  # o nome da pasta traz os sósias que o yt-dlp usa no lugar de / : ? e cia.; o título não
  serie=${serie//⧸//}; serie=${serie//⧹/\\}; serie=${serie//：/:}; serie=${serie//？/?}; serie=${serie//＊/*}
  serie=${serie//＂/\"}; serie=${serie//＜/<}; serie=${serie//＞/>}; serie=${serie//｜/|}
  declare -A tag=()
  while IFS= read -r l; do                    # format_tags_TITLE="…" (o ffprobe escapa \ " e \n)
    [[ $l =~ ^format_tags_([A-Za-z0-9_]+)=\"(.*)\"$ ]] || continue
    v=${BASH_REMATCH[2]}
    v=${v//\\\\/$'\x01'}; v=${v//\\n/$'\n'}; v=${v//\\r/}; v=${v//\\\"/\"}; v=${v//$'\x01'/\\}
    tag[${BASH_REMATCH[1],,}]=$v
  done < <(ffprobe -v error -show_entries format_tags -of flat=s=_ -- "$arq" 2>/dev/null)
  # (substituições entre aspas: no Bash 5.2+ um & solto vira "o trecho encontrado")
  xml() { local v=${1//&/"&amp;"}; v=${v//</"&lt;"}; v=${v//>/"&gt;"}; XML=${v//\"/"&quot;"}; }
  data=${tag[date]:-}
  [[ $data =~ ^([0-9]{4})([0-9]{2})([0-9]{2})$ ]] && data="${BASH_REMATCH[1]}-${BASH_REMATCH[2]}-${BASH_REMATCH[3]}"
  {
    printf '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<episodedetails>\n'
    xml "${tag[title]:-${base##*/}}";  printf '  <title>%s</title>\n' "$XML"
    xml "$serie";                      printf '  <showtitle>%s</showtitle>\n' "$XML"
    [[ -n $data ]] &&                  printf '  <aired>%s</aired>\n  <premiered>%s</premiered>\n' "$data" "$data"
    xml "${tag[description]:-${tag[synopsis]:-}}"
    [[ -n $XML ]] &&                   printf '  <plot>%s</plot>\n' "$XML"
    for img in "$base".{jpg,png,webp,avif}; do
      if [[ -f $img ]]; then xml "${img##*/}"; printf '  <thumb>%s</thumb>\n' "$XML"; break; fi
    done
    printf '</episodedetails>\n'
  } > "$base.nfo.tmp" && mv -f -- "$base.nfo.tmp" "$base.nfo"
  if [[ ! -e $serie_dir/tvshow.nfo ]]; then
    xml "$serie"
    printf '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<tvshow>\n  <title>%s</title>\n</tvshow>\n' \
      "$XML" > "$serie_dir/tvshow.nfo"
  fi
  exit 0
fi

# ───────────────────────────── Configuração ───────────────────────────────────
# Onde o GrabIt mora de verdade (seguindo links simbólicos, como ~/.local/bin/grabit):
# é ali, ao lado do script, que fica o grabit.config.
resolve_caminho() {                           # resolve_caminho ARQUIVO → CAMINHO_REAL
  local f=$1 alvo dir
  while [[ -L $f ]]; do
    alvo=$(readlink -- "$f"); dir=$(cd -P -- "$(dirname -- "$f")" && pwd)
    if [[ $alvo == /* ]]; then f=$alvo; else f="$dir/$alvo"; fi
  done
  dir=$(cd -P -- "$(dirname -- "$f")" && pwd)
  CAMINHO_REAL="$dir/${f##*/}"
}
resolve_caminho "$0"
GRABIT_SCRIPT=$CAMINHO_REAL
GRABIT_DIR=${GRABIT_SCRIPT%/*}
CONFIG_ARQ="${GRABIT_CONFIG:-$GRABIT_DIR/grabit.config}"

# Chaves aceitas no grabit.config (e como variáveis de ambiente). Prioridade, da menor
# para a maior: padrão do script < grabit.config < variável de ambiente < opção do comando.
CHAVES_CONFIG=(IDIOMA ARQUIVO_LINKS PASTA_SAIDA RESOLUCAO_MAXIMA RESOLUCAO_ALERTA SO_AUDIO FORMATO_AUDIO DOWNLOADS_SIMULTANEOS CONEXOES_POR_VIDEO TENTATIVAS
  LIMITE_POR_SITE PAUSA_ENTRE_VIDEOS LIMITE_VELOCIDADE
  IDIOMAS_LEGENDAS LEGENDAS_AUTOMATICAS SPONSORBLOCK SEM_PLAYLIST SO_PRINCIPAL VERIFICAR COOKIES_NAVEGADOR
  USER_AGENT OPCOES_YTDLP USAR_NAVEGADOR PROGRAMA_NAVEGADOR USAR_HISTORICO ARQUIVO_FALHAS NOTIFICAR NTFY_TOPICO)
declare -A DO_AMBIENTE=() ORIGEM=()
for k in "${CHAVES_CONFIG[@]}"; do [[ -v $k ]] && DO_AMBIENTE[$k]=${!k}; done

IDIOMA=auto                                   # pt, en ou auto (pelo idioma do sistema)
ARQUIVO_LINKS=links.txt
PASTA_SAIDA=./Downloads
RESOLUCAO_MAXIMA=0                            # altura máxima (1080, 2160…); 0 = sem limite
RESOLUCAO_ALERTA=720                          # avisa quando o melhor disponível é menor; 0 = nunca
SO_AUDIO=0                                    # 1 = baixa só o áudio
FORMATO_AUDIO=original                        # original (sem recomprimir), mp3, m4a, opus, flac…
DOWNLOADS_SIMULTANEOS=4                       # vídeos ao mesmo tempo
CONEXOES_POR_VIDEO=4                          # fragmentos por vídeo
TENTATIVAS=2                                  # tentativas por link (1 = sem repetir)
LIMITE_POR_SITE=0                             # downloads ao mesmo tempo do mesmo site (0 = automático)
PAUSA_ENTRE_VIDEOS=0                          # segundos de espera antes de cada vídeo
LIMITE_VELOCIDADE=0                           # por download, ex.: 5M ou 500K (0 = livre)
IDIOMAS_LEGENDAS='pt.*,en.*'                  # "all" para todas
LEGENDAS_AUTOMATICAS=0                        # 1 = inclui legendas automáticas
SPONSORBLOCK=0                                # 1 = marca patrocínios/intros como capítulos
SEM_PLAYLIST=0                                # 1 = link vídeo+playlist baixa só o vídeo
SO_PRINCIPAL=0                                # 1 = página com vários vídeos baixa só o principal
VERIFICAR=0                                   # 1 = decodifica cada vídeo inteiro para achar defeitos
COOKIES_NAVEGADOR=                            # ex.: firefox, chrome, brave
USER_AGENT=                                   # o User-Agent do navegador (para usar junto com os cookies)
OPCOES_YTDLP=                                 # opções a mais para o yt-dlp, separadas por espaços
USAR_NAVEGADOR=1                              # 0 = nunca abrir um navegador para achar o vídeo
PROGRAMA_NAVEGADOR=                           # vazio = procura Firefox, Chrome, Chromium, Brave, Edge…
USAR_HISTORICO=1                              # 0 = não pula o que já foi baixado antes
ARQUIVO_FALHAS=links_falhos.txt
NOTIFICAR=1                                   # sino + notificação no fim (lotes de 1 min ou mais)
NTFY_TOPICO=                                  # tópico do ntfy.sh (ou URL completa) para avisar no celular
HIST_DO_AMBIENTE=${ARQUIVO_HISTORICO:+1}
ARQUIVO_HISTORICO="${ARQUIVO_HISTORICO:-}"    # padrão: <pasta de saída>/.grabit-historico.txt
TEMPLATE_SAIDA='%(title).180B [%(id)s].%(ext)s'
CONFIG_CRIADO=0; AVISOS_CONFIG=(); N_AJUSTES_CONFIG=0

# carrega_config: lê CHAVE=valor do grabit.config (sem executar nada do arquivo). Valores
# podem vir entre aspas; "# comentário" no fim da linha é ignorado.
carrega_config() {
  local linha chave valor n=0
  [[ -f $CONFIG_ARQ && -r $CONFIG_ARQ ]] || return 0
  while IFS= read -r linha || [[ -n $linha ]]; do
    n=$(( n + 1 ))
    linha=${linha%$'\r'}
    [[ $linha =~ ^[[:space:]]*(#|$) ]] && continue
    if [[ $linha =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
      chave=${BASH_REMATCH[1]}; valor=${BASH_REMATCH[2]}
      valor=${valor%%[[:space:]]#*}
      valor=${valor%"${valor##*[![:space:]]}"}
      if [[ $valor == \"*\" || $valor == \'*\' ]] && (( ${#valor} >= 2 )); then valor=${valor:1:-1}; fi
      if [[ " ${CHAVES_CONFIG[*]} " == *" $chave "* ]]; then
        printf -v "$chave" '%s' "$valor"; ORIGEM[$chave]=config
        N_AJUSTES_CONFIG=$(( N_AJUSTES_CONFIG + 1 ))
      else
        AVISOS_CONFIG+=("$n: $chave")
      fi
    else
      AVISOS_CONFIG+=("$n: $linha")
    fi
  done < "$CONFIG_ARQ"
}
carrega_config
for k in "${!DO_AMBIENTE[@]}"; do printf -v "$k" '%s' "${DO_AMBIENTE[$k]}"; ORIGEM[$k]=ambiente; done

# "grabit curl 'https://…' -H …": o comando copiado do navegador, colado depois de "grabit".
# O que vem depois do link é dele, não do GrabIt (um -L ali não é o idioma, por exemplo).
CURL_ARGS=()
for (( i = 1; i <= $#; i++ )); do
  a=${!i}; j=$(( i + 1 ))
  if [[ ( $a == curl || $a == --curl ) && ${!j:-} == http?(s)://* ]]; then
    CURL_ARGS=("${@:j}")
    set -- "${@:1:i}"
    break
  fi
done

# ───────────────────────────── Idioma ─────────────────────────────────────────
# -L é lido antes do getopts, para que até os erros nas opções saiam no idioma certo.
# Percorre as opções como o getopts faria (aceita -L en, -Len e -sL en).
for (( i = 1; i <= $#; i++ )); do
  a=${!i}
  [[ $a == -- ]] && break
  [[ $a == --* ]] && continue                   # --config, --help…
  [[ $a == -?* ]] || continue                   # link ou arquivo: pode haver opções depois
  for (( c = 1; c < ${#a}; c++ )); do
    case ${a:c:1} in
      L)         j=$(( i + 1 )); IDIOMA=${a:c+1}; [[ -z $IDIOMA ]] && { IDIOMA=${!j:-}; i=$j; }
                 ORIGEM[IDIOMA]=opção; break ;;
      [lojcbrA]) [[ -z ${a:c+1} ]] && i=$(( i + 1 )); break ;;   # o valor é o próximo argumento
    esac
  done
done
unset a c i j

# resolve_idioma VALOR → LINGUA (pt|en); "auto" segue o sistema (sem idioma definido: pt)
IDIOMA_INVALIDO=""
resolve_idioma() {
  case ${1,,} in
    pt|pt-br|pt_br|portugues|português) LINGUA=pt ;;
    en|en-us|en_us|english|ingles|inglês) LINGUA=en ;;
    auto|"")
      case ${LOCALE_ORIGINAL,,} in
        pt*|""|c|c.*|posix) LINGUA=pt ;;
        *)                  LINGUA=en ;;
      esac ;;
    *) IDIOMA_INVALIDO=$1; resolve_idioma auto ;;
  esac
}
resolve_idioma "$IDIOMA"

declare -A T=()
# t CHAVE [ARGS...] → TXT: o texto no idioma atual (com ARGS, a frase é um formato do printf)
t() {
  local f=${T[$1]-$1}
  shift
  # shellcheck disable=SC2059
  if (( $# )); then printf -v TXT "$f" "$@"; else TXT=$f; fi
}

idioma_pt() {
  T=(
    [titulo]="GrabIt  ·  Downloader em lote  ·  Máxima qualidade (MKV)"
    [titulo_curto]="GrabIt · Downloader em lote"
    [opcao_invalida]="Opção inválida: %s"
    [opcao_valor]="A opção -%s precisa de um valor."
    [idioma_invalido]="Idioma desconhecido: '%s' (use pt ou en). Usando: %s."
    [origem_opção]="opção do comando"
    [origem_config]="grabit.config"
    [origem_ambiente]="variável de ambiente"
    [origem_padrão]="padrão"
    [val_numero]="%s precisa ser um número inteiro maior que zero (recebi '%s', de: %s)."
    [val_01]="%s precisa ser 0 ou 1 (recebi '%s', de: %s)."
    [val_resolucao]="%s precisa ser uma altura como 720, 1080 ou 2160, ou 0 para não limitar (recebi '%s', de: %s)."
    [val_audio]="%s precisa ser original, mp3, m4a, aac, opus, flac, wav, alac ou vorbis (recebi '%s', de: %s)."
    [cfg_criado]="(criado agora)"
    [cfg_inexistente]="(não existe e não pôde ser criado)"
    [cfg_linha]="grabit.config, linha %s: ignorada (chave desconhecida ou sem \"=\"):%s"
    [kv_links]="Links"
    [kv_destino]="Destino"
    [kv_config]="Config"
    [kv_historico]="Histórico"
    [kv_paralelo]="Paralelo"
    [kv_extras]="Extras"
    [kv_ferramentas]="Ferramentas"
    [kv_recursos]="Recursos"
    [kv_limites]="Limites"
    [lim_res]="até %dp"
    [lim_site]="%d vídeo(s) por site"
    [lim_pausa]="pausa de ~%d s"
    [lim_vel]="%s/s por vídeo"
    [lim_f]=" · -F ignora"
    [lim_desligados]="%sdesligados (-F)%s · ignorando: %s"
    [lim_ignorando]=" · -F desligou: %s"
    [et_pausa]="pausa entre vídeos (%s s)"
    [val_inteiro0]="%s precisa ser um número inteiro, 0 para desligar (recebi '%s', de: %s)."
    [val_velocidade]="%s precisa ser uma velocidade como 5M ou 500K, ou 0 para não limitar (recebi '%s', de: %s)."
    [kv_config_criado]="%scriado agora%s em %s — edite para mudar os padrões"
    [kv_config_ajustes]="grabit.config · %d ajuste(s) · grabit --config mostra tudo"
    [kv_hist_on]="%s vídeo(s) registrados · os já baixados são pulados"
    [kv_hist_off]="%signorado (-i)%s: confere arquivo por arquivo"
    [kv_paralelo_v]="%d vídeo(s) × %d conexões"
    [kv_tentativas]=" · até %d tentativas"
    [kv_legendas]="legendas %s"
    [kv_automaticas]=" (+automáticas)"
    [kv_extras_resto]=", capa, capítulos, metadados"
    [kv_principal]=", só o vídeo principal de cada página"
    [kv_verificar]=", verificação completa"
    [kv_modo]="Modo"
    [kv_subpastas]="<site>/<canal>/"
    [kv_midia]="<canal>/Season <ano>/  (Jellyfin, Plex, Kodi)"
    [kv_nfo]=", .nfo"
    [et_nfo]="gravando o .nfo"
    [kv_audio_original]="só áudio · a melhor faixa, no formato original (sem recomprimir)"
    [kv_audio_conv]="só áudio · convertido para %s"
    [kv_extras_audio]="capa, capítulos, metadados"
    [imp_indisp]="indisponível"
    [imp_retry]="nas novas tentativas"
    [imp_off]="desligado (TENTATIVAS=1)"
    [js_nenhum]="nenhum"
    [links_ignorados]=" · ignorados:%s"
    [links_repetidos]=" %d repetido(s)"
    [links_sem_link]=" %d linha(s) sem link"
    [links_na_secao]=" · %d já na seção BAIXADOS"
    [links_sites]=" · %d sites"
    [fonte_stdin]="entrada padrão"
    [fonte_cli]="linha de comando"
    [av_linhas]="Terminal com só %s linhas: limitei a %d download(s) simultâneo(s)."
    [av_linhas2]="     (pedido: %d — aumente a janela para ver todos no painel)"
    [av_ytdlp]="Seu yt-dlp (%s) está desatualizado: os sites mudam o tempo todo."
    [av_ytdlp2]="     Atualize:  %s"
    [av_curl]="curl_cffi ausente: sites com proteção anti-robô podem falhar."
    [av_curl2]="     Instale com:  %s"
    [av_js]="Sem runtime JavaScript: o YouTube pode falhar ou vir em qualidade menor."
    [av_js_velho]="O yt-dlp não aceita o %s (versão antiga demais): o YouTube pode falhar ou vir em qualidade menor."
    [av_js2]="     Para instalar o Deno:  %s"
    [js_velho]="%s (antigo demais para o yt-dlp)"
    [s_js_dica]="                       O runtime mais garantido é o Deno: https://deno.com"
    [av_disco]="Só %s livres em %s: os vídeos podem não caber."
    [d_disco_para]="Disco cheio: nenhum download novo vai começar; os que faltam vão para a lista de falhas."
    [f_antes]=" (mais %d de execuções anteriores)"
    [kv_situacao]="Situação"
    [ver_em_dia]="em dia com o repositório"
    [ver_nova]="há uma versão mais nova"
    [ver_sem_net]="não deu para conferir (sem conexão?)"
    [ver_sem_git]="cópia sem Git"
    [dica_ctrlc]="Ctrl+C cancela · o que estiver pela metade recomeça do zero"
    [dica_teclas]="p pausa · q termina depois dos atuais · + e - mudam quantos baixam ao mesmo tempo"
    [k_pausado]="pausado · p continua"
    [k_parando]="terminando os downloads atuais · q de novo cancela"
    [k_simultaneos]="%d download(s) ao mesmo tempo"
    [notif_msg]="Terminou: %d baixado(s), %d já existia(m), %d com erro · %s"
    [notif_sem_curl]="Para avisar no celular (NTFY_TOPICO) é preciso o curl."
    [notif_falhou]="Não consegui enviar o aviso para %s."
    [kv_ntfy]=", aviso no celular"
    [fv_aguardando]="fila viva: acrescente links em %s · q sai"
    [fv_novos]="%d link(s) novo(s) na fila"
    [fv_titulo]="aguardando links"
    [fv_sem_arquivo]="-f vigia arquivos de links, mas a lista veio do comando ou da entrada padrão: nada a vigiar."
    [kv_fila_viva]="Fila viva"
    [kv_fv]="ligada (-f): o GrabIt continua aberto esperando novos links · q sai"
    [kv_captura]="Captura"
    [kv_upgrade]="upgrade (-U): troca os vídeos já baixados por versões melhores, se o site tiver"
    [dep_instalador]="     Para instalar tudo de uma vez: %s"
    [ins_titulo]="GrabIt · instalação das dependências"
    [ins_sem_ger]="Não achei um gerenciador de pacotes conhecido (apt, dnf, pacman, zypper, apk ou brew)."
    [ins_manual]="Instale à mão pelo sistema: %s"
    [ins_p_sistema]="instalar pelo %s: %s"
    [ins_p_ytdlp]="instalar o yt-dlp (com curl-cffi) pelo pipx"
    [ins_p_curlcffi]="acrescentar o curl-cffi ao yt-dlp (para imitar um navegador)"
    [ins_p_deno]="instalar o Deno, exigido pelo YouTube (instalador oficial, na sua pasta pessoal)"
    [ins_p_comando]="criar o comando grabit (%s)"
    [ins_nada]="Tudo o que o GrabIt usa já está instalado."
    [ins_vai]="O GrabIt vai:"
    [ins_continuar]="Continuar? [S/n]"
    [ins_cancelado]="Nada foi feito."
    [ins_ok]="feito"
    [ins_falhou]="falhou (veja as mensagens acima)"
    [ins_path]="A pasta ~/.local/bin não está no seu PATH. Acrescente ao ~/.bashrc (ou ~/.zshrc): %s"
    [ins_pronto]="Pronto! Rode: grabit -h"
    [ins_path_novo]="Abra um novo terminal para o comando grabit (e o yt-dlp) entrarem no PATH."
    [atu_titulo]="GrabIt · atualização"
    [atu_git]="atualizar o GrabIt (git pull)"
    [atu_baixa]="baixar a versão mais nova do GrabIt"
    [atu_igual]="o GrabIt já está na versão mais nova"
    [atu_trocado]="GrabIt atualizado"
    [atu_sem_escrita]="Sem permissão para gravar em %s: rode com sudo ou atualize à mão."
    [vc_titulo]="GrabIt · verificação dos vídeos já baixados"
    [vc_sem_pasta]="A pasta '%s' não existe."
    [vc_vazio]="Nenhum vídeo ou áudio para verificar nesta pasta."
    [vc_arquivos_r]="Arquivos"
    [vc_arquivos]="%d vídeo(s) e áudio(s)"
    [vc_dica]="Cada arquivo é decodificado do começo ao fim: pode demorar · Ctrl+C para"
    [vc_verificando]="verificando"
    [vc_ilegivel]="o ffprobe não consegue ler o arquivo"
    [vc_defeito]="com defeito"
    [vc_incompleto]="incompleto"
    [vc_incompleto_det]="tem %s de %s"
    [vc_s_titulo]="Verificação"
    [vc_s_parcial]="Verificação interrompida"
    [vc_s_ok]="Perfeitos"
    [vc_s_defeito]="Com defeito"
    [vc_s_incompleto]="Incompletos"
    [vc_sem_link]="%d arquivo(s) com problema não têm o link registrado (só os MKV do GrabIt têm): baixe-os de novo à mão."
    [vc_terminal]="Para baixar de novo os que têm problema, rode grabit --verificar num terminal."
    [vc_pergunta]="Baixar de novo os %d com problema? O arquivo atual fica com %s no nome. [S/n]"
    [bx_cab]="%s · seção BAIXADOS · %d link(s)"
    [bx_vazia]="A seção BAIXADOS está vazia."
    [bx_ajuda]="  grabit --baixados editar          abre só a seção no seu editor
  grabit --baixados voltar 3 5      devolve os links 3 e 5 para a lista de baixar
  grabit --baixados marcar LINK…    põe links na seção sem baixá-los
  grabit --baixados limpar          esvazia a seção (guarda uma cópia .bak)
  Para outro arquivo de links: grabit -l ARQUIVO --baixados …"
    [bx_limpar_p]="Apagar os %d links da seção BAIXADOS de %s? Uma cópia fica em %s. [s/N]"
    [bx_limpo]="Seção esvaziada (%d links)."
    [bx_historico]="O histórico de vídeos continua valendo: para baixar de novo um vídeo que já foi baixado, use -i."
    [bx_voltar_uso]="Diga quais: grabit --baixados voltar 3 5 (os números saem em grabit --baixados)."
    [bx_numero]="'%s' não é um número da lista (vai de 1 a %d)."
    [bx_voltou]="%d link(s) de volta à lista de baixar."
    [bx_marcar_uso]="Diga quais: grabit --baixados marcar LINK…"
    [bx_nao_link]="'%s' não é um link (http ou https)."
    [bx_a_mao]="marcado à mão"
    [bx_marcou]="%d link(s) marcados como baixados."
    [bx_sem_editor]="Nenhum editor encontrado: defina a variável EDITOR (ex.: EDITOR=nano)."
    [bx_sem_terminal]="Para editar é preciso um terminal."
    [bx_ed_cab]="#: Seção BAIXADOS — apague as linhas dos links que quer tirar daqui e acrescente
#: links (um por linha) para marcá-los como baixados. Para devolver um link à lista
#: de baixar, mova-o para baixo da última linha. Salve e feche para aplicar."
    [bx_ed_volta]="#: ============ abaixo daqui: volta para a lista de baixar ============"
    [bx_nada_mudou]="Nada mudou."
    [bx_editado]="Seção atualizada: %d link(s) nela, %d de volta à lista de baixar."
    [bx_acao]="Ação desconhecida: '%s'."
    [atu_ytdlp]="atualizar o yt-dlp e as dependências dele"
    [atu_deno]="atualizar o Deno"
    [atu_pacote_p]="atualizar o %s (%s)"
    [atu_sem_senha]="Há uma versão nova do %s, mas instalá-la pede a senha do sudo: rode de novo num terminal."
    [atu_pronto]="Tudo na versão mais nova."
    [cmd_instalar]="--instalar"
    [cmd_atualizar]="--atualizar"
    [atu_pacote]="Este yt-dlp veio do gerenciador de pacotes, que costuma ficar para trás: prefira pipx install \"yt-dlp[default,curl-cffi]\"."
    [et_upgrade]="comparando com o vídeo já baixado"
    [r_sem_melhor]="nenhuma versão melhor que %sp"
    [r_sem_melhor_n]="%d sem versão melhor"
    [r_fora_n]="%d fora da pasta"
    [r_fora]="não está na pasta (pulado)"
    [up_audio]="-U compara a qualidade de vídeo; com -x ele fica desligado."
    [up_fila]="-U trabalha com a lista que já existe; -f e -C ficam desligados."
    [kv_clip]="área de transferência (%s): links copiados vão para %s e entram na fila"
    [clip_aguardando]="copie um link para baixar · q sai"
    [clip_capturado]="%d link(s) capturado(s) da área de transferência"
    [clip_origem]="(área de transferência)"
    [clip_stdin]="-C anota os links capturados no arquivo de links, então ele não pode ser a entrada padrão (-l -)."
    [clip_sem]="-C precisa de um programa que leia a área de transferência."
    [clip_sem2]="     Instale um: wl-clipboard (Wayland), xclip ou xsel (X11); no macOS o pbpaste já vem instalado."
    [dep_faltando]="Faltando: %s"
    [dep_instale]="instale '%s' pelo gerenciador de pacotes do sistema"
    [sem_arquivo]="O arquivo '%s' não foi encontrado."
    [sem_arquivo2]="     Crie-o com um link por linha, use  -l CAMINHO  ou passe os links no próprio comando."
    [nada_1]="Nada para baixar: o único link de %s já está na seção BAIXADOS."
    [nada_n]="Nada para baixar: os %d links de %s já estão na seção BAIXADOS."
    [sem_links]="Nenhum link válido (http/https) em: %s."
    [nada]="nada"
    [marca]="# ==================== BAIXADOS ===================="
    [marca_desc]="# Links já baixados com sucesso. O GrabIt ignora tudo até o fim desta seção."
    [marca_fim]="# ================ FIM DOS BAIXADOS ================"
    [tentativa_n]="%dª tentativa · "
    [ni_tentativa]="(%dª tentativa)"
    [log_tentativa]="# ── tentativa %d ──"
    [tipo_legendas]="legendas"
    [tipo_audio]="áudio"
    [tipo_video]="vídeo"
    [total]="Total"
    [restam]="faltam ≈%s"
    [et_finalizando]="finalizando"
    [et_mesclando]="mesclando vídeo e áudio"
    [et_mkv]="convertendo para MKV"
    [et_metadados]="gravando metadados"
    [et_legendas_emb]="embutindo legendas"
    [et_capa_emb]="embutindo a capa"
    [et_capitulos]="processando capítulos"
    [et_fixup]="corrigindo o arquivo"
    [et_legendas]="baixando legendas"
    [et_capa]="baixando a capa"
    [et_hist]="já baixado antes (histórico)"
    [et_existe]="arquivo já existe"
    [et_iniciando]="iniciando download"
    [et_principal]="procurando o vídeo principal da página"
    [et_verificando]="verificando o arquivo"
    [et_processando]="processando"
    [et_item]="obtendo informações · item %s/%s"
    [et_info]="obtendo informações"
    [r_ja_existia]="já existia"
    [r_ja_baixado]="já baixado antes"
    [r_n_ja_baixados]="%d já baixados antes"
    [r_concluido]="concluído"
    [r_aviso]="aviso:"
    [r_av_capa]="a capa não converteu para JPG e foi embutida no formato original"
    [r_av_sponsor]="não deu para consultar o SponsorBlock"
    [r_av_outro]="uma etapa de acabamento falhou (detalhes no log)"
    [r_av_completo]="%s — o vídeo está completo"
    [r_parcial]="parcial"
    [r_falhou]="falhou"
    [r_falhou_n]="falhou %d×"
    [r_codigo]="yt-dlp terminou com código %d"
    [d_privado]="vídeo privado"
    [d_idade]="restrito por idade — use -b NAVEGADOR"
    [d_bot]="o YouTube pediu login — use -b NAVEGADOR"
    [d_membros]="exclusivo para membros"
    [d_regiao]="bloqueado na sua região"
    [d_removido]="vídeo indisponível ou removido"
    [d_url]="nenhum vídeo reconhecido nesta página"
    [d_url_invalida]="link não suportado"
    [d_antirobo]="o site pede a verificação anti-robô"
    [d_login]="precisa de login — use -b NAVEGADOR"
    [d_drm]="protegido por DRM: o GrabIt não baixa"
    [d_ssl]="certificado do site inválido"
    [s_nav_tit]="Se o vídeo toca no seu navegador, dá para baixá-lo:"
    [s_nav_b]="     · Passe pela verificação no navegador e use a sessão dele:  %s"
    [s_nav_b2]="       (se ainda recusar, acrescente -A com o User Agent do navegador)"
    [s_nav_c]="     · Ou dê play, aperte F12, aba Rede, filtre por m3u8 (o master, se houver) ou mp4, clique com o direito no pedido, Copiar como cURL, e rode:  %s"
    [curl_sem_py]="grabit curl precisa do python3 para ler o comando copiado."
    [curl_invalido]="Isso não é um comando cURL com um link. Na aba Rede do navegador (F12), clique com o direito no pedido do vídeo e escolha Copiar como cURL."
    [curl_colar]="     Também dá para colar o comando depois de grabit:  grabit curl 'https://…' -H …"
    [clip_wayland]="No Wayland, ler a área de transferência precisa do wl-clipboard. Para instalar:  %s"
    [et_navegador]="no navegador · faça a verificação ou dê play, se precisar"
    [nav_abrindo]="Este site precisa de um navegador: vou abrir o %s. Se aparecer uma verificação, é só fazê-la na janela."
    [k_freio]="%s pediu para ir mais devagar: no máximo %d download(s) ao mesmo tempo desse site, e o próximo daqui a %d s"
    [k_parado]="%s está recusando os pedidos: os links que faltam dele ficam para depois, e os outros sites continuam"
    [k_espera_site]="aguardando %s liberar (%d s) · q sai"
    [k_espera_ant]="%s pediu calma há pouco: os links dele começam daqui a %d s (-F não espera)"
    [s_adiados]="Adiados"
    [s_adiados_det]="(o site estava recusando: tente mais tarde)"
    [ins_q_curlcffi]="Instalar o curl-cffi? Ajuda quando um site bloqueia downloads automáticos. [S/n]"
    [ins_q_deno]="Instalar o Deno? O YouTube exige um runtime JavaScript para liberar as melhores resoluções. [S/n]"
    [ins_q_clip]="Instalar o %s? Serve para capturar links copiados (-C) e ler o cURL copiado. [S/n]"
    [ins_q_nav]="Instalar o Firefox? Só é útil em sites que funcionam apenas num navegador, e você não tem nenhum que o GrabIt use. [s/N]"
    [ins_nav_nota]="Nenhum navegador compatível: sites que só funcionam num navegador não serão baixados. Para instalar um: grabit install firefox (ou chromium, chrome, brave, edge)."
    [ins_nav_desconhecido]="Navegador desconhecido: '%s'. Dá para pedir firefox, chromium, chrome, brave ou edge."
    [ins_nav_ja]="O %s já está instalado."
    [ins_nav_site]="O %s não está no gerenciador de pacotes deste sistema. Baixe em: %s"
    [nav_sem_video]="nenhum vídeo apareceu no navegador (a janela fechou ou o tempo acabou)"
    [nav_sem_navegador]="     Com o Firefox ou o Chrome instalado, o GrabIt faz isso sozinho."
    [curl_sem_clip]="Não consegui ler a área de transferência. Guarde o comando num arquivo e rode:  %s"
    [curl_sem_arquivo]="O arquivo '%s' não foi encontrado."
    [kv_curl]="cURL do navegador · %d cabeçalho(s), %d cookie(s) · arquivo: %s"
    [curl_falhou]="O link copiado costuma expirar: se falhou por isso, copie o cURL de novo."
    [d_live]="a live/estreia ainda não começou"
    [d_404]="não encontrado (404)"
    [d_disco]="disco cheio"
    [d_invalido]="o arquivo baixado não é um vídeo válido"
    [d_fragmento]="um pedaço do vídeo não baixou"
    [d_403]="acesso negado (403)"
    [d_429]="muitas requisições (429)"
    [d_rede]="falha de rede"
    [d_resolucao]="nenhuma versão até %dp — use -F para baixar mesmo assim"
    [d_resolucao_r]="nenhuma versão até %dp (-r)"
    [nota_n]="%d vídeos · %s e outros"
    [nota_n0]="%d vídeos"
    [sufixo_ruim]=".com-erros"
    [d_verificacao]="o arquivo tem defeitos (ficou com %s no nome)"
    [r_baixa]="resolução baixa:"
    [r_baixa_det]="%dp era a melhor versão disponível (com login, -b, às vezes há mais)"
    [s_baixa]="Baixa resolução"
    [s_baixa_det]="%d vídeo(s) abaixo de %dp"
    [s_resumo]="Resumo"
    [s_resumo_parcial]="Resumo parcial"
    [s_baixados]="Baixados"
    [s_ja]="Já existiam"
    [s_erro]="Links com erro"
    [s_aviso]="Com aviso"
    [s_aviso_det]="(arquivos completos · logs em %s/)"
    [s_tempo]="Tempo"
    [s_baixado_agora]="Baixado agora"
    [s_media]="(média de %s/s)"
    [s_pasta]="Pasta"
    [s_lista]="Lista"
    [s_movidos]="%d link(s) movidos para a seção BAIXADOS"
    [f_todos_ok]="Todos os links de %s deram certo — arquivo removido."
    [f_nao_gravou]="Não consegui gravar '%s'."
    [f_com_erro]="com erro"
    [f_erro_pend]="com erro ou pendentes"
    [f_pend]="pendentes"
    [f_salvos]="%d link(s) %s salvos em %s"
    [f_logs]=" — logs em %s/"
    [f_continuar]="     Para continuar:  %s"
    [c_cancelado]="Cancelado."
    [c_descartado]=" O que estava pela metade foi descartado e recomeça do zero na próxima vez."
    [tmp_falhou]="Não consegui criar a pasta temporária."
    [pasta_falhou]="Não consegui criar a pasta '%s'."
  )
  T[ajuda]=$(cat <<'EOF'
Uso:  grabit [opções] [LINK ou ARQUIVO ...]

  -l ARQUIVO    arquivo com os links ("-" = entrada padrão)  (padrão: links.txt)
  -o PASTA      pasta onde os vídeos serão salvos            (padrão: ./Downloads)
  -j N          downloads simultâneos                        (padrão: 4)
  -c N          conexões (fragmentos) por vídeo              (padrão: 4)
  -r ALTURA     resolução máxima: 720, 1080, 2160, 4k…       (padrão: sem limite)
  -F            força: ignora os limites do grabit.config (resolução, sites, pausa…)
  -b NAVEGADOR  usa os cookies do navegador (firefox, chrome, brave…)
  -A AGENTE     usa o User-Agent do navegador, junto com -b, em sites com verificação
  -p            só o vídeo, se o link tiver vídeo + playlist
  -u            só o vídeo principal (o mais longo) de páginas com vários vídeos
  -x            só o áudio (a melhor faixa, sem recomprimir)
  -d            organiza em subpastas por site e canal: Downloads/site/canal/
  -m            para Jellyfin, Plex e Kodi: canal/Season ano/, com .nfo e capa
  -f            fila viva: depois da lista, continua aberto baixando o que você
                acrescentar no arquivo de links (q ou Ctrl+C para sair)
  -U            upgrade: confere os vídeos já baixados (inclusive os da seção
                BAIXADOS) e troca pelos que hoje têm versão melhor no site
  -C            captura: com o GrabIt aberto, todo link que você copiar entra na
                fila (anotado no links.txt); nada fica rodando depois que ele fecha
  -a            inclui legendas automáticas (a manual continua tendo prioridade)
  -s            marca patrocínios/intros como capítulos (SponsorBlock)
  -i            ignora o histórico de baixados (confere arquivo por arquivo)
  -v            verificação completa: decodifica cada vídeo inteiro atrás de defeitos
  -L pt|en      idioma das mensagens (Language)
  -h            mostra esta ajuda

Comandos, em português ou inglês, com ou sem os traços (grabit update é o mesmo
que grabit --atualizar):

  config             mostra o grabit.config e os valores em uso
  instalar, install  instala o que falta (ffmpeg, yt-dlp…) e o comando grabit, e pergunta
                     sobre o que é opcional; com -y, instala tudo sem perguntar (navegador, só
                     se não houver nenhum compatível, e aí só o Firefox)
  instalar NAVEGADOR instala um navegador a pedido: firefox, chromium, chrome, brave ou edge
  atualizar, update  deixa tudo na versão mais nova (GrabIt, yt-dlp, Deno e FFmpeg)
                     e instala o que faltar
  versao, version    mostra a versão instalada, se há outra mais nova e o que o GrabIt usa
  curl [ARQUIVO]     baixa o que toca no navegador, pelo "Copiar como cURL" da aba Rede (F12):
                     lê a área de transferência, um arquivo ou, com -, a entrada padrão;
                     também dá para colar o comando copiado depois de grabit
  verificar, check [PASTA]
                     confere os vídeos já baixados (defeitos e incompletos)
                     e oferece baixar de novo os que tiverem problema
  baixados, downloaded [AÇÃO]
                     lista a seção BAIXADOS; ações: editar, voltar N…, marcar LINK…, limpar
  ajuda, help        mostra esta ajuda

• Um arquivo de links com o nome de um comando precisa de ./ na frente: grabit ./update
• Links e arquivos de links também podem vir direto no comando (aí o
  links.txt só é lido se você passar -l), e as opções valem antes ou depois deles:
      grabit https://youtu.be/xxxx outra_lista.txt -j 4
• Nos arquivos: linhas vazias e comentários (# …, inclusive no fim da linha)
  são ignorados, assim como texto em volta do link; repetidos são descartados.
• Links baixados com sucesso vão para a seção "# ===== BAIXADOS =====" no fim
  do próprio arquivo. Tudo nessa seção é ignorado: vira o seu histórico de links.
• Cada vídeo baixado entra no histórico (Downloads/.grabit-historico.txt): da
  próxima vez ele é pulado na hora, sem acessar o site nem mexer no arquivo.
  Apagou um vídeo e quer baixá-lo de novo? Use -i ou apague a linha dele lá.
• Link que falha por motivo passageiro (rede, 403…) ganha nova tentativa no
  fim da fila, imitando um navegador (--impersonate) se houver curl_cffi.
• Links que falharem vão para links_falhos.txt, prontos para reexecutar:
      grabit -l links_falhos.txt
• Download que não terminou (Ctrl+C, erro) recomeça do zero na próxima vez:
  retomar pedaços não garante a qualidade. A pasta Downloads/.parciais só existe
  enquanto o GrabIt roda.

Configurações permanentes ficam no grabit.config, ao lado do grabit.sh (criado
na primeira execução, com todos os padrões comentados): grabit --config
Prioridade: grabit.config < variável de ambiente < opção do comando, ex.:
    DOWNLOADS_SIMULTANEOS=3 grabit        grabit -j 3
EOF
)
  T[modelo_config]=$(cat <<'EOF'
# ==============================================================================
#  grabit.config — configurações do GrabIt
#
#  Criado automaticamente na primeira execução, com todos os padrões comentados.
#  Para mudar um valor, tire o "#" do começo da linha e edite. Para voltar ao
#  padrão, comente a linha de novo (ou apague este arquivo: ele é recriado).
#
#  Prioridade: este arquivo < variáveis de ambiente < opções do comando.
#  Veja os valores em uso com: grabit --config
# ==============================================================================

# Idioma das mensagens: pt, en ou auto (pelo idioma do sistema) (-L)
#IDIOMA=auto

# Lista de links lida quando você roda só "grabit"
#ARQUIVO_LINKS=links.txt

# Pasta onde os vídeos são salvos
#PASTA_SAIDA=./Downloads

# Resolução máxima: 720, 1080, 1440, 2160 (ou 4k)…; 0 = sem limite (-r). Vale para o
# lado menor da imagem: um vídeo vertical de 1080×1920 conta como 1080p. Vídeo sem
# nenhuma versão dentro do limite falha com um aviso; -F ignora o limite numa execução.
#RESOLUCAO_MAXIMA=0

# Avisa quando a melhor versão que o site oferece fica abaixo desta resolução (0 = nunca)
#RESOLUCAO_ALERTA=720

# Só áudio (-x): a melhor faixa de som, no formato em que o site entrega (original, sem
# recomprimir) ou convertida para mp3, m4a, aac, opus, flac, wav, alac ou vorbis.
# Tem um histórico próprio, separado do dos vídeos.
#SO_AUDIO=0
#FORMATO_AUDIO=original

# Quantos vídeos baixar ao mesmo tempo (-j) e conexões por vídeo (-c)
#DOWNLOADS_SIMULTANEOS=4
#CONEXOES_POR_VIDEO=4

# Tentativas por link quando a falha é passageira (1 = não tentar de novo)
#TENTATIVAS=2

# Cortesia com os sites (ajuda com os que bloqueiam muitos downloads seguidos): no
# máximo N downloads ao mesmo tempo do mesmo site, uma pausa de N segundos (com uma
# variação aleatória) antes de cada vídeo e uma velocidade máxima por download, como
# 5M ou 500K. 0 = desligado. -F ignora tudo isso numa execução.
#LIMITE_POR_SITE=0
#PAUSA_ENTRE_VIDEOS=0
#LIMITE_VELOCIDADE=0

# Idiomas das legendas ("all" = todas) e se inclui as automáticas (-a)
#IDIOMAS_LEGENDAS=pt.*,en.*
#LEGENDAS_AUTOMATICAS=0

# Marca patrocínios/intros como capítulos com o SponsorBlock (-s)
#SPONSORBLOCK=0

# Link de vídeo dentro de playlist: baixar só o vídeo (-p)
#SEM_PLAYLIST=0

# Página com vários vídeos (prévias, relacionados…): baixar só o principal, o mais longo (-u)
#SO_PRINCIPAL=0

# Verificação completa: decodifica cada vídeo baixado do começo ao fim e, se achar um
# defeito, baixa de novo do zero. Garante o arquivo perfeito, mas usa CPU e tempo (-v)
#VERIFICAR=0

# Usar os cookies (login) de um navegador: firefox, chrome, brave… (-b)
#COOKIES_NAVEGADOR=

# O User-Agent desse navegador (-A). Sites com verificação anti-robô só aceitam os cookies
# junto com ele. No Firefox, ele aparece em about:support.
#USER_AGENT=

# Opções a mais para o yt-dlp, separadas por espaços. Ex.: --force-ipv4 --no-check-certificates
#OPCOES_YTDLP=

# Quando a página só funciona num navegador (player em JavaScript, verificação anti-robô), abrir
# um, num perfil só do GrabIt, para achar o vídeo. Uma verificação, se aparecer, é você quem faz
# na janela. 0 = nunca abrir. Vale o que já estiver instalado: Firefox, Chrome, Chromium, Brave,
# Edge…; para escolher, ponha o nome do programa em PROGRAMA_NAVEGADOR.
#USAR_NAVEGADOR=1
#PROGRAMA_NAVEGADOR=

# Pular na hora os vídeos já baixados antes (0 = conferir sempre; o mesmo que -i)
#USAR_HISTORICO=1

# Onde salvar os links que falharam
#ARQUIVO_FALHAS=links_falhos.txt

# No fim de um lote que levou 1 minuto ou mais: sino do terminal e notificação na área
# de trabalho (notify-send no Linux, central de notificações no macOS). 0 = silêncio.
#NOTIFICAR=1

# Aviso no celular pelo ntfy (https://ntfy.sh): instale o app, assine um tópico com um
# nome difícil de adivinhar e coloque-o aqui (ou a URL completa de um servidor seu).
# Vai só o resumo (quantos baixaram e quantos falharam), nunca os links ou os títulos.
#NTFY_TOPICO=
EOF
)
}

idioma_en() {
  T=(
    [titulo]="GrabIt  ·  Batch downloader  ·  Maximum quality (MKV)"
    [titulo_curto]="GrabIt · Batch downloader"
    [opcao_invalida]="Invalid option: %s"
    [opcao_valor]="Option -%s needs a value."
    [idioma_invalido]="Unknown language: '%s' (use pt or en). Using: %s."
    [origem_opção]="command-line option"
    [origem_config]="grabit.config"
    [origem_ambiente]="environment variable"
    [origem_padrão]="default"
    [val_numero]="%s must be a whole number greater than zero (got '%s', from: %s)."
    [val_01]="%s must be 0 or 1 (got '%s', from: %s)."
    [val_resolucao]="%s must be a height like 720, 1080 or 2160, or 0 for no limit (got '%s', from: %s)."
    [val_audio]="%s must be original, mp3, m4a, aac, opus, flac, wav, alac or vorbis (got '%s', from: %s)."
    [cfg_criado]="(just created)"
    [cfg_inexistente]="(missing and could not be created)"
    [cfg_linha]="grabit.config, line %s: ignored (unknown key or no \"=\"):%s"
    [kv_links]="Links"
    [kv_destino]="Destination"
    [kv_config]="Config"
    [kv_historico]="History"
    [kv_paralelo]="Parallel"
    [kv_extras]="Extras"
    [kv_ferramentas]="Tools"
    [kv_recursos]="Features"
    [kv_limites]="Limits"
    [lim_res]="up to %dp"
    [lim_site]="%d video(s) per site"
    [lim_pausa]="~%d s pause"
    [lim_vel]="%s/s per video"
    [lim_f]=" · -F ignores them"
    [lim_desligados]="%soff (-F)%s · ignoring: %s"
    [lim_ignorando]=" · -F turned off: %s"
    [et_pausa]="pause between videos (%s s)"
    [val_inteiro0]="%s must be a whole number, 0 to turn it off (got '%s', from: %s)."
    [val_velocidade]="%s must be a speed like 5M or 500K, or 0 for no limit (got '%s', from: %s)."
    [kv_config_criado]="%sjust created%s at %s — edit it to change the defaults"
    [kv_config_ajustes]="grabit.config · %d setting(s) · grabit --config shows all"
    [kv_hist_on]="%s video(s) recorded · already downloaded ones are skipped"
    [kv_hist_off]="%signored (-i)%s: checks file by file"
    [kv_paralelo_v]="%d video(s) × %d connections"
    [kv_tentativas]=" · up to %d attempts"
    [kv_legendas]="subtitles %s"
    [kv_automaticas]=" (+automatic)"
    [kv_extras_resto]=", cover, chapters, metadata"
    [kv_principal]=", only each page's main video"
    [kv_verificar]=", full check"
    [kv_modo]="Mode"
    [kv_subpastas]="<site>/<channel>/"
    [kv_midia]="<channel>/Season <year>/  (Jellyfin, Plex, Kodi)"
    [kv_nfo]=", .nfo"
    [et_nfo]="writing the .nfo"
    [kv_audio_original]="audio only · the best track, in its original format (no re-encoding)"
    [kv_audio_conv]="audio only · converted to %s"
    [kv_extras_audio]="cover, chapters, metadata"
    [imp_indisp]="unavailable"
    [imp_retry]="on retries"
    [imp_off]="off (TENTATIVAS=1)"
    [js_nenhum]="none"
    [links_ignorados]=" · ignored:%s"
    [links_repetidos]=" %d duplicate(s)"
    [links_sem_link]=" %d line(s) without a link"
    [links_na_secao]=" · %d already in the DOWNLOADED section"
    [links_sites]=" · %d sites"
    [fonte_stdin]="standard input"
    [fonte_cli]="command line"
    [av_linhas]="The terminal has only %s rows: limited to %d simultaneous download(s)."
    [av_linhas2]="     (requested: %d — enlarge the window to see them all)"
    [av_ytdlp]="Your yt-dlp (%s) is outdated: websites change all the time."
    [av_ytdlp2]="     Update:  %s"
    [av_curl]="curl_cffi is missing: sites with anti-bot protection may fail."
    [av_curl2]="     Install it with:  %s"
    [av_js]="No JavaScript runtime: YouTube may fail or come in lower quality."
    [av_js_velho]="yt-dlp doesn't accept %s (version too old): YouTube may fail or come in lower quality."
    [av_js2]="     To install Deno:  %s"
    [js_velho]="%s (too old for yt-dlp)"
    [s_js_dica]="                       The safest runtime is Deno: https://deno.com"
    [av_disco]="Only %s free in %s: the videos may not fit."
    [d_disco_para]="Disk full: no new download will start; the rest go to the failed list."
    [f_antes]=" (plus %d from earlier runs)"
    [kv_situacao]="Status"
    [ver_em_dia]="up to date with the repository"
    [ver_nova]="there's a newer version"
    [ver_sem_net]="couldn't check (no connection?)"
    [ver_sem_git]="copy without Git"
    [dica_ctrlc]="Ctrl+C cancels · anything half-done starts over from scratch"
    [dica_teclas]="p pauses · q stops after the current ones · + and - change how many run at once"
    [k_pausado]="paused · p resumes"
    [k_parando]="finishing the current downloads · q again cancels"
    [k_simultaneos]="%d download(s) at once"
    [notif_msg]="Done: %d downloaded, %d already there, %d failed · %s"
    [notif_sem_curl]="Phone notifications (NTFY_TOPICO) need curl."
    [notif_falhou]="Couldn't send the notification to %s."
    [kv_ntfy]=", phone notification"
    [fv_aguardando]="live queue: add links to %s · q quits"
    [fv_novos]="%d new link(s) in the queue"
    [fv_titulo]="waiting for links"
    [fv_sem_arquivo]="-f watches link files, but the list came from the command line or standard input: nothing to watch."
    [kv_fila_viva]="Live queue"
    [kv_fv]="on (-f): GrabIt stays open waiting for new links · q quits"
    [kv_captura]="Capture"
    [kv_upgrade]="upgrade (-U): replaces videos already downloaded with better versions, if the site has them"
    [dep_instalador]="     To install everything at once: %s"
    [ins_titulo]="GrabIt · installing dependencies"
    [ins_sem_ger]="Couldn't find a known package manager (apt, dnf, pacman, zypper, apk or brew)."
    [ins_manual]="Install these through your system: %s"
    [ins_p_sistema]="install with %s: %s"
    [ins_p_ytdlp]="install yt-dlp (with curl-cffi) through pipx"
    [ins_p_curlcffi]="add curl-cffi to yt-dlp (to impersonate a browser)"
    [ins_p_deno]="install Deno, required by YouTube (official installer, in your home folder)"
    [ins_p_comando]="create the grabit command (%s)"
    [ins_nada]="Everything GrabIt uses is already installed."
    [ins_vai]="GrabIt is going to:"
    [ins_continuar]="Continue? [Y/n]"
    [ins_cancelado]="Nothing was done."
    [ins_ok]="done"
    [ins_falhou]="failed (see the messages above)"
    [ins_path]="The ~/.local/bin folder isn't in your PATH. Add this to ~/.bashrc (or ~/.zshrc): %s"
    [ins_pronto]="Done! Run: grabit -h"
    [ins_path_novo]="Open a new terminal so the grabit command (and yt-dlp) are in your PATH."
    [atu_titulo]="GrabIt · update"
    [atu_git]="update GrabIt (git pull)"
    [atu_baixa]="download the newest GrabIt"
    [atu_igual]="GrabIt is already the newest version"
    [atu_trocado]="GrabIt updated"
    [atu_sem_escrita]="No permission to write to %s: run it with sudo or update by hand."
    [vc_titulo]="GrabIt · checking the videos already downloaded"
    [vc_sem_pasta]="Folder '%s' doesn't exist."
    [vc_vazio]="No video or audio to check in this folder."
    [vc_arquivos_r]="Files"
    [vc_arquivos]="%d video(s) and audio file(s)"
    [vc_dica]="Each file is decoded from start to end: it may take a while · Ctrl+C stops"
    [vc_verificando]="checking"
    [vc_ilegivel]="ffprobe can't read the file"
    [vc_defeito]="defective"
    [vc_incompleto]="incomplete"
    [vc_incompleto_det]="has %s of %s"
    [vc_s_titulo]="Check"
    [vc_s_parcial]="Check interrupted"
    [vc_s_ok]="Flawless"
    [vc_s_defeito]="Defective"
    [vc_s_incompleto]="Incomplete"
    [vc_sem_link]="%d file(s) with problems have no recorded link (only GrabIt's MKVs do): download them again by hand."
    [vc_terminal]="To download the problem ones again, run grabit --check in a terminal."
    [vc_pergunta]="Download the %d problem one(s) again? The current file keeps %s in its name. [Y/n]"
    [bx_cab]="%s · DOWNLOADED section · %d link(s)"
    [bx_vazia]="The DOWNLOADED section is empty."
    [bx_ajuda]="  grabit --downloaded edit          open just the section in your editor
  grabit --downloaded back 3 5      send links 3 and 5 back to the list to download
  grabit --downloaded add LINK…     put links in the section without downloading them
  grabit --downloaded clear         empty the section (keeps a .bak copy)
  For another link file: grabit -l FILE --downloaded …"
    [bx_limpar_p]="Delete the %d links in the DOWNLOADED section of %s? A copy stays in %s. [y/N]"
    [bx_limpo]="Section emptied (%d links)."
    [bx_historico]="The video history still applies: to download again a video already downloaded, use -i."
    [bx_voltar_uso]="Say which: grabit --downloaded back 3 5 (the numbers come from grabit --downloaded)."
    [bx_numero]="'%s' isn't a number in the list (it goes from 1 to %d)."
    [bx_voltou]="%d link(s) back in the list to download."
    [bx_marcar_uso]="Say which: grabit --downloaded add LINK…"
    [bx_nao_link]="'%s' isn't a link (http or https)."
    [bx_a_mao]="marked by hand"
    [bx_marcou]="%d link(s) marked as downloaded."
    [bx_sem_editor]="No editor found: set the EDITOR variable (e.g. EDITOR=nano)."
    [bx_sem_terminal]="Editing needs a terminal."
    [bx_ed_cab]="#: DOWNLOADED section — delete the lines of the links you want out of here and add
#: links (one per line) to mark them as downloaded. To send a link back to the list
#: to download, move it below the last line. Save and close to apply."
    [bx_ed_volta]="#: ============ below here: back to the list to download ============"
    [bx_nada_mudou]="Nothing changed."
    [bx_editado]="Section updated: %d link(s) in it, %d back in the list to download."
    [bx_acao]="Unknown action: '%s'."
    [atu_ytdlp]="update yt-dlp and its dependencies"
    [atu_deno]="update Deno"
    [atu_pacote_p]="update %s (%s)"
    [atu_sem_senha]="There's a new version of %s, but installing it needs the sudo password: run this again in a terminal."
    [atu_pronto]="Everything is on the newest version."
    [cmd_instalar]="--install"
    [cmd_atualizar]="--update"
    [atu_pacote]="This yt-dlp came from the package manager, which tends to lag behind: prefer pipx install \"yt-dlp[default,curl-cffi]\"."
    [et_upgrade]="comparing with the video already downloaded"
    [r_sem_melhor]="no version better than %sp"
    [r_sem_melhor_n]="%d with no better version"
    [r_fora_n]="%d not in the folder"
    [r_fora]="not in the folder (skipped)"
    [up_audio]="-U compares video quality; with -x it's turned off."
    [up_fila]="-U works on the list that already exists; -f and -C are turned off."
    [kv_clip]="clipboard (%s): copied links go to %s and join the queue"
    [clip_aguardando]="copy a link to download it · q quits"
    [clip_capturado]="%d link(s) captured from the clipboard"
    [clip_origem]="(clipboard)"
    [clip_stdin]="-C writes the captured links to the link file, so it can't be standard input (-l -)."
    [clip_sem]="-C needs a program that reads the clipboard."
    [clip_sem2]="     Install one: wl-clipboard (Wayland), xclip or xsel (X11); on macOS pbpaste is already there."
    [dep_faltando]="Missing: %s"
    [dep_instale]="install '%s' with your system's package manager"
    [sem_arquivo]="File '%s' not found."
    [sem_arquivo2]="     Create it with one link per line, use  -l PATH  or pass the links on the command line."
    [nada_1]="Nothing to download: the only link in %s is already in the DOWNLOADED section."
    [nada_n]="Nothing to download: all %d links in %s are already in the DOWNLOADED section."
    [sem_links]="No valid (http/https) links in: %s."
    [nada]="nothing"
    [marca]="# ==================== DOWNLOADED ===================="
    [marca_desc]="# Successfully downloaded links. GrabIt ignores everything until the end of this section."
    [marca_fim]="# ================ END OF DOWNLOADED ================"
    [tentativa_n]="attempt %d · "
    [ni_tentativa]="(attempt %d)"
    [log_tentativa]="# ── attempt %d ──"
    [tipo_legendas]="subtitles"
    [tipo_audio]="audio"
    [tipo_video]="video"
    [total]="Total"
    [restam]="≈%s left"
    [et_finalizando]="finishing"
    [et_mesclando]="merging video and audio"
    [et_mkv]="converting to MKV"
    [et_metadados]="writing metadata"
    [et_legendas_emb]="embedding subtitles"
    [et_capa_emb]="embedding the cover"
    [et_capitulos]="processing chapters"
    [et_fixup]="fixing the file"
    [et_legendas]="downloading subtitles"
    [et_capa]="downloading the cover"
    [et_hist]="already downloaded (history)"
    [et_existe]="file already exists"
    [et_iniciando]="starting download"
    [et_principal]="looking for the page's main video"
    [et_verificando]="checking the file"
    [et_processando]="processing"
    [et_item]="fetching info · item %s/%s"
    [et_info]="fetching info"
    [r_ja_existia]="already existed"
    [r_ja_baixado]="already downloaded"
    [r_n_ja_baixados]="%d already downloaded"
    [r_concluido]="done"
    [r_aviso]="warning:"
    [r_av_capa]="the cover couldn't be converted to JPG and was embedded as is"
    [r_av_sponsor]="couldn't reach SponsorBlock"
    [r_av_outro]="a finishing step failed (see the log)"
    [r_av_completo]="%s — the video is complete"
    [r_parcial]="partial"
    [r_falhou]="failed"
    [r_falhou_n]="failed %d×"
    [r_codigo]="yt-dlp exited with code %d"
    [d_privado]="private video"
    [d_idade]="age-restricted — use -b BROWSER"
    [d_bot]="YouTube asked you to sign in — use -b BROWSER"
    [d_membros]="members only"
    [d_regiao]="blocked in your region"
    [d_removido]="video unavailable or removed"
    [d_url]="no video recognized on this page"
    [d_url_invalida]="unsupported link"
    [d_antirobo]="the site asks for its anti-bot check"
    [d_login]="needs a login — use -b BROWSER"
    [d_drm]="DRM protected: GrabIt doesn't download it"
    [d_ssl]="the site's certificate is invalid"
    [s_nav_tit]="If the video plays in your browser, you can download it:"
    [s_nav_b]="     · Pass the check in the browser and use its session:  %s"
    [s_nav_b2]="       (if it still refuses, add -A with the browser's User Agent)"
    [s_nav_c]="     · Or press play, hit F12, Network tab, filter by m3u8 (the master, if there is one) or mp4, right-click the request, Copy as cURL, and run:  %s"
    [curl_sem_py]="grabit curl needs python3 to read the copied command."
    [curl_invalido]="That isn't a cURL command with a link. In the browser's Network tab (F12), right-click the video request and choose Copy as cURL."
    [curl_colar]="     You can also paste the command after grabit:  grabit curl 'https://…' -H …"
    [clip_wayland]="On Wayland, reading the clipboard needs wl-clipboard. To install it:  %s"
    [et_navegador]="in the browser · do the check or press play, if needed"
    [nav_abrindo]="This site needs a browser: I'll open %s. If a check shows up, just do it in the window."
    [k_freio]="%s asked to slow down: at most %d download(s) at once from that site, and the next one in %d s"
    [k_parado]="%s is refusing requests: its remaining links are left for later, and the other sites carry on"
    [k_espera_site]="waiting for %s to clear (%d s) · q quits"
    [k_espera_ant]="%s asked for a break recently: its links start in %d s (-F doesn't wait)"
    [s_adiados]="Postponed"
    [s_adiados_det]="(the site was refusing: try again later)"
    [ins_q_curlcffi]="Install curl-cffi? It helps when a site blocks automated downloads. [Y/n]"
    [ins_q_deno]="Install Deno? YouTube requires a JavaScript runtime to unlock the best resolutions. [Y/n]"
    [ins_q_clip]="Install %s? It's for capturing copied links (-C) and reading the copied cURL. [Y/n]"
    [ins_q_nav]="Install Firefox? It's only useful on sites that just work in a browser, and you have none that GrabIt can use. [y/N]"
    [ins_nav_nota]="No compatible browser: sites that only work in a browser won't be downloaded. To install one: grabit install firefox (or chromium, chrome, brave, edge)."
    [ins_nav_desconhecido]="Unknown browser: '%s'. You can ask for firefox, chromium, chrome, brave or edge."
    [ins_nav_ja]="%s is already installed."
    [ins_nav_site]="%s isn't in this system's package manager. Download it from: %s"
    [nav_sem_video]="no video showed up in the browser (the window closed or time ran out)"
    [nav_sem_navegador]="     With Firefox or Chrome installed, GrabIt does this by itself."
    [curl_sem_clip]="I couldn't read the clipboard. Save the command to a file and run:  %s"
    [curl_sem_arquivo]="The file '%s' wasn't found."
    [kv_curl]="browser cURL · %d header(s), %d cookie(s) · file: %s"
    [curl_falhou]="Copied links tend to expire: if that's why it failed, copy the cURL again."
    [d_live]="the live stream/premiere hasn't started yet"
    [d_404]="not found (404)"
    [d_disco]="disk full"
    [d_invalido]="the downloaded file isn't a valid video"
    [d_fragmento]="a piece of the video failed to download"
    [d_403]="access denied (403)"
    [d_429]="too many requests (429)"
    [d_rede]="network failure"
    [d_resolucao]="no version up to %dp — use -F to download it anyway"
    [d_resolucao_r]="no version up to %dp (-r)"
    [nota_n]="%d videos · %s and others"
    [nota_n0]="%d videos"
    [sufixo_ruim]=".with-errors"
    [d_verificacao]="the file has defects (kept with %s in its name)"
    [r_baixa]="low resolution:"
    [r_baixa_det]="%dp was the best version available (logged in, -b, there may be more)"
    [s_baixa]="Low resolution"
    [s_baixa_det]="%d video(s) below %dp"
    [s_resumo]="Summary"
    [s_resumo_parcial]="Partial summary"
    [s_baixados]="Downloaded"
    [s_ja]="Already had"
    [s_erro]="Failed links"
    [s_aviso]="With warnings"
    [s_aviso_det]="(files complete · logs in %s/)"
    [s_tempo]="Time"
    [s_baixado_agora]="Downloaded now"
    [s_media]="(average %s/s)"
    [s_pasta]="Folder"
    [s_lista]="List"
    [s_movidos]="%d link(s) moved to the DOWNLOADED section"
    [f_todos_ok]="Every link in %s succeeded — file removed."
    [f_nao_gravou]="Couldn't write '%s'."
    [f_com_erro]="failed"
    [f_erro_pend]="failed or pending"
    [f_pend]="pending"
    [f_salvos]="%d %s link(s) saved to %s"
    [f_logs]=" — logs in %s/"
    [f_continuar]="     To continue:  %s"
    [c_cancelado]="Canceled."
    [c_descartado]=" Anything half-done was discarded and will start over next time."
    [tmp_falhou]="Couldn't create the temporary folder."
    [pasta_falhou]="Couldn't create folder '%s'."
  )
  T[ajuda]=$(cat <<'EOF'
Usage:  grabit [options] [LINK or FILE ...]

  -l FILE       file with the links ("-" = stdin)    (default: links.txt)
  -o FOLDER     where videos are saved               (default: ./Downloads)
  -j N          simultaneous downloads               (default: 4)
  -c N          connections (fragments) per video    (default: 4)
  -r HEIGHT     maximum resolution: 720, 1080, 4k…   (default: no limit)
  -F            force: ignore the grabit.config limits (resolution, sites, pause…)
  -b BROWSER    use the browser's cookies (firefox, chrome, brave…)
  -A AGENT      use the browser's User-Agent, along with -b, on sites with a check
  -p            only the video, when the link is video + playlist
  -u            only the main video (the longest) of pages with several videos
  -x            audio only (the best track, no re-encoding)
  -d            sort into subfolders by site and channel: Downloads/site/channel/
  -m            for Jellyfin, Plex and Kodi: channel/Season year/, with .nfo and cover
  -f            live queue: after the list, stays open downloading whatever you add
                to the link file (q or Ctrl+C to quit)
  -U            upgrade: check videos already downloaded (including the ones in the
                DOWNLOADED section) and replace those with a better version today
  -C            capture: while GrabIt is open, every link you copy joins the queue
                (written to links.txt); nothing keeps running once it closes
  -a            include automatic subtitles (manual ones still win)
  -s            mark sponsors/intros as chapters (SponsorBlock)
  -i            ignore the download history (check file by file)
  -v            full check: decode every video end to end looking for defects
  -L pt|en      language of the messages
  -h            show this help

Commands, in English or Portuguese, with or without the dashes (grabit update is
the same as grabit --atualizar):

  config             show grabit.config and the values in use
  install, instalar  install what's missing (ffmpeg, yt-dlp…) and the grabit command, and ask
                     about what's optional; with -y, install it all without asking (a browser,
                     only if there's no compatible one, and then only Firefox)
  install BROWSER    install a browser on request: firefox, chromium, chrome, brave or edge
  update, atualizar  put everything on the newest version (GrabIt, yt-dlp, Deno and FFmpeg)
                     and install what's missing
  version, versao    show the installed version, whether there's a newer one and what GrabIt uses
  curl [FILE]        download what plays in the browser, from "Copy as cURL" in the Network tab
                     (F12): reads the clipboard, a file or, with -, standard input;
                     you can also paste the copied command after grabit
  check, verificar [FOLDER]
                     check the videos already downloaded (defects and incomplete files)
                     and offer to download the problem ones again
  downloaded, baixados [ACTION]
                     list the DOWNLOADED section; actions: edit, back N…, add LINK…, clear
  help, ajuda        show this help

• A link file named like a command needs ./ in front of it: grabit ./update
• Links and link files can also go straight on the command line (then
  links.txt is only read if you pass -l), and options work before or after them:
      grabit https://youtu.be/xxxx another_list.txt -j 4
• In the files: empty lines and comments (# …, also at the end of a line)
  are ignored, as is any text around the link; duplicates are dropped.
• Successfully downloaded links move to the "# ===== DOWNLOADED =====" section
  at the end of the same file. Everything there is ignored: it becomes your
  link history.
• Every downloaded video goes into the history
  (Downloads/.grabit-historico.txt): next time it is skipped right away,
  without touching the site or the file.
  Deleted a video and want it again? Use -i or delete its line there.
• A link that fails for a temporary reason (network, 403…) gets another try at
  the end of the queue, impersonating a browser (--impersonate) if curl_cffi
  is installed.
• Failed links go to links_falhos.txt, ready to run again:
      grabit -l links_falhos.txt
• A download that didn't finish (Ctrl+C, error) starts over from scratch next
  time: resuming pieces doesn't guarantee quality. The Downloads/.parciais
  folder only exists while GrabIt runs.

Permanent settings live in grabit.config, next to grabit.sh (created on the
first run, with every default commented out): grabit --config
Priority: grabit.config < environment variable < command-line option, e.g.:
    DOWNLOADS_SIMULTANEOS=3 grabit        grabit -j 3
EOF
)
  T[modelo_config]=$(cat <<'EOF'
# ==============================================================================
#  grabit.config — GrabIt settings
#
#  Created automatically on the first run, with every default commented out.
#  To change a value, remove the "#" at the start of the line and edit it. To go
#  back to the default, comment the line again (or delete this file: it is
#  recreated).
#
#  Priority: this file < environment variables < command-line options.
#  See the values in use with: grabit --config
# ==============================================================================

# Language of the messages: pt, en or auto (follows the system) (-L)
#IDIOMA=auto

# Link list read when you run just "grabit"
#ARQUIVO_LINKS=links.txt

# Folder where videos are saved
#PASTA_SAIDA=./Downloads

# Maximum resolution: 720, 1080, 1440, 2160 (or 4k)…; 0 = no limit (-r). It applies to
# the shorter side of the picture: a 1080×1920 vertical video counts as 1080p. A video
# with no version within the limit fails with a notice; -F ignores the limit for a run.
#RESOLUCAO_MAXIMA=0

# Warn when the best version a site offers is below this resolution (0 = never)
#RESOLUCAO_ALERTA=720

# Audio only (-x): the best sound track, in the format the site delivers (original, no
# re-encoding) or converted to mp3, m4a, aac, opus, flac, wav, alac or vorbis.
# It has its own history, separate from the videos'.
#SO_AUDIO=0
#FORMATO_AUDIO=original

# How many videos to download at once (-j) and connections per video (-c)
#DOWNLOADS_SIMULTANEOS=4
#CONEXOES_POR_VIDEO=4

# Attempts per link when the failure is temporary (1 = don't retry)
#TENTATIVAS=2

# Being nice to sites (helps with the ones that block many downloads in a row): at
# most N downloads at once from the same site, an N-second pause (with some random
# variation) before each video and a maximum speed per download, like 5M or 500K.
# 0 = off. -F ignores all of this for a run.
#LIMITE_POR_SITE=0
#PAUSA_ENTRE_VIDEOS=0
#LIMITE_VELOCIDADE=0

# Subtitle languages ("all" = every one) and whether to include automatic ones (-a)
#IDIOMAS_LEGENDAS=pt.*,en.*
#LEGENDAS_AUTOMATICAS=0

# Mark sponsors/intros as chapters with SponsorBlock (-s)
#SPONSORBLOCK=0

# Video link inside a playlist: download only the video (-p)
#SEM_PLAYLIST=0

# Page with several videos (previews, related…): download only the main one, the longest (-u)
#SO_PRINCIPAL=0

# Full check: decode every downloaded video from start to end and, if a defect shows
# up, download it again from scratch. Guarantees a flawless file, but costs CPU and time (-v)
#VERIFICAR=0

# Use a browser's cookies (login): firefox, chrome, brave… (-b)
#COOKIES_NAVEGADOR=

# That browser's User-Agent (-A). Sites with an anti-bot check only accept the cookies
# along with it. In Firefox, it's shown in about:support.
#USER_AGENT=

# Extra options for yt-dlp, separated by spaces. E.g.: --force-ipv4 --no-check-certificates
#OPCOES_YTDLP=

# When a page only works in a browser (JavaScript player, anti-bot check), open one, in a
# profile just for GrabIt, to find the video. A check, if one shows up, is yours to do in the
# window. 0 = never open it. Whatever is already installed works: Firefox, Chrome, Chromium,
# Brave, Edge…; to choose, put the program's name in PROGRAMA_NAVEGADOR.
#USAR_NAVEGADOR=1
#PROGRAMA_NAVEGADOR=

# Skip videos already downloaded before (0 = always check; same as -i)
#USAR_HISTORICO=1

# Where to save the links that failed
#ARQUIVO_FALHAS=links_falhos.txt

# At the end of a batch that took 1 minute or more: terminal bell and desktop
# notification (notify-send on Linux, Notification Center on macOS). 0 = silence.
#NOTIFICAR=1

# Phone notification through ntfy (https://ntfy.sh): install the app, subscribe to a
# topic with a hard-to-guess name and put it here (or the full URL of your own server).
# Only the summary goes out (how many downloaded and how many failed), never links or titles.
#NTFY_TOPICO=
EOF
)
}
"idioma_$LINGUA"

# ───────────────────────────── Cores e terminal ───────────────────────────────
ESC=$'\033'
INTERATIVO=0
[[ -t 1 && ${TERM:-dumb} != dumb ]] && INTERATIVO=1

if (( INTERATIVO )) && [[ -z "${NO_COLOR:-}" ]]; then
  R="${ESC}[0m";            NEG="${ESC}[1m"
  DIM="${ESC}[38;5;245m";   CINZA="${ESC}[38;5;238m"
  VERDE="${ESC}[38;5;78m";  VERMELHO="${ESC}[38;5;203m"
  AMARELO="${ESC}[38;5;221m"; CIANO="${ESC}[38;5;81m"; ACENTO="${ESC}[38;5;141m"
else
  R=""; NEG=""; DIM=""; CINZA=""; VERDE=""; VERMELHO=""; AMARELO=""; CIANO=""; ACENTO=""
fi

erro()  { printf '  %s✖%s %s\n' "$VERMELHO" "$R" "$*" >&2; }
aviso() { printf '  %s⚠%s %s\n' "$AMARELO" "$R" "$*"; }
uso()   { printf '%s\n' "${T[ajuda]}"; }

# Primeira execução: cria o grabit.config, com os padrões comentados, no idioma atual
if [[ ! -e $CONFIG_ARQ && -w ${CONFIG_ARQ%/*} ]]; then
  printf '%s\n' "${T[modelo_config]}" > "$CONFIG_ARQ" 2>/dev/null && CONFIG_CRIADO=1
fi

# palavra_comando PALAVRA → COMANDO: os comandos valem nas duas línguas, com ou sem os traços
palavra_comando() {
  case ${1,,} in
    config|configuracao|configuração) COMANDO=config ;;
    ajuda|help)                       COMANDO=ajuda ;;
    instalar|install)                 COMANDO=instalar ;;
    atualizar|update)                 COMANDO=atualizar ;;
    verificar|check)                  COMANDO=verificar ;;
    baixados|downloaded)              COMANDO=baixados ;;
    versao|versão|version)            COMANDO=versao ;;
    curl)                             COMANDO=curl ;;
    *) return 1 ;;
  esac
}

# Comandos longos (--config, --help) saem da lista antes do getopts; depois de "--", nada é comando
COMANDO=""; ARGS_CURTOS=(); SO_LINKS=0; ASSUME_SIM=0; ATUALIZANDO=0
for a in "$@"; do
  if (( SO_LINKS )); then ARGS_CURTOS+=("$a"); continue; fi
  case $a in
    --)  ARGS_CURTOS+=("$a"); SO_LINKS=1 ;;
    --yes|--sim) ASSUME_SIM=1 ;;
    --*) palavra_comando "${a#--}" || { t opcao_invalida "$a"; erro "$TXT"; uso; exit 2; } ;;
    *)   ARGS_CURTOS+=("$a") ;;
  esac
done
set -- "${ARGS_CURTOS[@]}"

OPCOES=(); LISTA_EXPLICITA=0; FORCAR=0; SUBPASTAS=0; MIDIA=0; FILA_VIVA=0; CAPTURA=0; UPGRADE=0; ARGS_LINKS=()
# As opções valem em qualquer posição: "grabit LINK -x" é o mesmo que "grabit -x LINK".
# O getopts para no primeiro link; aqui ele o guarda e continua. Depois de "--", só há links.
while (( $# )); do
  OPTIND=1
  while getopts ":l:o:j:c:b:r:L:A:pausivxdmfCUFhy" op; do
    case $op in
      l) ARQUIVO_LINKS=$OPTARG; LISTA_EXPLICITA=1; ORIGEM[ARQUIVO_LINKS]=opção; continue ;;
      o) PASTA_SAIDA=$OPTARG;            ORIGEM[PASTA_SAIDA]=opção ;;
      j) DOWNLOADS_SIMULTANEOS=$OPTARG;  ORIGEM[DOWNLOADS_SIMULTANEOS]=opção ;;
      c) CONEXOES_POR_VIDEO=$OPTARG;     ORIGEM[CONEXOES_POR_VIDEO]=opção ;;
      b) COOKIES_NAVEGADOR=$OPTARG;      ORIGEM[COOKIES_NAVEGADOR]=opção ;;
      A) USER_AGENT=$OPTARG;             ORIGEM[USER_AGENT]=opção ;;
      r) RESOLUCAO_MAXIMA=$OPTARG;       ORIGEM[RESOLUCAO_MAXIMA]=opção ;;
      F) FORCAR=1 ;;
      L) ;;                              # já tratado acima, antes de carregar os textos
      p) SEM_PLAYLIST=1;                 ORIGEM[SEM_PLAYLIST]=opção ;;
      u) SO_PRINCIPAL=1;                 ORIGEM[SO_PRINCIPAL]=opção ;;
      a) LEGENDAS_AUTOMATICAS=1;         ORIGEM[LEGENDAS_AUTOMATICAS]=opção ;;
      s) SPONSORBLOCK=1;                 ORIGEM[SPONSORBLOCK]=opção ;;
      i) USAR_HISTORICO=0;               ORIGEM[USAR_HISTORICO]=opção ;;
      v) VERIFICAR=1;                    ORIGEM[VERIFICAR]=opção ;;
      x) SO_AUDIO=1;                     ORIGEM[SO_AUDIO]=opção ;;
      d) SUBPASTAS=1 ;;                  # só pela opção, de propósito: nada de pastas sem pedir
      m) MIDIA=1 ;;                      # idem
      f) FILA_VIVA=1 ;;                  # idem: o GrabIt só fica aberto esperando links se pedido
      C) CAPTURA=1; FILA_VIVA=1 ;;       # idem: só lê a área de transferência se pedido, e só aberto
      U) UPGRADE=1 ;;
      h) COMANDO=ajuda ;;
      y) ASSUME_SIM=1 ;;
      :) t opcao_valor "$OPTARG"; erro "$TXT"; exit 2 ;;
      *) t opcao_invalida "-$OPTARG"; erro "$TXT"; uso; exit 2 ;;
    esac
    OPCOES+=("-$op" ${OPTARG+"$OPTARG"})      # guardadas para sugerir o comando de nova tentativa
  done
  if (( OPTIND > 1 )) && [[ ${*:OPTIND-1:1} == -- ]]; then
    shift $(( OPTIND - 1 )); ARGS_LINKS+=("$@"); break
  fi
  shift $(( OPTIND - 1 ))
  (( $# )) || break
  ARGS_LINKS+=("$1"); shift
done
# Sem os traços: "grabit update". Só a primeira palavra conta, e o getopts já separou os valores
# das opções ("-l update" é um arquivo). Um arquivo com esse nome continua valendo como ./update.
if [[ -z $COMANDO && ${#ARGS_LINKS[@]} -gt 0 ]] && (( ! SO_LINKS )) && palavra_comando "${ARGS_LINKS[0]}"; then
  ARGS_LINKS=("${ARGS_LINKS[@]:1}")
fi
# "~" num valor que não passou pelo shell (grabit.config, aspas): sem isto, PASTA_SAIDA=~/Vídeos
# viraria uma pasta chamada "~" aqui e, para o yt-dlp, a pasta pessoal.
for k in ARQUIVO_LINKS PASTA_SAIDA ARQUIVO_FALHAS ARQUIVO_HISTORICO; do
  case ${!k} in \~|\~/*) printf -v "$k" '%s' "$HOME${!k:1}" ;; esac
done
# Só áudio tem histórico próprio: ter baixado o vídeo não significa ter o áudio, e vice-versa
if [[ -z $ARQUIVO_HISTORICO ]]; then
  if (( SO_AUDIO )); then ARQUIVO_HISTORICO="$PASTA_SAIDA/.grabit-historico-audio.txt"
  else ARQUIVO_HISTORICO="$PASTA_SAIDA/.grabit-historico.txt"; fi
fi

[[ $COMANDO == ajuda ]] && { uso; exit 0; }
if (( UPGRADE && SO_AUDIO )); then aviso "${T[up_audio]}"; UPGRADE=0; fi
if (( UPGRADE && FILA_VIVA )); then aviso "${T[up_fila]}"; FILA_VIVA=0; CAPTURA=0; fi

# -d: uma pasta por site e, dentro dela, uma por canal (quando o site informa o canal;
# sem ele, o vídeo fica direto na pasta do site)
(( SUBPASTAS )) && TEMPLATE_SAIDA="%(webpage_url_domain,extractor_key|site)s/%(channel,uploader|).80B/$TEMPLATE_SAIDA"
# -m: o canal vira uma "série" de Jellyfin/Plex/Kodi, com uma temporada por ano e episódios
# nomeados pela data (os três reconhecem "Série - 2026-10-24 - Título"). Sem data no
# site, vale a de hoje.
printf -v HOJE '%(%Y-%m-%d)T' -1
if (( MIDIA )); then
  serie='%(channel,uploader,webpage_url_domain|GrabIt).80B'
  TEMPLATE_SAIDA="$serie/Season %(upload_date>%Y|${HOJE%%-*})s/$serie - %(upload_date>%Y-%m-%d|$HOJE)s - %(title).150B [%(id)s].%(ext)s"
fi

if [[ -n $IDIOMA_INVALIDO ]]; then t idioma_invalido "$IDIOMA_INVALIDO" "$LINGUA"; aviso "$TXT"; fi
origem_txt() { FMT=${T[origem_${ORIGEM[$1]:-padrão}]}; }  # origem_txt CHAVE → FMT: de onde veio o valor
for nome in DOWNLOADS_SIMULTANEOS CONEXOES_POR_VIDEO TENTATIVAS; do
  if ! [[ ${!nome} =~ ^[1-9][0-9]*$ ]]; then
    origem_txt "$nome"; t val_numero "$nome" "${!nome}" "$FMT"; erro "$TXT"
    exit 2
  fi
done
for nome in SO_AUDIO LEGENDAS_AUTOMATICAS SPONSORBLOCK SEM_PLAYLIST SO_PRINCIPAL VERIFICAR USAR_NAVEGADOR USAR_HISTORICO NOTIFICAR; do
  if ! [[ ${!nome} =~ ^[01]$ ]]; then
    origem_txt "$nome"; t val_01 "$nome" "${!nome}" "$FMT"; erro "$TXT"
    exit 2
  fi
done
for nome in LIMITE_POR_SITE PAUSA_ENTRE_VIDEOS; do
  [[ -z ${!nome} ]] && printf -v "$nome" 0
  if ! [[ ${!nome} =~ ^[0-9]+$ ]]; then
    origem_txt "$nome"; t val_inteiro0 "$nome" "${!nome}" "$FMT"; erro "$TXT"
    exit 2
  fi
  printf -v "$nome" '%d' $(( 10#${!nome} ))
done
[[ -z $LIMITE_VELOCIDADE ]] && LIMITE_VELOCIDADE=0
if ! [[ $LIMITE_VELOCIDADE =~ ^(0|[0-9]+(\.[0-9]+)?[KkMmGg]?)$ ]]; then
  origem_txt LIMITE_VELOCIDADE; t val_velocidade LIMITE_VELOCIDADE "$LIMITE_VELOCIDADE" "$FMT"; erro "$TXT"
  exit 2
fi
LIMITE_VELOCIDADE=${LIMITE_VELOCIDADE^^}
case ${FORMATO_AUDIO,,} in
  original|best|"") FORMATO_AUDIO=original ;;
  mp3|m4a|aac|opus|flac|wav|alac|vorbis) FORMATO_AUDIO=${FORMATO_AUDIO,,} ;;
  *) origem_txt FORMATO_AUDIO; t val_audio FORMATO_AUDIO "$FORMATO_AUDIO" "$FMT"; erro "$TXT"; exit 2 ;;
esac
# Resolução: "1080", "1080p", "4k" e "8k" viram a altura; vazio ou 0 = desligado
for nome in RESOLUCAO_MAXIMA RESOLUCAO_ALERTA; do
  case ${!nome,,} in
    "") printf -v "$nome" 0 ;;
    4k) printf -v "$nome" 2160 ;;
    8k) printf -v "$nome" 4320 ;;
    *)
      if [[ ${!nome,,} =~ ^([0-9]{1,5})p?$ ]]; then
        printf -v "$nome" '%d' $(( 10#${BASH_REMATCH[1]} ))
      else
        origem_txt "$nome"; t val_resolucao "$nome" "${!nome}" "$FMT"; erro "$TXT"
        exit 2
      fi ;;
  esac
done

# --config: onde está o arquivo e os valores em uso, com a origem de cada um
mostra_config() {
  local k v pad
  printf '\n  %sgrabit.config%s  %s' "$NEG" "$R" "$CONFIG_ARQ"
  if (( CONFIG_CRIADO )); then printf '  %s%s%s\n\n' "$VERDE" "${T[cfg_criado]}" "$R"
  elif [[ -f $CONFIG_ARQ ]]; then printf '\n\n'
  else printf '  %s%s%s\n\n' "$AMARELO" "${T[cfg_inexistente]}" "$R"; fi
  for k in "${CHAVES_CONFIG[@]}"; do
    v=${!k:-—}; origem_txt "$k"
    pad=""; (( ${#v} < 22 )) && printf -v pad '%*s' $(( 22 - ${#v} )) ''   # por caracteres: "—" ocupa 3 bytes
    printf '  %-22s %s%s%s%s %s%s%s\n' "$k" "$NEG" "$v" "$R" "$pad" "$DIM" "$FMT" "$R"
  done
  for v in "${AVISOS_CONFIG[@]}"; do t cfg_linha "${v%%:*}" "${v#*:}"; aviso "$TXT"; done
  printf '\n'
}
[[ $COMANDO == config ]] && { mostra_config; exit 0; }

# -F: os limites que vieram do grabit.config (ou do ambiente) não valem nesta execução;
# os passados no próprio comando continuam valendo.
CHAVES_LIMITE=(RESOLUCAO_MAXIMA LIMITE_POR_SITE PAUSA_ENTRE_VIDEOS LIMITE_VELOCIDADE)
declare -A IGNORADO=()
if (( FORCAR )); then
  for nome in "${CHAVES_LIMITE[@]}"; do
    [[ ${!nome} == 0 || ${ORIGEM[$nome]:-} == opção ]] && continue
    IGNORADO[$nome]=${!nome}; printf -v "$nome" 0
  done
fi
# Alerta de baixa resolução: nunca acima do limite escolhido (com limite de 480p,
# avisar de tudo abaixo de 720p seria só ruído)
ALERTA=$RESOLUCAO_ALERTA
(( RESOLUCAO_MAXIMA > 0 && RESOLUCAO_MAXIMA < ALERTA )) && ALERTA=$RESOLUCAO_MAXIMA

# ───────────────────────────── Estado global ──────────────────────────────────
J=0; TOTAL=0; COLS=100; TICK=0; LIVE_H=0; CANCELADO=0; SINAL=""; STTY_SAVE=""; TMP=""
N_OK=0; N_JA=0; N_ERRO=0; N_AVISOS=0; N_FATAIS=0; N_COSMETICOS=0; AVISO_CTX=""; BYTES_NOVOS=0; FINALIZADOS=0; DUPLICADOS=0; INVALIDAS=0
VEL_TOTAL=0; EM_REPETICAO=0; REDIM=1; JANELA=""; TITULO_EMPILHADO=0; COMECOU=0
ULTIMO_PID=0; IMPERSONATE=""; JS_RUNTIME=""; JS_PATH=""; JS_RECUSADO=""; JS_CANDIDATOS=(); AVISO_JSC=""; YTDLP_VER=""; FFMPEG_VER=""; TEM_JS_RUNTIMES=0
S_H=0; S_FPS=0; S_HDR="SDR"; S_VC=""; S_AC=""; S_CANAIS=0; S_DUR=0; S_TAM=0
FMT=""; LARG=0; LINHA=""; BARRA=""; META=""; NUM=0; ETAPA=""; MOTIVO=""; DICA=""; REPETE=1; ARQUIVO_RUIM=0; DISCO_CHEIO=0
AJUSTE=""; AJUSTES=(); DICA_NAVEGADOR=0; MODO_CURL=0; EXTRA_YTDLP=(); N_CAB_CURL=0; N_COOK_CURL=0; ROTULO_CURL=""
NIVEL=(); NIVEL_INICIO=(); NAV_AVISADO=0; NAV_DONO=0; NAV_PROG=""; NAV_TIPO=""; NAV_NOME=""; NAV_ROTULO=""; PASTA_NAV=""
CAB_ARGS=(); CAB_REFERER=""; SAIDA_PAGINA=""; ARQ_METODOS=""; PROX_BLOQ=0; MUITAS_REQ=0
declare -A METODO=() METODO_QUANDO=() ESPERA_ATE=()
declare -A FILA_CAB=() FILA_RAB=() PEND_SITE=() ATIVOS_SITE=()
declare -A LIM_SITE=() CREDITO_SITE=() BLOQ_SITE=() ESPERA_SITE=() PROX_INICIO_SITE=() FALHAS_SITE=() PARADO_SITE=()
SEG=(); SITES=(); SAUDAVEL=(); N_PENDENTES=0; N_ADIADOS=0; BLOQUEIO=0
ESPERA_BASE=${GRABIT_ESPERA_BASE:-30}         # segundos de espera no primeiro 429 de um site
FORMATO='bv*+ba/b'; PRINCIPAL=0; HOJE=""
FONTE_LINKS=""; LOG_DIR=""; DIR_TEMP=""; TEMP_REL=""; N_NA_SECAO=0; N_MOVIDOS=0; N_BAIXA_RES=0
MARCA_BAIXADOS=${T[marca]}
LINKS=(); SLOT_IDX=(); SLOT_PID=(); PERM=(); LIVE=(); FALHAS=(); YTDLP_ARGS=()
TENTATIVA=(); FEITO=(); REBAIXAR=(); SUCESSO=(); NOTA=(); INICIADO=(); SITE=(); ARQUIVOS_ENTRADA=(); PALAVRAS_LINK=()
ESCOLHIDO=0; INICIO_JOB=(); ETA_JOB=(); N_INICIADOS=0; T_SOMA=0; T_N=0; BAIXOU=0
TECLAS=0; PAUSADO=0; PARANDO=0; J_ALVO=0; MSG_PAINEL=""; MSG_ATE=0
ATIVOS=0; PROX_VIGIA=0; OCUPADO_DESDE=-1; MOVER=0; PROX_MOVER=60
CLIP_CMD=(); CLIP_ULTIMO=""; CLIP_PRIMEIRA=1; PROX_CLIP=0; ARQ_CAPTURA=""
declare -A CONHECIDO=() MARCA_ARQ=() CAPTURADO=()
declare -A TITULO=() CACHE_CORTA=()
SEP=$'\x1f'                                  # separador de campos nos logs
SPIN=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
UNID=(B KiB MiB GiB TiB)

# ───────────────────────────── Formatação ─────────────────────────────────────
# Todas devolvem o resultado em variável global (evita subshells a 5 quadros/s)

num() {                                       # NUM = parte inteira, ou 0
  local v=${1%%.*}
  if [[ $v =~ ^[0-9]+$ ]]; then NUM=$v; else NUM=0; fi
}

fmt_bytes() {                                 # 1536000 → "1.5 MiB"
  local b=${1:-0} i=0 d=1 v
  [[ $b =~ ^[0-9]+$ ]] || b=0
  while (( b >= d * 1024 && i < 4 )); do d=$(( d * 1024 )); i=$(( i + 1 )); done
  if (( i == 0 )); then
    FMT="${b} B"
  else
    v=$(( b * 10 / d ))
    FMT="$(( v / 10 )).$(( v % 10 )) ${UNID[$i]}"
  fi
}

fmt_tempo() {                                 # 3725 → 01:02:05
  local s=${1:-0}
  printf -v FMT '%02d:%02d:%02d' $(( s / 3600 )) $(( s % 3600 / 60 )) $(( s % 60 ))
}

fmt_dur() {                                   # 125 → 02:05 · 3725 → 1:02:05
  local s=${1:-0}
  if (( s >= 3600 )); then
    printf -v FMT '%d:%02d:%02d' $(( s / 3600 )) $(( s % 3600 / 60 )) $(( s % 60 ))
  else
    printf -v FMT '%02d:%02d' $(( s / 60 )) $(( s % 60 ))
  fi
}

# corta(texto, colunas) → FMT (com reticências se não couber) e LARG (colunas que
# FMT ocupa). Mede colunas, não caracteres: emoji e CJK ocupam 2, acentos
# combinantes 0 — senão títulos como "🔥 测试" empurram o fim da linha para fora.
corta() {
  local s=$1 n=$2 i c cp cw w=0 corte=0 w_corte=0 chave
  if (( n < 1 )); then FMT=""; LARG=0; return; fi
  if [[ $s != *[![:ascii:]]* ]]; then         # só ASCII: 1 caractere = 1 coluna
    if (( ${#s} > n )); then FMT="${s:0:n-1}…"; else FMT=$s; fi
    LARG=${#FMT}; return
  fi
  chave="$n$SEP$s"
  if [[ -n ${CACHE_CORTA[$chave]:-} ]]; then
    LARG=${CACHE_CORTA[$chave]%%"$SEP"*}; FMT=${CACHE_CORTA[$chave]#*"$SEP"}; return
  fi
  for (( i = 0; i < ${#s}; i++ )); do
    c=${s:i:1}
    printf -v cp '%d' "'$c"
    if (( cp < 0x300 )); then cw=1
    elif (( (cp >= 0x300 && cp <= 0x36F) || (cp >= 0x200B && cp <= 0x200F) || (cp >= 0xFE00 && cp <= 0xFE0F) ||
            cp == 0x20E3 || (cp >= 0x1F3FB && cp <= 0x1F3FF) )); then cw=0
    elif (( (cp >= 0x1100 && cp <= 0x115F) || (cp >= 0x2E80 && cp <= 0xA4CF && cp != 0x303F) ||
            (cp >= 0xAC00 && cp <= 0xD7A3) || (cp >= 0xF900 && cp <= 0xFAFF) || (cp >= 0xFE30 && cp <= 0xFE4F) ||
            (cp >= 0xFF00 && cp <= 0xFF60) || (cp >= 0xFFE0 && cp <= 0xFFE6) || (cp >= 0x1F300 && cp <= 0x1F64F) ||
            (cp >= 0x1F680 && cp <= 0x1F6FF) || (cp >= 0x1F900 && cp <= 0x1FAFF) || (cp >= 0x20000 && cp <= 0x3FFFD) ||
            cp == 0x231A || cp == 0x231B || (cp >= 0x23E9 && cp <= 0x23EC) || cp == 0x23F0 || cp == 0x23F3 ||
            cp == 0x2614 || cp == 0x2615 || (cp >= 0x2648 && cp <= 0x2653) || cp == 0x26A1 || cp == 0x26BD ||
            cp == 0x26BE || cp == 0x2705 || cp == 0x270A || cp == 0x270B || cp == 0x2728 || cp == 0x274C ||
            (cp >= 0x2753 && cp <= 0x2757) || (cp >= 0x2795 && cp <= 0x2797) || cp == 0x2B50 || cp == 0x2B55 )); then cw=2
    else cw=1
    fi
    if (( w + cw > n - 1 && corte == 0 )); then corte=$i; w_corte=$w; fi
    w=$(( w + cw ))
    (( w > n )) && break
  done
  if (( w <= n )); then FMT=$s; LARG=$w; else FMT="${s:0:corte}…"; LARG=$(( w_corte + 1 )); fi
  (( ${#CACHE_CORTA[@]} > 2000 )) && CACHE_CORTA=()
  CACHE_CORTA[$chave]="$LARG$SEP$FMT"
}

barra() {                                     # barra(preenchido, largura) → BARRA
  local fill=$1 w=$2 a b
  (( fill > w )) && fill=$w
  (( fill < 0 )) && fill=0
  printf -v a '%*s' "$fill" ''
  printf -v b '%*s' "$(( w - fill ))" ''
  BARRA="${VERDE}${a// /━}${R}${CINZA}${b// /━}${R}"
}

nome_codec() {                                # avc1.640028 → h264
  case "${1%%.*}" in
    avc1|avc3)  FMT=h264 ;;
    hev1|hvc1)  FMT=hevc ;;
    vp09)       FMT=vp9  ;;
    av01)       FMT=av1  ;;
    mp4a)       FMT=aac  ;;
    ec-3)       FMT=eac3 ;;
    ac-3)       FMT=ac3  ;;
    none|""|"?") FMT=""  ;;
    *)          FMT="${1%%.*}" ;;
  esac
}

montar_meta() {                               # h fps hdr vcodec acodec canais duração bytes → META
  local h fps hdr=$3 res="" vc ac cod="" p=() i
  num "$1"; h=$NUM; num "$2"; fps=$NUM
  if (( h > 0 )); then
    res="${h}p"
    (( fps > 30 )) && res+="$fps"
    [[ -n $hdr && $hdr != SDR && $hdr != NA ]] && res+=" $hdr"
    p+=("$res")
  fi
  nome_codec "$4"; vc=$FMT
  nome_codec "$5"; ac=$FMT
  if [[ -n $ac ]]; then                       # som surround merece destaque
    num "$6"
    case $NUM in 6) ac+=" 5.1" ;; 8) ac+=" 7.1" ;; esac
  fi
  cod=$vc
  [[ -n $vc && -n $ac ]] && cod+="+"
  cod+=$ac
  [[ -n $cod ]] && p+=("$cod")
  num "$8"; if (( NUM > 0 )); then fmt_bytes "$NUM"; p+=("$FMT"); fi
  num "$7"; if (( NUM > 0 )); then fmt_dur "$NUM"; p+=("$FMT"); fi
  META=""
  for i in "${!p[@]}"; do
    (( i > 0 )) && META+=" · "
    META+=${p[$i]}
  done
}

# linha_resultado GLIFO COR IDX TITULO META → LINHA (com pontilhado até a meta)
linha_resultado() {
  local g=$1 cor=$2 idx=$3 t=$4 m=$5 dots pad avail fixo
  fixo=$(( 2 + 1 + 1 + ${#idx} + 2 ))                      # "  ✔ 1/4  "
  avail=$(( COLS - fixo - ${#m} - 4 ))
  if (( avail < 24 )); then                                # terminal estreito: meta vai para a linha de baixo
    corta "$t" $(( COLS - fixo - 1 )); t=$FMT
    corta "$m" $(( COLS - fixo - 1 )); m=$FMT
    printf -v pad '%*s' "$fixo" ''
    LINHA="  ${cor}${g}${R} ${DIM}${idx}${R}  ${t}"$'\n'"${pad}${CIANO}${m}${R}"
    return
  fi
  corta "$t" "$avail"; t=$FMT
  pad=$(( avail - LARG + 1 ))
  (( pad < 1 )) && pad=1
  printf -v dots '%*s' "$pad" ''
  LINHA="  ${cor}${g}${R} ${DIM}${idx}${R}  ${t} ${DIM}${dots// /·}${R} ${CIANO}${m}${R}"
}

atualiza_largura() {                          # relê o tamanho do terminal (no início e a cada SIGWINCH)
  (( INTERATIVO && REDIM )) || return 0
  REDIM=0
  COLS=$(tput cols 2>/dev/null) || COLS=80
  [[ $COLS =~ ^[0-9]+$ ]] || COLS=80
  (( COLS < 50 )) && COLS=50
  return 0
}

# ───────────────────────────── Erros do yt-dlp ────────────────────────────────
# analisa_log LOG → N_FATAIS, N_COSMETICOS, MOTIVO (último erro fatal) e AVISO_CTX.
# Um ERROR seguido de @@D@@ (o arquivo final foi entregue mesmo assim) foi só
# cosmético — ex.: a capa não converteu. Fatal é o erro de um item que nunca
# chegou ao fim. O yt-dlp sai com código 1 nos dois casos.
analisa_log() {
  local r=()
  mapfile -t r < <(awk '
    /^ERROR:/                         { if (!pend) ctx = ant; pend = 1; msg = $0; next }
    /^\[download\] Downloading item / { if (pend) { fatais++; fatal = msg } pend = 0 }
    /^@@D@@/                          { if (pend) { cosm++; avctx = ctx } pend = 0 }
    !/^(@@P@@|WARNING:)/              { ant = $0 }
    END {
      if (pend) { fatais++; fatal = msg }
      print fatais + 0; print cosm + 0; print fatal; print avctx
    }' "$1" 2>/dev/null)
  N_FATAIS=${r[0]:-0}; N_COSMETICOS=${r[1]:-0}; MOTIVO=${r[2]:-}; AVISO_CTX=${r[3]:-}
  [[ -z $MOTIVO ]] && MOTIVO=$(grep -av -e '^@@' -e '^WARNING:' "$1" 2>/dev/null | tail -n 1)
  if [[ $MOTIVO == *"error code 86" ]]; then  # reprovado na verificação (-v): mostra o que o ffmpeg achou
    MOTIVO=$(grep -a '^@@V@@ERRO ' "$1" 2>/dev/null | tail -n 1)
    MOTIVO="ERROR: [Verify] ${MOTIVO#@@V@@ERRO }"
  fi
  MOTIVO=${MOTIVO//[[:cntrl:]]/ }
}

# classifica_erro TEXTO → DICA (explicação curta), REPETE (0 = não adianta tentar de
# novo), ARQUIVO_RUIM (1 = o arquivo baixado está corrompido: refazer do zero),
# DISCO_CHEIO (1 = os próximos downloads também não vão caber), AJUSTE (opções do yt-dlp que
# podem resolver esse erro na nova tentativa) e DICA_NAVEGADOR (1 = no navegador daria certo)
classifica_erro() {
  DICA=""; REPETE=1; ARQUIVO_RUIM=0; DISCO_CHEIO=0; AJUSTE=""; MUITAS_REQ=0; BLOQUEIO=0
  # O site está recusando quem pede? (MUITAS_REQ: e diz para esperar)
  case ${1,,} in
    *"http error 429"*|*"too many requests"*|*"rate-limit"*|*"rate limit"*) BLOQUEIO=1; MUITAS_REQ=1 ;;
    *"http error 403"*|*"anti-bot"*|*"not a bot"*|*"access denied"*)        BLOQUEIO=1 ;;
  esac
  case ${1,,} in
    *"[verify]"*)                                           t d_verificacao "${T[sufixo_ruim]}"; DICA=$TXT ;;
    *"private video"*)                                      DICA=${T[d_privado]}; REPETE=0 ;;
    *"confirm your age"*|*"age-restricted"*|*"inappropriate for some users"*)
                                                            DICA=${T[d_idade]}; REPETE=0 ;;
    *"not a bot"*)                                          DICA=${T[d_bot]}; REPETE=0 ;;
    *"members-only"*|*"join this channel"*)                 DICA=${T[d_membros]}; REPETE=0 ;;
    *"drm protected"*)                                      DICA=${T[d_drm]}; REPETE=0 ;;
    *"unable to download video subtitles"*)                 AJUSTE="--sleep-subtitles 5" ;;
    *"anti-bot"*)                                           DICA=${T[d_antirobo]}; DICA_NAVEGADOR=1 ;;
    *"--cookies"*|*"log in"*|*"login required"*|*"sign in"*|*"registered users"*|*"requires authentication"*)
                                                            DICA=${T[d_login]}; REPETE=0 ;;
    *"certificate verify failed"*)                          DICA=${T[d_ssl]}; REPETE=0 ;;
    *"unsafe legacy renegotiation"*|*"unsafe_legacy_renegotiation"*)
                                                            AJUSTE="--legacy-server-connect" ;;
    *"not available in your country"*|*"geo restrict"*|*"geo-restrict"*)
                                                            DICA=${T[d_regiao]}; REPETE=0 ;;
    *"video unavailable"*|*"has been removed"*|*"no longer available"*)
                                                            DICA=${T[d_removido]}; REPETE=0 ;;
    *"unsupported url"*)                                    DICA=${T[d_url]}; REPETE=0; DICA_NAVEGADOR=1 ;;
    *"is not a valid url"*)                                 DICA=${T[d_url_invalida]}; REPETE=0 ;;
    *"live event will begin"*|*"premieres in"*)             DICA=${T[d_live]}; REPETE=0 ;;
    *"http error 404"*|*"http error 410"*)                  DICA=${T[d_404]}; REPETE=0 ;;
    *"no space left"*)                                      DICA=${T[d_disco]}; REPETE=0; DISCO_CHEIO=1 ;;
    *"requested format is not available"*)                  REPETE=0
      if (( RESOLUCAO_MAXIMA > 0 )); then
        if [[ ${ORIGEM[RESOLUCAO_MAXIMA]:-} == opção ]]; then t d_resolucao_r "$RESOLUCAO_MAXIMA"
        else t d_resolucao "$RESOLUCAO_MAXIMA"; fi
        DICA=$TXT
      fi ;;
    *"invalid data found when processing input"*|*"moov atom not found"*|*"ebml header parsing failed"*)
                                                            DICA=${T[d_invalido]}; ARQUIVO_RUIM=1 ;;
    *"fragment"*"not found"*|*"unable to download fragment"*) DICA=${T[d_fragmento]}; AJUSTE="-N 1" ;;
    *"http error 403"*)                                     DICA=${T[d_403]}; [[ ${1,,} == *fragment* ]] && AJUSTE="-N 1" ;;
    *"http error 429"*|*"too many requests"*|*"rate-limit"*|*"rate limit"*)
                                                            DICA=${T[d_429]}; AJUSTE="-N 1 --sleep-requests 2 --sleep-interval 5" ;;
    *"timed out"*|*"connection reset"*|*"name resolution"*|*"name or service not known"*|*"network is unreachable"*)
                                                            DICA=${T[d_rede]}; AJUSTE="--force-ipv4" ;;
  esac
}

# ───────────────────────────── Painel ao vivo ─────────────────────────────────
etapa_da_linha() {                            # o que uma linha do log diz sobre a etapa → ETAPA ("" = nada)
  ETAPA=""
  case $1 in
    *"aren't any"*|*"are no "*|*"Not remuxing"*|"Deleting original"*|WARNING:*) ;;   # "nada a fazer"
    @@D@@*|"[MoveFiles]"*)                                         ETAPA=${T[et_finalizando]} ;;
    "[grabit] principal"*)                                         ETAPA=${T[et_principal]} ;;
    "[grabit] navegador"*)                                         ETAPA=${T[et_navegador]} ;;
    "[Exec]"*"--nfo "*)                                            ETAPA=${T[et_nfo]} ;;
    "[Exec]"*)                                                     ETAPA=${T[et_verificando]} ;;
    "[download] Sleeping "*)
      [[ $1 =~ Sleeping\ ([0-9]+) ]] && { t et_pausa "${BASH_REMATCH[1]}"; ETAPA=$TXT; } ;;
    "[grabit] upgrade"*)                                           ETAPA=${T[et_upgrade]} ;;
    "[Merger]"*)                                                   ETAPA=${T[et_mesclando]} ;;
    "[VideoRemuxer]"*)                                             ETAPA=${T[et_mkv]} ;;
    "[Metadata]"*|"[EmbedInfoJson]"*)                              ETAPA=${T[et_metadados]} ;;
    "[EmbedSubtitle]"*|"[SubtitlesConvertor]"*)                    ETAPA=${T[et_legendas_emb]} ;;
    "[EmbedThumbnail]"*|"[ThumbnailsConvertor]"*)                  ETAPA=${T[et_capa_emb]} ;;
    "[SponsorBlock]"*|"[ModifyChapters]"*)                         ETAPA=${T[et_capitulos]} ;;
    "[Fixup"*)                                                     ETAPA=${T[et_fixup]} ;;
    *"Downloading subtitles"*|*"Writing video subtitles"*)         ETAPA=${T[et_legendas]} ;;
    *"Downloading video thumbnail"*|*"Writing video thumbnail"*)   ETAPA=${T[et_capa]} ;;
    *" has already been recorded in the archive")                  ETAPA=${T[et_hist]} ;;
    *" has already been downloaded")                               ETAPA=${T[et_existe]} ;;
    "[download] Destination"*|"[info] "*" format(s): "*|"[hlsnative]"*|"[dashsegments]"*)
                                                                   ETAPA=${T[et_iniciando]} ;;
    @@P@@*)                                                        ETAPA=${T[et_processando]} ;;
    "[download] Downloading item "*)
      if [[ $1 =~ item\ ([0-9]+)\ of\ ([0-9]+) ]]; then
        t et_item "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"; ETAPA=$TXT
      fi ;;
  esac
}

bloco_job() {                                 # monta as 2 linhas de um slot (slot livre não aparece)
  local s=$1
  local idx=${SLOT_IDX[$s]}
  (( idx == 0 )) && return

  local log="$TMP/$idx.log" ult=() linha="" k idxs spin titulo pre="" pre_txt="" l1 l2 seps tent
  mapfile -t ult < <(tail -n 30 "$log" 2>/dev/null)
  for (( k = ${#ult[@]} - 1; k >= 0; k-- )); do
    linha=${ult[$k]}
    [[ $linha == WARNING:* ]] && continue
    if [[ $linha == @@P@@* ]]; then           # linha de progresso pela metade (ainda sendo escrita)? usa a anterior
      seps=${linha//[!$SEP]/}
      (( ${#seps} == 10 )) || continue
    fi
    break
  done
  (( k < 0 )) && linha=""

  printf -v idxs "%0${#TOTAL}d/%d" "$idx" "$TOTAL"
  spin=${SPIN[$(( TICK % ${#SPIN[@]} ))]}
  (( PAUSADO )) && spin="‖"
  titulo=${TITULO[$idx]:-${LINKS[$(( idx - 1 ))]}}
  tent=${TENTATIVA[$idx]:-1}
  if (( tent > 1 )); then t tentativa_n "$tent"; pre_txt=$TXT; pre="${AMARELO}${pre_txt}${R}"; fi

  if [[ $linha == @@P@@* ]]; then
    local baixado total vel eta pidx pn vcod alt fps ext ttl tipo bw p10 pct detalhe fb ft resto parte vs="" es=""
    IFS=$SEP read -r baixado total vel eta pidx pn vcod alt fps ext ttl <<<"${linha#@@P@@}"
    ttl=${ttl//[[:cntrl:]]/ }
    if [[ -n $ttl && $ttl != "?" ]]; then TITULO[$idx]=$ttl; titulo=$ttl; fi
    num "$baixado"; baixado=$NUM
    num "$total";   total=$NUM
    num "$vel";     vel=$NUM
    num "$eta";     eta=$NUM
    (( PAUSADO )) && { vel=0; eta=0; }          # a última velocidade do log não vale mais
    ETA_JOB[$idx]=$eta
    VEL_TOTAL=$(( VEL_TOTAL + vel ))
    if [[ $pidx =~ ^[0-9]+$ ]]; then pre_txt+="item ${pidx}${pn:+/$pn} · "; pre+="${DIM}item ${pidx}${pn:+/$pn} · ${R}"; fi
    case $ext in
      vtt|srt|ass|ssa|ttml|dfxp|srv[123]|json3|lrc) tipo=${T[tipo_legendas]} ;;
      *)
        if [[ $vcod == none ]]; then
          tipo=${T[tipo_audio]}
        else                                  # ex.: "vídeo 2160p60" — dá para ver a qualidade chegando
          tipo=${T[tipo_video]}; num "$alt"
          if (( NUM > 0 )); then tipo+=" ${NUM}p"; num "$fps"; (( NUM > 30 )) && tipo+="$NUM"; fi
        fi ;;
    esac

    corta "$titulo" $(( COLS - (2 + 1 + 1 + ${#idxs} + 2) - ${#pre_txt} - 2 ))
    l1="  ${ACENTO}${spin}${R} ${DIM}${idxs}${R}  ${pre}${FMT}"

    # A largura da barra depende só da largura do terminal (não do conteúdo), para
    # ela não "pular" entre quadros; os detalhes à direita entram enquanto couberem.
    bw=$(( COLS - 76 ))
    (( bw > 30 )) && bw=30
    (( bw < 10 )) && bw=10
    resto=$(( COLS - 14 - bw ))                 # "     " + barra + "  " + "100.0%" + margem
    fmt_bytes "$baixado"; fb=$FMT
    if (( total > 0 )); then
      p10=$(( baixado * 1000 / total )); (( p10 > 1000 )) && p10=1000
      printf -v pct '%3d.%d%%' $(( p10 / 10 )) $(( p10 % 10 ))
      fmt_bytes "$total"; ft=$FMT
      detalhe="  ${fb} / ${ft}"
    else
      p10=0; pct="  ··· "
      detalhe="  ${fb}"
    fi
    if (( vel > 0 )); then fmt_bytes "$vel"; vs="${FMT}/s"; fi
    if (( eta > 0 )); then fmt_dur "$eta";  es="ETA ${FMT}"; fi
    for parte in "$vs" "$es" "$tipo"; do
      [[ -n $parte ]] || continue
      (( ${#detalhe} + 2 + ${#parte} <= resto )) || break
      detalhe+="  ${parte}"
    done
    barra $(( p10 * bw / 1000 )) "$bw"
    l2="     ${BARRA}  ${NEG}${pct}${R}${DIM}${detalhe}${R}"
  elif [[ $linha == @@V@@*"$SEP"* ]]; then      # verificação completa (-v): quanto já foi decodificado
    local pos dur bw p10 pct det
    IFS=$SEP read -r pos dur <<<"${linha#@@V@@}"
    num "$pos"; pos=$NUM; num "$dur"; dur=$NUM
    corta "$titulo" $(( COLS - (2 + 1 + 1 + ${#idxs} + 2) - ${#pre_txt} - 2 ))
    l1="  ${ACENTO}${spin}${R} ${DIM}${idxs}${R}  ${pre}${FMT}"
    bw=$(( COLS - 76 )); (( bw > 30 )) && bw=30; (( bw < 10 )) && bw=10
    if (( dur > 0 )); then
      p10=$(( pos * 1000 / dur )); (( p10 > 1000 )) && p10=1000
      printf -v pct '%3d.%d%%' $(( p10 / 10 )) $(( p10 % 10 ))
    else
      p10=0; pct="  ··· "
    fi
    fmt_dur "$pos"; det="  ${T[et_verificando]} · ${FMT}"
    if (( dur > 0 )); then fmt_dur "$dur"; det+=" / ${FMT}"; fi
    corta "$det" $(( COLS - 14 - bw )); det=$FMT
    barra $(( p10 * bw / 1000 )) "$bw"
    l2="     ${BARRA}  ${NEG}${pct}${R}${DIM}${det}${R}"
  else
    # Sem progresso agora: a linha informativa mais recente do log diz a etapa
    # (extraindo, baixando legendas, mesclando, embutindo…).
    ETA_JOB[$idx]=0
    ETAPA=""
    for (( k = ${#ult[@]} - 1; k >= 0; k-- )); do
      etapa_da_linha "${ult[$k]}"
      [[ -n $ETAPA ]] && break
    done
    [[ -z $ETAPA ]] && ETAPA=${T[et_info]}
    corta "$titulo" $(( COLS - (2 + 1 + 1 + ${#idxs} + 2) - ${#pre_txt} - 2 ))
    l1="  ${ACENTO}${spin}${R} ${DIM}${idxs}${R}  ${pre}${FMT}"
    l2="     ${DIM}↳ ${ETAPA}…${R}"
  fi
  LIVE+=("$l1" "$l2")
}

monta_live() {
  LIVE=(); VEL_TOTAL=0
  local s larg reg bw l w i plano partes=() cores=()
  for (( s = 0; s < J; s++ )); do bloco_job "$s"; done

  larg=$(( COLS - 4 )); (( larg > 78 )) && larg=78
  # a régua entre os downloads e o total mostra o estado das teclas (pausado, parando…)
  local msg=""
  if (( PARANDO )); then msg=${T[k_parando]}
  elif (( PAUSADO )); then msg=${T[k_pausado]}
  elif (( MSG_ATE >= SECONDS )); then msg=$MSG_PAINEL
  elif (( ATIVOS == 0 && N_PENDENTES > 0 )) && espera_restante; then t k_espera_site "$FMT" "$NUM"; msg=$TXT
  elif (( CAPTURA && ATIVOS == 0 )); then msg=${T[clip_aguardando]}
  elif (( FILA_VIVA && ATIVOS == 0 )); then t fv_aguardando "$FONTE_LINKS"; msg=$TXT; fi
  if [[ -n $msg ]]; then
    corta "$msg" $(( larg - 6 )); msg=$FMT
    printf -v reg '%*s' $(( larg - 4 - LARG )) ''
    LIVE+=("  ${CINZA}── ${R}${AMARELO}${msg}${R} ${CINZA}${reg// /─}${R}")
  else
    printf -v reg '%*s' "$larg" ''
    LIVE+=("  ${CINZA}${reg// /─}${R}")
  fi

  # barra total com largura fixa por terminal; some em terminal estreito
  l="  ${NEG}${T[total]}${R} "; w=$(( 3 + ${#T[total]} ))
  bw=$(( COLS - 76 )); (( bw > 24 )) && bw=24
  if (( bw >= 6 )); then
    if (( TOTAL > 0 )); then barra $(( FINALIZADOS * bw / TOTAL )) "$bw"; else barra 0 "$bw"; fi
    l+="${BARRA}  "; w=$(( w + bw + 2 ))
  fi
  plano="${FINALIZADOS}/${TOTAL}  ✔ ${N_OK}  ↷ ${N_JA}  ✖ ${N_ERRO}"
  l+="${NEG}${FINALIZADOS}/${TOTAL}${R}  ${VERDE}✔ ${N_OK}${R}  ${AMARELO}↷ ${N_JA}${R}  ${VERMELHO}✖ ${N_ERRO}${R}"
  w=$(( w + ${#plano} ))
  # o resto entra enquanto couber, do mais para o menos importante
  if (( EM_REPETICAO > 0 )); then partes+=("↻ ${EM_REPETICAO}"); cores+=("$AMARELO"); fi
  fmt_tempo "$SECONDS";     partes+=("◷ ${FMT}"); cores+=("$DIM")
  eta_lote
  if (( NUM > 0 )); then fmt_tempo "$NUM"; t restam "$FMT"; partes+=("$TXT"); cores+=("$DIM"); fi
  fmt_bytes "$BYTES_NOVOS"; partes+=("▣ ${FMT}"); cores+=("$DIM")
  if (( VEL_TOTAL > 0 )); then fmt_bytes "$VEL_TOTAL"; partes+=("⇣ ${FMT}/s"); cores+=("$CIANO"); fi
  for i in "${!partes[@]}"; do
    (( w + 2 + ${#partes[$i]} < COLS )) || break
    l+="  ${cores[$i]}${partes[$i]}${R}"; w=$(( w + 2 + ${#partes[$i]} ))
  done
  LIVE+=("$l")
}

# eta_lote → NUM: segundos estimados até o fim do lote (0 = ainda não dá para estimar).
# A média de tempo por link (dos que baixaram algo) vale para os que faltam; os que estão
# rodando usam a previsão do próprio yt-dlp quando há. Com J ao mesmo tempo, o trabalho
# se divide por J, mas nunca termina antes do mais demorado dos que estão rodando.
eta_lote() {
  local s idx media pend e soma=0 maior=0
  NUM=0
  (( T_N > 0 && FINALIZADOS < TOTAL )) || return 0
  media=$(( T_SOMA / T_N )); (( media < 1 )) && media=1
  pend=$N_PENDENTES
  for (( s = 0; s < J; s++ )); do
    idx=${SLOT_IDX[$s]}
    (( idx > 0 )) || continue
    e=${ETA_JOB[$idx]:-0}
    if (( e <= 0 )); then e=$(( media - (SECONDS - ${INICIO_JOB[$idx]:-$SECONDS}) )); (( e < 1 )) && e=1; fi
    soma=$(( soma + e )); (( e > maior )) && maior=$e
  done
  NUM=$(( (soma + pend * media + J - 1) / J ))
  (( NUM < maior )) && NUM=$maior
  return 0
}

# desenha [final] — imprime as linhas permanentes pendentes e redesenha o painel
desenha() {
  local out="" l j
  TICK=$(( TICK + 1 ))
  # DEC 2026 (synchronized output): terminais que suportam só mostram o quadro
  # pronto; os que não suportam ignoram a sequência.
  (( INTERATIVO )) && out+="${ESC}[?2026h"
  if (( INTERATIVO && LIVE_H > 0 )); then
    out+="${ESC}[${LIVE_H}A"$'\r'"${ESC}[J"
    LIVE_H=0
  fi
  for l in "${PERM[@]}"; do out+="$l"$'\n'; done
  PERM=()
  if (( INTERATIVO )) && [[ ${1:-} != final ]]; then
    monta_live
    for l in "${LIVE[@]}"; do out+="$l"$'\n'; done
    LIVE_H=${#LIVE[@]}
    j="${FINALIZADOS}/${TOTAL} · GrabIt"           # título da janela/aba do terminal
    (( FILA_VIVA && ATIVOS == 0 )) && j="GrabIt · ${T[fv_titulo]}"
    if [[ $j != "$JANELA" ]]; then out+="${ESC}]0;${j}"$'\a'; JANELA=$j; fi
  fi
  [[ ${1:-} == final ]] && (( INTERATIVO )) && out+="${ESC}[?7h"   # religa a quebra de linha
  (( INTERATIVO )) && out+="${ESC}[?2026l"
  printf '%s' "$out"
}

# ───────────────────────────── Resultado de cada link ─────────────────────────
salva_log() {                                 # guarda o log de todas as tentativas (sem o spam de progresso)
  local idx=$1 t tent=${TENTATIVA[$1]:-1} nome
  mkdir -p "$LOG_DIR" 2>/dev/null || return 0
  printf -v nome '%s/%0*d.log' "$LOG_DIR" "${#TOTAL}" "$idx"
  {
    printf '# %s\n' "${LINKS[$(( idx - 1 ))]}"
    for (( t = 1; t <= tent; t++ )); do
      if (( tent > 1 )); then t log_tentativa "$t"; printf '\n%s\n' "$TXT"; fi
      if (( t < tent )); then grep -av '^@@P@@' "$TMP/$idx.t$t.log"; else grep -av '^@@P@@' "$TMP/$idx.log"; fi
    done
  } > "$nome" 2>/dev/null
}

processa_resultado() {                        # processa_resultado IDX CÓDIGO_DE_SAÍDA
  local idx=$1 rc=$2 url idxs d n_done n_ja n_hist t tent logs=() dones=() hist=()
  local tipo h fps hdr vc ac canais dur titulo vid caminho tam glifo cor det l hid filtrados=()
  local nota="" n_nota=0
  local -A baixados=()
  url=${LINKS[$(( idx - 1 ))]}
  tent=${TENTATIVA[$idx]:-1}
  printf -v idxs "%0${#TOTAL}d/%d" "$idx" "$TOTAL"
  for (( t = 1; t < tent; t++ )); do logs+=("$TMP/$idx.t$t.log"); done
  logs+=("$TMP/$idx.log")

  # Só na hora de resolver o desafio do YouTube o yt-dlp descobre que o runtime não tem mais
  # suporte (ex.: um Bun novo demais). O aviso ficaria perdido no log: vai para o resumo.
  if [[ -z $AVISO_JSC ]]; then
    AVISO_JSC=$(cat "${logs[@]}" 2>/dev/null | grep -a -m 1 -E '^WARNING: .*\[jsc:[^]]+\] .*is not supported')
    AVISO_JSC=${AVISO_JSC##*\[jsc:*\] }; AVISO_JSC=${AVISO_JSC%% DO NOT*}; AVISO_JSC=${AVISO_JSC//[[:cntrl:]]/ }
  fi

  # Cada vídeo concluído deixa uma linha @@D@@ (em qualquer tentativa). Ele "já
  # existia" só se o yt-dlp avisou "<arquivo final> has already been downloaded"
  # e nenhuma tentativa desta execução o baixou de fato. Compara pelo nome do
  # arquivo: o aviso usa caminho relativo e o @@D@@, absoluto; e pedaços .fNNN
  # deixados por uma execução cancelada não contam.
  mapfile -t dones < <(cat "${logs[@]}" 2>/dev/null | awk -v S="$SEP" '
    index($0, "[download] ") == 1 && / has already been downloaded$/ {
      p = substr($0, 12, length($0) - 39); sub(/.*\//, "", p); ja[p] = 1; next
    }
    /^@@D@@/ {
      d = substr($0, 6); n = split(d, f, S); p = f[n]; sub(/.*\//, "", p); novo = !(p in ja)
      if (!(p in st)) { ordem[++k] = p; st[p] = novo } else if (novo) st[p] = 1
      dado[p] = d; ruim[p] = 0; ult = p
    }
    /^@@V@@ERRO/ { if (ult != "") { ruim[ult] = 1; delete ja[ult] } }   # reprovado na verificação (-v): o próximo é novo
    END { for (i = 1; i <= k; i++) if (!ruim[ordem[i]]) print (st[ordem[i]] ? "N" : "J") S dado[ordem[i]] }')
  n_done=${#dones[@]}

  # -U: o que melhorou (resolução antiga), o que já estava no melhor e o que não está na pasta
  local -A antes=()
  local iguais=() fora=() lado
  if (( UPGRADE )); then
    while IFS= read -r l; do
      case $l in
        "@@U@@↑"*) l=${l#@@U@@↑}; antes[${l%%"$SEP"*}]=${l#*"$SEP"} ;;
        "@@U@@="*) iguais+=("${l#@@U@@=}") ;;
        "@@U@@?"*) fora+=("${l#@@U@@?}") ;;
      esac
    done < <(grep -a '^@@U@@' "$TMP/$idx.log" 2>/dev/null)
  fi

  for d in "${dones[@]}"; do
    IFS=$SEP read -r tipo h fps hdr vc ac dur titulo vid caminho <<<"$d"
    [[ -n $vid ]] && baixados[$vid]=1
    titulo=${titulo//[[:cntrl:]]/ }
    n_nota=$(( n_nota + 1 )); [[ -z $nota ]] && nota=$titulo
    canais=0; tam=0
    # os dados do arquivo gravado (ffprobe) valem mais que os do extrator
    if sonda "$caminho"; then h=$S_H; fps=$S_FPS; hdr=$S_HDR; vc=$S_VC; ac=$S_AC; canais=$S_CANAIS; dur=$S_DUR; tam=$S_TAM; fi
    if (( tam == 0 )); then                     # sem ffprobe: stat do GNU (Linux) ou do BSD (macOS)
      tam=$(stat -c %s -- "$caminho" 2>/dev/null || stat -f %z -- "$caminho" 2>/dev/null)
      num "$tam"; tam=$NUM
    fi
    montar_meta "$h" "$fps" "$hdr" "$vc" "$ac" "$canais" "$dur" "$tam"
    [[ -n ${antes[$vid]:-} ]] && META="${antes[$vid]}p → $META"     # -U: o que era antes
    if [[ $tipo == J ]]; then
      glifo="↷"; cor=$AMARELO; N_JA=$(( N_JA + 1 ))
      META="${T[r_ja_existia]}${META:+ · $META}"
    else
      glifo="✔"; cor=$VERDE; N_OK=$(( N_OK + 1 )); BYTES_NOVOS=$(( BYTES_NOVOS + tam )); BAIXOU=1
    fi
    linha_resultado "$glifo" "$cor" "$idxs" "$titulo" "$META"
    PERM+=("$LINHA")
    # Baixou, mas o melhor que o site tinha é pouco: talvez com login (-b) haja mais
    num "$h"
    if [[ $tipo == N ]] && (( ALERTA > 0 && NUM > 0 && NUM < ALERTA )); then
      N_BAIXA_RES=$(( N_BAIXA_RES + 1 ))
      t r_baixa_det "$NUM"; corta "$TXT" $(( COLS - 13 - ${#T[r_baixa]} ))
      PERM+=("         ${AMARELO}↳ ${T[r_baixa]}${R}${DIM} ${FMT}${R}")
    fi
  done

  # Pulados pelo histórico: o yt-dlp nem abre o vídeo, então não há @@D@@.
  # A linha é "<id>: has already…" (pulado antes de acessar o site) ou
  # "<id>: <título> has already…" (pulado depois de ler a página).
  mapfile -t hist < <(cat "${logs[@]}" 2>/dev/null | grep -a 'has already been recorded in the archive$' | sort -u)
  # Um vídeo baixado na 1ª tentativa aparece como "já no histórico" na 2ª: não conta duas vezes.
  for l in "${hist[@]}"; do
    hid=${l#\[download\] }; hid=${hid%%: *}
    [[ -n ${baixados[$hid]:-} ]] || filtrados+=("$l")
  done
  hist=("${filtrados[@]}")
  n_hist=${#hist[@]}
  if (( n_hist > 0 )); then
    N_JA=$(( N_JA + n_hist )); n_nota=$(( n_nota + n_hist ))
    if (( n_done == 0 && n_hist == 1 )); then
      titulo=${hist[0]#\[download\] }
      titulo=${titulo% has already been recorded in the archive}
      if [[ $titulo == *": "* ]]; then titulo=${titulo#*: }; else titulo=""; fi
      titulo=${titulo//[[:cntrl:]]/ }
      nota=${titulo:-${TITULO[$idx]:-}}
      linha_resultado "↷" "$AMARELO" "$idxs" "${titulo:-${TITULO[$idx]:-$url}}" "${T[r_ja_baixado]}"
    else
      t r_n_ja_baixados "$n_hist"; linha_resultado "↷" "$AMARELO" "$idxs" "$url" "$TXT"
    fi
    PERM+=("$LINHA")
  fi

  if (( ${#iguais[@]} + ${#fora[@]} > 0 )); then
    N_JA=$(( N_JA + ${#iguais[@]} + ${#fora[@]} ))
    if (( n_done == 0 && ${#iguais[@]} + ${#fora[@]} == 1 )); then
      if (( ${#iguais[@]} )); then
        IFS=$SEP read -r _ lado titulo <<<"${iguais[0]}"; t r_sem_melhor "$lado"
      else
        IFS=$SEP read -r _ titulo <<<"${fora[0]}"; TXT=${T[r_fora]}
      fi
      linha_resultado "↷" "$AMARELO" "$idxs" "${titulo:-$url}" "$TXT"
    else
      lado=""
      (( ${#iguais[@]} )) && { t r_sem_melhor_n "${#iguais[@]}"; lado=$TXT; }
      (( ${#fora[@]} )) && { t r_fora_n "${#fora[@]}"; lado+="${lado:+, }$TXT"; }
      linha_resultado "↷" "$AMARELO" "$idxs" "$url" "$lado"
    fi
    PERM+=("$LINHA")
    n_hist=1                                    # já foi contado: o bloco de baixo não vale
  fi

  if (( n_done == 0 && n_hist == 0 && rc == 0 )); then
    titulo=${TITULO[$idx]:-$url}
    nota=${TITULO[$idx]:-}
    n_ja=$(cat "${logs[@]}" 2>/dev/null | grep -ac 'has already been downloaded')
    if (( n_ja > 0 )); then
      N_JA=$(( N_JA + 1 ))
      linha_resultado "↷" "$AMARELO" "$idxs" "$titulo" "${T[r_ja_existia]}"
    else
      N_OK=$(( N_OK + 1 ))
      linha_resultado "✔" "$VERDE" "$idxs" "$titulo" "${T[r_concluido]}"
    fi
    PERM+=("$LINHA")
  fi

  if (( rc != 0 )); then
    analisa_log "$TMP/$idx.log"
    if (( N_FATAIS == 0 && N_COSMETICOS > 0 && n_done > 0 )); then
      # Tudo foi entregue; só um acabamento falhou. Aviso, não falha.
      case $AVISO_CTX in
        "[ThumbnailsConvertor]"*) det=${T[r_av_capa]} ;;
        "[SponsorBlock]"*)        det=${T[r_av_sponsor]} ;;
        *)                        det=${T[r_av_outro]} ;;
      esac
      t r_av_completo "$det"; corta "$TXT" $(( COLS - 13 - ${#T[r_aviso]} ))
      PERM+=("         ${AMARELO}↳ ${T[r_aviso]}${R}${DIM} ${FMT}${R}")
      N_AVISOS=$(( N_AVISOS + 1 ))
      salva_log "$idx"
      rc=0
    fi
  fi

  if (( rc != 0 )); then
    classifica_erro "$MOTIVO"
    # a última tentativa pode ter dito só "403": o motivo de verdade veio na primeira
    if grep -aqF 'anti-bot challenge' "${logs[@]}" 2>/dev/null; then DICA=${T[d_antirobo]}; DICA_NAVEGADOR=1; fi
    MOTIVO=$(sed -E 's/^ERROR: //; s/^\[[^]]+\] //; s/^[^ :]+: //; s/ \(caused by .*$//; s/; please report this issue.*$//' <<<"$MOTIVO")
    if (( n_done > 0 || n_hist > 0 )); then
      linha_resultado "⚠" "$AMARELO" "$idxs" "${TITULO[$idx]:-$url}" "${T[r_parcial]}"
    elif (( tent > 1 )); then
      t r_falhou_n "$tent"; linha_resultado "✖" "$VERMELHO" "$idxs" "${TITULO[$idx]:-$url}" "$TXT"
    else
      linha_resultado "✖" "$VERMELHO" "$idxs" "${TITULO[$idx]:-$url}" "${T[r_falhou]}"
    fi
    if [[ -n $DICA ]]; then                     # "↳ dica no idioma do usuário · mensagem original"
      corta "$MOTIVO" $(( COLS - 15 - ${#DICA} ))
      det="${VERMELHO}↳ ${DICA}${R}"
      (( LARG >= 10 )) && det+="${DIM} · ${FMT}${R}"
    else
      t r_codigo "$rc"; corta "${MOTIVO:-$TXT}" $(( COLS - 12 ))
      det="${VERMELHO}↳ ${FMT}${R}"
    fi
    PERM+=("$LINHA" "         $det")
    FALHAS+=("$url")
    N_ERRO=$(( N_ERRO + 1 ))
    salva_log "$idx"
    # Sem espaço, os próximos também falhariam (depois de baixar um bom pedaço): para aqui
    if (( DISCO_CHEIO && ! PARANDO )); then
      PARANDO=1
      PERM+=("  ${AMARELO}⚠${R} ${T[d_disco_para]}")
    fi
  fi
  if (( rc == 0 )); then
    SUCESSO[$idx]=1
    lembra_metodo "${SITE[$idx]:-}" "${NIVEL[$idx]:-0}"
    if (( n_nota > 1 )); then
      if [[ -n $nota ]]; then t nota_n "$n_nota" "$nota"; else t nota_n0 "$n_nota"; fi
      nota=$TXT
    fi
    NOTA[$idx]=$nota                           # vai junto com o link para a seção BAIXADOS
  fi

  FEITO[$idx]=1
  FINALIZADOS=$(( FINALIZADOS + 1 ))
}

# ───────────────────────────── Execução dos jobs ──────────────────────────────
lanca_job() {                                 # lanca_job IDX
  local i=$1 url=${LINKS[$(( $1 - 1 ))]} tent=${TENTATIVA[$1]:-1} extra=() ajuste=() idxs s e
  # A cascata vai do método mais rápido ao mais caro: 0 é direto; 1 manda o Referer, que os
  # vídeos protegidos contra links de fora costumam exigir, força a imitação de navegador (o
  # próprio yt-dlp avisa que forçá-la sempre pode deixar os downloads mais lentos e instáveis)
  # e leva o ajuste para o erro que deu; 2 é pelo navegador. Veja nivel_do_link e vale_repetir.
  nivel_do_link "$i"
  if (( NIVEL[$i] == 1 )); then
    (( MODO_CURL )) || extra+=(--referer "$url")
    [[ -n $IMPERSONATE ]] && extra+=(--impersonate "$IMPERSONATE")
  fi
  read -ra ajuste <<<"${AJUSTES[$i]:-}"
  extra+=("${ajuste[@]}")
  # Playlist e canal viram dezenas de pedidos seguidos ao mesmo site, num processo só
  case $url in
    *[?\&]list=*|*/playlist*|*/channel/*|*/c/*|*/@*|*/user/*|*/videos) extra+=(--sleep-requests 0.5) ;;
  esac
  # O intervalo até o próximo download deste site. Quem já pediu calma vai com menos conexões
  # e com pausas entre os pedidos, e com um intervalo maior.
  s=${SITE[$i]}
  if (( ${BLOQ_SITE[$s]:-0} )); then
    extra+=(-N 1 --sleep-requests 1)
    e=$(( ESPERA_BASE > 0 ? SECONDS + 2 + RANDOM % 3 : SECONDS ))
  elif (( FORCAR || PAUSA_ENTRE_VIDEOS > 0 )); then
    e=$SECONDS
  else
    e=$(( SECONDS + 1 ))
  fi
  (( e > ${PROX_INICIO_SITE[$s]:-0} )) && PROX_INICIO_SITE[$s]=$e
  # O arquivo da tentativa anterior veio corrompido: sem isso o yt-dlp o reaproveitaria
  # ("has already been downloaded") e falharia igual. Itens já concluídos estão no
  # histórico e continuam sendo pulados.
  (( ${REBAIXAR[$i]:-0} )) && extra+=(--force-overwrites)
  if (( NIVEL[$i] == 2 )); then
    mkdir "$TMP/navegador.trava" 2>/dev/null; NAV_DONO=$i    # uma janela por vez: o perfil é um só
    if (( ! NAV_AVISADO )); then
      NAV_AVISADO=1; t nav_abrindo "$NAV_ROTULO"; PERM+=("  ${CIANO}↗${R} $TXT")
    fi
    baixa_pelo_navegador "$url" "$i" </dev/null >"$TMP/$i.log" 2>&1 &
  else
    baixa_link "$url" "${extra[@]}" </dev/null >"$TMP/$i.log" 2>&1 &
  fi
  ULTIMO_PID=$!
  ATIVOS_SITE[${SITE[$i]}]=$(( ${ATIVOS_SITE[${SITE[$i]}]:-0} + 1 ))
  INICIO_JOB[$i]=$SECONDS; ETA_JOB[$i]=0
  if (( ! INTERATIVO )); then                  # sem painel (saída redirecionada): avisa o início
    printf -v idxs "%0${#TOTAL}d/%d" "$i" "$TOTAL"
    if (( tent > 1 )); then t ni_tentativa "$tent"; PERM+=("  ↻ ${idxs}  ${url}  $TXT"); else PERM+=("  ▶ ${idxs}  ${url}"); fi
  fi
}

# baixa_link URL [OPÇÕES EXTRAS…]: roda em segundo plano, com a saída indo para o log.
# Com -u, antes descobre qual é o vídeo principal da página e pede só ele.
baixa_link() {
  local url=$1 escolha=()
  shift
  if (( UPGRADE )); then upgrade_link "$url" "$@"; exit $?; fi
  if (( SO_PRINCIPAL )); then
    printf '[grabit] principal\n'
    escolhe_principal "$url" "$@" && escolha=(--playlist-items "$PRINCIPAL")
  fi
  exec yt-dlp "${YTDLP_ARGS[@]}" "$@" "${escolha[@]}" -- "$url"
}

# ───── Modo upgrade (-U): para cada vídeo do link, compara a melhor versão que o site tem
# ───── hoje com o arquivo que já está na pasta e só baixa de novo o que ficou melhor
# ───── (resolução maior, mais quadros por segundo ou HDR). O arquivo antigo sai do
# ───── caminho e só é apagado quando o novo chega; se não chegar, ele volta.
acha_arquivo() {                              # acha_arquivo ID → ACHADO: o vídeo "… [ID].ext" na pasta
  local g=$1 f
  ACHADO=""
  g=${g//\\/\\\\}; g=${g//\*/\\*}; g=${g//\?/\\?}; g=${g//\[/\\[}; g=${g//\]/\\]}
  while IFS= read -r -d '' f; do
    case $f in
      *.part|*.ytdl|*.nfo|*.jpg|*.png|*.webp|*.avif|*.json|*.vtt|*.srt|*.grabit-antigo) continue ;;
      *"${T[sufixo_ruim]}".*) continue ;;
    esac
    ACHADO=$f; return 0
  done < <(find "$PASTA_SAIDA" \( -path "$PASTA_SAIDA/.parciais" -o -path "$PASTA_SAIDA/logs" \) -prune \
             -o -type f -name "*\\[$g\\].*" -print0 2>/dev/null)
  return 1
}

upgrade_link() {
  local url=$1 args=() itens=() id idx alt larg fps hdr titulo novo melhor n=0 rc
  local -A antigo=()
  shift
  printf '[grabit] upgrade\n'
  [[ -n $COOKIES_NAVEGADOR ]] && args+=(--cookies-from-browser "$COOKIES_NAVEGADOR")
  [[ -n $USER_AGENT ]] && args+=(--user-agent "$USER_AGENT")
  (( TEM_JS_RUNTIMES )) && [[ -n $JS_RUNTIME ]] && args+=(--js-runtimes "$JS_RUNTIME:$JS_PATH")
  (( SEM_PLAYLIST )) && args+=(--no-playlist)
  while IFS=$SEP read -r idx id alt larg fps hdr titulo; do
    [[ -n $id ]] || continue
    n=$(( n + 1 ))
    titulo=${titulo//[[:cntrl:]]/ }
    if ! acha_arquivo "$id"; then printf '@@U@@?%s%s%s\n' "$id" "$SEP" "$titulo"; continue; fi
    sonda "$ACHADO"
    num "$alt"; novo=$NUM; num "$larg"; (( NUM > 0 && NUM < novo )) && novo=$NUM   # o lado menor
    num "$fps"; fps=$NUM
    melhor=0                                    # resolução maior; ou a mesma com mais fps ou com HDR
    if (( novo > S_H )); then melhor=1
    elif (( novo == S_H && novo > 0 )); then
      (( fps > S_FPS + 1 )) && melhor=1
      [[ $hdr != SDR && $hdr != NA && $S_HDR == SDR ]] && melhor=1
    fi
    if (( melhor )); then
      itens+=("$idx"); antigo[$id]=$ACHADO
      printf '@@U@@↑%s%s%s\n' "$id" "$SEP" "$S_H"
    else
      printf '@@U@@=%s%s%s%s%s\n' "$id" "$SEP" "$S_H" "$SEP" "$titulo"
    fi
  done < <(yt-dlp --ignore-config --no-warnings --simulate -f "$FORMATO" \
             --print "%(playlist_index|0)s${SEP}%(id)s${SEP}%(height|0)s${SEP}%(width|0)s${SEP}%(fps|0)s${SEP}%(dynamic_range|SDR)s${SEP}%(title)s" \
             "${args[@]}" "$@" -- "$url" 2>/dev/null)
  # a consulta falhou (site fora do ar, link removido…): o download normal mostra o motivo
  (( n > 0 )) || exec yt-dlp "${YTDLP_ARGS[@]}" "$@" -- "$url"
  (( ${#itens[@]} )) || return 0

  # Sem o histórico (o vídeo já está nele) e sobrescrevendo; só os itens que melhoraram
  local filtrados=() i sel=()
  for (( i = 0; i < ${#YTDLP_ARGS[@]}; i++ )); do
    if [[ ${YTDLP_ARGS[$i]} == --download-archive ]]; then i=$(( i + 1 )); continue; fi
    filtrados+=("${YTDLP_ARGS[$i]}")
  done
  [[ ${itens[0]} != 0 ]] && sel=(--playlist-items "$(IFS=,; printf '%s' "${itens[*]}")")
  for id in "${!antigo[@]}"; do mv -f -- "${antigo[$id]}" "${antigo[$id]}.grabit-antigo"; done
  trap 'devolve_antigos; exit 143' TERM INT HUP
  yt-dlp "${filtrados[@]}" --force-overwrites "${sel[@]}" "$@" -- "$url"; rc=$?
  trap - TERM INT HUP
  devolve_antigos
  return "$rc"
}

devolve_antigos() {                           # o novo chegou? apaga o antigo. Não chegou? ele volta.
  local id
  for id in "${!antigo[@]}"; do
    [[ -e ${antigo[$id]}.grabit-antigo ]] || continue
    if acha_arquivo "$id"; then rm -f -- "${antigo[$id]}.grabit-antigo"
    else mv -f -- "${antigo[$id]}.grabit-antigo" "${antigo[$id]}"; fi
  done
}

# Um -U derrubado à força (queda de energia, SIGKILL) não chegou a devolver os antigos: eles
# ficaram de lado com outro nome, invisíveis para o GrabIt. A próxima execução arruma. Um
# arquivo com o nome original é o novo, inteiro: só chega à pasta depois de pronto.
recupera_antigos() {
  local f
  while IFS= read -r -d '' f; do
    if [[ -e ${f%.grabit-antigo} ]]; then rm -f -- "$f"
    else mv -f -- "$f" "${f%.grabit-antigo}"; fi
  done < <(find "$PASTA_SAIDA" -type f -name '*.grabit-antigo' -print0 2>/dev/null)
}

# escolhe_principal URL [OPÇÕES…] → PRINCIPAL: o item mais longo da página (empate: o de
# maior resolução, depois o primeiro). O yt-dlp lista os vídeos de uma página na ordem
# em que os acha, não na ordem da página; e prévias e relacionados costumam ser curtos.
# Quando o site não informa a duração, o ffprobe lê só o cabeçalho do vídeo.
# Falha (= baixa o link como está) se não houver mais de um vídeo para comparar.
escolhe_principal() {
  local url=$1 idx dur alt link n=0 melhor=0 melhor_dur=-1 melhor_alt=-1 args=()
  shift
  [[ -n $COOKIES_NAVEGADOR ]] && args+=(--cookies-from-browser "$COOKIES_NAVEGADOR")
  [[ -n $USER_AGENT ]] && args+=(--user-agent "$USER_AGENT")
  (( TEM_JS_RUNTIMES )) && [[ -n $JS_RUNTIME ]] && args+=(--js-runtimes "$JS_RUNTIME:$JS_PATH")
  (( SEM_PLAYLIST )) && args+=(--no-playlist)
  while IFS=$SEP read -r idx dur alt link; do
    num "$idx"; idx=$NUM
    (( idx > 0 )) || continue
    n=$(( n + 1 ))
    num "$dur"; dur=$NUM
    if (( dur == 0 )) && [[ $link == http* ]] && command -v ffprobe >/dev/null 2>&1; then
      dur=$(ffprobe -v error -rw_timeout 15000000 -show_entries format=duration -of csv=p=0 -- "$link" 2>/dev/null)
      num "$dur"; dur=$NUM
    fi
    num "$alt"; alt=$NUM
    if (( dur > melhor_dur || (dur == melhor_dur && alt > melhor_alt) )); then
      melhor=$idx; melhor_dur=$dur; melhor_alt=$alt
    fi
  done < <(yt-dlp --ignore-config --no-warnings --simulate --playlist-items 1:20 -f "$FORMATO" \
             --print "%(playlist_index|0)s${SEP}%(duration|0)s${SEP}%(height|0)s${SEP}%(requested_formats.0.url,url|)s" \
             "${args[@]}" "$@" -- "$url" 2>/dev/null)
  (( n > 1 )) || return 1
  PRINCIPAL=$melhor
  printf '[grabit] principal: item %d de %d\n' "$PRINCIPAL" "$n"
}

# escolhe_proximo → ESCOLHIDO: o próximo link a começar (primeiro os novos, na ordem da
# lista, depois as novas tentativas), pulando os de um site que já está no limite.
escolhe_proximo() {
  local s melhor="" at pend i melhor_at=0 melhor_pend=0
  ESCOLHIDO=0
  for s in "${SITES[@]}"; do
    pend=${PEND_SITE[$s]}
    (( pend > 0 )) || continue
    at=${ATIVOS_SITE[$s]:-0}
    site_pode_comecar "$s" "$at" || continue
    # o site com menos downloads rodando; no empate, o que tem mais links esperando
    if [[ -z $melhor ]] || (( at < melhor_at || (at == melhor_at && pend > melhor_pend) )); then
      melhor=$s; melhor_at=$at; melhor_pend=$pend
    fi
  done
  [[ -n $melhor ]] || return 1
  i=${FILA_CAB[$melhor]}
  FILA_CAB[$melhor]=${SEG[$i]}
  PEND_SITE[$melhor]=$(( melhor_pend - 1 )); N_PENDENTES=$(( N_PENDENTES - 1 ))
  ESCOLHIDO=$i
  if [[ -z ${INICIADO[$i]:-} ]]; then INICIADO[$i]=1; N_INICIADOS=$(( N_INICIADOS + 1 )); fi
  return 0
}

# ───── Os links ficam em filas, uma por site, e os downloads se espalham entre os sites: com
# ───── 4 vagas e 4 sites, é um de cada, e nenhum deles recebe uma rajada só porque os links
# ───── dele vieram juntos na lista. Listas encadeadas: nem uma lista de milhares pesa no Bash.
enfileira() {                                 # enfileira IDX: no fim da fila do site dele
  local i=$1 s=${SITE[$1]}
  SEG[$i]=0
  if (( ${PEND_SITE[$s]:-0} == 0 )); then FILA_CAB[$s]=$i; else SEG[${FILA_RAB[$s]}]=$i; fi
  FILA_RAB[$s]=$i
  [[ -n ${PEND_SITE[$s]+x} ]] || SITES+=("$s")
  PEND_SITE[$s]=$(( ${PEND_SITE[$s]:-0} + 1 )); N_PENDENTES=$(( N_PENDENTES + 1 ))
}

# reenfileira IDX: na frente da fila. A nova tentativa sai antes dos outros links do site: é
# ela que descobre o caminho certo, e eles não gastam pedidos num que já se viu que falha.
reenfileira() {
  local i=$1 s=${SITE[$1]}
  if (( ${PEND_SITE[$s]:-0} == 0 )); then SEG[$i]=0; FILA_RAB[$s]=$i; else SEG[$i]=${FILA_CAB[$s]}; fi
  FILA_CAB[$s]=$i
  PEND_SITE[$s]=$(( ${PEND_SITE[$s]:-0} + 1 )); N_PENDENTES=$(( N_PENDENTES + 1 ))
}

# ───── Cada site tem o seu ritmo, como o TCP: começa com um download só e sobe um a cada um que
# ───── o site aceita. Se ele pedir calma (429), o limite cai pela metade e ele fica um tempo sem
# ───── novos pedidos, cada vez mais longo; os outros sites seguem. Se continuar recusando, os
# ───── links que faltam dele ficam para depois, em vez de gastar tentativas contra um bloqueio.
# ───── -F dispensa o começo devagar e o intervalo, mas um 429 continua valendo.

# site_pode_comecar SITE ATIVOS: chegou a hora desse site, há vaga nele e, se o próximo link dele
# vai pelo navegador, a janela está livre? (Enquanto ela está ocupada, os outros sites passam.)
site_pode_comecar() {
  local s=$1 at=$2 lim=${LIM_SITE[$s]:-1}
  if (( ${PARADO_SITE[$s]:-0} )); then adia_site "$s"; return 1; fi
  (( SECONDS >= ${PROX_INICIO_SITE[$s]:-0} )) || return 1
  (( FORCAR && ! ${BLOQ_SITE[$s]:-0} )) && lim=$J_ALVO
  (( LIMITE_POR_SITE > 0 && LIMITE_POR_SITE < lim )) && lim=$LIMITE_POR_SITE
  (( at < lim )) || return 1
  nivel_previsto "${FILA_CAB[$s]}"
  (( NUM < 2 )) || [[ ! -d $TMP/navegador.trava ]]
}

# site_aceitou SITE: um download dele começou de verdade (ou terminou bem)
site_aceitou() {
  local s=$1 falta=1 c
  FALHAS_SITE[$s]=0
  (( ${BLOQ_SITE[$s]:-0} )) && falta=5         # depois de um 429, sobe bem mais devagar
  c=$(( ${CREDITO_SITE[$s]:-0} + 1 ))
  if (( c >= falta )); then
    c=0
    (( ${LIM_SITE[$s]:-1} < 16 )) && LIM_SITE[$s]=$(( ${LIM_SITE[$s]:-1} + 1 ))
    if (( ${BLOQ_SITE[$s]:-0} )); then BLOQ_SITE[$s]=$(( ${BLOQ_SITE[$s]} - 1 )); ESPERA_SITE[$s]=$(( ${ESPERA_SITE[$s]:-0} / 2 )); fi
  fi
  CREDITO_SITE[$s]=$c
}

# site_pediu_calma SITE: 429 ou parecido. Vários downloads do site recebem o aviso ao mesmo tempo:
# dentro da mesma espera, conta uma vez só.
site_pediu_calma() {
  local s=$1 e lim
  (( SECONDS >= ${PROX_INICIO_SITE[$s]:-0} )) || return 0
  e=${ESPERA_SITE[$s]:-0}
  if (( e == 0 )); then e=$ESPERA_BASE; else e=$(( e * 2 )); fi
  (( e > 600 )) && e=600
  ESPERA_SITE[$s]=$e
  BLOQ_SITE[$s]=$(( ${BLOQ_SITE[$s]:-0} + 1 ))
  lim=$(( ${LIM_SITE[$s]:-1} / 2 )); (( lim < 1 )) && lim=1
  LIM_SITE[$s]=$lim; CREDITO_SITE[$s]=0
  PROX_INICIO_SITE[$s]=$(( SECONDS + e + RANDOM % (e / 4 + 1) ))
  t k_freio "$s" "$lim" "$e"; PERM+=("  ${AMARELO}⚠${R} $TXT")
  lembra_espera "$s" "$e"
  (( ${BLOQ_SITE[$s]} >= 4 )) && para_site "$s"
  return 0
}

para_site() {
  local s=$1
  (( ${PARADO_SITE[$s]:-0} )) && return 0
  PARADO_SITE[$s]=1
  t k_parado "$s"; PERM+=("  ${AMARELO}⚠${R} $TXT")
}

# adia_site SITE: os links que faltavam dele vão para a lista de falhas, para outra hora
adia_site() {
  local s=$1 i
  while (( ${PEND_SITE[$s]:-0} > 0 )); do
    i=${FILA_CAB[$s]}
    FILA_CAB[$s]=${SEG[$i]}
    PEND_SITE[$s]=$(( ${PEND_SITE[$s]} - 1 )); N_PENDENTES=$(( N_PENDENTES - 1 ))
    (( ${TENTATIVA[$i]:-1} > 1 )) && EM_REPETICAO=$(( EM_REPETICAO - 1 ))
    FALHAS+=("${LINKS[$(( i - 1 ))]}")
    FEITO[$i]=1; FINALIZADOS=$(( FINALIZADOS + 1 )); N_ADIADOS=$(( N_ADIADOS + 1 ))
  done
}

# vigia_saude: o download já está chegando? Então o site aceitou, e dá para abrir mais uma vaga
# nele sem esperar o vídeo inteiro terminar.
vigia_saude() {
  local s idx
  for (( s = 0; s < J; s++ )); do
    idx=${SLOT_IDX[$s]}
    (( idx > 0 )) && [[ -z ${SAUDAVEL[$idx]:-} ]] || continue
    grep -aqm 1 '^@@[PD]@@' "$TMP/$idx.log" 2>/dev/null || continue
    SAUDAVEL[$idx]=1
    site_aceitou "${SITE[$idx]}"
  done
  return 0
}

# aplica_esperas: quem pediu calma numa execução recente continua com a espera dela, e sem pressa
aplica_esperas() {
  local s agora resto
  (( ! FORCAR )) || return 0
  printf -v agora '%(%s)T' -1
  for s in "${SITES[@]}"; do
    resto=$(( ${ESPERA_ATE[$s]:-0} - agora ))
    (( resto > 0 )) || continue
    PROX_INICIO_SITE[$s]=$(( SECONDS + resto )); BLOQ_SITE[$s]=1
    t k_espera_ant "$s" "$resto"; PERM+=("  ${AMARELO}⚠${R} $TXT")
  done
}

# espera_restante → FMT (o site) e NUM (segundos): o site cuja espera termina primeiro
espera_restante() {
  local s r
  FMT=""; NUM=0
  for s in "${SITES[@]}"; do
    (( ${PEND_SITE[$s]:-0} > 0 )) || continue
    r=$(( ${PROX_INICIO_SITE[$s]:-0} - SECONDS ))
    (( r > 1 )) || continue
    if [[ -z $FMT ]] || (( r < NUM )); then FMT=$s; NUM=$r; fi
  done
  [[ -n $FMT ]]
}

# ───── A cascata lembra: numa lista longa, repetir em todo link o caminho que já se sabe que
# ───── falha é o que mais custa. Cada site guarda o nível que funcionou (metodos.txt, fora da
# ───── pasta do projeto) e os próximos links já começam nele. A memória vence em 30 dias, para
# ───── o site ter a chance de voltar ao caminho rápido, e cai se o método deixar de funcionar.
carrega_metodos() {
  local site n quando ate agora
  ARQ_METODOS="${XDG_DATA_HOME:-$HOME/.local/share}/grabit/metodos.txt"
  [[ -r $ARQ_METODOS ]] || return 0
  printf -v agora '%(%s)T' -1
  while read -r site n quando ate; do
    [[ $site =~ ^[a-z0-9._?-]+$ && $n =~ ^[012]$ && $quando =~ ^[0-9]+$ ]] || continue
    if (( n > 0 && agora - quando < 2592000 )); then METODO[$site]=$n; METODO_QUANDO[$site]=$quando; fi
    [[ $ate =~ ^[0-9]+$ ]] && (( ate > agora )) && ESPERA_ATE[$site]=$ate
  done < "$ARQ_METODOS"
}

# Uma linha por site: o site, o nível que funcionou, desde quando, e até quando ele pediu calma
grava_metodos() {
  local site agora
  [[ -n $ARQ_METODOS ]] || return 0
  mkdir -p "${ARQ_METODOS%/*}" 2>/dev/null || return 0
  printf -v agora '%(%s)T' -1
  for site in "${!METODO[@]}"; do
    printf '%s %s %s %s\n' "$site" "${METODO[$site]}" "${METODO_QUANDO[$site]:-0}" "${ESPERA_ATE[$site]:-0}"
  done > "$ARQ_METODOS.tmp" 2>/dev/null || return 0
  for site in "${!ESPERA_ATE[@]}"; do
    [[ -z ${METODO[$site]:-} ]] && (( ${ESPERA_ATE[$site]} > agora )) && printf '%s 0 %s %s\n' "$site" "$agora" "${ESPERA_ATE[$site]}"
  done >> "$ARQ_METODOS.tmp"
  mv -f -- "$ARQ_METODOS.tmp" "$ARQ_METODOS"
}

lembra_espera() {                             # lembra_espera SITE SEGUNDOS
  local agora
  printf -v agora '%(%s)T' -1
  ESPERA_ATE[$1]=$(( agora + $2 ))
  grava_metodos
}

lembra_metodo() {                             # lembra_metodo SITE NÍVEL
  local site=$1 n=$2
  [[ -n $site ]] && (( ! MODO_CURL && ! UPGRADE )) || return 0
  [[ ${METODO[$site]:-0} == "$n" ]] && return 0
  if (( n == 0 )); then
    unset "METODO[$site]" "METODO_QUANDO[$site]"
  else
    METODO[$site]=$n; printf -v "METODO_QUANDO[$site]" '%(%s)T' -1
  fi
  grava_metodos
}

# nivel_previsto IDX → NUM: por onde o link iria agora. Só se decide de vez quando ele começa
# (nivel_do_link): até lá, outro link do site pode ter descoberto um caminho melhor.
nivel_previsto() {
  local i=$1 n=0 site=${SITE[$1]:-}
  if [[ -n ${NIVEL[$i]:-} ]]; then NUM=${NIVEL[$i]}; return 0; fi
  if [[ -n $site ]] && (( ! MODO_CURL && ! UPGRADE )); then n=${METODO[$site]:-0}; fi
  (( n == 2 )) && ! pode_navegador && n=1
  NUM=$n
}

nivel_do_link() {
  [[ -n ${NIVEL[$1]:-} ]] && return 0
  nivel_previsto "$1"
  NIVEL[$1]=$NUM; NIVEL_INICIO[$1]=$NUM
}

# site_de URL → FMT: o site do link, para o limite por site (www.youtube.com,
# m.youtube.com e youtu.be contam todos como youtube.com)
site_de() {
  local h=${1#*://}
  h=${h%%[/?#]*}; h=${h##*@}; h=${h%%:*}; h=${h,,}
  # Vira chave de tabelas do Bash: um link de fora (a captura -C lê o que vier) não pode levar
  # nada além de um nome de site, ou "$(…)" num link acabaria executado.
  h=${h//[!a-z0-9.-]/_}
  [[ $h == youtu.be ]] && h=youtube.com
  if [[ $h =~ ([^.]+\.(com|co|net|org|gov|edu|ac)\.[a-z]{2})$ ]]; then h=${BASH_REMATCH[1]}
  elif [[ $h =~ ([^.]+\.[^.]+)$ ]]; then h=${BASH_REMATCH[1]}; fi
  FMT=${h:-?}
}

# ───── Teclas no painel: p pausa/continua · q termina depois dos atuais (de novo: cancela)
# ───── + e - mudam quantos downloads rodam ao mesmo tempo
sinaliza_arvore() {                           # sinaliza_arvore PID SINAL (o processo e seus filhos)
  local f
  for f in $(pgrep -P "$1" 2>/dev/null); do sinaliza_arvore "$f" "$2"; done
  kill -s "$2" "$1" 2>/dev/null
}

alterna_pausa() {
  local s sinal=STOP
  if (( PAUSADO )); then PAUSADO=0; sinal=CONT; else PAUSADO=1; fi
  for (( s = 0; s < J; s++ )); do
    (( SLOT_IDX[$s] > 0 )) && sinaliza_arvore "${SLOT_PID[$s]}" "$sinal"
  done
}

muda_simultaneos() {                          # muda_simultaneos +1|-1
  local novo=$(( J_ALVO + $1 )) linhas max
  linhas=$(tput lines 2>/dev/null); [[ $linhas =~ ^[0-9]+$ ]] || linhas=24
  max=$(( (linhas - 3) / 2 )); (( max < 1 )) && max=1          # o painel precisa caber na tela
  (( ! FILA_VIVA && max > TOTAL )) && max=$TOTAL
  (( novo > max )) && novo=$max
  (( novo < 1 )) && novo=1
  J_ALVO=$novo
  while (( J < J_ALVO )); do SLOT_IDX[$J]=0; SLOT_PID[$J]=0; J=$(( J + 1 )); done
  t k_simultaneos "$J_ALVO"; MSG_PAINEL=$TXT; MSG_ATE=$(( SECONDS + 3 ))
}

trata_tecla() {
  case $1 in
    p|P|" ") alterna_pausa ;;
    q|Q)
      if (( PARANDO )); then CANCELADO=1; SINAL=INT; exit 130; fi   # q de novo = Ctrl+C
      PARANDO=1
      (( PAUSADO )) && alterna_pausa ;;
    +|=) muda_simultaneos 1 ;;
    -|_) muda_simultaneos -1 ;;
  esac
  return 0
}

# ───── Fila viva (-f): depois da lista, o GrabIt continua aberto vigiando os arquivos de
# ───── links; o que for acrescentado entra no fim da fila.
novos_links() {
  local arq m linha palavra palavras=() bruto=() n=0 salva=$N_NA_SECAO
  for arq in "${ARQUIVOS_ENTRADA[@]}"; do
    [[ -f $arq && -r $arq ]] || continue
    m=$(stat -c %Y:%s -- "$arq" 2>/dev/null || stat -f %m:%z -- "$arq" 2>/dev/null)
    [[ $m == "${MARCA_ARQ[$arq]:-}" ]] && continue
    MARCA_ARQ[$arq]=$m
    bruto=()
    le_lista "$arq"
    for linha in "${bruto[@]}"; do
      IFS=$' \t\r' read -ra palavras <<<"${linha#$'\xef\xbb\xbf'}"
      (( ${#palavras[@]} )) || continue
      [[ ${palavras[0]} == \#* ]] && continue
      links_da_linha "$linha"
      for palavra in "${PALAVRAS_LINK[@]}"; do
        [[ -n ${CONHECIDO[$palavra]:-} ]] && continue
        CONHECIDO[$palavra]=1; LINKS+=("$palavra"); TOTAL=$(( TOTAL + 1 ))
        site_de "$palavra"; SITE[$TOTAL]=$FMT
        enfileira "$TOTAL"
        n=$(( n + 1 ))
      done
    done
  done
  N_NA_SECAO=$salva
  if (( n > 0 )); then t fv_novos "$n"; MSG_PAINEL=$TXT; MSG_ATE=$(( SECONDS + 4 )); fi
  return 0
}

# ───── Captura da área de transferência (-C): enquanto o GrabIt está aberto, cada link
# ───── copiado é anotado no fim do arquivo de links e entra na fila viva. Nada roda em
# ───── segundo plano: fechou o GrabIt, acabou a captura.
detecta_clip() {                              # → CLIP_CMD: o comando que lê a área de transferência
  if [[ -n ${WAYLAND_DISPLAY:-} ]] && command -v wl-paste >/dev/null 2>&1; then CLIP_CMD=(wl-paste --no-newline --type text)
  elif [[ -n ${DISPLAY:-} ]] && command -v xclip >/dev/null 2>&1; then CLIP_CMD=(xclip -o -selection clipboard)
  elif [[ -n ${DISPLAY:-} ]] && command -v xsel >/dev/null 2>&1; then CLIP_CMD=(xsel --clipboard --output)
  elif command -v pbpaste >/dev/null 2>&1; then CLIP_CMD=(pbpaste)
  elif command -v powershell.exe >/dev/null 2>&1; then CLIP_CMD=(powershell.exe -NoProfile -Command Get-Clipboard)
  elif command -v termux-clipboard-get >/dev/null 2>&1; then CLIP_CMD=(termux-clipboard-get)
  else return 1; fi
}

# Sem o wl-paste no Wayland, o que se copia no navegador não chega ao xclip nem ao xsel:
# a leitura vem vazia, sem erro nenhum
aviso_wayland() {
  [[ -n ${WAYLAND_DISPLAY:-} ]] && ! command -v wl-paste >/dev/null 2>&1 || return 0
  comando_grabit "${T[cmd_instalar]}"; t clip_wayland "${CIANO}${FMT}${R}"; aviso "$TXT"
}

captura_clip() {
  local txt linha p novos=()
  txt=$("${CLIP_CMD[@]}" 2>/dev/null | head -c 200000)
  [[ $txt == "$CLIP_ULTIMO" ]] && return 0
  CLIP_ULTIMO=$txt
  if (( CLIP_PRIMEIRA )); then CLIP_PRIMEIRA=0; return 0; fi   # o que já estava copiado antes não conta
  while IFS= read -r linha; do
    links_da_linha "$linha"
    for p in "${PALAVRAS_LINK[@]}"; do
      [[ -n ${CONHECIDO[$p]:-} || -n ${CAPTURADO[$p]:-} ]] && continue
      CAPTURADO[$p]=1; novos+=("$p")
    done
  done <<<"$txt"
  (( ${#novos[@]} )) || return 0
  # anota no arquivo (garantindo a quebra de linha antes) e confere o arquivo já
  [[ -s $ARQ_CAPTURA && -n $(tail -c 1 -- "$ARQ_CAPTURA" 2>/dev/null) ]] && printf '\n' >> "$ARQ_CAPTURA"
  printf '%s\n' "${novos[@]}" >> "$ARQ_CAPTURA"
  for p in "${novos[@]}"; do PERM+=("  ${CIANO}+${R} ${DIM}${p}  ${T[clip_origem]}${R}"); done
  t clip_capturado "${#novos[@]}"; MSG_PAINEL=$TXT; MSG_ATE=$(( SECONDS + 4 ))
  PROX_VIGIA=0
}

# vale_repetir IDX: falhou por algo passageiro e ainda há tentativas? Se sim,
# guarda o log desta tentativa e põe o link no fim da fila.
vale_repetir() {
  local idx=$1 tent=${TENTATIVA[$1]:-1} site e
  analisa_log "$TMP/$idx.log"
  (( N_FATAIS == 0 && N_COSMETICOS > 0 )) && return 1   # o vídeo saiu inteiro: repetir não muda nada
  classifica_erro "$MOTIVO"
  site=${SITE[$idx]}
  nivel_do_link "$idx"
  # Depois de uma recusa, nada de voltar ao site no mesmo instante
  if (( BLOQUEIO && ESPERA_BASE > 0 )); then
    e=$(( SECONDS + ESPERA_BASE / 10 + RANDOM % 3 ))
    (( e > ${PROX_INICIO_SITE[$site]:-0} )) && PROX_INICIO_SITE[$site]=$e
  fi
  if (( MUITAS_REQ )); then
    # Pediu calma: o link espera junto com o site, e isso não conta como tentativa. Quantas vezes
    # pode acontecer quem limita é o site_pediu_calma, que acaba parando o site.
    site_pediu_calma "$site"
    (( ${PARADO_SITE[$site]:-0} )) && return 1
  elif (( NIVEL[$idx] < 2 && REPETE && tent < TENTATIVAS )); then
    (( NIVEL[$idx] == 0 )) && NIVEL[$idx]=1     # o próximo degrau da cascata
  elif vai_ao_navegador "$idx"; then            # se a página só funciona num navegador, é a vez dele
    NIVEL[$idx]=2
  else
    # O método lembrado não serve mais: na próxima vez, a cascata recomeça do início
    if (( ${NIVEL_INICIO[$idx]:-0} > 0 && REPETE )); then lembra_metodo "$site" 0; fi
    if (( BLOQUEIO )); then                     # recusas seguidas: o problema é o site, não o link
      FALHAS_SITE[$site]=$(( ${FALHAS_SITE[$site]:-0} + 1 ))
      (( ${FALHAS_SITE[$site]} >= 3 )) && para_site "$site"
    fi
    return 1
  fi
  (( ARQUIVO_RUIM )) && REBAIXAR[$idx]=1
  AJUSTES[$idx]=$AJUSTE
  mv -f "$TMP/$idx.log" "$TMP/$idx.t$tent.log"
  (( tent == 1 )) && EM_REPETICAO=$(( EM_REPETICAO + 1 ))
  TENTATIVA[$idx]=$(( tent + 1 ))
  reenfileira "$idx"
}

# Pedaço recusado (401, 403, 404, 410): o yt-dlp insiste em cada um, com espera crescente, e
# um link bloqueado segura a vaga por minutos sem nunca conseguir. A recusa não muda com o
# tempo: depois de algumas seguidas, a tentativa acaba e a cascata segue. Só contam as linhas
# recentes: num download de horas, um erro passageiro aqui e outro ali não quer dizer nada.
vigia_bloqueios() {
  local s idx n m ultima
  for (( s = 0; s < J; s++ )); do
    idx=${SLOT_IDX[$s]}
    (( idx > 0 )) || continue
    n=$(tail -n 12 "$TMP/$idx.log" 2>/dev/null | grep -acE 'Got error: HTTP Error (401|403|404|410)')
    m=$(tail -n 12 "$TMP/$idx.log" 2>/dev/null | grep -ac 'Got error: HTTP Error 429')   # 429: insistir piora
    (( ${n:-0} >= 5 || ${m:-0} >= 3 )) || continue
    ultima=$(grep -aE 'Got error: HTTP Error (401|403|404|410|429)' "$TMP/$idx.log" | tail -n 1)
    mata_arvore "${SLOT_PID[$s]}"
    printf 'ERROR: %s\n' "$ultima" >> "$TMP/$idx.log"
  done
  return 0
}

mata_arvore() {                               # mata o processo e seus filhos (ffmpeg…)
  local pid=$1 filho
  if command -v pgrep >/dev/null 2>&1; then
    for filho in $(pgrep -P "$pid" 2>/dev/null); do mata_arvore "$filho"; done
  fi
  kill -TERM "$pid" 2>/dev/null
  kill -CONT "$pid" 2>/dev/null               # pausado (tecla p), ele só morre depois de continuar
}

mata_jobs() {
  local s
  for (( s = 0; s < J; s++ )); do
    (( ${SLOT_IDX[$s]:-0} > 0 )) && mata_arvore "${SLOT_PID[$s]}"
  done
  # espera até 2 s eles saírem (e recolhe os processos); o que sobrar leva SIGKILL
  local i restantes
  for (( i = 0; i < 20; i++ )); do
    restantes=$(jobs -pr)
    [[ -z $restantes ]] && break
    sleep 0.1
  done
  [[ -n $restantes ]] && kill -KILL $restantes 2>/dev/null
  wait 2>/dev/null
  return 0
}

comando_repetir() {                           # → FMT: o mesmo comando, só com os links do arquivo de falhas
  local eu=$0 nome=${0##*/} p txt=""
  if [[ $(command -v -- "$nome" 2>/dev/null) -ef $eu ]]; then eu=$nome   # instalado no PATH: basta o nome
  elif [[ $eu != */* ]]; then eu="./$eu"; fi
  [[ $eu == */* && ! -x $eu ]] && txt="bash "
  for p in "$eu" "${OPCOES[@]}" -l "$ARQUIVO_FALHAS"; do
    if [[ $p =~ ^[[:alnum:]_./:=@%+,-]+$ ]]; then txt+="$p "; else txt+="${p@Q} "; fi
  done
  FMT=${txt% }
}

salva_falhas() {                              # grava links_falhos.txt (+ o que faltava, se cancelado)
  local lista=("${FALHAS[@]}") i l n_pend=0 n_lidos=0 antigos=() o_que=${T[f_com_erro]}
  local -A desta=()
  if (( MODO_CURL )); then                    # sem a sessão copiada, o link não serviria depois
    if (( N_ERRO > 0 )); then
      printf '\n  %s⚠%s  %s' "$AMARELO" "$R" "${T[curl_falhou]}"; t f_logs "$LOG_DIR"; printf '%s\n' "$TXT"
    fi
    return 0
  fi
  if (( CANCELADO || PARANDO )); then
    for (( i = 1; i <= TOTAL; i++ )); do
      [[ -n ${FEITO[$i]:-} ]] && continue
      lista+=("${LINKS[$(( i - 1 ))]}"); n_pend=$(( n_pend + 1 ))
    done
  fi
  # O arquivo pode ter falhas de execuções anteriores, de outros links: elas continuam lá.
  # Só saem os links desta execução (os que falharam de novo voltam pela lista).
  if [[ -f $ARQUIVO_FALHAS && -r $ARQUIVO_FALHAS ]]; then
    for l in "${LINKS[@]}"; do desta[$l]=1; done
    while IFS= read -r l || [[ -n $l ]]; do
      links_da_linha "$l"
      (( ${#PALAVRAS_LINK[@]} )) || continue
      n_lidos=$(( n_lidos + 1 ))
      [[ -n ${desta[${PALAVRAS_LINK[0]}]:-} ]] || antigos+=("$l")
    done < "$ARQUIVO_FALHAS"
  fi

  if (( ${#lista[@]} == 0 )); then
    (( n_lidos == ${#antigos[@]} )) && return 0   # nada desta execução estava no arquivo
    if (( ${#antigos[@]} )); then printf '%s\n' "${antigos[@]}" > "$ARQUIVO_FALHAS"
    elif rm -f -- "$ARQUIVO_FALHAS"; then         # todos deram certo: ele cumpriu o papel
      t f_todos_ok "$ARQUIVO_FALHAS"; printf '\n  %s✔%s  %s\n' "$VERDE" "$R" "$TXT"
    fi
    return 0
  fi
  if ! printf '%s\n' "${antigos[@]}" "${lista[@]}" > "$ARQUIVO_FALHAS"; then
    t f_nao_gravou "$ARQUIVO_FALHAS"; erro "$TXT"
    return 0
  fi
  (( n_pend + N_ADIADOS > 0 && N_ERRO > 0 )) && o_que=${T[f_erro_pend]}
  (( n_pend + N_ADIADOS > 0 && N_ERRO == 0 )) && o_que=${T[f_pend]}
  t f_salvos "${#lista[@]}" "$o_que" "${NEG}${ARQUIVO_FALHAS}${R}"
  printf '\n  %s⚠%s  %s' "$AMARELO" "$R" "$TXT"
  if (( ${#antigos[@]} )); then t f_antes "${#antigos[@]}"; printf '%s' "$TXT"; fi
  if (( N_ERRO > 0 )); then t f_logs "$LOG_DIR"; printf '%s\n' "$TXT"; else printf '\n'; fi
  comando_repetir
  t f_continuar "${CIANO}${FMT}${R}"; printf '%s\n' "$TXT"
}

linha_resumo() {                              # linha_resumo GLIFO COR RÓTULO VALOR (alinha por caracteres)
  local pad
  printf -v pad '%*s' $(( 18 - ${#3} )) ''
  printf '  %s%s%s  %s%s%s\n' "$2" "$1" "$R" "$3" "$pad" "$4"
}

resumo() {
  (( INTERATIVO )) && printf '%s' "${ESC}[?7h"     # religa a quebra de linha para o texto final
  local t b media="" titulo_r=${T[s_resumo]}
  fmt_tempo "$SECONDS"; t=$FMT
  fmt_bytes "$BYTES_NOVOS"; b=$FMT
  if (( BYTES_NOVOS > 0 && SECONDS > 0 )); then
    fmt_bytes $(( BYTES_NOVOS / SECONDS )); t s_media "$FMT"; media="  ${DIM}${TXT}${R}"
  fi
  (( (CANCELADO || PARANDO) && FINALIZADOS < TOTAL )) && titulo_r=${T[s_resumo_parcial]}
  printf '\n  %s── %s ─────────────────────────────────────%s\n' "$DIM" "$titulo_r" "$R"
  linha_resumo "✔" "$VERDE"    "${T[s_baixados]}" "${NEG}${N_OK}${R}"
  linha_resumo "↷" "$AMARELO"  "${T[s_ja]}"       "${NEG}${N_JA}${R}"
  linha_resumo "✖" "$VERMELHO" "${T[s_erro]}"     "${NEG}${N_ERRO}${R}"
  if (( N_ADIADOS > 0 )); then
    linha_resumo "‖" "$AMARELO" "${T[s_adiados]}" "${NEG}${N_ADIADOS}${R}  ${DIM}${T[s_adiados_det]}${R}"
  fi
  if (( N_AVISOS > 0 )); then
    t s_aviso_det "$LOG_DIR"; linha_resumo "⚠" "$AMARELO" "${T[s_aviso]}" "${NEG}${N_AVISOS}${R}  ${DIM}${TXT}${R}"
  fi
  if (( N_BAIXA_RES > 0 )); then
    t s_baixa_det "$N_BAIXA_RES" "$ALERTA"; linha_resumo "▾" "$AMARELO" "${T[s_baixa]}" "$TXT"
  fi
  if [[ -n $AVISO_JSC ]]; then
    linha_resumo "⚠" "$AMARELO" "JavaScript" "$AVISO_JSC"; printf '%s\n' "${T[s_js_dica]}"
  fi
  linha_resumo "◷" "$DIM" "${T[s_tempo]}"         "$t"
  linha_resumo "▣" "$DIM" "${T[s_baixado_agora]}" "${b}${media}"
  linha_resumo "▸" "$DIM" "${T[s_pasta]}"         "$PASTA_SAIDA"
  if (( N_MOVIDOS > 0 )); then
    t s_movidos "$N_MOVIDOS"; linha_resumo "✎" "$DIM" "${T[s_lista]}" "$TXT"
  fi
  salva_falhas
  if (( DICA_NAVEGADOR && N_ERRO > 0 && ! MODO_CURL )); then
    printf '\n  %s\n' "${T[s_nav_tit]}"
    comando_grabit "-b ${COOKIES_NAVEGADOR:-firefox} LINK"; t s_nav_b "${CIANO}${FMT}${R}"; printf '%s\n%s\n' "$TXT" "${T[s_nav_b2]}"
    comando_grabit curl; t s_nav_c "${CIANO}${FMT}${R}"; printf '%s\n' "$TXT"
    acha_navegador || printf '%s\n' "${T[nav_sem_navegador]}"
  fi
  printf '\n'
}

limpa() {                                     # trap EXIT: sempre devolve o terminal limpo
  local rc=$? s rodando=0
  trap - EXIT INT TERM HUP WINCH
  for (( s = 0; s < J; s++ )); do (( ${SLOT_IDX[$s]:-0} > 0 )) && rodando=1; done
  mata_jobs
  descarta_parciais
  if (( CANCELADO && COMECOU )); then
    move_baixados
    desenha final
    # na fila viva, Ctrl+C com nada baixando é só o jeito de sair
    if (( rodando || ! FILA_VIVA )); then
      printf '\n  %s⚠ %s%s%s\n' "$AMARELO" "${T[c_cancelado]}" "$R" "${T[c_descartado]}"
    fi
    resumo
  elif (( CANCELADO )); then
    printf '\n  %s⚠ %s%s\n\n' "$AMARELO" "${T[c_cancelado]}" "$R"
  fi
  if (( INTERATIVO )); then
    printf '%s' "${ESC}[?7h${ESC}[?25h"
    (( TITULO_EMPILHADO )) && printf '%s' "${ESC}[23;0t"     # devolve o título original da janela
    [[ -n $STTY_SAVE ]] && stty "$STTY_SAVE" </dev/tty 2>/dev/null
  fi
  [[ -n $TMP ]] && rm -rf "$TMP"
  # Morre pelo mesmo sinal recebido: assim um laço que chamou o script (ex.:
  # "for l in ...; do grabit ...; done") também para no Ctrl+C.
  if [[ -n $SINAL ]]; then trap - "$SINAL"; kill -s "$SINAL" "$$"; fi
  exit "$rc"
}

# Pasta temporária desta execução: .parciais/<pid>-<data>. Como nada é retomado entre
# execuções, o que sobrou de execuções anteriores é lixo e vai embora — menos a pasta de
# outro GrabIt que esteja rodando agora na mesma pasta de destino.
prepara_parciais() {
  local raiz="$PASTA_SAIDA/.parciais" item
  if [[ -d $raiz ]]; then
    for item in "$raiz"/* "$raiz"/.[!.]*; do
      [[ -e $item ]] || continue
      if [[ -d $item && ${item##*/} =~ ^([0-9]+)- ]] && kill -0 "${BASH_REMATCH[1]}" 2>/dev/null; then
        continue
      fi
      rm -rf -- "$item"
    done
  fi
  printf -v TEMP_REL '.parciais/%s-%(%Y%m%d%H%M%S)T' "$$" -1
  DIR_TEMP="$PASTA_SAIDA/$TEMP_REL"
}

descarta_parciais() {                         # apaga a pasta temporária desta execução
  [[ -n $TEMP_REL && -d $DIR_TEMP ]] && rm -rf -- "$DIR_TEMP"
  rmdir -- "$PASTA_SAIDA/.parciais" 2>/dev/null
  return 0
}

# ───────────────────────────── Verificações iniciais ──────────────────────────
cabecalho() {
  local t=${T[titulo]} w h
  w=$(( ${#t} + 4 ))
  if (( COLS < w + 4 )); then                   # terminal estreito: título simples, sem moldura
    printf '\n  %s%s%s\n\n' "$NEG" "${T[titulo_curto]}" "$R"
    return
  fi
  printf -v h '%*s' "$w" ''
  printf '\n  %s╭%s╮%s\n  %s│%s  %s%s%s  %s│%s\n  %s╰%s╯%s\n\n' \
    "$ACENTO" "${h// /─}" "$R"  "$ACENTO" "$R" "$NEG" "$t" "$R" "$ACENTO" "$R"  "$ACENTO" "${h// /─}" "$R"
}

kv() {                                        # kv RÓTULO VALOR (o valor pode ter cores)
  local v=$2 plano=${2//$'\e['+([0-9;])m/}
  # não cabe? corta com reticências (sem as cores) em vez de quebrar no meio da palavra
  if (( ${#plano} > COLS - 16 )); then corta "$plano" $(( COLS - 16 )); v=$FMT; fi
  local pad                                   # alinha por caracteres: o %-12s do printf conta bytes ("ó" = 2)
  printf -v pad '%*s' $(( 12 - ${#1} )) ''
  printf '  %s%s%s%s %s\n' "$DIM" "$1" "$R" "$pad" "$v"
}

comando_instalar() {                          # comando_instalar PACOTE → FMT (conforme o sistema)
  local g
  for g in brew apt dnf pacman zypper apk; do command -v "$g" >/dev/null 2>&1 && break; g=""; done
  case $g in
    brew)   FMT="brew install $1" ;;
    apt)    FMT="sudo apt install $1" ;;
    dnf)    FMT="sudo dnf install $1" ;;
    pacman) FMT="sudo pacman -S $1" ;;
    zypper) FMT="sudo zypper install $1" ;;
    apk)    FMT="sudo apk add $1" ;;
    *)      t dep_instale "$1"; FMT=$TXT ;;
  esac
}

# comando_grabit ARGUMENTOS → FMT: o comando que funciona aqui, para as dicas na tela:
# "grabit" se ele estiver instalado; senão, o caminho do script
comando_grabit() {
  local p=$GRABIT_SCRIPT
  if [[ $(command -v grabit 2>/dev/null) -ef $p ]]; then FMT="grabit $1"; return; fi
  [[ $p =~ ^[[:alnum:]_./:=@%+,-]+$ ]] || p=${p@Q}
  FMT="bash $p $1"
}

# YouTube precisa de um runtime JavaScript externo. O yt-dlp só liga o Deno sozinho;
# node/quickjs/bun precisam de --js-runtimes (feito em monta_args_ytdlp). E não basta o
# programa existir: quem diz se a versão serve é o próprio yt-dlp, porque o mínimo de cada
# runtime muda com o tempo. Por isso são três passos, e a consulta pode rodar em paralelo:
#   candidatos_js → JS_CANDIDATOS: os runtimes que podem ser executados aqui, como nome:caminho
#   consulta_js   → a linha do yt-dlp, ex.: "[debug] JS runtimes: bun-1.4.2, node-18.19.1 (unsupported)"
#   escolhe_js LINHA → JS_RUNTIME JS_PATH (o primeiro aceito) e JS_RECUSADO (o velho demais)
candidatos_js() {
  local par nome p PATH="$PATH:$HOME/.deno/bin:$HOME/.bun/bin"   # onde eles se instalam
  JS_CANDIDATOS=()
  for par in deno:deno node:node node:nodejs quickjs:qjs quickjs:quickjs bun:bun; do
    nome=${par%%:*}
    [[ " ${JS_CANDIDATOS[*]} " == *" $nome:"* ]] && continue
    p=$(command -v "${par#*:}" 2>/dev/null) && [[ -x $p ]] && JS_CANDIDATOS+=("$nome:$p")
  done
  return 0
}

consulta_js() {
  local c args=()
  for c in "${JS_CANDIDATOS[@]}"; do args+=(--js-runtimes "$c"); done
  yt-dlp -v --ignore-config "${args[@]}" 2>&1 | grep -a -m 1 '^\[debug\] JS runtimes: '
  return 0
}

escolhe_js() {
  local info=${1#*JS runtimes: } c nome item itens=()
  JS_RUNTIME=""; JS_PATH=""; JS_RECUSADO=""
  (( ${#JS_CANDIDATOS[@]} )) || return 0
  if [[ -z $info ]]; then                     # yt-dlp antigo: não há como perguntar
    c=${JS_CANDIDATOS[0]}; JS_RUNTIME=${c%%:*}; JS_PATH=${c#*:}
    return 0
  fi
  IFS=, read -ra itens <<<"$info"
  for c in "${JS_CANDIDATOS[@]}"; do
    nome=${c%%:*}
    for item in "${itens[@]}"; do
      item=${item# }
      [[ $item == "$nome"-* ]] || continue
      if [[ $item == *" (unsupported)" ]]; then JS_RECUSADO=${JS_RECUSADO:-${item% (unsupported)}}
      else JS_RUNTIME=$nome; JS_PATH=${c#*:}; return 0; fi
    done
  done
  return 0
}

verifica_dependencias() {
  local faltando=() p1 p2 p3 linha
  command -v yt-dlp >/dev/null 2>&1 || faltando+=("yt-dlp")
  command -v ffmpeg >/dev/null 2>&1 || faltando+=("ffmpeg")
  if (( ${#faltando[@]} )); then
    t dep_faltando "${faltando[*]}"; erro "$TXT"
    comando_grabit "${T[cmd_instalar]}"; t dep_instalador "${CIANO}${FMT}${R}"; printf '%s\n' "$TXT"
    comando_instalar ffmpeg
    printf '\n     %syt-dlp%s  →  pipx install "yt-dlp[default,curl-cffi]"\n' "$CIANO" "$R"
    printf '     %sffmpeg%s  →  %s\n\n' "$CIANO" "$R" "$FMT"
    exit 1
  fi
  # cada consulta ao yt-dlp leva quase 1 s (é Python): roda as três em paralelo
  candidatos_js
  yt-dlp --version                  >"$TMP/versao" 2>/dev/null & p1=$!
  consulta_js                       >"$TMP/js"     2>/dev/null & p2=$!
  yt-dlp --list-impersonate-targets >"$TMP/alvos"  2>/dev/null & p3=$!
  FFMPEG_VER=$(ffmpeg -version 2>/dev/null | awk 'NR==1{print $3}')
  wait "$p1" "$p2" "$p3"
  YTDLP_VER=$(head -n 1 "$TMP/versao")
  linha=$(<"$TMP/js")
  [[ -n $linha ]] && TEM_JS_RUNTIMES=1          # yt-dlp antigo não entende --js-runtimes
  escolhe_js "$linha"

  # --impersonate só funciona com curl_cffi instalado; senão o yt-dlp aborta
  if grep -i '^[[:space:]]*chrome' "$TMP/alvos" | grep -viq 'unavailable'; then
    IMPERSONATE="chrome"
  fi
}

idade_ytdlp() {                               # meses desde a versão do yt-dlp (AAAA.MM.DD) → NUM (-1 = ?)
  local hoje
  NUM=-1
  [[ $YTDLP_VER =~ ^([0-9]{4})\.([0-9]{2})\. ]] || return 0
  printf -v hoje '%(%Y %m)T' -1
  NUM=$(( ${hoje% *} * 12 + 10#${hoje#* } - BASH_REMATCH[1] * 12 - 10#${BASH_REMATCH[2]} ))
}

# sonda ARQUIVO → S_H S_FPS S_HDR S_VC S_AC S_CANAIS S_DUR S_TAM, lidos do arquivo final
# com ffprobe (é o que realmente foi gravado, não o que o site prometeu). Retorna 1 se falhar.
sonda() {
  S_H=0; S_FPS=0; S_HDR="SDR"; S_VC=""; S_AC=""; S_CANAIS=0; S_DUR=0; S_TAM=0
  command -v ffprobe >/dev/null 2>&1 || return 1
  local saida linha campo tipo ok=1 a b w h fr
  local -A c=()
  local -a campos=()
  saida=$(ffprobe -v error -of compact \
    -show_entries stream=codec_type,codec_name,width,height,avg_frame_rate,r_frame_rate,color_transfer,channels:stream_disposition=attached_pic:format=duration,size \
    -- "$1" 2>/dev/null) || return 1
  while IFS= read -r linha; do
    c=(); IFS='|' read -ra campos <<<"$linha"
    for campo in "${campos[@]:1}"; do c[${campo%%=*}]=${campo#*=}; done
    tipo=${campos[0]:-}
    if [[ $tipo == stream ]]; then
      if [[ ${c[codec_type]:-} == video && -z $S_VC && ${c[disposition:attached_pic]:-0} != 1 ]]; then
        S_VC=${c[codec_name]:-}
        # a "qualidade" é o lado menor: um vídeo vertical 1080×1920 é 1080p, não 1920p
        num "${c[width]:-0}"; w=$NUM; num "${c[height]:-0}"; h=$NUM
        if (( w > 0 && w < h )); then S_H=$w; else S_H=$h; fi
        fr=${c[avg_frame_rate]:-0/0}
        [[ $fr == 0/0 ]] && fr=${c[r_frame_rate]:-0/0}
        a=${fr%%/*}; b=${fr##*/}
        if [[ $a =~ ^[0-9]+$ && $b =~ ^[0-9]+$ ]] && (( b > 0 )); then
          S_FPS=$(( (a + b / 2) / b ))
        fi
        case ${c[color_transfer]:-} in
          smpte2084)     S_HDR="HDR10" ;;
          arib-std-b67)  S_HDR="HLG" ;;
        esac
        ok=0
      elif [[ ${c[codec_type]:-} == audio && -z $S_AC ]]; then
        S_AC=${c[codec_name]:-}; num "${c[channels]:-0}"; S_CANAIS=$NUM; ok=0
      fi
    elif [[ $tipo == format ]]; then
      num "${c[duration]:-0}"; S_DUR=$NUM
      num "${c[size]:-0}";     S_TAM=$NUM
    fi
  done <<<"$saida"
  return $ok
}

# A seção BAIXADOS de um arquivo de links começa numa linha como
#   # ==================== BAIXADOS ====================   (ou DOWNLOADED, em inglês)
# e vai até o fim do arquivo: o GrabIt ignora tudo o que estiver nela.
eh_marca_baixados() {
  local l=${1%$'\r'}
  [[ ${l,,} =~ ^[[:space:]]*#[[:space:]]*=+[[:space:]]*(baixados|downloaded)[[:space:]]*=+[[:space:]]*$ ]]
}

# A seção termina numa linha "# ===== FIM DOS BAIXADOS =====" (ou END OF DOWNLOADED);
# o que vier depois dela volta a contar — assim "echo LINK >> links.txt" funciona mesmo
# com a seção no fim do arquivo. Sem essa linha (arquivos antigos), a seção vai até o fim.
eh_fim_baixados() {
  local l=${1%$'\r'}
  [[ ${l,,} =~ ^[[:space:]]*#[[:space:]]*=+[[:space:]]*(fim[[:space:]]+dos[[:space:]]+baixados|end[[:space:]]+of[[:space:]]+downloaded)[[:space:]]*=+[[:space:]]*$ ]]
}

# links_da_linha LINHA → PALAVRAS_LINK: os links da linha, sem o comentário do fim
# ("www." e "site.com/caminho" viram "https://…"; só o domínio, sem caminho, não conta:
# "lista.txt" ou "e.g." numa anotação não são links)
links_da_linha() {
  local palavras=() p
  PALAVRAS_LINK=()
  IFS=$' \t\r' read -ra palavras <<<"${1#$'﻿'}"
  for p in "${palavras[@]}"; do
    [[ $p == \#* ]] && break
    [[ $p == www.* || $p =~ ^([[:alnum:]-]+\.)+[[:alpha:]]{2,}/ ]] && p="https://$p"
    [[ $p =~ ^https?:// ]] && PALAVRAS_LINK+=("$p")
  done
  return 0
}

# le_lista ARQUIVO: as linhas antes da seção BAIXADOS vão para "bruto" (de ler_links);
# os links dentro da seção só são contados
le_lista() {
  local conteudo=() linha secao=0
  mapfile -t conteudo < "$1"
  for linha in "${conteudo[@]}"; do
    if (( secao )); then
      if eh_fim_baixados "$linha"; then secao=0; continue; fi
      if (( UPGRADE )); then bruto+=("$linha"); continue; fi   # -U: são justamente esses
      links_da_linha "$linha"; N_NA_SECAO=$(( N_NA_SECAO + ${#PALAVRAS_LINK[@]} ))
    elif eh_marca_baixados "$linha"; then
      secao=1
    else
      bruto+=("$linha")
    fi
  done
}

# Junta os links do arquivo (-l), dos argumentos e dos arquivos passados como argumento.
ler_links() {
  local bruto=() fontes=() a linha palavra palavras=() soltos=0
  local -A visto=()
  if (( ${#ARGS_LINKS[@]} == 0 || LISTA_EXPLICITA || CAPTURA )); then
    if (( CAPTURA )); then
      [[ $ARQUIVO_LINKS == - ]] && { erro "${T[clip_stdin]}"; exit 2; }
      [[ -e $ARQUIVO_LINKS ]] || : > "$ARQUIVO_LINKS" 2>/dev/null
      ARQ_CAPTURA=$ARQUIVO_LINKS
    fi
    if [[ $ARQUIVO_LINKS == - ]]; then
      le_lista /dev/stdin; fontes+=("${T[fonte_stdin]}")
    elif [[ -f $ARQUIVO_LINKS && -r $ARQUIVO_LINKS ]]; then
      le_lista "$ARQUIVO_LINKS"; fontes+=("$ARQUIVO_LINKS"); ARQUIVOS_ENTRADA+=("$ARQUIVO_LINKS")
    else
      t sem_arquivo "$ARQUIVO_LINKS"; erro "$TXT"
      printf '%s\n\n' "${T[sem_arquivo2]}"
      exit 1
    fi
  fi
  for a in "${ARGS_LINKS[@]}"; do
    if [[ -f $a ]]; then
      le_lista "$a"; fontes+=("$a"); ARQUIVOS_ENTRADA+=("$a")
    else
      bruto+=("$a"); soltos=1
    fi
  done
  (( soltos )) && fontes+=("${T[fonte_cli]}")

  for linha in "${bruto[@]}"; do
    IFS=$' \t\r' read -ra palavras <<<"${linha#$'﻿'}"   # ﻿ do Bloco de Notas do Windows
    (( ${#palavras[@]} )) || continue
    [[ ${palavras[0]} == \#* ]] && continue
    links_da_linha "$linha"
    if (( ${#PALAVRAS_LINK[@]} == 0 )); then INVALIDAS=$(( INVALIDAS + 1 )); continue; fi
    for palavra in "${PALAVRAS_LINK[@]}"; do
      if [[ -n ${visto[$palavra]:-} ]]; then DUPLICADOS=$(( DUPLICADOS + 1 ))
      else visto[$palavra]=1; LINKS+=("$palavra"); CONHECIDO[$palavra]=1; fi
    done
  done
  TOTAL=${#LINKS[@]}
  if (( FILA_VIVA && ${#ARQUIVOS_ENTRADA[@]} == 0 )); then   # sem arquivo, não há o que vigiar
    aviso "${T[fv_sem_arquivo]}"; FILA_VIVA=0
  fi
  FONTE_LINKS=$(IFS=,; printf '%s' "${fontes[*]}"); FONTE_LINKS=${FONTE_LINKS//,/, }
  if (( TOTAL == 0 && ! FILA_VIVA )); then
    if (( N_NA_SECAO > 0 )); then
      if (( N_NA_SECAO == 1 )); then t nada_1 "$FONTE_LINKS"; else t nada_n "$N_NA_SECAO" "$FONTE_LINKS"; fi
      printf '  %s✔%s %s\n\n' "$VERDE" "$R" "$TXT"
      exit 0
    fi
    t sem_links "${FONTE_LINKS:-${T[nada]}}"; erro "$TXT"
    exit 1
  fi
}

# move_baixados: nos arquivos de links usados, as linhas cujos links terminaram todos com
# sucesso saem da parte de cima e vão para o fim da seção BAIXADOS (criada se preciso).
# O arquivo é relido agora: o que você acrescentou durante a execução não se perde.
move_baixados() {
  (( UPGRADE )) && return 0                   # no -U nada muda de lugar: os links já são da seção
  local -A ok=() nota=()
  local i arq
  printf -v HOJE '%(%Y-%m-%d)T' -1
  for (( i = 1; i <= TOTAL; i++ )); do
    [[ -n ${SUCESSO[$i]:-} ]] || continue
    ok[${LINKS[$(( i - 1 ))]}]=1; nota[${LINKS[$(( i - 1 ))]}]=${NOTA[$i]:-}
  done
  (( ${#ok[@]} )) || return 0
  for arq in "${ARQUIVOS_ENTRADA[@]}"; do
    [[ -f $arq && -w $arq ]] || continue
    [[ $arq -ef $ARQUIVO_FALHAS ]] && continue          # esse é regravado a cada execução
    move_no_arquivo "$arq"
  done
  return 0
}

# anota LINHA NOTA → FMT: a linha com a data e o título do que foi baixado, ex.:
#   https://site/video  # ✔ 2026-10-24 · Título do vídeo
# Se a linha já tem um comentário seu, a anotação entra no fim dele (sem outro "#").
ANOTACAO_ANTIGA='^(.*[^[:space:]])[[:space:]]+(#[[:space:]]*)?✔ [0-9]{4}-[0-9]{2}-[0-9]{2}( · .*)?$'
anota() {
  local l=$1 n=${2//[[:cntrl:]]/ } cr=""
  [[ $l == *$'\r' ]] && { cr=$'\r'; l=${l%$'\r'}; }
  # link que voltou da seção para ser baixado de novo: troca a anotação antiga
  [[ $l =~ $ANOTACAO_ANTIGA ]] && l=${BASH_REMATCH[1]}
  (( ${#n} > 120 )) && n="${n:0:119}…"
  if [[ $l =~ (^|[[:space:]])# ]]; then FMT="$l  ✔ $HOJE"; else FMT="$l  # ✔ $HOJE"; fi
  [[ -n $n ]] && FMT+=" · $n"
  FMT+=$cr
}

move_no_arquivo() {                           # move_no_arquivo ARQUIVO (usa "ok" e "nota" de move_baixados)
  local arq=$1 linha p todos secao=0 tem_secao=0 depois=0 bom="" eol="" n
  local conteudo=() ativa=() cauda=() resto=() movidas=()
  mapfile -t conteudo < "$arq" || return 0
  (( ${#conteudo[@]} )) || return 0
  if [[ ${conteudo[0]} == $'\xef\xbb\xbf'* ]]; then bom=$'\xef\xbb\xbf'; conteudo[0]=${conteudo[0]#$'\xef\xbb\xbf'}; fi
  [[ ${conteudo[0]} == *$'\r' ]] && eol=$'\r'          # mantém o fim de linha do Windows
  for linha in "${conteudo[@]}"; do
    if (( secao )); then
      if eh_fim_baixados "$linha"; then secao=0; depois=1; continue; fi   # ela é reescrita no fim
      resto+=("$linha"); continue
    fi
    if eh_marca_baixados "$linha"; then secao=1; tem_secao=1; resto+=("$linha"); continue; fi
    links_da_linha "$linha"
    todos=$(( ${#PALAVRAS_LINK[@]} > 0 ))
    for p in "${PALAVRAS_LINK[@]}"; do [[ -n ${ok[$p]:-} ]] || { todos=0; break; }; done
    if (( todos )); then
      n=""
      for p in "${PALAVRAS_LINK[@]}"; do [[ -n ${nota[$p]:-} ]] && n+="${n:+ | }${nota[$p]}"; done
      anota "$linha" "$n"; movidas+=("$FMT")
    elif (( depois )); then
      cauda+=("$linha")                         # acrescentado depois da seção: sobe para a lista
    else
      ativa+=("$linha")
    fi
  done
  (( ${#movidas[@]} )) || return 0
  # a lista de cima, depois o que estava abaixo da seção, uma linha em branco e a seção
  while (( ${#ativa[@]} )) && [[ -z ${ativa[-1]//[[:space:]]/} ]]; do unset 'ativa[-1]'; done
  while (( ${#cauda[@]} )) && [[ -z ${cauda[-1]//[[:space:]]/} ]]; do unset 'cauda[-1]'; done
  ativa+=("${cauda[@]}")
  (( ${#ativa[@]} )) && ativa+=("$eol")
  (( tem_secao )) || resto=("${MARCA_BAIXADOS}${eol}" "${T[marca_desc]}${eol}")
  { printf '%s' "$bom"; printf '%s\n' "${ativa[@]}" "${resto[@]}" "${movidas[@]}" "${T[marca_fim]}${eol}"; } > "$arq.grabit-tmp" &&
    cat "$arq.grabit-tmp" > "$arq"
  rm -f -- "$arq.grabit-tmp"
  N_MOVIDOS=$(( N_MOVIDOS + ${#movidas[@]} ))
}

monta_args_ytdlp() {
  local langs=$IDIOMAS_LEGENDAS n=$RESOLUCAO_MAXIMA cmd qualidade=() opcoes=()
  FORMATO='bv*+ba/b'
  # Com limite, vale o lado menor da imagem: a altura em vídeos deitados e a largura nos
  # verticais. Dimensão desconhecida passa (o "?"); se nada couber, o vídeo falha.
  if (( n > 0 )); then
    FORMATO="(bv*[height<=?$n][aspect_ratio>=?1]/bv*[width<=?$n][aspect_ratio<1])+ba"
    FORMATO+="/b[height<=?$n][aspect_ratio>=?1]/b[width<=?$n][aspect_ratio<1]"
  fi
  # "all" incluiria o chat ao vivo: um JSON enorme que nem dá para embutir
  [[ ,$langs, == *,all,* && $langs != *live_chat* ]] && langs+=",-live_chat"
  if (( SO_AUDIO )); then
    # Só áudio: a melhor faixa, no formato em que veio (opus, m4a…), sem recomprimir;
    # com FORMATO_AUDIO, converte (no mp3, na melhor qualidade VBR).
    FORMATO='ba/b'
    qualidade=(-f "$FORMATO" -x --audio-format "${FORMATO_AUDIO/#original/best}" --audio-quality 0)
  else
    # Qualidade máxima: melhor vídeo + melhor áudio, empacotados em MKV, com as legendas
    qualidade=(-f "$FORMATO" --merge-output-format mkv --remux-video mkv --embed-subs --sub-langs "$langs")
  fi
  YTDLP_ARGS=(
    --ignore-config --color never --newline --no-quiet --no-simulate --progress
    --progress-delta 0.5

    # Linhas "máquina" lidas pelo painel (ficam só no log, nunca no terminal)
    --progress-template "download:@@P@@%(progress.downloaded_bytes|0)s${SEP}%(progress.total_bytes,progress.total_bytes_estimate|0)s${SEP}%(progress.speed|0)s${SEP}%(progress.eta|0)s${SEP}%(info.playlist_index|)s${SEP}%(info.n_entries|)s${SEP}%(info.vcodec|?)s${SEP}%(info.height|)s${SEP}%(info.fps|)s${SEP}%(info.ext|)s${SEP}%(info.title|?)s"
    --print "after_move:@@D@@%(height|0)s${SEP}%(fps|0)s${SEP}%(dynamic_range|SDR)s${SEP}%(vcodec|?)s${SEP}%(acodec|?)s${SEP}%(duration|0)s${SEP}%(title|?)s${SEP}%(id)s${SEP}%(filepath)s"

    # Destino: os temporários ficam em .parciais/<esta execução> e só o arquivo final
    # vai para a pasta
    -P "$PASTA_SAIDA" -P "temp:$TEMP_REL" -o "$TEMPLATE_SAIDA"

    "${qualidade[@]}"

    # Tudo o que o yt-dlp encontrar vai para dentro do arquivo
    --embed-metadata --embed-chapters --embed-info-json
    # Capa em JPG (a mais compatível), menos AVIF: para converter, o yt-dlp força o
    # leitor "image2" do ffmpeg, que não abre AVIF — ela é embutida como veio.
    --embed-thumbnail --convert-thumbnails 'webp>jpg/png>jpg/gif>jpg/bmp>jpg'

    # Velocidade e resiliência (com espera crescente entre as repetições)
    -N "$CONEXOES_POR_VIDEO"
    --retries 10 --fragment-retries 10 --extractor-retries 3
    --retry-sleep exp=1:30 --retry-sleep fragment:exp=1:30 --retry-sleep extractor:exp=2:30
    # Qualidade garantida: nunca pula um fragmento que falhou (por padrão o yt-dlp pula
    # em silêncio e entrega o vídeo com um salto) e nunca retoma pedaços de um download
    # interrompido (a retomada pode deixar buracos); nesses casos, recomeça do zero.
    --abort-on-unavailable-fragments --no-continue
    # Sem --throttled-rate: abaixo do limite, o yt-dlp refaz a extração e, com o --no-continue,
    # recomeça do zero, sem limite de vezes. Numa conexão lenta, seria um laço sem fim de pedidos.
    --socket-timeout 30
  )
  # Com --write-auto-subs o yt-dlp para de pedir as legendas manuais sozinho:
  # pede as duas (a manual tem prioridade) e apaga os .vtt depois de embutir.
  (( LEGENDAS_AUTOMATICAS && ! SO_AUDIO )) && YTDLP_ARGS+=(--write-subs --write-auto-subs --compat-options no-keep-subs)
  (( SPONSORBLOCK ))         && YTDLP_ARGS+=(--sponsorblock-mark all)
  # pausa com variação aleatória (até +50%): um ritmo fixo é a cara de um robô
  (( PAUSA_ENTRE_VIDEOS > 0 )) &&
    YTDLP_ARGS+=(--sleep-interval "$PAUSA_ENTRE_VIDEOS" --max-sleep-interval $(( PAUSA_ENTRE_VIDEOS * 3 / 2 )))
  [[ $LIMITE_VELOCIDADE != 0 ]] && YTDLP_ARGS+=(--limit-rate "$LIMITE_VELOCIDADE")
  (( SEM_PLAYLIST ))         && YTDLP_ARGS+=(--no-playlist)
  if (( VERIFICAR )); then                    # o "%" do caminho viraria campo do modelo do yt-dlp
    printf -v cmd 'bash %q --verificar-arquivo %q' "${GRABIT_SCRIPT//%/%%}" "${T[sufixo_ruim]}"
    YTDLP_ARGS+=(--exec "after_move:$cmd %(filepath)q %(duration|0)q")
  fi
  if (( MIDIA )); then                        # a capa fica também ao lado do vídeo, e o .nfo
    printf -v cmd 'bash %q --nfo' "${GRABIT_SCRIPT//%/%%}"
    YTDLP_ARGS+=(--write-thumbnail --exec "after_move:$cmd %(filepath)q")
  fi
  # Histórico: o que já foi baixado é pulado antes de tudo (na maioria dos sites,
  # sem nem acessar a página). Sem ele, o yt-dlp reextrai o vídeo, baixa a capa de
  # novo e reescreve o arquivo inteiro só para dizer que ele já existe.
  (( USAR_HISTORICO ))       && YTDLP_ARGS+=(--download-archive "$ARQUIVO_HISTORICO")
  [[ -n $COOKIES_NAVEGADOR ]] && YTDLP_ARGS+=(--cookies-from-browser "$COOKIES_NAVEGADOR")
  [[ -n $USER_AGENT ]]        && YTDLP_ARGS+=(--user-agent "$USER_AGENT")
  (( TEM_JS_RUNTIMES ))       && [[ -n $JS_RUNTIME ]] && YTDLP_ARGS+=(--js-runtimes "$JS_RUNTIME:$JS_PATH")
  read -ra opcoes <<<"$OPCOES_YTDLP"
  YTDLP_ARGS+=("${EXTRA_YTDLP[@]}" "${opcoes[@]}")
  return 0
}

# ───────────────────────────── Download pelo navegador ────────────────────────
# grabit curl: há vídeos que só o navegador alcança (player em JavaScript, verificação
# anti-robô). Quem passa por isso é a pessoa, no navegador dela; o "Copiar como cURL" da aba
# Rede traz o link do vídeo e a sessão (cookies, Referer, User-Agent) e o yt-dlp baixa com
# ela. O comando copiado é só lido, nunca executado. Os cookies vão num arquivo temporário,
# e não na linha de comando, onde qualquer usuário da máquina os veria.
le_curl() {
  local origem=${ARGS_LINKS[0]:-} txt campos=() url
  if ! command -v python3 >/dev/null 2>&1; then erro "${T[curl_sem_py]}"; exit 1; fi
  if (( ${#CURL_ARGS[@]} )); then txt=""
  elif [[ $origem == - ]]; then txt=$(cat)
  elif [[ -n $origem ]]; then
    [[ -f $origem ]] || { t curl_sem_arquivo "$origem"; erro "$TXT"; exit 1; }
    txt=$(<"$origem")
  elif detecta_clip; then txt=$("${CLIP_CMD[@]}" 2>/dev/null)
  else
    comando_grabit "curl ARQUIVO"; t curl_sem_clip "${CIANO}${FMT}${R}"; erro "$TXT"; exit 1
  fi
  mapfile -d '' campos < <(python3 -I -c '
import shlex, sys
if len(sys.argv) > 1:
    a = ["curl"] + sys.argv[1:]
else:
    try:
        a = shlex.split(sys.stdin.read().replace("\\\n", " "))
    except ValueError:
        sys.exit(1)
if not a or a[0] != "curl":
    sys.exit(1)
com_valor = {"-H", "--header", "-b", "--cookie", "-A", "--user-agent", "-e", "--referer", "--url",
             "-X", "--request", "-d", "--data", "--data-raw", "--data-binary", "--data-urlencode",
             "-o", "--output", "-u", "--user", "-x", "--proxy", "-m", "--max-time", "--connect-timeout"}
url, cab, i = "", [], 1
while i < len(a):
    o = a[i]
    i += 1
    if o in com_valor:
        v = a[i] if i < len(a) else ""
        i += 1
        if o in ("-H", "--header"):
            cab.append(v)
        elif o in ("-b", "--cookie"):
            cab.append("Cookie: " + v)
        elif o in ("-A", "--user-agent"):
            cab.append("User-Agent: " + v)
        elif o in ("-e", "--referer"):
            cab.append("Referer: " + v)
        elif o == "--url":
            url = v
    elif not o.startswith("-") and not url:
        url = o
if not url.startswith(("http://", "https://")):
    sys.exit(1)
sys.stdout.write("\0".join([url] + cab) + "\0")' "${CURL_ARGS[@]}" <<<"$txt" 2>/dev/null)
  url=${campos[0]:-}
  if [[ -z $url ]]; then
    [[ -z $origem ]] && aviso_wayland
    erro "${T[curl_invalido]}"; printf '%s\n\n' "${T[curl_colar]}"
    exit 2
  fi

  cabecalhos_ytdlp "$url" "$TMP/cookies-curl.txt" "${campos[@]:1}"
  nome_pela_pagina "${CAB_REFERER:-$url}" "$url"
  EXTRA_YTDLP+=("${CAB_ARGS[@]}" --parse-metadata "$ROTULO_CURL:%(title)s")
  TEMPLATE_SAIDA=$SAIDA_PAGINA
  MODO_CURL=1; USAR_HISTORICO=0; FILA_VIVA=0; CAPTURA=0; UPGRADE=0; LISTA_EXPLICITA=0
  ARGS_LINKS=("$url")
}

# cabecalhos_ytdlp URL ARQ_COOKIES LINHA… → CAB_ARGS (as opções do yt-dlp), CAB_REFERER,
# N_CAB_CURL e N_COOK_CURL. Vão os cabeçalhos que dizem quem pede; os que descrevem aquele
# pedido (Range…) ficam. Os cookies vão no arquivo, e só para o site do vídeo.
cabecalhos_ytdlp() {
  local url=$1 arq=$2 h nome valor cookies="" par pares=() site
  shift 2
  CAB_ARGS=(); CAB_REFERER=""; N_CAB_CURL=0; N_COOK_CURL=0
  for h in "$@"; do
    [[ $h == *:* ]] || continue
    nome=${h%%:*}; valor=${h#*:}; valor=${valor# }
    [[ -n $nome ]] || continue
    case ${nome,,} in
      host|accept-encoding|connection|content-length|range|if-*|priority|te|upgrade-insecure-requests|pragma|cache-control) continue ;;
      cookie) cookies=$valor; continue ;;
      referer) CAB_REFERER=$valor ;;
    esac
    CAB_ARGS+=(--add-header "$nome:$valor"); N_CAB_CURL=$(( N_CAB_CURL + 1 ))
  done
  [[ -n $cookies ]] || return 0
  site=${url#*://}; site=${site%%[/?#]*}; site=${site##*@}; site=${site%%:*}
  printf '# Netscape HTTP Cookie File\n' > "$arq"
  IFS=';' read -ra pares <<<"$cookies"
  for par in "${pares[@]}"; do
    par=${par# }
    [[ $par == *=* ]] || continue
    printf '%s\tFALSE\t/\tFALSE\t0\t%s\t%s\n' "$site" "${par%%=*}" "${par#*=}" >> "$arq"
    N_COOK_CURL=$(( N_COOK_CURL + 1 ))
  done
  CAB_ARGS+=(--cookies "$arq")
}

# nome_pela_pagina PÁGINA URL_DO_VÍDEO → ROTULO_CURL e SAIDA_PAGINA (o modelo do nome). O link
# do vídeo costuma se chamar só "master.m3u8": o nome vem da página, e o [número] a separa das
# outras. Vindo de outro domínio, o Referer costuma trazer só "https://site/": aí vale o
# caminho do vídeo.
nome_pela_pagina() {
  local pagina=$1 url=$2 caminho site resto h palavras=() ck
  caminho=${pagina#*://}; caminho=${caminho%%#*}
  site=${caminho%%[/?]*}; resto=${caminho#"$site"}
  site=${site##*@}; site=${site%%:*}; site=${site#www.}
  if [[ -z ${resto//[\/?]/} ]]; then
    resto=${url#*://}; resto=${resto%%[?#]*}
    if [[ $resto == */* ]]; then resto=/${resto#*/}; else resto=""; fi
    h=${resto##*/}; h=${h%.*}
    case ${h,,} in
      master|index|main|playlist|manifest|chunklist|stream|video) resto=${resto%/*} ;;
      *) resto=${resto%/*}/$h ;;
    esac
  fi
  read -ra palavras <<<"${resto//[\/?&=_+%.:]/ }"
  ROTULO_CURL="$site${palavras[*]:+ - ${palavras[*]}}"; ROTULO_CURL=${ROTULO_CURL:0:150}
  ck=$(printf '%s %s' "$pagina" "${url%%\?*}" | cksum); ck=${ck%% *}
  SAIDA_PAGINA=${TEMPLATE_SAIDA/'%(title).180B [%(id)s]'/"$ROTULO_CURL [$ck]"}
  SAIDA_PAGINA=${SAIDA_PAGINA/'%(title).150B [%(id)s]'/"$ROTULO_CURL [$ck]"}
}

# ───────────────────────────── Vídeo achado pelo navegador ────────────────────
# Há páginas que só um navegador resolve: o player é um programa em JavaScript que monta o link
# do vídeo, ou o site pede uma verificação anti-robô. Aí o GrabIt abre um navegador de verdade,
# visível, num perfil só dele, e lê no log oficial dele (MOZ_LOG no Firefox, NetLog na família
# do Chrome) o pedido do vídeo. Nada controla o navegador nem disfarça o que ele é: uma
# verificação, se aparecer, é a pessoa quem faz na janela, e o perfil a guarda para os próximos
# links. O GrabIt só usa o que já está instalado: nunca instala um navegador sem perguntar.
acha_navegador() {                            # → NAV_PROG NAV_TIPO (firefox|chromium) NAV_NOME NAV_ROTULO
  local c
  NAV_PROG=""
  if [[ -n $PROGRAMA_NAVEGADOR ]]; then
    NAV_PROG=$(command -v -- "$PROGRAMA_NAVEGADOR" 2>/dev/null)
  else
    for c in firefox google-chrome google-chrome-stable chromium chromium-browser brave-browser brave \
             microsoft-edge microsoft-edge-stable vivaldi vivaldi-stable opera; do
      NAV_PROG=$(command -v "$c" 2>/dev/null) && break
    done
    if [[ -z $NAV_PROG ]]; then
      for c in "Firefox.app/Contents/MacOS/firefox" "Google Chrome.app/Contents/MacOS/Google Chrome" \
               "Chromium.app/Contents/MacOS/Chromium" "Brave Browser.app/Contents/MacOS/Brave Browser" \
               "Microsoft Edge.app/Contents/MacOS/Microsoft Edge"; do
        [[ -x /Applications/$c ]] && { NAV_PROG=/Applications/$c; break; }
      done
    fi
  fi
  [[ -n $NAV_PROG && -x $NAV_PROG ]] || return 1
  NAV_NOME=${NAV_PROG##*/}; NAV_NOME=${NAV_NOME,,}; NAV_NOME=${NAV_NOME// /-}
  NAV_TIPO=chromium
  case $NAV_NOME in
    *firefox*)  NAV_TIPO=firefox; NAV_ROTULO=Firefox ;;
    *chromium*) NAV_ROTULO=Chromium ;;
    *chrome*)   NAV_ROTULO=Chrome ;;
    *brave*)    NAV_ROTULO=Brave ;;
    *edge*)     NAV_ROTULO=Edge ;;
    *vivaldi*)  NAV_ROTULO=Vivaldi ;;
    *opera*)    NAV_ROTULO=Opera ;;
    *)          NAV_ROTULO=$NAV_NOME ;;
  esac
}

pode_navegador() {
  (( USAR_NAVEGADOR && ! MODO_CURL && ! UPGRADE )) || return 1
  acha_navegador || return 1
  [[ $NAV_TIPO == firefox ]] || command -v python3 >/dev/null 2>&1 || return 1   # lê o NetLog
  [[ -n ${GRABIT_NAVEGADOR_OPCOES:-} ]] && return 0  # (os testes: navegador sem janela)
  (( INTERATIVO )) || return 1                       # com a saída redirecionada, ninguém veria a janela
  [[ -n ${DISPLAY:-}${WAYLAND_DISPLAY:-} || $OSTYPE == darwin* ]]
}

# vai_ao_navegador IDX: o erro deste link é dos que um navegador resolve? E há um à mão?
vai_ao_navegador() {
  local idx=$1 f achou=0
  (( ${NIVEL[$idx]:-0} < 2 )) && pode_navegador || return 1
  for f in "$TMP/$idx".t*.log "$TMP/$idx.log"; do
    [[ -f $f ]] && grep -aqE 'anti-bot challenge|Unsupported URL: ' "$f" && achou=1
  done
  (( achou ))
}

pasta_navegador() {                           # → PASTA_NAV: um navegador do snap só escreve na pasta dele
  local snap
  if [[ $(readlink -f -- "$NAV_PROG" 2>/dev/null) == /snap/* ]] || head -c 300 -- "$NAV_PROG" 2>/dev/null | grep -aq '/snap/'; then
    case $NAV_NOME in
      *firefox*)  snap=firefox ;;
      *chromium*) snap=chromium ;;
      *)          snap=${NAV_NOME%%-*} ;;
    esac
    PASTA_NAV="$HOME/snap/$snap/common/grabit"
  else
    PASTA_NAV="${XDG_DATA_HOME:-$HOME/.local/share}/grabit/$NAV_NOME"
  fi
  mkdir -p "$PASTA_NAV/perfil" && chmod 700 "$PASTA_NAV" || return 1
  [[ $NAV_TIPO == firefox && ! -e $PASTA_NAV/perfil/user.js ]] || return 0
  cat > "$PASTA_NAV/perfil/user.js" <<'EOF'
// Perfil do GrabIt: sem telas de boas-vindas e com o vídeo começando sozinho, sem precisar de play.
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.aboutwelcome.enabled", false);
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("browser.sessionstore.resume_from_crash", false);
user_pref("toolkit.startup.max_resumed_crashes", -1);
user_pref("media.autoplay.default", 0);
user_pref("media.autoplay.blocking_policy", 0);
EOF
}

# O log → a 1ª linha é "2 LINK" (playlist) ou "1 LINK" (arquivo de vídeo); depois, os cabeçalhos
AWK_PEDIDO_VIDEO='
/E\/nsHttp uri=/ {
  u = $0; sub(/^.*E\/nsHttp uri=/, "", u); p = u; sub(/^[a-z]+:\/\/[^\/]*/, "", p); uri[p] = u
  next
}
/E\/nsHttp   GET / {
  l = $0; sub(/^.*E\/nsHttp   GET /, "", l); sub(/ HTTP\/[0-9.]+.*$/, "", l)
  b = l; sub(/[?#].*$/, "", b)
  t = (b ~ /\.(m3u8|mpd)$/) ? 2 : ((b ~ /\.(mp4|webm|m4v|mkv|mov)$/) ? 1 : 0)
  if (t == 2 || (t == 1 && salvo == "")) {
    em = 1; tipo = t; cam = l; cab = ""; host = ""; pre = $0; sub(/E\/nsHttp.*$/, "", pre)
  } else em = 0
  next
}
em {
  q = $0; sub(/E\/nsHttp.*$/, "", q)
  if (q != pre) next                          # outra thread escreveu no meio
  if ($0 ~ /E\/nsHttp   [A-Za-z0-9-]+: /) {
    h = $0; sub(/^.*E\/nsHttp   /, "", h); cab = cab h "\n"
    if (tolower(h) ~ /^host: /) { host = h; sub(/^[^:]*: */, "", host) }
    next
  }
  em = 0
  link = (cam in uri) ? uri[cam] : "https://" host cam
  if (tipo == 2) { printf "2 %s\n%s", link, cab; saiu = 1; exit }
  salvo = "1 " link "\n" cab
}
END { if (!saiu && salvo != "") printf "%s", salvo }'

# O mesmo, para o NetLog da família do Chrome: um evento JSON por linha, com o nome de cada tipo
# de evento na primeira. O arquivo está sendo escrito: uma linha pela metade fica para a próxima.
PY_PEDIDO_NETLOG='
import json, re, sys
tipos, urls, salvo = {}, {}, None
def mostra(t, url, cab):
    print(t, url)
    for h in cab:
        if not h.startswith(":"):
            print(h)
with open(sys.argv[1], encoding="utf-8", errors="replace") as f:
    for l in f:
        l = l.strip().rstrip(",")
        if l.startswith("{\"constants\""):
            try:
                tipos = {v: k for k, v in json.loads(l + "}")["constants"]["logEventTypes"].items()}
            except (ValueError, KeyError):
                pass
            continue
        if "\"headers\":[" not in l and "\"url\":\"" not in l:
            continue
        try:
            e = json.loads(l)
        except ValueError:
            continue
        nome, p, fonte = tipos.get(e.get("type"), ""), e.get("params") or {}, (e.get("source") or {}).get("id")
        if nome == "URL_REQUEST_START_JOB" and "url" in p:
            urls[fonte] = p["url"]
            continue
        if not nome.endswith("SEND_REQUEST_HEADERS") or "TUNNEL" in nome:
            continue
        cab = p.get("headers") or []
        metodo = p.get("line", "").split(" ")[0] or next((h[9:] for h in cab if h.startswith(":method: ")), "")
        url = urls.get(fonte, "")
        if metodo != "GET" or not url:
            continue
        b = re.sub(r"[?#].*$", "", url)
        if re.search(r"\.(m3u8|mpd)$", b, re.I):
            mostra(2, url, cab)
            sys.exit(0)
        if salvo is None and re.search(r"\.(mp4|webm|m4v|mkv|mov)$", b, re.I):
            salvo = (1, url, cab)
if salvo:
    mostra(*salvo)'

baixa_pelo_navegador() {
  local url=$1 idx=$2 log pid pedido=() opcoes=() inicio primeiro=0 media
  printf '[grabit] navegador\n'
  pasta_navegador
  log="$PASTA_NAV/http"                       # tem os cookies: só vive enquanto a janela está aberta
  rm -f -- "$log"*
  read -ra opcoes <<<"${GRABIT_NAVEGADOR_OPCOES:-}"
  if [[ $NAV_TIPO == firefox ]]; then
    MOZ_LOG=nsHttp:1 MOZ_LOG_FILE=$log "$NAV_PROG" --no-remote --profile "$PASTA_NAV/perfil" "${opcoes[@]}" "$url" >/dev/null 2>&1 &
  else
    "$NAV_PROG" --user-data-dir="$PASTA_NAV/perfil" --no-first-run --no-default-browser-check \
      --autoplay-policy=no-user-gesture-required --log-net-log="$log.json" --net-log-capture-mode=IncludeSensitive \
      "${opcoes[@]}" "$url" >/dev/null 2>&1 &
  fi
  pid=$!
  trap 'mata_arvore "$pid"; rm -f -- "$log"*; exit 143' TERM INT HUP
  inicio=$SECONDS
  while (( SECONDS - inicio < ${GRABIT_NAVEGADOR_ESPERA:-300} )); do
    if [[ $NAV_TIPO == firefox ]]; then
      mapfile -t pedido < <(cat "$log"* 2>/dev/null | awk "$AWK_PEDIDO_VIDEO")
    else
      mapfile -t pedido < <(python3 -I -c "$PY_PEDIDO_NETLOG" "$log.json" 2>/dev/null)
    fi
    [[ ${pedido[0]:-} == 2\ * ]] && break
    if [[ ${pedido[0]:-} == 1\ * ]]; then      # só um arquivo: uma playlist, se vier, é o vídeo de verdade
      (( primeiro )) || primeiro=$SECONDS
      (( SECONDS - primeiro >= 8 )) && break
    fi
    kill -0 "$pid" 2>/dev/null || break        # a pessoa fechou a janela
    sleep 1
  done
  mata_arvore "$pid"
  for _ in 1 2 3 4 5 6 7 8 9 10; do kill -0 "$pid" 2>/dev/null || break; sleep 0.3; done
  kill -KILL "$pid" 2>/dev/null
  trap - TERM INT HUP
  rm -f -- "$log"*
  rmdir "$TMP/navegador.trava" 2>/dev/null
  if [[ ${pedido[0]:-} != [12]\ * ]]; then printf 'ERROR: [grabit] %s\n' "${T[nav_sem_video]}"; exit 1; fi
  media=${pedido[0]#* }
  cabecalhos_ytdlp "$media" "$TMP/cookies-$idx.txt" "${pedido[@]:1}"
  nome_pela_pagina "$url" "$media"
  # Sem o histórico: o vídeo costuma se chamar "master", e o próximo "master" pareceria já baixado
  exec yt-dlp "${YTDLP_ARGS[@]}" "${CAB_ARGS[@]}" --no-download-archive \
    --parse-metadata "$ROTULO_CURL:%(title)s" -o "$SAIDA_PAGINA" -- "$media"
}

# notifica: avisa que o lote acabou — sino e notificação na área de trabalho (se levou 1 min
# ou mais: lote rápido você viu acabar) e, com NTFY_TOPICO, no celular. Só o resumo sai daqui.
notifica() {                                  # notifica [DURAÇÃO] (padrão: o tempo todo)
  local msg tempo url etiqueta=white_check_mark dur=${1:-$SECONDS}
  fmt_tempo "$SECONDS"; tempo=$FMT
  t notif_msg "$N_OK" "$N_JA" "$N_ERRO" "$tempo"; msg=$TXT
  if (( NOTIFICAR && dur >= 60 )); then
    (( INTERATIVO )) && printf '\a'
    if command -v notify-send >/dev/null 2>&1; then
      notify-send -a GrabIt -i folder-download "GrabIt" "$msg" 2>/dev/null
    elif command -v osascript >/dev/null 2>&1; then
      osascript -e "display notification \"${msg//\"/}\" with title \"GrabIt\"" >/dev/null 2>&1
    fi
  fi
  [[ -n $NTFY_TOPICO ]] || return 0
  url=$NTFY_TOPICO; [[ $url == http?(s)://* ]] || url="https://ntfy.sh/$url"
  (( N_ERRO > 0 )) && etiqueta=warning
  if ! command -v curl >/dev/null 2>&1; then aviso "${T[notif_sem_curl]}"; return 0; fi
  if ! curl -fsS -m 15 -H "Title: GrabIt" -H "Tags: $etiqueta" -d "$msg" "$url" >/dev/null 2>&1; then
    t notif_falhou "$url"; aviso "$TXT"
  fi
  return 0
}

# descreve_limites RESOLUÇÃO POR_SITE PAUSA VELOCIDADE → TXT ("até 1080p · 1 vídeo(s) por site…")
descreve_limites() {
  local p=() x
  (( $1 > 0 && ! SO_AUDIO )) && { t lim_res "$1";   p+=("$TXT"); }
  (( $2 > 0 ))               && { t lim_site "$2";  p+=("$TXT"); }
  (( $3 > 0 ))               && { t lim_pausa "$3"; p+=("$TXT"); }
  [[ $4 != 0 ]]              && { t lim_vel "$4";   p+=("$TXT"); }
  TXT=""
  for x in "${p[@]}"; do TXT+="${TXT:+ · }$x"; done
}

# ───────────────────────────── Instalador e atualizador ───────────────────────
# grabit --instalar: instala o que falta (pedindo uma confirmação só, com o plano à vista).
# grabit --atualizar: deixa tudo na versão mais nova, cada um pelo seu caminho, e instala o
# que faltar (sem perguntar: é para isso que foi chamado).
URL_SCRIPT="https://raw.githubusercontent.com/Canela-san/GrabIt/main/grabit.sh"

gerenciador() {                               # → GER (brew, apt, dnf, pacman, zypper, apk ou "")
  GER=""
  local g
  for g in brew apt dnf pacman zypper apk; do command -v "$g" >/dev/null 2>&1 && { GER=$g; return 0; }; done
  return 1
}

pacote() {                                    # pacote NOME → PKG: o nome do pacote neste sistema
  PKG=$1
  case $GER:$1 in
    pacman:pipx)          PKG=python-pipx ;;
    zypper:pipx)          PKG=python3-pipx ;;
    apk:pipx)             PKG=pipx ;;
    zypper:firefox)       PKG=MozillaFirefox ;;
  esac
}

# pacote_disponivel PACOTE: o gerenciador do sistema tem esse pacote? (o Chrome, o Brave e o
# Edge só estão lá se o repositório deles tiver sido acrescentado)
pacote_disponivel() {
  case $GER in
    brew)   brew info "$1" >/dev/null 2>&1 ;;
    apt)    apt-cache policy "$1" 2>/dev/null | grep -q 'Candidate: [^(]' ;;
    dnf)    dnf -q info "$1" >/dev/null 2>&1 ;;
    pacman) pacman -Si "$1" >/dev/null 2>&1 ;;
    zypper) zypper -q info "$1" 2>/dev/null | grep -qi "^name *: *$1" ;;
    apk)    apk search -e "$1" 2>/dev/null | grep -q . ;;
    *)      return 1 ;;
  esac
}

instala_pacotes() {                           # instala_pacotes PACOTE... (pelo gerenciador do sistema)
  local sudo=()
  [[ $GER != brew ]] && (( EUID != 0 )) && sudo=(sudo)
  case $GER in
    brew)   brew install "$@" ;;
    apt)    "${sudo[@]}" apt-get update -qq && "${sudo[@]}" apt-get install -y "$@" ;;
    dnf)    "${sudo[@]}" dnf install -y "$@" ;;
    pacman) "${sudo[@]}" pacman -S --needed --noconfirm "$@" ;;
    zypper) "${sudo[@]}" zypper --non-interactive install "$@" ;;
    apk)    "${sudo[@]}" apk add "$@" ;;
    *)      return 1 ;;
  esac
}

# pacote_defasado PACOTE: o gerenciador tem versão mais nova? Não precisa de sudo: vale o
# índice que o sistema já tem. Quem instalou por fora do gerenciador nunca é "defasado".
pacote_defasado() {
  case $GER in
    brew)   [[ -n $(brew outdated --quiet "$1" 2>/dev/null) ]] ;;
    apt)    apt-get -s --only-upgrade install "$1" 2>/dev/null | grep -q "^Inst $1 " ;;
    dnf)    dnf -q check-update "$1" >/dev/null 2>&1; (( $? == 100 )) ;;
    pacman) pacman -Qu "$1" >/dev/null 2>&1 ;;
    zypper) zypper -q list-updates 2>/dev/null | grep -q "| $1 " ;;
    apk)    apk -u list "$1" 2>/dev/null | grep -q "^$1" ;;
    *)      return 1 ;;
  esac
}

atualiza_pacote() {                           # atualiza_pacote PACOTE (pelo gerenciador do sistema)
  local sudo=()
  [[ $GER != brew ]] && (( EUID != 0 )) && sudo=(sudo)
  case $GER in
    brew)   brew upgrade "$1" ;;
    apt)    "${sudo[@]}" apt-get update -qq && "${sudo[@]}" apt-get install -y --only-upgrade "$1" ;;
    dnf)    "${sudo[@]}" dnf upgrade -y "$1" ;;
    pacman) "${sudo[@]}" pacman -S --needed --noconfirm "$1" ;;
    zypper) "${sudo[@]}" zypper --non-interactive update "$1" ;;
    apk)    "${sudo[@]}" apk upgrade "$1" ;;
    *)      return 1 ;;
  esac
}

# atualiza_do_sistema PACOTE: só incomoda (e só pede a senha) se houver versão nova
atualiza_do_sistema() {
  pacote_defasado "$1" || return 0
  if [[ $GER != brew ]] && (( EUID != 0 )) && ! sudo -n true 2>/dev/null && [[ ! -t 0 ]]; then
    t atu_sem_senha "$1"; aviso "$TXT"
    return 0
  fi
  t atu_pacote_p "$1" "$GER"; passo "$TXT" atualiza_pacote "$1"
}

pergunta_sim() {                              # pergunta_sim TEXTO [n] → 0 se a resposta for sim (Enter = sim; com n, Enter = não)
  local resp=""
  printf '\n  %s%s%s ' "$NEG" "$1" "$R"
  if [[ -r /dev/tty ]]; then read -r resp </dev/tty || resp=n; else resp=n; fi
  [[ -z $resp ]] && resp=${2:-s}
  [[ ${resp,,} == s* || ${resp,,} == y* ]]
}

passo() {                                     # passo DESCRIÇÃO COMANDO... (mostra, roda e diz se deu certo)
  local d=$1
  shift
  printf '\n  %s▸%s %s\n' "$CIANO" "$R" "$d"
  if "$@"; then printf '  %s✔%s %s\n' "$VERDE" "$R" "${T[ins_ok]}"; return 0; fi
  printf '  %s✖%s %s\n' "$VERMELHO" "$R" "${T[ins_falhou]}"; FALHOU_PASSO=1
  return 1
}

# monta_plano → SISTEMA e ETAPAS: o que falta instalar, e PLANO: a descrição de cada passo
monta_plano() {
  local clip=""
  SISTEMA=(); ETAPAS=(); PLANO=(); OPCIONAIS=(); NOTA_NAV=0; ALVO_GRABIT="$HOME/.local/bin/grabit"
  # Sem isto, o GrabIt não funciona
  command -v ffmpeg >/dev/null 2>&1 && command -v ffprobe >/dev/null 2>&1 || SISTEMA+=(ffmpeg)
  command -v curl >/dev/null 2>&1 || SISTEMA+=(curl)
  if ! command -v yt-dlp >/dev/null 2>&1; then
    command -v pipx >/dev/null 2>&1 || { pacote pipx; SISTEMA+=("$PKG"); }
    ETAPAS+=(ytdlp)
  elif command -v pipx >/dev/null 2>&1 && pipx list --short 2>/dev/null | grep -q '^yt-dlp ' &&
       ! yt-dlp --list-impersonate-targets 2>/dev/null | grep -i '^[[:space:]]*chrome' | grep -viq unavailable; then
    OPCIONAIS+=(curlcffi)                     # sem o curl_cffi, nada de imitar um navegador
  fi
  command -v grabit >/dev/null 2>&1 || [[ -e $ALVO_GRABIT ]] || ETAPAS+=(comando)

  # Isto só melhora o que ele consegue fazer: decide_opcionais pergunta
  candidatos_js; escolhe_js "$(consulta_js)"
  # Sem o yt-dlp ainda não há quem diga se ele aceita os outros: só o Deno é garantido. E o
  # Bun pode ser novo demais, o que o yt-dlp só descobre na hora de usar.
  command -v yt-dlp >/dev/null 2>&1 || [[ $JS_RUNTIME == deno ]] || JS_RUNTIME=""
  [[ $JS_RUNTIME == bun ]] && JS_RUNTIME=""
  [[ -z $JS_RUNTIME ]] && OPCIONAIS+=(deno)
  # No Wayland, só o wl-paste serve: xclip e xsel enxergam apenas o que programas X copiaram
  if [[ $GER != brew ]] && ! command -v wl-paste >/dev/null 2>&1; then
    if [[ -n ${WAYLAND_DISPLAY:-} ]]; then clip=wl-clipboard
    elif [[ -n ${DISPLAY:-} ]] && ! command -v xclip >/dev/null 2>&1 && ! command -v xsel >/dev/null 2>&1; then clip=xclip; fi
    [[ -n $clip ]] && OPCIONAIS+=("clip:$clip")
  fi
  acha_navegador || OPCIONAIS+=(navegador)
  descreve_plano
}

# decide_opcionais: com -y, aceita tudo sem perguntar. O navegador é um programa grande, que a
# pessoa pode nem precisar: só entra quando não há nenhum compatível, e aí só o Firefox, que o
# GrabIt lê sem precisar de mais nada. Outros, só a pedido: grabit install chrome. O --atualizar
# nunca instala um navegador.
decide_opcionais() {
  local o pkg
  for o in "${OPCIONAIS[@]}"; do
    case $o in
      curlcffi)
        if (( ASSUME_SIM )) || pergunta_sim "${T[ins_q_curlcffi]}"; then ETAPAS+=(curlcffi); fi ;;
      deno)
        if (( ASSUME_SIM )) || pergunta_sim "${T[ins_q_deno]}"; then
          case $GER in
            brew|pacman) SISTEMA+=(deno) ;;
            *) command -v unzip >/dev/null 2>&1 || SISTEMA+=(unzip); ETAPAS+=(deno) ;;
          esac
        fi ;;
      clip:*)
        pkg=${o#clip:}; t ins_q_clip "$pkg"
        if (( ASSUME_SIM )) || pergunta_sim "$TXT"; then SISTEMA+=("$pkg"); fi ;;
      navegador)
        if (( ATUALIZANDO )); then continue; fi
        if (( ASSUME_SIM )) || pergunta_sim "${T[ins_q_nav]}" n; then pacote firefox; SISTEMA+=("$PKG")
        else NOTA_NAV=1; fi ;;
    esac
  done
  descreve_plano
}

# grabit install NAVEGADOR: o pedido explícito, para instalar um navegador em especial
instalar_navegador() {
  local pedido=${1,,} pacotes=() programas=() site="" p
  case $pedido in
    firefox)              pacote firefox; pacotes=("$PKG"); programas=(firefox); site=https://www.mozilla.org/firefox/ ;;
    chromium)             pacotes=(chromium chromium-browser); programas=(chromium chromium-browser); site=https://www.chromium.org/getting-involved/download-chromium/ ;;
    chrome|google-chrome) pacotes=(google-chrome-stable google-chrome); programas=(google-chrome google-chrome-stable); site=https://www.google.com/chrome/ ;;
    brave)                pacotes=(brave-browser); programas=(brave-browser brave); site=https://brave.com/download/ ;;
    edge|microsoft-edge)  pacotes=(microsoft-edge-stable microsoft-edge); programas=(microsoft-edge microsoft-edge-stable); site=https://www.microsoft.com/edge ;;
    *) t ins_nav_desconhecido "$1"; erro "$TXT"; printf '\n'; return 2 ;;
  esac
  for p in "${programas[@]}"; do
    if command -v "$p" >/dev/null 2>&1; then
      t ins_nav_ja "$pedido"; printf '\n  %s✔%s %s\n\n' "$VERDE" "$R" "$TXT"
      return 0
    fi
  done
  for p in "${pacotes[@]}"; do
    pacote_disponivel "$p" || continue
    t ins_p_sistema "$GER" "$p"; passo "$TXT" instala_pacotes "$p" || { printf '\n'; return 1; }
    printf '\n'
    return 0
  done
  t ins_nav_site "$pedido" "$site"; aviso "$TXT"; printf '\n'
  return 1
}

descreve_plano() {                            # → PLANO: a descrição do que vai ser instalado
  local p
  PLANO=()
  if [[ -n $GER && ${#SISTEMA[@]} -gt 0 ]]; then t ins_p_sistema "$GER" "${SISTEMA[*]}"; PLANO+=("$TXT"); fi
  for p in "${ETAPAS[@]}"; do
    case $p in
      ytdlp)    PLANO+=("${T[ins_p_ytdlp]}") ;;
      curlcffi) PLANO+=("${T[ins_p_curlcffi]}") ;;
      deno)     PLANO+=("${T[ins_p_deno]}") ;;
      comando)  t ins_p_comando "${ALVO_GRABIT/#$HOME/\~}"; PLANO+=("$TXT") ;;
    esac
  done
}

executa_plano() {
  local p
  if [[ -n $GER && ${#SISTEMA[@]} -gt 0 ]]; then
    if ! passo "${PLANO[0]}" instala_pacotes "${SISTEMA[@]}" && [[ $GER == dnf && " ${SISTEMA[*]} " == *" ffmpeg "* ]]; then
      # Fedora sem o RPM Fusion: o ffmpeg do repositório oficial se chama ffmpeg-free
      FALHOU_PASSO=0
      passo "dnf: ffmpeg-free" instala_pacotes "${SISTEMA[@]/#ffmpeg/ffmpeg-free}"
    fi
  fi
  for p in "${ETAPAS[@]}"; do
    case $p in
      ytdlp)    passo "${T[ins_p_ytdlp]}" pipx install "yt-dlp[default,curl-cffi]" ;;
      curlcffi) passo "${T[ins_p_curlcffi]}" pipx inject yt-dlp curl-cffi ;;
      # em dois tempos: num "curl | sh", um download que falha passaria por sucesso
      deno)     passo "${T[ins_p_deno]}" sh -c 'i=$(curl -fsSL https://deno.land/install.sh) && printf "%s\n" "$i" | sh -s -- -y' ;;
      comando)  t ins_p_comando "${ALVO_GRABIT/#$HOME/\~}"
                passo "$TXT" sh -c 'mkdir -p "$(dirname "$1")" && ln -sf "$2" "$1"' _ "$ALVO_GRABIT" "$GRABIT_SCRIPT" ;;
    esac
  done
}

confere_path() {
  [[ -e $ALVO_GRABIT || -e $HOME/.local/bin/yt-dlp ]] || return 0   # só importa se algo foi parar lá
  case ":$PATH_ORIGINAL:" in
    *":$HOME/.local/bin:"*) ;;
    *)
      # com o PATH de antes: no deste processo o ~/.local/bin já entrou, e o pipx acharia
      # que não há nada a fazer
      command -v pipx >/dev/null 2>&1 && env PATH="$PATH_ORIGINAL" "$(command -v pipx)" ensurepath >/dev/null 2>&1
      # o pipx ensurepath já pode ter posto no ~/.bashrc: aí basta abrir outro terminal
      if grep -qs '\.local/bin' "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile" "$HOME/.bash_profile"; then
        aviso "${T[ins_path_novo]}"
      else
        t ins_path "${CIANO}export PATH=\"\$HOME/.local/bin:\$PATH\"${R}"; aviso "$TXT"
      fi ;;
  esac
}

instalar() {
  local p
  FALHOU_PASSO=0
  gerenciador
  export PATH="$HOME/.local/bin:$HOME/.deno/bin:$PATH"     # onde pipx e deno instalam
  printf '\n  %s%s%s\n' "$NEG" "${T[ins_titulo]}" "$R"
  [[ -z $GER ]] && aviso "${T[ins_sem_ger]}"
  if (( ${#ARGS_LINKS[@]} )); then instalar_navegador "${ARGS_LINKS[0]}"; return; fi
  monta_plano
  if (( ${#PLANO[@]} == 0 && ${#SISTEMA[@]} == 0 && ${#OPCIONAIS[@]} == 0 )); then
    printf '\n  %s✔%s %s\n' "$VERDE" "$R" "${T[ins_nada]}"
    mostra_versoes; return 0
  fi
  if [[ -z $GER && ${#SISTEMA[@]} -gt 0 ]]; then
    t ins_manual "${SISTEMA[*]}"; aviso "$TXT"
  fi
  if (( ${#PLANO[@]} )); then                  # o indispensável, à vista
    printf '\n  %s\n' "${T[ins_vai]}"
    for p in "${!PLANO[@]}"; do printf '    %d. %s\n' $(( p + 1 )) "${PLANO[$p]}"; done
    if (( ! ASSUME_SIM )) && ! pergunta_sim "${T[ins_continuar]}"; then
      printf '\n  %s\n\n' "${T[ins_cancelado]}"; return 1
    fi
  fi
  decide_opcionais
  executa_plano
  mostra_versoes
  confere_path
  (( NOTA_NAV )) && { aviso "${T[ins_nav_nota]}"; printf '\n'; }
  (( ${#SISTEMA[@]} )) && [[ -z $GER ]] && return 1
  (( FALHOU_PASSO )) && return 1
  printf '\n  %s✔%s %s\n\n' "$VERDE" "$R" "${T[ins_pronto]}"
}

mostra_versoes() {
  local v
  printf '\n'
  v=$(yt-dlp --version 2>/dev/null) || v="—"
  kv "yt-dlp" "$v"
  v=$(ffmpeg -version 2>/dev/null | awk 'NR==1{print $3}'); kv "ffmpeg" "${v:-—}"
  candidatos_js; escolhe_js "$(consulta_js)"
  if [[ -n $JS_RUNTIME ]]; then kv "JavaScript" "$JS_RUNTIME"
  elif [[ -n $JS_RECUSADO ]]; then t js_velho "$JS_RECUSADO"; kv "JavaScript" "${AMARELO}${TXT}${R}"
  else kv "JavaScript" "${AMARELO}${T[js_nenhum]}${R}"; fi
  printf '\n'
}

# eh_clone_grabit: o script está na raiz de um clone do GrabIt? Um grabit.sh copiado para
# dentro de outro repositório (dotfiles…) não pode levar "git pull" nele.
eh_clone_grabit() {
  local raiz
  raiz=$(git -C "$GRABIT_DIR" rev-parse --show-toplevel 2>/dev/null) || return 1
  [[ $raiz -ef $GRABIT_DIR ]] && git -C "$GRABIT_DIR" ls-files --error-unmatch grabit.sh >/dev/null 2>&1
}

# grabit --versao: o que está instalado e se há coisa mais nova. O GrabIt não tem número de
# versão: num clone do Git, ela é o commit; numa cópia solta, compara com o arquivo publicado.
mostra_versao() {
  local v remoto tmp nova=0 situacao=${T[ver_sem_net]}
  atualiza_largura
  if eh_clone_grabit; then
    v=$(git -C "$GRABIT_DIR" log -1 --format='%h · %cd' --date=short 2>/dev/null)
    remoto=$(GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND=${GIT_SSH_COMMAND:-ssh -oBatchMode=yes -oConnectTimeout=8} \
      git -C "$GRABIT_DIR" -c http.lowSpeedLimit=1 -c http.lowSpeedTime=8 ls-remote origin HEAD 2>/dev/null)
    remoto=${remoto%%[[:space:]]*}
    if [[ -n $remoto ]]; then
      if git -C "$GRABIT_DIR" merge-base --is-ancestor "$remoto" HEAD 2>/dev/null; then situacao=${T[ver_em_dia]}
      else nova=1; fi
    fi
  else
    v=${T[ver_sem_git]}
    if tmp=$(mktemp "${TMPDIR:-/tmp}/grabit.XXXXXX"); then
      if curl -fsSL -m 10 "$URL_SCRIPT" -o "$tmp" 2>/dev/null; then
        if cmp -s "$tmp" "$GRABIT_SCRIPT"; then situacao=${T[ver_em_dia]}; else nova=1; fi
      fi
      rm -f -- "$tmp"
    fi
  fi
  (( nova )) && situacao=${T[ver_nova]}
  printf '\n'
  kv "GrabIt" "$v"
  kv "${T[kv_situacao]}" "$situacao"
  if (( nova )); then comando_grabit "${T[cmd_atualizar]}"; t av_ytdlp2 "${CIANO}${FMT}${R}"; printf '%s\n' "$TXT"; fi
  mostra_versoes
}

# atualiza_grabit → 0 se o script mudou. Clone do Git: git pull; arquivo solto: baixa, confere e troca
atualiza_grabit() {
  local antes depois tmp modo
  if eh_clone_grabit; then
    antes=$(git -C "$GRABIT_DIR" rev-parse --short HEAD)
    passo "${T[atu_git]}" git -C "$GRABIT_DIR" pull --ff-only --quiet || return 1
    depois=$(git -C "$GRABIT_DIR" rev-parse --short HEAD)
    if [[ $antes == "$depois" ]]; then printf '    %s\n' "${T[atu_igual]}"; return 1; fi
    printf '    %s → %s\n' "$antes" "$depois"; git -C "$GRABIT_DIR" log --format='      · %s' "$antes..$depois" | head -15
    return 0
  fi
  if ! tmp=$(mktemp "${GRABIT_SCRIPT}.XXXXXX" 2>/dev/null); then
    t atu_sem_escrita "$GRABIT_DIR"; erro "$TXT"; FALHOU_PASSO=1
    return 1
  fi
  # bash -n e a assinatura do cabeçalho: uma página de erro nunca substitui o script
  if ! passo "${T[atu_baixa]}" sh -c 'curl -fsSL "$1" -o "$2" && bash -n "$2" && grep -q "GrabIt (grabit.sh)" "$2"' _ "$URL_SCRIPT" "$tmp"; then
    rm -f -- "$tmp"
    return 1
  fi
  if cmp -s "$tmp" "$GRABIT_SCRIPT"; then
    printf '    %s\n' "${T[atu_igual]}"; rm -f -- "$tmp"
    return 1
  fi
  # arquivo novo no lugar (mv), com as permissões do antigo: o GrabIt em execução
  # continua lendo o arquivo velho, sem tropeçar no meio da troca
  modo=$(stat -c %a -- "$GRABIT_SCRIPT" 2>/dev/null || stat -f %Lp -- "$GRABIT_SCRIPT" 2>/dev/null)
  chmod "${modo:-755}" "$tmp" && mv -f -- "$tmp" "$GRABIT_SCRIPT" && printf '    %s\n' "${T[atu_trocado]}"
}

# O yt-dlp, pelo caminho por onde foi instalado: pipx; pip (o Python do "#!" do próprio
# yt-dlp tem o pacote — vale para venvs; no Python do sistema, só na pasta do usuário);
# ou o executável oficial, que se atualiza sozinho com -U. Sem o yt-dlp, quem cuida é o plano.
atualiza_ytdlp() {
  local antes depois py="" usuario=() spec saida
  antes=$(yt-dlp --version 2>/dev/null)
  [[ -n $antes ]] || return 0
  py=$(head -n 1 -- "$(command -v yt-dlp 2>/dev/null)" 2>/dev/null); py=${py#\#!}; py=${py%% *}
  [[ $py == /* && -x $py ]] && "$py" -m pip show yt-dlp >/dev/null 2>&1 || py=""
  if command -v pipx >/dev/null 2>&1 && pipx list --short 2>/dev/null | grep -q '^yt-dlp '; then
    # Instalado sem os extras, falta pedaço: default traz o yt-dlp-ejs (os desafios do YouTube)
    # e curl-cffi imita um navegador. Quem instalou de um link ou de uma pasta fica como está.
    spec=$(pipx list --json 2>/dev/null | awk '/"yt-dlp": \{/ {y=1} y && /"main_package"/ {m=1} m && /"package_or_url"/ {print; exit}')
    if [[ $spec == *'": "yt-dlp'* && ( $spec != *default* || $spec != *curl-cffi* ) ]]; then
      passo "${T[atu_ytdlp]} (pipx)" pipx install --force "yt-dlp[default,curl-cffi]"
    else
      # eager: as dependências também vão para a versão mais nova que o yt-dlp aceita
      passo "${T[atu_ytdlp]} (pipx)" pipx upgrade --include-injected --pip-args=--upgrade-strategy=eager yt-dlp
    fi
  elif [[ -n $py ]]; then
    [[ $py == /usr/* && $(command -v yt-dlp) == "$HOME"/* ]] && usuario=(--user)
    passo "${T[atu_ytdlp]} (pip)" "$py" -m pip install -U --upgrade-strategy eager --quiet --disable-pip-version-check "${usuario[@]}" "yt-dlp[default,curl-cffi]"
  else
    saida=$(yt-dlp -U 2>&1); printf '%s\n' "$saida" | sed 's/^/    /' | tail -3
    [[ $saida == *"package manager"* ]] && aviso "${T[atu_pacote]}"
  fi
  depois=$(yt-dlp --version 2>/dev/null)
  printf '    yt-dlp %s → %s\n' "$antes" "${depois:-?}"
}

# O Deno instalado pelo instalador oficial se atualiza sozinho; o outro, pelo gerenciador
atualiza_deno() {
  local p
  p=$(command -v deno 2>/dev/null) || return 0
  if [[ $p == "$HOME"/* ]]; then passo "${T[atu_deno]}" "$p" upgrade
  else atualiza_do_sistema deno; fi
}

atualizar() {
  FALHOU_PASSO=0
  gerenciador
  export PATH="$HOME/.local/bin:$HOME/.deno/bin:$PATH"     # onde pipx e deno instalam

  # 1) o GrabIt. Se ele mudou, quem termina o trabalho é a versão nova: ela pode saber
  #    atualizar mais coisas do que esta, que está rodando.
  if [[ -z ${GRABIT_RELANCADO:-} ]]; then
    printf '\n  %s%s%s\n' "$NEG" "${T[atu_titulo]}" "$R"
    if atualiza_grabit; then
      export GRABIT_RELANCADO=1
      exec "$BASH" "$GRABIT_SCRIPT" "${OPCOES[@]}" --atualizar
    fi
  fi

  # 2) o yt-dlp primeiro: é a versão nova dele que diz quais runtimes aceita
  atualiza_ytdlp

  # 3) o que estiver faltando (sem perguntar: é para isso que foi chamado; navegador, só se pedir)
  ASSUME_SIM=1; ATUALIZANDO=1
  monta_plano
  decide_opcionais
  if [[ -z $GER && ${#SISTEMA[@]} -gt 0 ]]; then t ins_manual "${SISTEMA[*]}"; aviso "$TXT"; FALHOU_PASSO=1; fi
  executa_plano

  # 4) o que já existia e vem de outro lugar (o que acabou de ser instalado já é o mais novo)
  [[ " ${ETAPAS[*]} " == *" deno "* ]] || atualiza_deno
  [[ " ${SISTEMA[*]} " == *" ffmpeg "* ]] || atualiza_do_sistema ffmpeg

  mostra_versoes
  confere_path
  (( FALHOU_PASSO )) && return 1
  printf '  %s✔%s %s\n\n' "$VERDE" "$R" "${T[atu_pronto]}"
}

# ───────────────────────────── Verificação da coleção ─────────────────────────
# grabit --verificar [PASTA]: confere os vídeos que já estão na pasta. Cada um é
# decodificado inteiro (defeitos) e tem a duração comparada com a registrada no
# info.json que o GrabIt embute nos MKV (incompletos). No fim, oferece baixar de novo
# os que tiverem problema, pelo link guardado nesse mesmo info.json.
le_info() {                                   # le_info ARQUIVO → I_DUR I_URL I_CHAVE (do info.json embutido)
  local j="$TMP/info.json"
  I_DUR=0; I_URL=""; I_CHAVE=""
  rm -f -- "$j"
  ffmpeg -v quiet -y -dump_attachment:m:filename:info.json "$j" -i "$1" >/dev/null 2>&1
  [[ -s $j ]] || return 1
  if command -v python3 >/dev/null 2>&1; then
    IFS=$'\t' read -r I_DUR I_URL I_CHAVE < <(python3 -c '
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
k = d.get("extractor_key") or d.get("ie_key") or ""
print(int(float(d.get("duration") or 0)), d.get("webpage_url") or "",
      (k.lower() + " " + str(d.get("id"))) if k and d.get("id") else "", sep="\t")' "$j" 2>/dev/null)
  else                                        # sem Python: ao menos o link
    I_URL=$(grep -o '"webpage_url": *"[^"]*"' "$j" | tail -n 1 | sed 's/.*: *"//; s/"$//')
  fi
  num "$I_DUR"; I_DUR=$NUM
  return 0
}

verifica_um() {                               # verifica_um ARQUIVO ROTULO → V_ESTADO (ok|defeito|incompleto) V_DET
  local arq=$1 k v pos tol erros="$TMP/erros" pct lin
  V_ESTADO=ok; V_DET=""
  if ! sonda "$arq"; then V_ESTADO=defeito; V_DET=${T[vc_ilegivel]}; return 0; fi
  le_info "$arq"
  while IFS='=' read -r k v; do
    [[ $k == out_time_us && $v =~ ^[0-9]+$ ]] || continue
    (( INTERATIVO )) || continue
    pos=$(( v / 1000000 )); pct=""
    (( S_DUR > 0 )) && { pct=$(( pos * 100 / S_DUR )); (( pct > 100 )) && pct=100; pct=" ${pct}%"; }
    corta "$2" $(( COLS - 30 )); lin="  ${ACENTO}${SPIN[$(( pos % ${#SPIN[@]} ))]}${R} ${FMT} ${DIM}· ${T[vc_verificando]}${pct}${R}"
    printf '\r%s[K%s' "$ESC" "$lin"
  done < <(ffmpeg -nostdin -hide_banner -v error -i "$arq" -map '0:v?' -map '0:a?' \
             -f null -progress pipe:1 -nostats - 2>"$erros")
  (( INTERATIVO )) && printf '\r%s[K' "$ESC"
  (( CANCELADO )) && return 0
  if [[ -s $erros ]]; then
    V_ESTADO=defeito
    V_DET=$(head -c 300 "$erros" | tr '\r\n' '  ' | sed -E 's/\[[^]]* @ 0x[0-9a-f]+\] //g')
    return 0
  fi
  tol=$(( I_DUR / 50 )); (( tol < 3 )) && tol=3          # 2% ou 3 s de folga
  if (( I_DUR > 0 && S_DUR + tol < I_DUR )); then
    V_ESTADO=incompleto
    fmt_dur "$S_DUR"; v=$FMT; fmt_dur "$I_DUR"; t vc_incompleto_det "$v" "$FMT"; V_DET=$TXT
  fi
  return 0
}

verifica_colecao() {
  local pasta=$PASTA_SAIDA arqs=() f i=0 n idxs nome hist rel bandeira rc=0 seg
  local n_ok=0 n_def=0 n_inc=0 ruins=() urls=() chaves=() sem_link=()
  (( ${#ARGS_LINKS[@]} )) && pasta=${ARGS_LINKS[0]}
  pasta=${pasta%/}
  if [[ ! -d $pasta ]]; then t vc_sem_pasta "$pasta"; erro "$TXT"; return 1; fi
  if ! command -v ffmpeg >/dev/null 2>&1 || ! command -v ffprobe >/dev/null 2>&1; then
    t dep_faltando ffmpeg; erro "$TXT"
    comando_grabit "${T[cmd_instalar]}"; t dep_instalador "${CIANO}${FMT}${R}"; printf '%s\n\n' "$TXT"
    return 1
  fi
  TMP=$(mktemp -d "${TMPDIR:-/tmp}/grabit.XXXXXX") || return 1
  trap 'rm -rf -- "$TMP"; (( INTERATIVO )) && printf "%s" "${ESC}[?25h"' EXIT
  trap 'CANCELADO=1' INT TERM                 # o ffmpeg recebe o mesmo Ctrl+C e para; o resumo sai
  atualiza_largura
  mapfile -d '' arqs < <(find "$pasta" \( -name .parciais -o -path "$pasta/logs" \) -prune -o -type f \
    \( -iname '*.mkv' -o -iname '*.mp4' -o -iname '*.webm' -o -iname '*.mov' -o -iname '*.m4v' -o -iname '*.avi' \
       -o -iname '*.ts' -o -iname '*.mka' -o -iname '*.m4a' -o -iname '*.aac' \
       -o -iname '*.opus' -o -iname '*.mp3' -o -iname '*.flac' -o -iname '*.ogg' -o -iname '*.wav' \) \
    ! -name "*${T[sufixo_ruim]}.*" -print0 2>/dev/null | sort -z)
  n=${#arqs[@]}
  printf '\n  %s%s%s\n\n' "$NEG" "${T[vc_titulo]}" "$R"
  kv "${T[s_pasta]}" "$pasta"
  if (( n == 0 )); then printf '\n  %s\n\n' "${T[vc_vazio]}"; return 0; fi
  t vc_arquivos "$n"; kv "${T[vc_arquivos_r]}" "$TXT"
  printf '  %s%s%s\n\n' "$DIM" "${T[vc_dica]}" "$R"
  (( INTERATIVO )) && printf '%s' "${ESC}[?25l"
  SECONDS=0
  for f in "${arqs[@]}"; do
    i=$(( i + 1 ))
    printf -v idxs "%0${#n}d/%d" "$i" "$n"
    nome=${f##*/}; nome=${nome%.*}
    verifica_um "$f" "$idxs  $nome"
    (( CANCELADO )) && break
    montar_meta "$S_H" "$S_FPS" "$S_HDR" "$S_VC" "$S_AC" "$S_CANAIS" "$S_DUR" "$S_TAM"
    case $V_ESTADO in
      ok)         n_ok=$(( n_ok + 1 )); linha_resultado "✔" "$VERDE" "$idxs" "$nome" "$META"; printf '%s\n' "$LINHA" ;;
      *)
        if [[ $V_ESTADO == defeito ]]; then
          n_def=$(( n_def + 1 )); linha_resultado "✖" "$VERMELHO" "$idxs" "$nome" "${T[vc_defeito]}"
        else
          n_inc=$(( n_inc + 1 )); linha_resultado "⚠" "$AMARELO" "$idxs" "$nome" "${T[vc_incompleto]}"
        fi
        corta "$V_DET" $(( COLS - 12 ))
        printf '%s\n         %s↳ %s%s\n' "$LINHA" "$DIM" "$FMT" "$R"
        if [[ -n $I_URL ]]; then ruins+=("$f"); urls+=("$I_URL"); chaves+=("$I_CHAVE")
        else sem_link+=("$nome"); fi ;;
    esac
  done
  (( INTERATIVO )) && printf '%s' "${ESC}[?25h"

  fmt_tempo "$SECONDS"; seg=$FMT
  if (( CANCELADO )); then printf '\n  %s── %s ──%s\n' "$DIM" "${T[vc_s_parcial]}" "$R"
  else printf '\n  %s── %s ─────────────────────────────────────%s\n' "$DIM" "${T[vc_s_titulo]}" "$R"; fi
  linha_resumo "✔" "$VERDE"    "${T[vc_s_ok]}"         "${NEG}${n_ok}${R}"
  linha_resumo "✖" "$VERMELHO" "${T[vc_s_defeito]}"    "${NEG}${n_def}${R}"
  linha_resumo "⚠" "$AMARELO"  "${T[vc_s_incompleto]}" "${NEG}${n_inc}${R}"
  linha_resumo "◷" "$DIM"      "${T[s_tempo]}"         "$seg"
  printf '\n'
  (( CANCELADO )) && return 130
  (( ${#sem_link[@]} )) && { t vc_sem_link "${#sem_link[@]}"; aviso "$TXT"; }
  (( ${#ruins[@]} )) || return $(( n_def + n_inc > 0 ))

  if (( ! INTERATIVO )) || [[ ! -r /dev/tty ]]; then aviso "${T[vc_terminal]}"; return 1; fi
  t vc_pergunta "${#ruins[@]}" "${T[sufixo_ruim]}"
  pergunta_sim "$TXT" || { printf '\n'; return 1; }

  # O arquivo ruim fica guardado à parte, o vídeo sai do histórico e o link volta a ser
  # baixado — com -m ou -d se o arquivo estava nesse tipo de pasta.
  if [[ -n $HIST_DO_AMBIENTE ]]; then hist=$ARQUIVO_HISTORICO; else hist="$pasta/.grabit-historico.txt"; fi
  printf '%s\n' "${chaves[@]}" | grep -v '^$' > "$TMP/chaves"
  if [[ -s $TMP/chaves && -f $hist ]]; then
    grep -vxF -f "$TMP/chaves" "$hist" > "$TMP/hist"; cat "$TMP/hist" > "$hist"
  fi
  local -a normal=() com_d=() com_m=()
  for i in "${!ruins[@]}"; do
    f=${ruins[$i]}
    mv -f -- "$f" "${f%.*}${T[sufixo_ruim]}.${f##*.}"
    rel=${f#"$pasta"/}
    if [[ $rel == *"/Season "*/* ]]; then com_m+=("${urls[$i]}")
    elif [[ $rel == */* ]]; then com_d+=("${urls[$i]}")
    else normal+=("${urls[$i]}"); fi
  done
  trap - INT TERM
  for bandeira in "" -d -m; do
    case $bandeira in
      "") (( ${#normal[@]} )) || continue; set -- "${normal[@]}" ;;
      -d) (( ${#com_d[@]} )) || continue; set -- "${com_d[@]}" ;;
      -m) (( ${#com_m[@]} )) || continue; set -- "${com_m[@]}" ;;
    esac
    bash "$GRABIT_SCRIPT" "${OPCOES[@]}" ${bandeira:+"$bandeira"} -o "$pasta" "$@" || rc=1
  done
  return "$rc"
}

# ───────────────────────────── Seção BAIXADOS (--baixados) ───────────────────
# grabit --baixados [listar|editar|voltar N…|marcar LINK…|limpar] cuida da seção BAIXADOS
# do arquivo de links (-l, ou o links.txt): listar, editar só ela no editor, devolver
# links para a lista de baixar, marcar links como baixados ou esvaziá-la.

# le_partes ARQUIVO → P_ANTES (lista de cima) P_CAB (a linha da seção e o comentário
# dela) P_SECAO (os links da seção) P_DEPOIS (o que veio depois da linha de fim),
# P_BOM e P_EOL (para regravar do mesmo jeito)
le_partes() {
  local linha estado=0 conteudo=()
  P_ANTES=(); P_CAB=(); P_SECAO=(); P_DEPOIS=(); P_VOLTA=(); P_BOM=""; P_EOL=""
  mapfile -t conteudo < "$1" || return 1
  if (( ${#conteudo[@]} )); then
    if [[ ${conteudo[0]} == $'\xef\xbb\xbf'* ]]; then P_BOM=$'\xef\xbb\xbf'; conteudo[0]=${conteudo[0]#$'\xef\xbb\xbf'}; fi
    [[ ${conteudo[0]} == *$'\r' ]] && P_EOL=$'\r'
  fi
  for linha in "${conteudo[@]}"; do
    case $estado in
      0) if eh_marca_baixados "$linha"; then estado=1; P_CAB+=("$linha"); else P_ANTES+=("$linha"); fi ;;
      1) if eh_fim_baixados "$linha"; then estado=3
         elif [[ ${#P_SECAO[@]} -eq 0 && $linha == \#* ]]; then P_CAB+=("$linha")   # o comentário da seção
         elif [[ -n ${linha//[[:space:]]/} ]]; then P_SECAO+=("$linha"); fi ;;
      3) P_DEPOIS+=("$linha") ;;
    esac
  done
}

grava_partes() {                              # grava_partes ARQUIVO: o inverso de le_partes (seção vazia some)
  local arq=$1 saida=() l
  # a lista de cima, o que estava depois da seção e o que volta dela (P_VOLTA), sem
  # linhas em branco sobrando no meio
  saida=("${P_ANTES[@]}")
  for l in "${P_DEPOIS[@]}" "${P_VOLTA[@]}"; do
    [[ -z ${l//[[:space:]]/} ]] && continue
    while (( ${#saida[@]} )) && [[ -z ${saida[-1]//[[:space:]]/} ]]; do unset 'saida[-1]'; done
    saida+=("$l")
  done
  while (( ${#saida[@]} )) && [[ -z ${saida[-1]//[[:space:]]/} ]]; do unset 'saida[-1]'; done
  if (( ${#P_SECAO[@]} )); then
    (( ${#saida[@]} )) && saida+=("$P_EOL")
    (( ${#P_CAB[@]} )) || P_CAB=("${MARCA_BAIXADOS}${P_EOL}" "${T[marca_desc]}${P_EOL}")
    saida+=("${P_CAB[@]}" "${P_SECAO[@]}" "${T[marca_fim]}${P_EOL}")
  fi
  { printf '%s' "$P_BOM"; (( ${#saida[@]} )) && printf '%s\n' "${saida[@]}"; } > "$arq.grabit-tmp" &&
    cat "$arq.grabit-tmp" > "$arq"
  rm -f -- "$arq.grabit-tmp"
}

sem_anotacao() {                              # sem_anotacao LINHA → FMT: a linha sem o "✔ data · título"
  FMT=${1%$'\r'}
  [[ $FMT =~ $ANOTACAO_ANTIGA ]] && FMT=${BASH_REMATCH[1]}
  [[ $FMT =~ ^(.*[^[:space:]])[[:space:]]+#[[:space:]]*$ ]] && FMT=${BASH_REMATCH[1]}
}

pergunta_nao() {                              # pergunta_nao TEXTO → 0 só se a resposta for sim (Enter = não)
  local resp=""                               # da entrada padrão: dá para confirmar com "echo s |"
  printf '\n  %s%s%s ' "$NEG" "$1" "$R"
  read -r resp || resp=""
  [[ ${resp,,} == s* || ${resp,,} == y* ]]
}

gerencia_baixados() {
  local arq=$ARQUIVO_LINKS acao=${ARGS_LINKS[0]:-listar} i n l lin url resto
  [[ -f $arq ]] || { t sem_arquivo "$arq"; erro "$TXT"; return 1; }
  le_partes "$arq"
  n=${#P_SECAO[@]}
  case ${acao,,} in
    listar|list|"")
      t bx_cab "$arq" "$n"; printf '\n  %s%s%s\n\n' "$NEG" "$TXT" "$R"
      atualiza_largura
      for i in "${!P_SECAO[@]}"; do
        l=${P_SECAO[$i]%$'\r'}; url=${l%%[[:space:]]*}; resto=${l#"$url"}
        resto=${resto#"${resto%%[![:space:]]*}"}; resto=${resto#\#}; resto=${resto# }
        corta "$url" $(( COLS - 12 )); lin=$FMT
        if [[ -n $resto ]] && (( LARG + ${#resto} + 12 < COLS )); then lin+="  ${DIM}${resto}${R}"; fi
        printf '  %s%4d%s  %s\n' "$DIM" $(( i + 1 )) "$R" "$lin"
      done
      (( n )) || printf '  %s\n' "${T[bx_vazia]}"
      printf '\n%s\n\n' "${T[bx_ajuda]}" ;;

    limpar|clear)
      (( n )) || { printf '\n  %s\n\n' "${T[bx_vazia]}"; return 0; }
      t bx_limpar_p "$n" "$arq" "$arq.bak"
      pergunta_nao "$TXT" || { printf '\n  %s\n\n' "${T[ins_cancelado]}"; return 1; }
      cp -p -- "$arq" "$arq.bak" || return 1
      P_SECAO=(); grava_partes "$arq"
      t bx_limpo "$n"; printf '\n  %s✔%s %s\n' "$VERDE" "$R" "$TXT"
      printf '  %s%s%s\n\n' "$DIM" "${T[bx_historico]}" "$R" ;;

    voltar|back|restore)
      local nums=("${ARGS_LINKS[@]:1}")
      local -A sai=()
      (( ${#nums[@]} )) || { erro "${T[bx_voltar_uso]}"; return 2; }
      for i in "${nums[@]}"; do
        if [[ $i =~ ^[0-9]+$ ]] && (( i >= 1 && i <= n )); then sai[$(( i - 1 ))]=1
        else t bx_numero "$i" "$n"; erro "$TXT"; return 2; fi
      done
      local fica=()
      for i in "${!P_SECAO[@]}"; do
        if [[ -n ${sai[$i]:-} ]]; then sem_anotacao "${P_SECAO[$i]}"; P_VOLTA+=("${FMT}${P_EOL}")
        else fica+=("${P_SECAO[$i]}"); fi
      done
      P_SECAO=("${fica[@]}"); grava_partes "$arq"
      t bx_voltou "${#sai[@]}"; printf '\n  %s✔%s %s\n' "$VERDE" "$R" "$TXT"
      printf '  %s%s%s\n\n' "$DIM" "${T[bx_historico]}" "$R" ;;

    marcar|add)
      local novos=("${ARGS_LINKS[@]:1}") fica=() p todos
      local -A marca=()
      (( ${#novos[@]} )) || { erro "${T[bx_marcar_uso]}"; return 2; }
      printf -v HOJE '%(%Y-%m-%d)T' -1
      for url in "${novos[@]}"; do
        links_da_linha "$url"
        (( ${#PALAVRAS_LINK[@]} )) || { t bx_nao_link "$url"; erro "$TXT"; return 2; }
        marca[${PALAVRAS_LINK[0]}]=1
        anota "${PALAVRAS_LINK[0]}" "${T[bx_a_mao]}"; P_SECAO+=("${FMT}${P_EOL}")
      done
      for l in "${P_ANTES[@]}"; do               # na lista de cima, a linha sai se todos os links dela foram marcados
        links_da_linha "$l"; todos=$(( ${#PALAVRAS_LINK[@]} > 0 ))
        for p in "${PALAVRAS_LINK[@]}"; do [[ -n ${marca[$p]:-} ]] || todos=0; done
        (( todos )) || fica+=("$l")
      done
      P_ANTES=("${fica[@]}"); grava_partes "$arq"
      t bx_marcou "${#novos[@]}"; printf '\n  %s✔%s %s\n\n' "$VERDE" "$R" "$TXT" ;;

    editar|edit)
      local ed=() tmp="$arq.grabit-editar.txt" depois=0 antes_md5 fica=() volta=()
      local -A original=()
      for l in "${P_SECAO[@]}"; do original[${l%$'\r'}]=1; done
      read -ra ed <<<"${VISUAL:-${EDITOR:-}}"
      if (( ${#ed[@]} == 0 )); then
        for l in nano vim vi; do command -v "$l" >/dev/null 2>&1 && { ed=("$l"); break; }; done
      fi
      (( ${#ed[@]} )) || { erro "${T[bx_sem_editor]}"; return 1; }
      { : </dev/tty; } 2>/dev/null || { erro "${T[bx_sem_terminal]}"; return 1; }
      { printf '%s\n' "${T[bx_ed_cab]}" ""
        for l in "${P_SECAO[@]}"; do printf '%s\n' "${l%$'\r'}"; done
        printf '\n%s\n' "${T[bx_ed_volta]}"; } > "$tmp"
      antes_md5=$(cksum < "$tmp")
      "${ed[@]}" "$tmp" </dev/tty >/dev/tty
      if [[ ! -f $tmp || $(cksum < "$tmp") == "$antes_md5" ]]; then
        rm -f -- "$tmp"; printf '\n  %s\n\n' "${T[bx_nada_mudou]}"; return 0
      fi
      while IFS= read -r l || [[ -n $l ]]; do
        l=${l%$'\r'}
        [[ $l == "${T[bx_ed_volta]}" ]] && { depois=1; continue; }
        [[ $l == '#:'* || -z ${l//[[:space:]]/} ]] && continue
        if (( depois )); then sem_anotacao "$l"; volta+=("${FMT}${P_EOL}"); continue; fi
        # link novo, acrescentado agora: ganha a mesma anotação do "marcar"
        if [[ -z ${original[$l]:-} && ! $l =~ $ANOTACAO_ANTIGA ]]; then
          links_da_linha "$l"
          (( ${#PALAVRAS_LINK[@]} )) && { printf -v HOJE '%(%Y-%m-%d)T' -1; anota "$l" "${T[bx_a_mao]}"; l=$FMT; }
        fi
        fica+=("${l}${P_EOL}")
      done < "$tmp"
      rm -f -- "$tmp"
      P_SECAO=("${fica[@]}"); P_VOLTA=("${volta[@]}"); grava_partes "$arq"
      t bx_editado "${#fica[@]}" "${#volta[@]}"; printf '\n  %s✔%s %s\n\n' "$VERDE" "$R" "$TXT" ;;

    *) t bx_acao "$acao"; erro "$TXT"; printf '%s\n\n' "${T[bx_ajuda]}"; return 2 ;;
  esac
  return 0
}

# ───────────────────────────── Principal ──────────────────────────────────────
case $COMANDO in
  instalar)  instalar;  exit $? ;;
  atualizar) atualizar; exit $? ;;
  verificar) verifica_colecao; exit $? ;;
  baixados)  gerencia_baixados; exit $? ;;
  versao)    mostra_versao; exit $? ;;
esac
trap 'CANCELADO=1; SINAL=INT;  exit 130' INT
trap 'CANCELADO=1; SINAL=TERM; exit 143' TERM
trap 'CANCELADO=1; SINAL=HUP;  exit 129' HUP
trap limpa EXIT

atualiza_largura
cabecalho
TMP=$(mktemp -d "${TMPDIR:-/tmp}/grabit.XXXXXX") || { erro "${T[tmp_falhou]}"; exit 1; }
verifica_dependencias
carrega_metodos
[[ $COMANDO == curl ]] && le_curl
if (( CAPTURA )) && ! detecta_clip; then
  erro "${T[clip_sem]}"; printf '%s\n\n' "${T[clip_sem2]}"; exit 1
fi
(( CAPTURA )) && aviso_wayland
ler_links

mkdir -p "$PASTA_SAIDA" || { t pasta_falhou "$PASTA_SAIDA"; erro "$TXT"; exit 1; }
printf -v LOG_DIR '%s/logs/%(%Y-%m-%d_%H%M%S)T' "$PASTA_SAIDA" -1
prepara_parciais
(( UPGRADE )) && recupera_antigos

J=$DOWNLOADS_SIMULTANEOS
(( ! FILA_VIVA && J > TOTAL )) && J=$TOTAL
LIMITE_J=0
if (( INTERATIVO )); then                       # o painel (2 linhas por vídeo + 2) precisa caber na tela
  linhas=$(tput lines 2>/dev/null); [[ $linhas =~ ^[0-9]+$ ]] || linhas=24
  max_j=$(( (linhas - 3) / 2 )); (( max_j < 1 )) && max_j=1
  if (( J > max_j )); then LIMITE_J=$J; J=$max_j; fi
fi
for (( s = 0; s < J; s++ )); do SLOT_IDX[$s]=0; SLOT_PID[$s]=0; done
for (( i = 1; i <= TOTAL; i++ )); do site_de "${LINKS[$(( i - 1 ))]}"; SITE[$i]=$FMT; enfileira "$i"; done
monta_args_ytdlp

extras=""
(( DUPLICADOS > 0 )) && { t links_repetidos "$DUPLICADOS"; extras+=$TXT; }
(( INVALIDAS  > 0 )) && { t links_sem_link "$INVALIDAS"; extras+="${extras:+,}$TXT"; }
[[ -n $extras ]] && { t links_ignorados "$extras"; extras=$TXT; }
(( N_NA_SECAO > 0 )) && { t links_na_secao "$N_NA_SECAO"; extras+=$TXT; }
if (( SO_AUDIO )); then
  txt_extras=${T[kv_extras_audio]}
else
  t kv_legendas "$IDIOMAS_LEGENDAS"; txt_extras=$TXT
  (( LEGENDAS_AUTOMATICAS )) && txt_extras+=${T[kv_automaticas]}
  txt_extras+=${T[kv_extras_resto]}
fi
(( SO_PRINCIPAL )) && txt_extras+=${T[kv_principal]}
(( VERIFICAR ))    && txt_extras+=${T[kv_verificar]}
[[ -n $NTFY_TOPICO ]] && txt_extras+=${T[kv_ntfy]}
(( MIDIA ))        && txt_extras+=${T[kv_nfo]}
(( SPONSORBLOCK )) && txt_extras+=", SponsorBlock"
if [[ -z $IMPERSONATE ]]; then txt_imp="${AMARELO}${T[imp_indisp]}${R}"
elif (( TENTATIVAS > 1 )); then txt_imp=${T[imp_retry]}
else txt_imp=${T[imp_off]}; fi

if (( ${#SITES[@]} > 1 )); then t links_sites "${#SITES[@]}"; extras+=$TXT; fi
kv "${T[kv_links]}"   "${NEG}${TOTAL}${R}${DIM} · ${FONTE_LINKS}${extras}${R}"
if (( MIDIA )); then kv "${T[kv_destino]}" "$PASTA_SAIDA/${T[kv_midia]}"
elif (( SUBPASTAS )); then kv "${T[kv_destino]}" "$PASTA_SAIDA/${T[kv_subpastas]}"
else kv "${T[kv_destino]}" "$PASTA_SAIDA"; fi
if (( UPGRADE )); then kv "${T[kv_modo]}" "${T[kv_upgrade]}"; fi
if (( MODO_CURL )); then t kv_curl "$N_CAB_CURL" "$N_COOK_CURL" "$ROTULO_CURL"; kv "${T[kv_modo]}" "$TXT"; fi
if (( SO_AUDIO )); then
  if [[ $FORMATO_AUDIO == original ]]; then kv "${T[kv_modo]}" "${T[kv_audio_original]}"
  else t kv_audio_conv "$FORMATO_AUDIO"; kv "${T[kv_modo]}" "$TXT"; fi
fi
txt_ign=""
if (( ${#IGNORADO[@]} )); then                  # o que o -F desligou nesta execução
  descreve_limites "${IGNORADO[RESOLUCAO_MAXIMA]:-0}" "${IGNORADO[LIMITE_POR_SITE]:-0}" \
    "${IGNORADO[PAUSA_ENTRE_VIDEOS]:-0}" "${IGNORADO[LIMITE_VELOCIDADE]:-0}"
  txt_ign=$TXT
fi
descreve_limites "$RESOLUCAO_MAXIMA" "$LIMITE_POR_SITE" "$PAUSA_ENTRE_VIDEOS" "$LIMITE_VELOCIDADE"
if [[ -n $TXT ]]; then
  txt_lim=$TXT
  for nome in "${CHAVES_LIMITE[@]}"; do         # algum veio do grabit.config? o -F o desligaria
    if [[ ${!nome} != 0 && ${ORIGEM[$nome]:-} != opção ]]; then txt_lim+=${T[lim_f]}; break; fi
  done
  [[ -n $txt_ign ]] && { t lim_ignorando "$txt_ign"; txt_lim+=$TXT; }
  kv "${T[kv_limites]}" "$txt_lim"
elif [[ -n $txt_ign ]]; then
  t lim_desligados "$AMARELO" "$R" "$txt_ign"; kv "${T[kv_limites]}" "$TXT"
fi
if (( CONFIG_CRIADO )); then
  t kv_config_criado "$VERDE" "$R" "${CONFIG_ARQ/#$HOME/\~}"; kv "${T[kv_config]}" "$TXT"
elif [[ -f $CONFIG_ARQ ]]; then
  t kv_config_ajustes "$N_AJUSTES_CONFIG"; kv "${T[kv_config]}" "$TXT"
fi
if (( USAR_HISTORICO )); then
  n_registrados=$(grep -c '' "$ARQUIVO_HISTORICO" 2>/dev/null) || n_registrados=0
  t kv_hist_on "$n_registrados"; kv "${T[kv_historico]}" "$TXT"
elif (( ! MODO_CURL )); then
  t kv_hist_off "$AMARELO" "$R"; kv "${T[kv_historico]}" "$TXT"
fi
t kv_paralelo_v "$J" "$CONEXOES_POR_VIDEO"; txt_paralelo=$TXT
(( TENTATIVAS > 1 )) && { t kv_tentativas "$TENTATIVAS"; txt_paralelo+=$TXT; }
kv "${T[kv_paralelo]}" "$txt_paralelo"
if (( CAPTURA )); then t kv_clip "${CLIP_CMD[0]}" "$ARQ_CAPTURA"; kv "${T[kv_captura]}" "$TXT"
elif (( FILA_VIVA )); then kv "${T[kv_fila_viva]}" "${T[kv_fv]}"; fi
kv "${T[kv_extras]}"   "$txt_extras"
FFMPEG_VER=${FFMPEG_VER:-?}
kv "${T[kv_ferramentas]}" "yt-dlp ${YTDLP_VER:-?} · ffmpeg ${FFMPEG_VER%%-*}"
kv "${T[kv_recursos]}"    "impersonate: ${txt_imp} · js: ${JS_RUNTIME:-${AMARELO}${T[js_nenhum]}${R}}"
printf '\n'
for a in "${AVISOS_CONFIG[@]}"; do t cfg_linha "${a%%:*}" "${a#*:}"; aviso "$TXT"; done
if (( LIMITE_J > 0 )); then
  t av_linhas "$linhas" "$J"; aviso "$TXT"
  t av_linhas2 "$LIMITE_J"; printf '%s\n' "$TXT"
fi
idade_ytdlp
if (( NUM >= 3 )) || (( ! TEM_JS_RUNTIMES )); then
  t av_ytdlp "${YTDLP_VER:-?}"; aviso "$TXT"
  comando_grabit "${T[cmd_atualizar]}"; t av_ytdlp2 "${CIANO}${FMT}${R}"; printf '%s\n' "$TXT"
fi
if [[ -z $IMPERSONATE ]]; then
  aviso "${T[av_curl]}"
  t av_curl2 "${CIANO}pipx inject yt-dlp curl-cffi${R}"; printf '%s\n' "$TXT"
fi
if [[ -z $JS_RUNTIME ]]; then
  if [[ -n $JS_RECUSADO ]]; then t av_js_velho "$JS_RECUSADO"; aviso "$TXT"; else aviso "${T[av_js]}"; fi
  comando_grabit "${T[cmd_instalar]}"; t av_js2 "${CIANO}${FMT}${R}"; printf '%s\n' "$TXT"
fi
# Pouco espaço na pasta de destino (menos de 2 GiB)? Melhor saber antes de começar.
livre=$(df -Pk -- "$PASTA_SAIDA" 2>/dev/null | awk 'NR==2 {print $4}')
if [[ $livre =~ ^[0-9]+$ ]] && (( livre < 2097152 )); then
  fmt_bytes $(( livre * 1024 )); t av_disco "$FMT" "$PASTA_SAIDA"; aviso "$TXT"
fi
# Teclas: o terminal para de ecoar e entrega cada tecla na hora (sem esperar o Enter)
if (( INTERATIVO )) && { exec 3</dev/tty; } 2>/dev/null; then
  if STTY_SAVE=$(stty -g <&3 2>/dev/null) && stty -echo -icanon min 1 time 0 <&3 2>/dev/null; then TECLAS=1; fi
fi
J_ALVO=$J
printf '  %s%s%s\n' "$DIM" "${T[dica_ctrlc]}" "$R"
(( TECLAS )) && printf '  %s%s%s\n' "$DIM" "${T[dica_teclas]}" "$R"
printf '\n'

# Redimensionou a janela? O painel se ajusta no próximo quadro. (O trap só entra
# agora: antes ele interromperia o "wait" das consultas ao yt-dlp.)
REDIM=1
trap 'REDIM=1' WINCH
COMECOU=1
SECONDS=0
aplica_esperas
if (( INTERATIVO )); then
  printf '%s' "${ESC}[?25l${ESC}[?7l${ESC}[22;0t"   # esconde o cursor, desliga a quebra de linha, guarda o título
  TITULO_EMPILHADO=1
fi

while (( FINALIZADOS < TOTAL )) || (( FILA_VIVA && ! PARANDO )); do
  atualiza_largura
  if (( CAPTURA && SECONDS >= PROX_CLIP )); then captura_clip; PROX_CLIP=$(( SECONDS + 1 )); fi
  if (( FILA_VIVA && SECONDS >= PROX_VIGIA )); then novos_links; PROX_VIGIA=$(( SECONDS + 2 )); fi
  if (( SECONDS >= PROX_BLOQ )); then vigia_saude; vigia_bloqueios; PROX_BLOQ=$(( SECONDS + 1 )); fi
  # Numa lista longa, o que já foi baixado não pode depender de a execução chegar ao fim: se a
  # luz acabar, a lista recomeça de onde parou, sem abrir o yt-dlp para cada link que já foi.
  if (( MOVER && SECONDS >= PROX_MOVER )); then move_baixados; MOVER=0; PROX_MOVER=$(( SECONDS + 60 )); fi

  # 1) recolhe quem terminou (e devolve à fila quem merece outra tentativa)
  for (( s = 0; s < J; s++ )); do
    idx=${SLOT_IDX[$s]}
    (( idx > 0 )) || continue
    kill -0 "${SLOT_PID[$s]}" 2>/dev/null && continue
    wait "${SLOT_PID[$s]}" 2>/dev/null; rc=$?
    SLOT_IDX[$s]=0
    ATIVOS_SITE[${SITE[$idx]}]=$(( ${ATIVOS_SITE[${SITE[$idx]}]:-1} - 1 ))
    if (( NAV_DONO == idx )); then NAV_DONO=0; rmdir "$TMP/navegador.trava" 2>/dev/null; fi
    if (( rc == 0 )) && [[ -z ${SAUDAVEL[$idx]:-} ]]; then SAUDAVEL[$idx]=1; site_aceitou "${SITE[$idx]}"; fi
    if (( rc != 0 )) && vale_repetir "$idx"; then continue; fi
    (( ${TENTATIVA[$idx]:-1} > 1 )) && EM_REPETICAO=$(( EM_REPETICAO - 1 ))
    BAIXOU=0
    processa_resultado "$idx" "$rc"
    [[ -n ${SUCESSO[$idx]:-} ]] && MOVER=1
    # para estimar o tempo restante, só contam os links que baixaram algo de fato
    (( BAIXOU )) && { T_SOMA=$(( T_SOMA + SECONDS - ${INICIO_JOB[$idx]:-$SECONDS} )); T_N=$(( T_N + 1 )); }
  done

  # 2) ocupa os slots livres, espalhando os downloads entre os sites
  ativos=0
  for (( s = 0; s < J; s++ )); do (( SLOT_IDX[$s] > 0 )) && ativos=$(( ativos + 1 )); done
  for (( s = 0; s < J; s++ )); do
    (( SLOT_IDX[$s] == 0 )) || continue
    (( PAUSADO || PARANDO || ativos >= J_ALVO )) && break
    escolhe_proximo || break
    idx=$ESCOLHIDO
    lanca_job "$idx"
    SLOT_IDX[$s]=$idx
    SLOT_PID[$s]=$ULTIMO_PID
    ativos=$(( ativos + 1 ))
  done
  ATIVOS=$ativos
  (( PARANDO && ativos == 0 )) && break         # q: os que estavam rodando terminaram
  if (( FILA_VIVA )); then
    if (( ativos > 0 && OCUPADO_DESDE < 0 )); then OCUPADO_DESDE=$SECONDS
    elif (( ativos == 0 && OCUPADO_DESDE >= 0 )); then
      # a fila esvaziou: os baixados vão para a seção BAIXADOS e, se demorou, avisa
      (( MOVER )) && { move_baixados; MOVER=0; }
      notifica $(( SECONDS - OCUPADO_DESDE )); OCUPADO_DESDE=-1
    fi
  fi

  desenha
  # Tecla apertada? "read -t 0" só confere, sem esperar. (Esperar no próprio read, com
  # "read -t 0.2", deixa o Ctrl+C fazer a limpeza toda de dentro do read, e o alarme dele
  # disparando no meio derruba o Bash 5.2.)
  if (( TECLAS )) && read -t 0 -u 3 2>/dev/null; then
    tecla=""
    read -rsn1 -u 3 tecla 2>/dev/null && trata_tecla "$tecla"
  fi
  sleep 0.2
done

desenha final
descarta_parciais
move_baixados
resumo
(( FILA_VIVA )) || notifica
(( N_ERRO > 0 || N_ADIADOS > 0 || FINALIZADOS < TOTAL )) && exit 1
exit 0
