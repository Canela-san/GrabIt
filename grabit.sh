#!/usr/bin/env bash
# ==============================================================================
#  GrabIt (grabit.sh)  —  yt-dlp em lote · máxima qualidade · terminal limpo
#  https://github.com/Canela-san/GrabIt
#  Copyright (c) 2026 Gabriel Canela (Canela-san) · Licença MIT (veja LICENSE)
#  SPDX-License-Identifier: MIT
# ==============================================================================
#  Uso:  grabit [opções] [LINK ou ARQUIVO ...]
#
#    -l ARQUIVO    arquivo com os links ("-" = entrada padrão)  (padrão: links.txt)
#    -o PASTA      pasta onde os vídeos serão salvos            (padrão: ./Downloads)
#    -j N          downloads simultâneos                        (padrão: 2)
#    -c N          conexões (fragmentos) por vídeo              (padrão: 4)
#    -b NAVEGADOR  usa os cookies do navegador (firefox, chrome, brave…)
#    -p            só o vídeo, se o link tiver vídeo + playlist
#    -a            inclui legendas automáticas (a manual continua tendo prioridade)
#    -s            marca patrocínios/intros como capítulos (SponsorBlock)
#    -i            ignora o histórico de baixados (confere arquivo por arquivo)
#    -h            mostra esta ajuda
#
#  • Links e arquivos de links também podem vir direto no comando (aí o
#    links.txt só é lido se você passar -l):
#        grabit https://youtu.be/xxxx outra_lista.txt
#  • Nos arquivos: linhas vazias e comentários (# …, inclusive no fim da linha)
#    são ignorados, assim como texto em volta do link; repetidos são descartados.
#  • Cada download roda com a saída do yt-dlp isolada em um log. O terminal
#    mostra só um painel ao vivo + uma linha por vídeo concluído.
#  • Cada vídeo baixado entra no histórico (Downloads/.grabit-historico.txt): da
#    próxima vez ele é pulado na hora, sem acessar o site nem mexer no arquivo.
#    Apagou um vídeo e quer baixá-lo de novo? Use -i ou apague a linha dele lá.
#  • Link que falha por motivo passageiro (rede, 403…) ganha nova tentativa no
#    fim da fila, imitando um navegador (--impersonate) se houver curl_cffi.
#  • Links que falharem vão para links_falhos.txt, prontos para reexecutar:
#        grabit -l links_falhos.txt
#  • Download que não terminou (Ctrl+C, erro) recomeça do zero na próxima vez:
#    retomar pedaços não garante a qualidade. A pasta Downloads/.parciais só existe
#    enquanto o GrabIt roda. Os links que faltavam vão para links_falhos.txt.
#
#  Variáveis de ambiente também funcionam, ex.: DOWNLOADS_SIMULTANEOS=3 grabit
#  Só por variável: IDIOMAS_LEGENDAS="pt.*,en.*" ("all" = todas) · TENTATIVAS=2 · NO_COLOR=1
# ==============================================================================

if [ -z "${BASH_VERSION:-}" ] || [ "${BASH_VERSINFO[0]}" -lt 4 ] ||
   { [ "${BASH_VERSINFO[0]}" -eq 4 ] && [ "${BASH_VERSINFO[1]}" -lt 4 ]; }; then
  echo "Este script precisa do Bash 4.4 ou superior (execute com: bash grabit.sh)." >&2
  echo "No macOS, instale um Bash novo com: brew install bash" >&2
  exit 1
fi

set -uo pipefail
shopt -s extglob

# Garante UTF-8 (necessário para os símbolos e para medir a largura do texto)
if [[ "$(locale charmap 2>/dev/null)" != "UTF-8" ]]; then
  for loc in C.UTF-8 en_US.UTF-8 pt_BR.UTF-8; do
    if [[ "$(LC_ALL=$loc locale charmap 2>/dev/null)" == "UTF-8" ]]; then export LC_ALL=$loc; break; fi
  done
fi
export PYTHONUNBUFFERED=1 PYTHONIOENCODING=utf-8

# ───────────────────────────── Configuração ───────────────────────────────────
ARQUIVO_LINKS="${ARQUIVO_LINKS:-links.txt}"
PASTA_SAIDA="${PASTA_SAIDA:-./Downloads}"
DOWNLOADS_SIMULTANEOS="${DOWNLOADS_SIMULTANEOS:-2}"   # vídeos ao mesmo tempo
CONEXOES_POR_VIDEO="${CONEXOES_POR_VIDEO:-4}"         # fragmentos por vídeo
TENTATIVAS="${TENTATIVAS:-2}"                         # tentativas por link (1 = sem repetir)
IDIOMAS_LEGENDAS="${IDIOMAS_LEGENDAS:-pt.*,en.*}"     # "all" para todas
LEGENDAS_AUTOMATICAS="${LEGENDAS_AUTOMATICAS:-0}"     # 1 = inclui legendas automáticas
SPONSORBLOCK="${SPONSORBLOCK:-0}"                     # 1 = marca patrocínios/intros como capítulos
SEM_PLAYLIST="${SEM_PLAYLIST:-0}"                     # 1 = link vídeo+playlist baixa só o vídeo
COOKIES_NAVEGADOR="${COOKIES_NAVEGADOR:-}"            # ex.: firefox, chrome, brave
ARQUIVO_FALHAS="${ARQUIVO_FALHAS:-links_falhos.txt}"
USAR_HISTORICO="${USAR_HISTORICO:-1}"                 # 0 = não pula o que já foi baixado antes
ARQUIVO_HISTORICO="${ARQUIVO_HISTORICO:-}"            # padrão: <pasta de saída>/.grabit-historico.txt
TEMPLATE_SAIDA='%(title).180B [%(id)s].%(ext)s'

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

uso() {                                       # a ajuda é o próprio cabeçalho deste arquivo
  awk '/^# =+$/ { n++; next } n == 2 { sub(/^#/, ""); sub(/^  ?/, ""); print }' "$0" 2>/dev/null ||
    printf 'Uso: %s [opções] [LINK ou ARQUIVO ...]\n' "$(basename "$0")"
}

OPCOES=(); LISTA_EXPLICITA=0
while getopts ":l:o:j:c:b:pasih" op; do
  case $op in
    l) ARQUIVO_LINKS=$OPTARG; LISTA_EXPLICITA=1; continue ;;
    o) PASTA_SAIDA=$OPTARG ;;
    j) DOWNLOADS_SIMULTANEOS=$OPTARG ;;
    c) CONEXOES_POR_VIDEO=$OPTARG ;;
    b) COOKIES_NAVEGADOR=$OPTARG ;;
    p) SEM_PLAYLIST=1 ;;
    a) LEGENDAS_AUTOMATICAS=1 ;;
    s) SPONSORBLOCK=1 ;;
    i) USAR_HISTORICO=0 ;;
    h) uso; exit 0 ;;
    :) erro "A opção -$OPTARG precisa de um valor."; exit 2 ;;
    *) erro "Opção inválida: -$OPTARG"; uso; exit 2 ;;
  esac
  OPCOES+=("-$op" ${OPTARG+"$OPTARG"})        # guardadas para sugerir o comando de nova tentativa
done
shift $(( OPTIND - 1 ))
ARGS_LINKS=("$@")
[[ -z $ARQUIVO_HISTORICO ]] && ARQUIVO_HISTORICO="$PASTA_SAIDA/.grabit-historico.txt"

for par in DOWNLOADS_SIMULTANEOS:-j CONEXOES_POR_VIDEO:-c TENTATIVAS:; do
  nome=${par%%:*}; flag=${par#*:}; valor=${!nome}
  if ! [[ $valor =~ ^[1-9][0-9]*$ ]]; then
    erro "${flag:+A opção $flag }($nome) precisa ser um número inteiro maior que zero (recebi: '$valor')."
    exit 2
  fi
done

# ───────────────────────────── Estado global ──────────────────────────────────
J=0; TOTAL=0; COLS=100; TICK=0; LIVE_H=0; CANCELADO=0; SINAL=""; STTY_SAVE=""; TMP=""
N_OK=0; N_JA=0; N_ERRO=0; N_AVISOS=0; N_FATAIS=0; N_COSMETICOS=0; AVISO_CTX=""; BYTES_NOVOS=0; FINALIZADOS=0; DUPLICADOS=0; INVALIDAS=0
VEL_TOTAL=0; EM_REPETICAO=0; PROXIMO=1; REDIM=1; JANELA=""; TITULO_EMPILHADO=0; COMECOU=0
ULTIMO_PID=0; IMPERSONATE=""; JS_RUNTIME=""; JS_PATH=""; YTDLP_VER=""; FFMPEG_VER=""; TEM_JS_RUNTIMES=0
S_H=0; S_FPS=0; S_HDR="SDR"; S_VC=""; S_AC=""; S_CANAIS=0; S_DUR=0; S_TAM=0
FMT=""; LARG=0; LINHA=""; BARRA=""; META=""; NUM=0; ETAPA=""; MOTIVO=""; DICA=""; REPETE=1; ARQUIVO_RUIM=0
FONTE_LINKS=""; LOG_DIR=""; DIR_TEMP=""; TEMP_REL=""
LINKS=(); SLOT_IDX=(); SLOT_PID=(); PERM=(); LIVE=(); FALHAS=(); YTDLP_ARGS=(); REPETIR=()
TENTATIVA=(); FEITO=(); REBAIXAR=(); ARQUIVOS_ENTRADA=()
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
  MOTIVO=${MOTIVO//[[:cntrl:]]/ }
}

# classifica_erro TEXTO → DICA (explicação curta), REPETE (0 = não adianta tentar de
# novo) e ARQUIVO_RUIM (1 = o arquivo baixado está corrompido: refazer do zero)
classifica_erro() {
  DICA=""; REPETE=1; ARQUIVO_RUIM=0
  case ${1,,} in
    *"private video"*)                                      DICA="vídeo privado"; REPETE=0 ;;
    *"confirm your age"*|*"age-restricted"*|*"inappropriate for some users"*)
                                                            DICA="restrito por idade — use -b NAVEGADOR"; REPETE=0 ;;
    *"not a bot"*)                                          DICA="o YouTube pediu login — use -b NAVEGADOR"; REPETE=0 ;;
    *"members-only"*|*"join this channel"*)                 DICA="exclusivo para membros"; REPETE=0 ;;
    *"not available in your country"*|*"geo restrict"*|*"geo-restrict"*)
                                                            DICA="bloqueado na sua região"; REPETE=0 ;;
    *"video unavailable"*|*"has been removed"*|*"no longer available"*)
                                                            DICA="vídeo indisponível ou removido"; REPETE=0 ;;
    *"unsupported url"*|*"is not a valid url"*)             DICA="link não suportado"; REPETE=0 ;;
    *"live event will begin"*|*"premieres in"*)             DICA="a live/estreia ainda não começou"; REPETE=0 ;;
    *"http error 404"*|*"http error 410"*)                  DICA="não encontrado (404)"; REPETE=0 ;;
    *"no space left"*)                                      DICA="disco cheio"; REPETE=0 ;;
    *"invalid data found when processing input"*|*"moov atom not found"*|*"ebml header parsing failed"*)
                                                            DICA="o arquivo baixado não é um vídeo válido"; ARQUIVO_RUIM=1 ;;
    *"fragment"*"not found"*|*"unable to download fragment"*) DICA="um pedaço do vídeo não baixou" ;;
    *"http error 403"*)                                     DICA="acesso negado (403)" ;;
    *"http error 429"*|*"too many requests"*)               DICA="muitas requisições (429)" ;;
    *"timed out"*|*"connection reset"*|*"name resolution"*|*"name or service not known"*|*"network is unreachable"*)
                                                            DICA="falha de rede" ;;
  esac
}

# ───────────────────────────── Painel ao vivo ─────────────────────────────────
etapa_da_linha() {                            # o que uma linha do log diz sobre a etapa → ETAPA ("" = nada)
  ETAPA=""
  case $1 in
    *"aren't any"*|*"are no "*|*"Not remuxing"*|"Deleting original"*|WARNING:*) ;;   # "nada a fazer"
    @@D@@*|"[MoveFiles]"*)                                         ETAPA="finalizando" ;;
    "[Merger]"*)                                                   ETAPA="mesclando vídeo e áudio" ;;
    "[VideoRemuxer]"*)                                             ETAPA="convertendo para MKV" ;;
    "[Metadata]"*|"[EmbedInfoJson]"*)                              ETAPA="gravando metadados" ;;
    "[EmbedSubtitle]"*|"[SubtitlesConvertor]"*)                    ETAPA="embutindo legendas" ;;
    "[EmbedThumbnail]"*|"[ThumbnailsConvertor]"*)                  ETAPA="embutindo a capa" ;;
    "[SponsorBlock]"*|"[ModifyChapters]"*)                         ETAPA="processando capítulos" ;;
    "[Fixup"*)                                                     ETAPA="corrigindo o arquivo" ;;
    *"Downloading subtitles"*|*"Writing video subtitles"*)         ETAPA="baixando legendas" ;;
    *"Downloading video thumbnail"*|*"Writing video thumbnail"*)   ETAPA="baixando a capa" ;;
    *" has already been recorded in the archive")                  ETAPA="já baixado antes (histórico)" ;;
    *" has already been downloaded")                               ETAPA="arquivo já existe" ;;
    "[download] Destination"*|"[info] "*" format(s): "*|"[hlsnative]"*|"[dashsegments]"*)
                                                                   ETAPA="iniciando download" ;;
    @@P@@*)                                                        ETAPA="processando" ;;
    "[download] Downloading item "*)
      [[ $1 =~ item\ ([0-9]+)\ of\ ([0-9]+) ]] &&
        ETAPA="obtendo informações · item ${BASH_REMATCH[1]}/${BASH_REMATCH[2]}" ;;
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
  titulo=${TITULO[$idx]:-${LINKS[$(( idx - 1 ))]}}
  tent=${TENTATIVA[$idx]:-1}
  if (( tent > 1 )); then pre_txt="${tent}ª tentativa · "; pre="${AMARELO}${pre_txt}${R}"; fi

  if [[ $linha == @@P@@* ]]; then
    local baixado total vel eta pidx pn vcod alt fps ext ttl tipo bw p10 pct detalhe fb ft resto parte vs="" es=""
    IFS=$SEP read -r baixado total vel eta pidx pn vcod alt fps ext ttl <<<"${linha#@@P@@}"
    ttl=${ttl//[[:cntrl:]]/ }
    if [[ -n $ttl && $ttl != "?" ]]; then TITULO[$idx]=$ttl; titulo=$ttl; fi
    num "$baixado"; baixado=$NUM
    num "$total";   total=$NUM
    num "$vel";     vel=$NUM
    num "$eta";     eta=$NUM
    VEL_TOTAL=$(( VEL_TOTAL + vel ))
    if [[ $pidx =~ ^[0-9]+$ ]]; then pre_txt+="item ${pidx}${pn:+/$pn} · "; pre+="${DIM}item ${pidx}${pn:+/$pn} · ${R}"; fi
    case $ext in
      vtt|srt|ass|ssa|ttml|dfxp|srv[123]|json3|lrc) tipo="legendas" ;;
      *)
        if [[ $vcod == none ]]; then
          tipo="áudio"
        else                                  # ex.: "vídeo 2160p60" — dá para ver a qualidade chegando
          tipo="vídeo"; num "$alt"
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
  else
    # Sem progresso agora: a linha informativa mais recente do log diz a etapa
    # (extraindo, baixando legendas, mesclando, embutindo…).
    ETAPA=""
    for (( k = ${#ult[@]} - 1; k >= 0; k-- )); do
      etapa_da_linha "${ult[$k]}"
      [[ -n $ETAPA ]] && break
    done
    [[ -z $ETAPA ]] && ETAPA="obtendo informações"
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
  printf -v reg '%*s' "$larg" ''
  LIVE+=("  ${CINZA}${reg// /─}${R}")

  # barra total com largura fixa por terminal; some em terminal estreito
  l="  ${NEG}Total${R} "; w=8
  bw=$(( COLS - 76 )); (( bw > 24 )) && bw=24
  if (( bw >= 6 )); then
    barra $(( FINALIZADOS * bw / TOTAL )) "$bw"
    l+="${BARRA}  "; w=$(( w + bw + 2 ))
  fi
  plano="${FINALIZADOS}/${TOTAL}  ✔ ${N_OK}  ↷ ${N_JA}  ✖ ${N_ERRO}"
  l+="${NEG}${FINALIZADOS}/${TOTAL}${R}  ${VERDE}✔ ${N_OK}${R}  ${AMARELO}↷ ${N_JA}${R}  ${VERMELHO}✖ ${N_ERRO}${R}"
  w=$(( w + ${#plano} ))
  # o resto entra enquanto couber, do mais para o menos importante
  if (( EM_REPETICAO > 0 )); then partes+=("↻ ${EM_REPETICAO}"); cores+=("$AMARELO"); fi
  fmt_tempo "$SECONDS";     partes+=("◷ ${FMT}"); cores+=("$DIM")
  fmt_bytes "$BYTES_NOVOS"; partes+=("▣ ${FMT}"); cores+=("$DIM")
  if (( VEL_TOTAL > 0 )); then fmt_bytes "$VEL_TOTAL"; partes+=("⇣ ${FMT}/s"); cores+=("$CIANO"); fi
  for i in "${!partes[@]}"; do
    (( w + 2 + ${#partes[$i]} < COLS )) || break
    l+="  ${cores[$i]}${partes[$i]}${R}"; w=$(( w + 2 + ${#partes[$i]} ))
  done
  LIVE+=("$l")
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
      (( tent > 1 )) && printf '\n# ── tentativa %d ──\n' "$t"
      if (( t < tent )); then grep -av '^@@P@@' "$TMP/$idx.t$t.log"; else grep -av '^@@P@@' "$TMP/$idx.log"; fi
    done
  } > "$nome" 2>/dev/null
}

processa_resultado() {                        # processa_resultado IDX CÓDIGO_DE_SAÍDA
  local idx=$1 rc=$2 url idxs d n_done n_ja n_hist t tent logs=() dones=() hist=()
  local tipo h fps hdr vc ac canais dur titulo vid caminho tam glifo cor det l hid filtrados=()
  local -A baixados=()
  url=${LINKS[$(( idx - 1 ))]}
  tent=${TENTATIVA[$idx]:-1}
  printf -v idxs "%0${#TOTAL}d/%d" "$idx" "$TOTAL"
  for (( t = 1; t < tent; t++ )); do logs+=("$TMP/$idx.t$t.log"); done
  logs+=("$TMP/$idx.log")

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
      dado[p] = d
    }
    END { for (i = 1; i <= k; i++) print (st[ordem[i]] ? "N" : "J") S dado[ordem[i]] }')
  n_done=${#dones[@]}

  for d in "${dones[@]}"; do
    IFS=$SEP read -r tipo h fps hdr vc ac dur titulo vid caminho <<<"$d"
    [[ -n $vid ]] && baixados[$vid]=1
    titulo=${titulo//[[:cntrl:]]/ }
    canais=0; tam=0
    # os dados do arquivo gravado (ffprobe) valem mais que os do extrator
    if sonda "$caminho"; then h=$S_H; fps=$S_FPS; hdr=$S_HDR; vc=$S_VC; ac=$S_AC; canais=$S_CANAIS; dur=$S_DUR; tam=$S_TAM; fi
    if (( tam == 0 )); then                     # sem ffprobe: stat do GNU (Linux) ou do BSD (macOS)
      tam=$(stat -c %s -- "$caminho" 2>/dev/null || stat -f %z -- "$caminho" 2>/dev/null)
      num "$tam"; tam=$NUM
    fi
    montar_meta "$h" "$fps" "$hdr" "$vc" "$ac" "$canais" "$dur" "$tam"
    if [[ $tipo == J ]]; then
      glifo="↷"; cor=$AMARELO; N_JA=$(( N_JA + 1 ))
      META="já existia${META:+ · $META}"
    else
      glifo="✔"; cor=$VERDE; N_OK=$(( N_OK + 1 )); BYTES_NOVOS=$(( BYTES_NOVOS + tam ))
    fi
    linha_resultado "$glifo" "$cor" "$idxs" "$titulo" "$META"
    PERM+=("$LINHA")
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
    N_JA=$(( N_JA + n_hist ))
    if (( n_done == 0 && n_hist == 1 )); then
      titulo=${hist[0]#\[download\] }
      titulo=${titulo% has already been recorded in the archive}
      if [[ $titulo == *": "* ]]; then titulo=${titulo#*: }; else titulo=""; fi
      titulo=${titulo//[[:cntrl:]]/ }
      linha_resultado "↷" "$AMARELO" "$idxs" "${titulo:-${TITULO[$idx]:-$url}}" "já baixado antes"
    else
      linha_resultado "↷" "$AMARELO" "$idxs" "$url" "${n_hist} já baixados antes"
    fi
    PERM+=("$LINHA")
  fi

  if (( n_done == 0 && n_hist == 0 && rc == 0 )); then
    titulo=${TITULO[$idx]:-$url}
    n_ja=$(cat "${logs[@]}" 2>/dev/null | grep -ac 'has already been downloaded')
    if (( n_ja > 0 )); then
      N_JA=$(( N_JA + 1 ))
      linha_resultado "↷" "$AMARELO" "$idxs" "$titulo" "já existia"
    else
      N_OK=$(( N_OK + 1 ))
      linha_resultado "✔" "$VERDE" "$idxs" "$titulo" "concluído"
    fi
    PERM+=("$LINHA")
  fi

  if (( rc != 0 )); then
    analisa_log "$TMP/$idx.log"
    if (( N_FATAIS == 0 && N_COSMETICOS > 0 && n_done > 0 )); then
      # Tudo foi entregue; só um acabamento falhou. Aviso, não falha.
      case $AVISO_CTX in
        "[ThumbnailsConvertor]"*) det="a capa não converteu para JPG e foi embutida no formato original" ;;
        "[SponsorBlock]"*)        det="não deu para consultar o SponsorBlock" ;;
        *)                        det="uma etapa de acabamento falhou (detalhes no log)" ;;
      esac
      corta "$det — o vídeo está completo" $(( COLS - 20 ))
      PERM+=("         ${AMARELO}↳ aviso:${R}${DIM} ${FMT}${R}")
      N_AVISOS=$(( N_AVISOS + 1 ))
      salva_log "$idx"
      rc=0
    fi
  fi

  if (( rc != 0 )); then
    classifica_erro "$MOTIVO"
    MOTIVO=$(sed -E 's/^ERROR: //; s/^\[[^]]+\] //; s/^[^ :]+: //; s/ \(caused by .*$//; s/; please report this issue.*$//' <<<"$MOTIVO")
    if (( n_done > 0 || n_hist > 0 )); then
      linha_resultado "⚠" "$AMARELO" "$idxs" "${TITULO[$idx]:-$url}" "parcial"
    elif (( tent > 1 )); then
      linha_resultado "✖" "$VERMELHO" "$idxs" "${TITULO[$idx]:-$url}" "falhou ${tent}×"
    else
      linha_resultado "✖" "$VERMELHO" "$idxs" "${TITULO[$idx]:-$url}" "falhou"
    fi
    if [[ -n $DICA ]]; then                     # "↳ dica em português · mensagem original"
      corta "$MOTIVO" $(( COLS - 15 - ${#DICA} ))
      det="${VERMELHO}↳ ${DICA}${R}"
      (( LARG >= 10 )) && det+="${DIM} · ${FMT}${R}"
    else
      corta "${MOTIVO:-yt-dlp terminou com código $rc}" $(( COLS - 12 ))
      det="${VERMELHO}↳ ${FMT}${R}"
    fi
    PERM+=("$LINHA" "         $det")
    FALHAS+=("$url")
    N_ERRO=$(( N_ERRO + 1 ))
    salva_log "$idx"
  fi

  FEITO[$idx]=1
  FINALIZADOS=$(( FINALIZADOS + 1 ))
}

# ───────────────────────────── Execução dos jobs ──────────────────────────────
lanca_job() {                                 # lanca_job IDX
  local i=$1 url=${LINKS[$(( $1 - 1 ))]} tent=${TENTATIVA[$1]:-1} extra=() idxs
  # Só a nova tentativa força a imitação de navegador: o próprio yt-dlp avisa que
  # forçá-la sempre pode deixar os downloads mais lentos e instáveis.
  (( tent > 1 )) && [[ -n $IMPERSONATE ]] && extra=(--impersonate "$IMPERSONATE")
  # O arquivo da tentativa anterior veio corrompido: sem isso o yt-dlp o reaproveitaria
  # ("has already been downloaded") e falharia igual. Itens já concluídos estão no
  # histórico e continuam sendo pulados.
  (( ${REBAIXAR[$i]:-0} )) && extra+=(--force-overwrites)
  yt-dlp "${YTDLP_ARGS[@]}" "${extra[@]}" -- "$url" </dev/null >"$TMP/$i.log" 2>&1 &
  ULTIMO_PID=$!
  if (( ! INTERATIVO )); then                  # sem painel (saída redirecionada): avisa o início
    printf -v idxs "%0${#TOTAL}d/%d" "$i" "$TOTAL"
    if (( tent > 1 )); then PERM+=("  ↻ ${idxs}  ${url}  (${tent}ª tentativa)"); else PERM+=("  ▶ ${idxs}  ${url}"); fi
  fi
}

# vale_repetir IDX: falhou por algo passageiro e ainda há tentativas? Se sim,
# guarda o log desta tentativa e põe o link no fim da fila.
vale_repetir() {
  local idx=$1 tent=${TENTATIVA[$1]:-1}
  (( tent < TENTATIVAS )) || return 1
  analisa_log "$TMP/$idx.log"
  (( N_FATAIS == 0 && N_COSMETICOS > 0 )) && return 1   # o vídeo saiu inteiro: repetir não muda nada
  classifica_erro "$MOTIVO"
  (( REPETE )) || return 1
  (( ARQUIVO_RUIM )) && REBAIXAR[$idx]=1
  mv -f "$TMP/$idx.log" "$TMP/$idx.t$tent.log"
  (( tent == 1 )) && EM_REPETICAO=$(( EM_REPETICAO + 1 ))
  TENTATIVA[$idx]=$(( tent + 1 ))
  REPETIR+=("$idx")
}

mata_arvore() {                               # mata o processo e seus filhos (ffmpeg…)
  local pid=$1 filho
  if command -v pgrep >/dev/null 2>&1; then
    for filho in $(pgrep -P "$pid" 2>/dev/null); do mata_arvore "$filho"; done
  fi
  kill -TERM "$pid" 2>/dev/null
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
  local lista=("${FALHAS[@]}") i n_pend=0 f era_falhas=0 o_que="com erro"
  if (( CANCELADO )); then
    for (( i = 1; i <= TOTAL; i++ )); do
      [[ -n ${FEITO[$i]:-} ]] && continue
      lista+=("${LINKS[$(( i - 1 ))]}"); n_pend=$(( n_pend + 1 ))
    done
  fi
  for f in "${ARQUIVOS_ENTRADA[@]}"; do [[ $f -ef $ARQUIVO_FALHAS ]] && era_falhas=1; done

  if (( ${#lista[@]} == 0 )); then
    # tudo certo: se a lista de entrada era o próprio arquivo de falhas, ele cumpriu o papel
    if (( era_falhas )) && rm -f -- "$ARQUIVO_FALHAS"; then
      printf '\n  %s✔%s  Todos os links de %s deram certo — arquivo removido.\n' "$VERDE" "$R" "$ARQUIVO_FALHAS"
    fi
    return 0
  fi
  if ! printf '%s\n' "${lista[@]}" > "$ARQUIVO_FALHAS"; then
    erro "Não consegui gravar '$ARQUIVO_FALHAS'."
    return 0
  fi
  (( n_pend > 0 && N_ERRO > 0 )) && o_que="com erro ou pendentes"
  (( n_pend > 0 && N_ERRO == 0 )) && o_que="pendentes"
  printf '\n  %s⚠%s  %d link(s) %s salvos em %s%s%s' "$AMARELO" "$R" "${#lista[@]}" "$o_que" "$NEG" "$ARQUIVO_FALHAS" "$R"
  if (( N_ERRO > 0 )); then printf ' — logs em %s/\n' "$LOG_DIR"; else printf '\n'; fi
  comando_repetir
  printf '     Para continuar:  %s%s%s\n' "$CIANO" "$FMT" "$R"
}

resumo() {
  (( INTERATIVO )) && printf '%s' "${ESC}[?7h"     # religa a quebra de linha para o texto final
  local t b media="" titulo_r="Resumo"
  fmt_tempo "$SECONDS"; t=$FMT
  fmt_bytes "$BYTES_NOVOS"; b=$FMT
  if (( BYTES_NOVOS > 0 && SECONDS > 0 )); then
    fmt_bytes $(( BYTES_NOVOS / SECONDS )); media="  ${DIM}(média de ${FMT}/s)${R}"
  fi
  (( CANCELADO )) && titulo_r="Resumo parcial"
  printf '\n  %s── %s ─────────────────────────────────────%s\n' "$DIM" "$titulo_r" "$R"
  printf '  %s✔%s  Baixados          %s%s%s\n'  "$VERDE"    "$R" "$NEG" "$N_OK"  "$R"
  printf '  %s↷%s  Já existiam       %s%s%s\n'   "$AMARELO"  "$R" "$NEG" "$N_JA"  "$R"
  printf '  %s✖%s  Links com erro    %s%s%s\n'   "$VERMELHO" "$R" "$NEG" "$N_ERRO" "$R"
  if (( N_AVISOS > 0 )); then
    printf '  %s⚠%s  Com aviso         %s%s%s  %s(arquivos completos · logs em %s/)%s\n' \
      "$AMARELO" "$R" "$NEG" "$N_AVISOS" "$R" "$DIM" "$LOG_DIR" "$R"
  fi
  printf '  %s◷%s  Tempo             %s\n'       "$DIM" "$R" "$t"
  printf '  %s▣%s  Baixado agora     %s%s\n'     "$DIM" "$R" "$b" "$media"
  printf '  %s▸%s  Pasta             %s\n'       "$DIM" "$R" "$PASTA_SAIDA"
  salva_falhas
  printf '\n'
}

limpa() {                                     # trap EXIT: sempre devolve o terminal limpo
  local rc=$?
  trap - EXIT INT TERM HUP WINCH
  mata_jobs
  descarta_parciais
  if (( CANCELADO && COMECOU )); then
    desenha final
    printf '\n  %s⚠ Cancelado.%s O que estava pela metade foi descartado e recomeça do zero na próxima vez.\n' \
      "$AMARELO" "$R"
    resumo
  elif (( CANCELADO )); then
    printf '\n  %s⚠ Cancelado.%s\n\n' "$AMARELO" "$R"
  fi
  if (( INTERATIVO )); then
    printf '%s' "${ESC}[?7h${ESC}[?25h"
    (( TITULO_EMPILHADO )) && printf '%s' "${ESC}[23;0t"     # devolve o título original da janela
    [[ -n $STTY_SAVE ]] && stty "$STTY_SAVE" 2>/dev/null
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
  local t="GrabIt  ·  Downloader em lote  ·  Máxima qualidade (MKV)" w h
  w=$(( ${#t} + 4 ))
  if (( COLS < w + 4 )); then                   # terminal estreito: título simples, sem moldura
    printf '\n  %sGrabIt · Downloader em lote%s\n\n' "$NEG" "$R"
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
    *)      FMT="instale '$1' pelo gerenciador de pacotes do sistema" ;;
  esac
}

verifica_dependencias() {
  local faltando=() par bin nome p1 p2 p3
  command -v yt-dlp >/dev/null 2>&1 || faltando+=("yt-dlp")
  command -v ffmpeg >/dev/null 2>&1 || faltando+=("ffmpeg")
  if (( ${#faltando[@]} )); then
    erro "Faltando: ${faltando[*]}"
    comando_instalar ffmpeg
    printf '\n     %syt-dlp%s  →  pipx install "yt-dlp[default,curl-cffi]"\n' "$CIANO" "$R"
    printf '     %sffmpeg%s  →  %s\n\n' "$CIANO" "$R" "$FMT"
    exit 1
  fi
  # cada consulta ao yt-dlp leva quase 1 s (é Python): roda as três em paralelo
  yt-dlp --version                  >"$TMP/versao" 2>/dev/null & p1=$!
  yt-dlp --help                     >"$TMP/ajuda"  2>/dev/null & p2=$!
  yt-dlp --list-impersonate-targets >"$TMP/alvos"  2>/dev/null & p3=$!
  FFMPEG_VER=$(ffmpeg -version 2>/dev/null | awk 'NR==1{print $3}')
  wait "$p1" "$p2" "$p3"
  YTDLP_VER=$(head -n 1 "$TMP/versao")
  grep -q -- '--js-runtimes' "$TMP/ajuda" && TEM_JS_RUNTIMES=1

  # --impersonate só funciona com curl_cffi instalado; senão o yt-dlp aborta
  if grep -i '^[[:space:]]*chrome' "$TMP/alvos" | grep -viq 'unavailable'; then
    IMPERSONATE="chrome"
  fi

  # YouTube precisa de um runtime JavaScript externo. O yt-dlp só liga o Deno
  # sozinho; node/quickjs/bun precisam de --js-runtimes (feito em monta_args_ytdlp).
  JS_RUNTIME=""; JS_PATH=""
  for par in deno:deno node:node node:nodejs quickjs:qjs quickjs:quickjs bun:bun; do
    nome=${par%%:*}; bin=${par#*:}
    if JS_PATH=$(command -v "$bin" 2>/dev/null) && [[ -n $JS_PATH ]]; then
      JS_RUNTIME=$nome
      break
    fi
    JS_PATH=""
  done
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

# Junta os links do arquivo (-l), dos argumentos e dos arquivos passados como argumento.
ler_links() {
  local bruto=() fontes=() a linha palavra palavras=() achou soltos=0
  local -A visto=()
  if (( ${#ARGS_LINKS[@]} == 0 || LISTA_EXPLICITA )); then
    if [[ $ARQUIVO_LINKS == - ]]; then
      mapfile -t bruto; fontes+=("entrada padrão")
    elif [[ -f $ARQUIVO_LINKS && -r $ARQUIVO_LINKS ]]; then
      mapfile -t bruto < "$ARQUIVO_LINKS"; fontes+=("$ARQUIVO_LINKS"); ARQUIVOS_ENTRADA+=("$ARQUIVO_LINKS")
    else
      erro "O arquivo '$ARQUIVO_LINKS' não foi encontrado."
      printf '     Crie-o com um link por linha, use  -l CAMINHO  ou passe os links no próprio comando.\n\n'
      exit 1
    fi
  fi
  for a in "${ARGS_LINKS[@]}"; do
    if [[ -f $a ]]; then
      mapfile -t -O "${#bruto[@]}" bruto < "$a"; fontes+=("$a"); ARQUIVOS_ENTRADA+=("$a")
    else
      bruto+=("$a"); soltos=1
    fi
  done
  (( soltos )) && fontes+=("linha de comando")

  for linha in "${bruto[@]}"; do
    linha=${linha#$'﻿'}                  # BOM do Bloco de Notas do Windows
    IFS=$' \t\r' read -ra palavras <<<"$linha"
    (( ${#palavras[@]} )) || continue
    [[ ${palavras[0]} == \#* ]] && continue
    achou=0
    for palavra in "${palavras[@]}"; do
      [[ $palavra == \#* ]] && break          # comentário no fim da linha
      [[ $palavra == www.* ]] && palavra="https://$palavra"
      [[ $palavra =~ ^https?:// ]] || continue
      achou=1
      if [[ -n ${visto[$palavra]:-} ]]; then DUPLICADOS=$(( DUPLICADOS + 1 ))
      else visto[$palavra]=1; LINKS+=("$palavra"); fi
    done
    (( achou )) || INVALIDAS=$(( INVALIDAS + 1 ))
  done
  TOTAL=${#LINKS[@]}
  FONTE_LINKS=$(IFS=,; printf '%s' "${fontes[*]}"); FONTE_LINKS=${FONTE_LINKS//,/, }
  if (( TOTAL == 0 )); then
    erro "Nenhum link válido (http/https) em: ${FONTE_LINKS:-nada}."
    exit 1
  fi
}

monta_args_ytdlp() {
  local langs=$IDIOMAS_LEGENDAS
  # "all" incluiria o chat ao vivo: um JSON enorme que nem dá para embutir
  [[ ,$langs, == *,all,* && $langs != *live_chat* ]] && langs+=",-live_chat"
  YTDLP_ARGS=(
    --ignore-config --color never --newline --no-quiet --no-simulate --progress
    --progress-delta 0.5

    # Linhas "máquina" lidas pelo painel (ficam só no log, nunca no terminal)
    --progress-template "download:@@P@@%(progress.downloaded_bytes|0)s${SEP}%(progress.total_bytes,progress.total_bytes_estimate|0)s${SEP}%(progress.speed|0)s${SEP}%(progress.eta|0)s${SEP}%(info.playlist_index|)s${SEP}%(info.n_entries|)s${SEP}%(info.vcodec|?)s${SEP}%(info.height|)s${SEP}%(info.fps|)s${SEP}%(info.ext|)s${SEP}%(info.title|?)s"
    --print "after_move:@@D@@%(height|0)s${SEP}%(fps|0)s${SEP}%(dynamic_range|SDR)s${SEP}%(vcodec|?)s${SEP}%(acodec|?)s${SEP}%(duration|0)s${SEP}%(title|?)s${SEP}%(id)s${SEP}%(filepath)s"

    # Destino: os temporários ficam em .parciais/<esta execução> e só o arquivo final
    # vai para a pasta
    -P "$PASTA_SAIDA" -P "temp:$TEMP_REL" -o "$TEMPLATE_SAIDA"

    # Qualidade máxima: melhor vídeo + melhor áudio, empacotados em MKV
    -f 'bv*+ba/b' --merge-output-format mkv --remux-video mkv

    # Tudo o que o yt-dlp encontrar vai para dentro do arquivo
    --embed-metadata --embed-chapters --embed-info-json
    # Capa em JPG (a mais compatível), menos AVIF: para converter, o yt-dlp força o
    # leitor "image2" do ffmpeg, que não abre AVIF — ela é embutida como veio.
    --embed-thumbnail --convert-thumbnails 'webp>jpg/png>jpg/gif>jpg/bmp>jpg'
    --embed-subs --sub-langs "$langs"

    # Velocidade e resiliência (com espera crescente entre as repetições)
    -N "$CONEXOES_POR_VIDEO"
    --retries 10 --fragment-retries 10 --extractor-retries 3
    --retry-sleep exp=1:30 --retry-sleep fragment:exp=1:30
    # Qualidade garantida: nunca pula um fragmento que falhou (por padrão o yt-dlp pula
    # em silêncio e entrega o vídeo com um salto) e nunca retoma pedaços de um download
    # interrompido (a retomada pode deixar buracos); nesses casos, recomeça do zero.
    --abort-on-unavailable-fragments --no-continue
    --socket-timeout 30 --throttled-rate 100K
  )
  # Com --write-auto-subs o yt-dlp para de pedir as legendas manuais sozinho:
  # pede as duas (a manual tem prioridade) e apaga os .vtt depois de embutir.
  (( LEGENDAS_AUTOMATICAS )) && YTDLP_ARGS+=(--write-subs --write-auto-subs --compat-options no-keep-subs)
  (( SPONSORBLOCK ))         && YTDLP_ARGS+=(--sponsorblock-mark all)
  (( SEM_PLAYLIST ))         && YTDLP_ARGS+=(--no-playlist)
  # Histórico: o que já foi baixado é pulado antes de tudo (na maioria dos sites,
  # sem nem acessar a página). Sem ele, o yt-dlp reextrai o vídeo, baixa a capa de
  # novo e reescreve o arquivo inteiro só para dizer que ele já existe.
  (( USAR_HISTORICO ))       && YTDLP_ARGS+=(--download-archive "$ARQUIVO_HISTORICO")
  [[ -n $COOKIES_NAVEGADOR ]] && YTDLP_ARGS+=(--cookies-from-browser "$COOKIES_NAVEGADOR")
  (( TEM_JS_RUNTIMES ))       && [[ -n $JS_RUNTIME ]] && YTDLP_ARGS+=(--js-runtimes "$JS_RUNTIME:$JS_PATH")
  return 0
}

# ───────────────────────────── Principal ──────────────────────────────────────
trap 'CANCELADO=1; SINAL=INT;  exit 130' INT
trap 'CANCELADO=1; SINAL=TERM; exit 143' TERM
trap 'CANCELADO=1; SINAL=HUP;  exit 129' HUP
trap limpa EXIT

atualiza_largura
cabecalho
TMP=$(mktemp -d "${TMPDIR:-/tmp}/grabit.XXXXXX") || { erro "Não consegui criar a pasta temporária."; exit 1; }
verifica_dependencias
ler_links

mkdir -p "$PASTA_SAIDA" || { erro "Não consegui criar a pasta '$PASTA_SAIDA'."; exit 1; }
printf -v LOG_DIR '%s/logs/%(%Y-%m-%d_%H%M%S)T' "$PASTA_SAIDA" -1
prepara_parciais

J=$DOWNLOADS_SIMULTANEOS
(( J > TOTAL )) && J=$TOTAL
LIMITE_J=0
if (( INTERATIVO )); then                       # o painel (2 linhas por vídeo + 2) precisa caber na tela
  linhas=$(tput lines 2>/dev/null); [[ $linhas =~ ^[0-9]+$ ]] || linhas=24
  max_j=$(( (linhas - 3) / 2 )); (( max_j < 1 )) && max_j=1
  if (( J > max_j )); then LIMITE_J=$J; J=$max_j; fi
fi
for (( s = 0; s < J; s++ )); do SLOT_IDX[$s]=0; SLOT_PID[$s]=0; done
monta_args_ytdlp

extras=""
(( DUPLICADOS > 0 )) && extras+=" ${DUPLICADOS} repetido(s)"
(( INVALIDAS  > 0 )) && extras+="${extras:+,} ${INVALIDAS} linha(s) sem link"
[[ -n $extras ]] && extras=" · ignorados:${extras}"
txt_extras="legendas ${IDIOMAS_LEGENDAS}"
(( LEGENDAS_AUTOMATICAS )) && txt_extras+=" (+automáticas)"
txt_extras+=", capa, capítulos, metadados"
(( SPONSORBLOCK )) && txt_extras+=", SponsorBlock"
if [[ -z $IMPERSONATE ]]; then txt_imp="${AMARELO}indisponível${R}"
elif (( TENTATIVAS > 1 )); then txt_imp="nas novas tentativas"
else txt_imp="desligado (TENTATIVAS=1)"; fi

kv "Links"    "${NEG}${TOTAL}${R}${DIM} · ${FONTE_LINKS}${extras}${R}"
kv "Destino"  "$PASTA_SAIDA"
if (( USAR_HISTORICO )); then
  n_registrados=$(grep -c '' "$ARQUIVO_HISTORICO" 2>/dev/null) || n_registrados=0
  kv "Histórico" "${n_registrados} vídeo(s) registrados · os já baixados são pulados"
else
  kv "Histórico" "${AMARELO}ignorado (-i)${R}: confere arquivo por arquivo"
fi
txt_paralelo="${J} vídeo(s) × ${CONEXOES_POR_VIDEO} conexões"
(( TENTATIVAS > 1 )) && txt_paralelo+=" · até ${TENTATIVAS} tentativas"
kv "Paralelo" "$txt_paralelo"
kv "Extras"   "$txt_extras"
FFMPEG_VER=${FFMPEG_VER:-?}
kv "Ferramentas" "yt-dlp ${YTDLP_VER:-?} · ffmpeg ${FFMPEG_VER%%-*}"
kv "Recursos"    "impersonate: ${txt_imp} · js: ${JS_RUNTIME:-${AMARELO}nenhum${R}}"
printf '\n'
if (( LIMITE_J > 0 )); then
  aviso "Terminal com só ${linhas} linhas: limitei a ${J} download(s) simultâneo(s)."
  printf '     (pedido: %d — aumente a janela para ver todos no painel)\n' "$LIMITE_J"
fi
idade_ytdlp
if (( NUM >= 3 )) || (( ! TEM_JS_RUNTIMES )); then
  aviso "Seu yt-dlp (${YTDLP_VER:-?}) está desatualizado: os sites mudam o tempo todo."
  printf '     Atualize:  %syt-dlp -U%s   (ou:  %spipx upgrade yt-dlp%s)\n' "$CIANO" "$R" "$CIANO" "$R"
fi
if [[ -z $IMPERSONATE ]]; then
  aviso "curl_cffi ausente: sites com proteção anti-robô podem falhar."
  printf '     Instale com:  %spipx inject yt-dlp curl-cffi%s\n' "$CIANO" "$R"
fi
if [[ -z $JS_RUNTIME ]]; then
  aviso "Sem runtime JavaScript: o YouTube pode falhar ou vir em qualidade menor."
  printf '     Instale o Deno (https://deno.com) e mantenha o yt-dlp atualizado.\n'
fi
printf '  %sCtrl+C cancela · o que estiver pela metade recomeça do zero%s\n\n' "$DIM" "$R"

# Redimensionou a janela? O painel se ajusta no próximo quadro. (O trap só entra
# agora: antes ele interromperia o "wait" das consultas ao yt-dlp.)
REDIM=1
trap 'REDIM=1' WINCH
COMECOU=1
SECONDS=0
if (( INTERATIVO )); then
  printf '%s' "${ESC}[?25l${ESC}[?7l${ESC}[22;0t"   # esconde o cursor, desliga a quebra de linha, guarda o título
  TITULO_EMPILHADO=1
  if [[ -t 0 ]]; then
    STTY_SAVE=$(stty -g 2>/dev/null) && stty -echo 2>/dev/null
  fi
fi

while (( FINALIZADOS < TOTAL )); do
  atualiza_largura

  # 1) recolhe quem terminou (e devolve à fila quem merece outra tentativa)
  for (( s = 0; s < J; s++ )); do
    idx=${SLOT_IDX[$s]}
    (( idx > 0 )) || continue
    kill -0 "${SLOT_PID[$s]}" 2>/dev/null && continue
    wait "${SLOT_PID[$s]}" 2>/dev/null; rc=$?
    SLOT_IDX[$s]=0
    if (( rc != 0 )) && vale_repetir "$idx"; then continue; fi
    (( ${TENTATIVA[$idx]:-1} > 1 )) && EM_REPETICAO=$(( EM_REPETICAO - 1 ))
    processa_resultado "$idx" "$rc"
  done

  # 2) ocupa os slots livres: primeiro os links novos, depois as novas tentativas
  for (( s = 0; s < J; s++ )); do
    (( SLOT_IDX[$s] == 0 )) || continue
    if (( PROXIMO <= TOTAL )); then
      idx=$PROXIMO; PROXIMO=$(( PROXIMO + 1 ))
    elif (( ${#REPETIR[@]} )); then
      idx=${REPETIR[0]}; REPETIR=("${REPETIR[@]:1}")
    else
      break
    fi
    lanca_job "$idx"
    SLOT_IDX[$s]=$idx
    SLOT_PID[$s]=$ULTIMO_PID
  done

  desenha
  sleep 0.2
done

desenha final
descarta_parciais
resumo
(( N_ERRO > 0 )) && exit 1
exit 0
