#!/usr/bin/env bash
# ==============================================================================
#  Testes do GrabIt
#
#    bash testes/rodar.sh            todos os testes
#    bash testes/rodar.sh --rapido   só os que não baixam nada (sem yt-dlp nem ffmpeg)
#
#  Os testes completos sobem um servidor HTTP local (python3) com vídeos gerados
#  pelo ffmpeg e rodam o GrabIt de verdade contra ele: nada sai da máquina.
# ==============================================================================
set -uo pipefail

RAIZ=$(cd -- "$(dirname -- "$0")/.." && pwd)
G="$RAIZ/grabit.sh"
RAPIDO=0
[[ ${1:-} == --rapido ]] && RAPIDO=1

TMP=$(mktemp -d "${TMPDIR:-/tmp}/grabit-testes.XXXXXX") || exit 1
SRV=0
trap '(( SRV )) && kill "$SRV" 2>/dev/null; rm -rf -- "$TMP"' EXIT
export GRABIT_CONFIG="$TMP/sem-config/grabit.config"   # pasta inexistente: nenhum config criado
export NO_COLOR=1 NOTIFICAR=0
unset IDIOMA DOWNLOADS_SIMULTANEOS RESOLUCAO_MAXIMA LIMITE_POR_SITE PAUSA_ENTRE_VIDEOS NTFY_TOPICO

N_OK=0; FALHAS=()
espera() {                                    # espera DESCRIÇÃO COMANDO... (passa se o comando der certo)
  if "${@:2}" >/dev/null 2>&1; then
    printf '  ✔ %s\n' "$1"; N_OK=$(( N_OK + 1 ))
  else
    printf '  ✖ %s\n' "$1"; FALHAS+=("$1")
  fi
}
contem() { grep -qF -- "$2" "$1"; }           # contem ARQUIVO TEXTO
nao_contem() { ! grep -qF -- "$2" "$1"; }
codigo() { [[ $1 == "$2" ]]; }                # codigo OBTIDO ESPERADO
roda() {                                      # roda SAÍDA [ARGS...] → RC (a saída vai para o arquivo)
  local saida=$1
  shift
  bash "$G" "$@" >"$saida" 2>&1
  RC=$?
}
secao() { printf '\n%s\n' "$1"; }

# ───────────────────────────── Rápidos ─────────────────────────────────────────
secao "Sintaxe e ajuda"
espera "bash -n" bash -n "$G"
roda "$TMP/ajuda" -L pt -h
espera "ajuda em português" contem "$TMP/ajuda" "Uso:  grabit"
roda "$TMP/ajuda_en" -L en --help
espera "ajuda em inglês" contem "$TMP/ajuda_en" "Usage:  grabit"
roda "$TMP/ajuda_lang" -sLen -h
espera "-L junto de outras opções (-sLen)" contem "$TMP/ajuda_lang" "Usage:  grabit"

secao "Opções inválidas"
roda "$TMP/op" -L pt -Z
espera "opção desconhecida sai com código 2" codigo "$RC" 2
espera "…e explica o erro" contem "$TMP/op" "Opção inválida: -Z"
roda "$TMP/op_longa" -L pt --nada
espera "opção longa desconhecida sai com código 2" codigo "$RC" 2
roda "$TMP/op_valor" -L pt -j
espera "opção sem valor sai com código 2" codigo "$RC" 2
roda "$TMP/lingua" -L xx --config               # cai no idioma do sistema, que pode ser qualquer um
espera "idioma inválido vira aviso" grep -qE "Idioma desconhecido: 'xx'|Unknown language: 'xx'" "$TMP/lingua"

secao "Configuração"
mkdir -p "$TMP/cfg"
GRABIT_CONFIG="$TMP/cfg/grabit.config" roda "$TMP/cfg1" -L pt --config
espera "o grabit.config é criado na primeira execução" test -f "$TMP/cfg/grabit.config"
espera "…com os padrões comentados" contem "$TMP/cfg/grabit.config" "#DOWNLOADS_SIMULTANEOS=2"
printf 'DOWNLOADS_SIMULTANEOS=3\nRESOLUCAO_MAXIMA=4k\nCHAVE_ERRADA=1\n' >> "$TMP/cfg/grabit.config"
GRABIT_CONFIG="$TMP/cfg/grabit.config" roda "$TMP/cfg2" -L pt --config
espera "valor do arquivo é lido" grep -qE 'DOWNLOADS_SIMULTANEOS +3 +grabit.config' "$TMP/cfg2"
espera "4k vira 2160" grep -qE 'RESOLUCAO_MAXIMA +2160' "$TMP/cfg2"
espera "chave desconhecida vira aviso" contem "$TMP/cfg2" "CHAVE_ERRADA"
GRABIT_CONFIG="$TMP/cfg/grabit.config" DOWNLOADS_SIMULTANEOS=5 roda "$TMP/cfg3" -L pt --config
espera "variável de ambiente vence o arquivo" grep -qE 'DOWNLOADS_SIMULTANEOS +5 +variável de ambiente' "$TMP/cfg3"
GRABIT_CONFIG="$TMP/cfg/grabit.config" DOWNLOADS_SIMULTANEOS=5 roda "$TMP/cfg4" -L pt -j 7 --config
espera "opção do comando vence tudo" grep -qE 'DOWNLOADS_SIMULTANEOS +7 +opção do comando' "$TMP/cfg4"

secao "Validação dos valores"
DOWNLOADS_SIMULTANEOS=0 roda "$TMP/v1" -L pt --config
espera "DOWNLOADS_SIMULTANEOS=0 é recusado" codigo "$RC" 2
SPONSORBLOCK=talvez roda "$TMP/v2" -L pt --config
espera "valor 0/1 inválido é recusado" codigo "$RC" 2
RESOLUCAO_MAXIMA=alta roda "$TMP/v3" -L pt --config
espera "resolução inválida é recusada" codigo "$RC" 2
FORMATO_AUDIO=ogg roda "$TMP/v4" -L pt --config
espera "formato de áudio inválido é recusado" codigo "$RC" 2
LIMITE_VELOCIDADE=5MB roda "$TMP/v5" -L pt --config
espera "velocidade inválida é recusada" codigo "$RC" 2
LIMITE_VELOCIDADE=1.5m roda "$TMP/v6" -L pt --config
espera "velocidade 1.5m vira 1.5M" grep -qE 'LIMITE_VELOCIDADE +1\.5M' "$TMP/v6"

secao "Traduções"
# toda chave da tabela em português existe na inglesa, e vice-versa
chaves() { awk -v f="$1" '$0 ~ "^idioma_"f"\\(\\)" {d=1} d && /^}/ {exit} d' "$G" | grep -oE '^ *\[[^]]+\]=' | tr -d ' []=' | sort -u; }
chaves pt > "$TMP/chaves_pt"; chaves en > "$TMP/chaves_en"
espera "a tabela em português tem chaves" test -s "$TMP/chaves_pt"
espera "as tabelas pt e en têm as mesmas chaves" diff "$TMP/chaves_pt" "$TMP/chaves_en"

if (( RAPIDO )); then
  printf '\n%d ok, %d falha(s)\n' "$N_OK" "${#FALHAS[@]}"
  (( ${#FALHAS[@]} == 0 ))
  exit
fi

# ───────────────────────────── Completos ───────────────────────────────────────
for p in yt-dlp ffmpeg ffprobe python3; do
  command -v "$p" >/dev/null 2>&1 || { printf '\nFalta %s para os testes completos (use --rapido).\n' "$p"; exit 1; }
done

secao "Preparando os vídeos de teste"
W="$TMP/www"; mkdir -p "$W/res" "$W/pagina"
video() {                                     # video ARQUIVO LxA SEGUNDOS
  ffmpeg -loglevel error -y -f lavfi -i "testsrc2=size=$2:rate=30:duration=$3" \
    -f lavfi -i "sine=frequency=440:duration=$3" -c:v libx264 -preset ultrafast -b:v 1500k \
    -c:a aac -b:a 64k -shortest "$1"
}
hls() {                                       # hls NOME LxA (uma variante de 2 s)
  ffmpeg -loglevel error -y -f lavfi -i "testsrc2=size=$2:rate=30:duration=2" \
    -f lavfi -i "sine=duration=2" -c:v libx264 -preset ultrafast -c:a aac -shortest \
    -hls_time 2 -hls_playlist_type vod -hls_segment_filename "$W/res/${1}_%d.ts" "$W/res/$1.m3u8"
}
video "$W/curto.mp4" 640x360 2
video "$W/longo.mp4" 640x360 4
cp "$W/curto.mp4" "$W/pagina/previa.mp4"; cp "$W/longo.mp4" "$W/pagina/principal.mp4"
cp "$W/curto.mp4" "$W/ruim.mp4"
python3 - "$W/ruim.mp4" <<'EOF'
import random, sys
f = open(sys.argv[1], 'r+b'); t = f.seek(0, 2); r = random.Random(42)
for off in range(t // 3, t // 3 + 60000, 3000):   # estraga pedaços do meio, sempre iguais
    f.seek(off); f.write(bytes(r.randrange(256) for _ in range(200)))
EOF
hls p360 640x360; hls p720 1280x720
printf '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=400000,RESOLUTION=640x360\np360.m3u8\n#EXT-X-STREAM-INF:BANDWIDTH=900000,RESOLUTION=1280x720\np720.m3u8\n' > "$W/res/mestre.m3u8"
cat > "$W/pagina/index.html" <<'EOF'
<!doctype html><html><head><title>Pagina de teste</title></head><body>
<video src="previa.mp4"></video><video src="principal.mp4"></video></body></html>
EOF
PORTA=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
python3 -m http.server --bind 127.0.0.1 --directory "$W" "$PORTA" >/dev/null 2>&1 & SRV=$!
B="http://127.0.0.1:$PORTA"
for _ in 1 2 3 4 5 6 7 8 9 10; do python3 -c "import urllib.request; urllib.request.urlopen('$B/curto.mp4')" 2>/dev/null && break; sleep 0.3; done
export NO_PROXY="127.0.0.1,${NO_PROXY:-}" no_proxy="127.0.0.1,${no_proxy:-}"
altura() { ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 -- "$1"; }
um() { local f; for f in "$@"; do [[ -e $f ]] && { printf '%s' "$f"; return 0; }; done; return 1; }

secao "Download, histórico e seção BAIXADOS"
D="$TMP/d1"; mkdir -p "$D"; cd "$D" || exit 1
printf '# minha lista\n%s\n%s  # anotação\n%s\nlinha sem link\n%s\n' \
  "$B/curto.mp4" "$B/longo.mp4" "$B/nao-existe.mp4" "$B/curto.mp4" > links.txt
roda saida1 -L pt
espera "com um link quebrado, sai com código 1" codigo "$RC" 1
espera "os vídeos viram MKV" test -f "Downloads/curto [curto].mkv"
espera "…e o MKV abre no ffprobe" altura "Downloads/longo [longo].mkv"
espera "o repetido e a linha sem link são avisados" contem saida1 "1 repetido(s), 1 linha(s) sem link"
espera "o link quebrado vai para links_falhos.txt" contem links_falhos.txt "$B/nao-existe.mp4"
espera "o link quebrado continua na lista" grep -q "^$B/nao-existe.mp4$" links.txt
espera "os baixados vão para a seção BAIXADOS" contem links.txt "# ==================== BAIXADOS ===================="
espera "…anotados com data e título" grep -qE "longo.mp4  # anotação  ✔ [0-9-]{10} · longo" links.txt
espera "…e a seção termina na linha de fim" contem links.txt "# ================ FIM DOS BAIXADOS ================"
espera "o histórico registra os vídeos" contem Downloads/.grabit-historico.txt "generic curto"
espera "não sobra a pasta .parciais" test ! -e Downloads/.parciais
echo "$B/curto.mp4" >> links.txt               # depois da linha de fim: volta a contar
roda saida2 -L pt "$B/curto.mp4"
espera "o histórico pula o que já foi baixado" contem saida2 "já baixado antes"
roda saida3 -L pt -l links.txt
espera "o link acrescentado depois da seção é lido" contem saida3 "Links        2"

secao "Inglês"
D="$TMP/d2"; mkdir -p "$D"; cd "$D" || exit 1
printf '%s\n' "$B/curto.mp4" > links.txt
roda saida -L en
espera "resumo em inglês" contem saida "── Summary"
espera "seção DOWNLOADED" contem links.txt "# ==================== DOWNLOADED ===================="

secao "Resolução máxima, upgrade e alerta"
D="$TMP/d3"; mkdir -p "$D"; cd "$D" || exit 1
roda saida1 -L pt -r 360 "$B/res/mestre.m3u8"
espera "-r 360 baixa 360p" codigo "$(altura "Downloads/mestre [mestre].mkv")" 360
espera "com o limite, 360p não é \"baixa resolução\"" nao_contem saida1 "resolução baixa"
roda saida0 -L pt -o ./Baixa "$B/res/p360.m3u8"
espera "sem limite, 360p ganha o alerta de baixa resolução" contem saida0 "resolução baixa"
roda saida2 -L pt -U "$B/res/mestre.m3u8"
espera "-U troca pela versão de 720p" codigo "$(altura "Downloads/mestre [mestre].mkv")" 720
espera "…e mostra a mudança" contem saida2 "360p → 720p"
espera "…sem deixar o arquivo antigo" test -z "$(find Downloads -name '*.grabit-antigo')"
roda saida3 -L pt -U "$B/res/mestre.m3u8"
espera "-U de novo não baixa nada" contem saida3 "nenhuma versão melhor que 720p"
roda saida4 -L pt -r 240 -i "$B/res/mestre.m3u8"
espera "sem versão dentro do limite, falha com aviso" contem saida4 "nenhuma versão até 240p (-r)"

secao "Só áudio, vídeo principal, Jellyfin/Plex/Kodi e verificação"
D="$TMP/d4"; mkdir -p "$D"; cd "$D" || exit 1
roda saida1 -L pt -x -o ./Musica "$B/curto.mp4"
espera "-x guarda só o áudio" test -n "$(um Musica/*.m4a)"
espera "-x tem histórico próprio" test -f Musica/.grabit-historico-audio.txt
roda saida2 -L pt -u -o ./Pagina "$B/pagina/index.html"
espera "-u baixa só o vídeo mais longo" test "$(find Pagina -name '*.mkv' | wc -l)" -eq 1
espera "…que é o principal" contem saida2 "00:04"
roda saida3 -L pt -m -o ./Midia "$B/curto.mp4"
espera "-m cria a pasta da série e da temporada" test -n "$(find Midia -path '*/Season *' -name '*.mkv')"
espera "-m escreve o .nfo" test -n "$(find Midia -name '*.nfo' ! -name tvshow.nfo)"
espera "…e o tvshow.nfo" test -n "$(find Midia -name tvshow.nfo)"
espera "os .nfo são XML válido" python3 -c "
import glob, sys, xml.dom.minidom
fs = glob.glob('Midia/**/*.nfo', recursive=True); [xml.dom.minidom.parse(f) for f in fs]; sys.exit(0 if fs else 1)"
roda saida4 -L pt -v -o ./Verif "$B/curto.mp4" "$B/ruim.mp4"
espera "-v aprova o vídeo bom" test -f "Verif/curto [curto].mkv"
espera "-v reprova o estragado e o guarda à parte" test -n "$(find Verif -name '*.com-erros.*')"
espera "…sem pô-lo no histórico" nao_contem Verif/.grabit-historico.txt "generic ruim"

# ───────────────────────────── Resultado ───────────────────────────────────────
printf '\n%d ok, %d falha(s)\n' "$N_OK" "${#FALHAS[@]}"
(( ${#FALHAS[@]} == 0 ))
