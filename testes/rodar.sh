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
export NO_COLOR=1 NOTIFICAR=0 USAR_NAVEGADOR=0   # nenhum teste abre uma janela sem pedir
export XDG_DATA_HOME="$TMP/dados"                # nem mexe na memória de métodos de verdade
export GRABIT_ESPERA_BASE=0                      # nem espera um site "pedir calma" de verdade
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
espera "…com os padrões comentados" contem "$TMP/cfg/grabit.config" "#DOWNLOADS_SIMULTANEOS=4"
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

secao "Seção BAIXADOS (--baixados)"
L="$TMP/secao.txt"
printf '%s\n' "# lista" "https://a.exemplo/1" "" "# ==================== BAIXADOS ====================" "# desc" \
  "https://a.exemplo/2  # ✔ 2026-01-01 · Dois" "https://a.exemplo/3  # meu  ✔ 2026-01-02 · Três" \
  "# ================ FIM DOS BAIXADOS ================" > "$L"
roda "$TMP/bx1" -L pt -l "$L" --baixados
espera "lista os links da seção, numerados" grep -qE '^ +2  https://a.exemplo/3' "$TMP/bx1"
roda "$TMP/bx2" -L pt -l "$L" --baixados voltar 2
espera "voltar devolve o link à lista de cima" grep -qx 'https://a.exemplo/3  # meu' "$L"
espera "…e ele sai da seção" test "$(grep -c 'a.exemplo/3' "$L")" -eq 1
roda "$TMP/bx3" -L pt -l "$L" --baixados marcar https://a.exemplo/1
espera "marcar põe o link na seção" grep -qE '^https://a.exemplo/1  # ✔ [0-9-]{10} · marcado à mão$' "$L"
espera "…e o tira da lista de cima" test "$(grep -c 'a.exemplo/1' "$L")" -eq 1
roda "$TMP/bx4" -L pt -l "$L" --baixados voltar 7
espera "número fora da lista é recusado" codigo "$RC" 2
cp "$L" "$TMP/secao.antes"
roda "$TMP/bx5" -L pt -l "$L" --baixados limpar </dev/null
espera "limpar sem confirmação não apaga nada" cmp -s "$L" "$TMP/secao.antes"
echo s | bash "$G" -L pt -l "$L" --baixados limpar >"$TMP/bx7" 2>&1
espera "limpar confirmado esvazia a seção" nao_contem "$L" "BAIXADOS"
espera "…e guarda a cópia .bak" cmp -s "$L.bak" "$TMP/secao.antes"
cp "$TMP/secao.antes" "$L"
if { : </dev/tty; } 2>/dev/null; then          # editar precisa de um terminal (no CI não há)
  printf '#!/bin/sh\nsed -i.x "/a.exemplo\\/2/d" "$1"\n' > "$TMP/editor"; chmod +x "$TMP/editor"
  EDITOR="$TMP/editor" roda "$TMP/bx6" -L pt -l "$L" --baixados editar
  espera "editar aplica o que foi mudado no editor" test "$(grep -c 'a.exemplo/2' "$L")" -eq 0
fi

secao "Opções em qualquer posição"
roda "$TMP/pos1" -L pt --config https://a.invalid/1 -j 7 https://a.invalid/2 -x
espera "-j depois do link vale" grep -qE 'DOWNLOADS_SIMULTANEOS +7 +opção do comando' "$TMP/pos1"
espera "…e -x entre os links também" grep -qE 'SO_AUDIO +1 +opção do comando' "$TMP/pos1"
roda "$TMP/pos2" https://a.invalid/1 -L en -h
espera "-L depois do link" contem "$TMP/pos2" "Usage:  grabit"
roda "$TMP/pos3" -L pt --config -- https://a.invalid/1 -j 7
espera "depois de -- nada é opção" grep -qE 'DOWNLOADS_SIMULTANEOS +4 ' "$TMP/pos3"

secao "Til no grabit.config"
mkdir -p "$TMP/casa"
printf 'PASTA_SAIDA=~/Videos\nARQUIVO_FALHAS=~/falhas.txt\n' > "$TMP/cfg/til.config"
GRABIT_CONFIG="$TMP/cfg/til.config" HOME="$TMP/casa" roda "$TMP/til" -L pt --config
espera "~ vira a pasta pessoal, em vez de uma pasta chamada ~" contem "$TMP/til" "$TMP/casa/Videos"
espera "…também em ARQUIVO_FALHAS" contem "$TMP/til" "$TMP/casa/falhas.txt"

# ───── yt-dlp de mentira: sem rede nem ffmpeg, mas passando pelo GrabIt inteiro ───────────
unset WAYLAND_DISPLAY DISPLAY
STUB="$TMP/stub"; mkdir -p "$STUB" "$TMP/sem" "$TMP/com"
export STUB_LOG="$TMP/stub.log" CLIP_ARQ="$TMP/clip" CLIP_LIDO="$TMP/clip.lido"
cat > "$STUB/yt-dlp" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$STUB_LOG"
case " $* " in
  *" --version "*) echo "${STUB_VER:-2099.01.01}"; exit 0 ;;
  *" --list-impersonate-targets "*) echo "Chrome-133  Macos-15  curl_cffi"; exit 0 ;;
  *" -v "*) echo "[debug] JS runtimes: ${STUB_JS:-none}"; exit 2 ;;
  *" -U "*) echo "yt-dlp is up to date"; exit 0 ;;
esac
[ -n "${STUB_AVISO:-}" ] && echo "WARNING: $STUB_AVISO"
case " $* " in *" --referer "*)                                                       # o 2º degrau da cascata
  [ -z "${STUB_ERRO2:-}" ] || STUB_ERRO=$STUB_ERRO2
  [ -z "${STUB_SO_SEM_REFERER:-}" ] || STUB_ERRO="" ;;
esac
case " $* " in *" -- https://video.n.invalid/"*) STUB_ERRO="" ;; esac                 # o vídeo achado pelo navegador
if [ -n "${STUB_429_UMA:-}" ] && [ ! -e "$STUB_429_UMA" ]; then                       # pede calma uma vez só
  case " $* " in *" -- http://c1.invalid/"*) : > "$STUB_429_UMA"; echo "ERROR: HTTP Error 429: Too Many Requests"; exit 1 ;; esac
fi
if [ -n "${STUB_DORME:-}" ]; then                                                     # um download que demora
  case "$*" in *"${STUB_DORME_SO:-}"*)
    [ -z "${STUB_PROGRESSO:-}" ] || echo "@@P@@1"
    printf 'ini\n' >> "$STUB_CONC"; sleep "$STUB_DORME"; printf 'fim\n' >> "$STUB_CONC" ;;
  esac
fi
case "$*" in *--downloader*)                                                          # o aria2c, por conta do teste
  [ -z "${STUB_RECUSA:-}" ] || echo "[grabit] recusou 429"
  if [ -n "${STUB_LENTO:-}" ]; then printf '[grabit] lento\nERROR: aria2c exited with code 7\n'; exit 1; fi
  if [ -n "${STUB_ARIA_FALHA:-}" ]; then echo "ERROR: aria2c exited with code 1"; exit 1; fi ;;
esac
[ -z "${STUB_D:-}" ] || printf '%s\n' "$STUB_D"                                       # o resultado, se o teste quiser um
[ -z "${STUB_ERRO:-}" ] && exit 0
echo "ERROR: $STUB_ERRO"; exit 1
EOF
printf '#!/bin/sh\necho "ffmpeg version 9.9"\n' > "$STUB/ffmpeg"
printf '#!/bin/sh\nexit 1\n' > "$STUB/ffprobe"
cat > "$STUB/curl" <<'EOF'
#!/bin/sh
case "$*" in
  *deno.land*) [ -z "${STUB_CURL_FALHA:-}" ] || exit 22
    cat <<'DENO'
mkdir -p "$HOME/.deno/bin"
printf '#!/bin/sh\nprintf "deno %%s\\n" "$*" >> "$STUB_LOG"\n' > "$HOME/.deno/bin/deno"
chmod +x "$HOME/.deno/bin/deno"
DENO
    ;;
  *) exit 1 ;;
esac
EOF
cat > "$STUB/pipx" <<'EOF'
#!/bin/sh
printf 'pipx %s\n' "$*" >> "$STUB_LOG"
case "$*" in
  "list --short") [ -z "${STUB_SPEC:-}" ] || echo "yt-dlp 2099.01.01"; exit 0 ;;
  "list --json") printf '{\n  "venvs": {\n    "yt-dlp": {\n      "metadata": {\n        "main_package": {\n          "package_or_url": "%s",\n        }\n      }\n    }\n  }\n}\n' "$STUB_SPEC"; exit 0 ;;
esac
[ -n "${STUB_SPEC:-}" ]
EOF
# gerenciadores de mentira, um em cada pasta: nenhum teste chega perto do sistema de verdade
GBREW="$TMP/gbrew"; GAPT="$TMP/gapt"; mkdir -p "$GBREW" "$GAPT" "$TMP/bun"
cat > "$GBREW/brew" <<'EOF'
#!/bin/sh
printf 'brew %s\n' "$*" >> "$STUB_LOG"
[ "$1" = outdated ] && [ -n "${STUB_VELHO:-}" ] && echo "$STUB_VELHO"
exit 0
EOF
printf '#!/bin/sh\nexit 0\n' > "$GAPT/apt"
printf '#!/bin/sh\nexit 0\n' > "$GAPT/apt-cache"                 # nenhum pacote a mais nos repositórios
cat > "$GAPT/apt-get" <<'EOF'
#!/bin/sh
printf 'apt-get %s\n' "$*" >> "$STUB_LOG"
case "$*" in
  "-s --only-upgrade install "*) [ -z "${STUB_VELHO:-}" ] || echo "Inst $STUB_VELHO [1] (2 stub)" ;;
esac
exit 0
EOF
cat > "$GAPT/sudo" <<'EOF'
#!/bin/sh
if [ "$1" = -n ]; then [ -z "${STUB_SENHA:-}" ]; exit; fi
exec "$@"
EOF
printf '#!/bin/sh\nexit 0\n' > "$TMP/bun/bun"
chmod +x "$GBREW"/* "$GAPT"/* "$TMP/bun/bun"
printf '#!/bin/sh\nexit 0\n' > "$STUB/node"
printf '#!/bin/sh\necho "fs 1K used free %%"\necho "x 1 1 ${STUB_DF:-99999999} 1%% /"\n' > "$STUB/df"
printf '#!/bin/sh\ncat "$CLIP_ARQ"\ntouch "$CLIP_LIDO"\n' > "$STUB/pbpaste"
printf '#!/bin/sh\n' > "$TMP/sem/grabit"
chmod +x "$STUB"/* "$TMP/sem/grabit"
printf 'sem permissão de execução\n' > "$STUB/bun"
ln -s "$G" "$TMP/com/grabit"
falso() { HOME="$TMP/casa" PATH="$STUB:$GBREW:$TMP/sem:$PATH" roda "$@"; }
ate() { local i; for (( i = 0; i < 150; i++ )); do "$@" 2>/dev/null && return 0; sleep 0.1; done; return 1; }
sem_runtime() { ! grep -F -- "$1" "$STUB_LOG" | grep -qF -- '--js-runtimes'; }
com_runtime() { grep -F -- "$1" "$STUB_LOG" | grep -qF -- "--js-runtimes $2"; }

secao "Runtime JavaScript"
D="$TMP/js"; mkdir -p "$D"; cd "$D" || exit 1
: > "$STUB_LOG"
STUB_JS="node-18.19.1 (unsupported)" falso s1 -L pt http://a.invalid/velho
espera "runtime velho não aparece como bom" contem s1 "js: nenhum"
espera "…ganha um aviso com a versão" contem s1 "O yt-dlp não aceita o node-18.19.1"
espera "…e não é passado ao yt-dlp" sem_runtime a.invalid/velho
espera "programa sem permissão de execução não é candidato" nao_contem "$STUB_LOG" "bun:$STUB/bun"
STUB_JS="node-22.1.0" falso s2 -L pt http://a.invalid/novo
espera "runtime aceito aparece no cabeçalho" contem s2 "js: node"
espera "…sem aviso" nao_contem s2 "não aceita"
espera "…e é passado ao yt-dlp" com_runtime a.invalid/novo "node:$STUB/node"
STUB_JS="none" falso s3 -L en http://a.invalid/nada
espera "sem runtime nenhum, o aviso de sempre" contem s3 "No JavaScript runtime"
STUB_JS="bun-1.4.2" STUB_AVISO="[youtube] [jsc:bun] bun version 1.4.2 is not supported! 1.3.14 is the last supported bun version. DO NOT open a bug report" \
  falso s4 -L pt http://a.invalid/bun
espera "aviso de runtime sem suporte chega ao resumo" contem s4 "bun version 1.4.2 is not supported! 1.3.14 is the last supported bun version."
espera "…sem o resto do sermão" nao_contem s4 "DO NOT"
espera "…e com a dica do Deno" contem s4 "https://deno.com"
falso s5 -L pt http://a.invalid/sem-aviso
espera "sem aviso do yt-dlp, nada no resumo" nao_contem s5 "deno.com"

secao "Dicas com o comando que funciona"
HOME="$TMP/casa" PATH="$STUB:$TMP/sem:$PATH" STUB_VER=2020.01.01 roda d1 -L pt http://a.invalid/d1
espera "sem o comando instalado, a dica traz o caminho" grep -qE 'bash .*grabit\.sh --atualizar' d1
HOME="$TMP/casa" PATH="$STUB:$TMP/com:$PATH" STUB_VER=2020.01.01 roda d2 -L pt http://a.invalid/d2
espera "com o comando instalado, basta o nome" grep -qE ': +grabit --atualizar' d2

secao "Pouco espaço e disco cheio"
D="$TMP/disco"; mkdir -p "$D"; cd "$D" || exit 1
STUB_DF=1024 falso e1 -L pt http://a.invalid/e1
espera "pouco espaço livre vira aviso" contem e1 "1.0 MiB livres"
falso e2 -L pt http://a.invalid/e2
espera "com espaço, nenhum aviso" nao_contem e2 "livres em"
printf '%s\n' http://b.invalid/1 http://b.invalid/2 http://b.invalid/3 > links.txt
rm -f links_falhos.txt; : > "$STUB_LOG"
STUB_ERRO="unable to write data: [Errno 28] No space left on device" DOWNLOADS_SIMULTANEOS=1 falso e3 -L pt
espera "disco cheio é explicado" contem e3 "disco cheio"
espera "…e nenhum download novo começa" test "$(grep -c 'b.invalid/' "$STUB_LOG")" -eq 1
espera "…os que faltam vão para a lista de falhas" test "$(grep -c 'b.invalid/' links_falhos.txt)" -eq 3
espera "…e sai com código 1" codigo "$RC" 1

secao "links_falhos.txt entre execuções"
D="$TMP/falhas"; mkdir -p "$D"; cd "$D" || exit 1
STUB_ERRO="HTTP Error 404" falso f1 -L pt http://c.invalid/1 http://c.invalid/2
STUB_ERRO="HTTP Error 404" falso f2 -L pt http://c.invalid/3
espera "falhas novas não apagam as de antes" test "$(grep -c 'c.invalid/' links_falhos.txt)" -eq 3
espera "…e o resumo diz isso" contem f2 "(mais 2 de execuções anteriores)"
falso f3 -L pt http://c.invalid/1
espera "o que deu certo sai da lista" nao_contem links_falhos.txt "c.invalid/1"
espera "…e o resto continua lá" test "$(grep -c 'c.invalid/' links_falhos.txt)" -eq 2
falso f4 -L pt http://c.invalid/outro
espera "um link sem relação não mexe nela" test "$(grep -c 'c.invalid/' links_falhos.txt)" -eq 2
falso f5 -L pt -l links_falhos.txt
espera "todos certos: o arquivo some" test ! -e links_falhos.txt

secao "Upgrade interrompido"
D="$TMP/antigos"; mkdir -p "$D/Downloads"; cd "$D" || exit 1
echo antigo > "Downloads/a [a].mkv.grabit-antigo"
echo novo > "Downloads/b [b].mkv"; echo antigo > "Downloads/b [b].mkv.grabit-antigo"
falso u1 -L pt -U http://a.invalid/u1
espera "-U devolve o arquivo que ficou de lado" test -f "Downloads/a [a].mkv"
espera "…e descarta o antigo se o novo chegou" contem "Downloads/b [b].mkv" novo
espera "…sem deixar sobras" test -z "$(find Downloads -name '*.grabit-antigo')"

secao "Fila viva e captura"
D="$TMP/fila"; mkdir -p "$D"; cd "$D" || exit 1
printf '%s\n' http://f.invalid/1 > links.txt
HOME="$TMP/casa" PATH="$STUB:$PATH" bash "$G" -L pt -f > saida 2>&1 & P=$!
ate grep -qF "f.invalid/1  # ✔" links.txt
echo http://f.invalid/2 >> links.txt
espera "-f: o link acrescentado ao arquivo é baixado" ate grep -qF "f.invalid/2  # ✔" links.txt
kill -TERM "$P" 2>/dev/null; wait "$P" 2>/dev/null
D="$TMP/captura"; mkdir -p "$D"; cd "$D" || exit 1
echo "https://g.invalid/ja-copiado" > "$CLIP_ARQ"
HOME="$TMP/casa" PATH="$STUB:$PATH" bash "$G" -L pt -C > saida 2>&1 & P=$!
ate test -e "$CLIP_LIDO"
echo "veja http://g.invalid/1 aqui" > "$CLIP_ARQ"
espera "-C: o link copiado é anotado e baixado" ate grep -qF "g.invalid/1  # ✔" links.txt
espera "…e o que já estava copiado não conta" nao_contem links.txt "ja-copiado"
kill -TERM "$P" 2>/dev/null; wait "$P" 2>/dev/null

secao "--versao e --atualizar"
D="$TMP/repos"; mkdir -p "$D/solto"; cd "$D" || exit 1
cp "$G" solto/grabit.sh
G="$D/solto/grabit.sh" falso v0 -L pt --versao
espera "cópia sem Git é reconhecida" contem v0 "cópia sem Git"
espera "…e diz quando não dá para conferir" contem v0 "não deu para conferir"
if command -v git >/dev/null 2>&1; then
  gitq() { git -c user.name=t -c user.email=t@t.invalid -c commit.gpgsign=false "$@"; }
  mkdir -p up alheio/bin
  cp "$G" up/grabit.sh; gitq init -q up; gitq -C up add grabit.sh; gitq -C up commit -qm um
  git clone -q up clone
  G="$D/clone/grabit.sh" falso v1 -L pt --versao
  espera "--versao mostra o commit" contem v1 "$(git -C up rev-parse --short HEAD)"
  espera "…e que está em dia" contem v1 "em dia com o repositório"
  espera "…e o runtime em uso" grep -qE 'JavaScript +nenhum' v1
  # a versão nova se denuncia quando é relançada
  { head -n 1 up/grabit.sh; echo '[[ -n ${GRABIT_RELANCADO:-} ]] && echo "RELANCADO-COM-O-NOVO"'; tail -n +2 up/grabit.sh; } > up/novo
  mv up/novo up/grabit.sh; gitq -C up commit -qam dois
  G="$D/clone/grabit.sh" falso v2 -L pt --versao
  espera "--versao avisa da versão mais nova" contem v2 "há uma versão mais nova"
  G="$D/clone/grabit.sh" STUB_JS="node-22.1.0" falso a1 -L pt --atualizar
  espera "--atualizar puxa a versão nova" contem clone/grabit.sh "RELANCADO-COM-O-NOVO"
  espera "…e é ela que termina o trabalho" contem a1 "RELANCADO-COM-O-NOVO"
  cp "$G" alheio/bin/grabit.sh; gitq init -q alheio; gitq -C alheio add bin; gitq -C alheio commit -qm um
  G="$D/alheio/bin/grabit.sh" STUB_JS="node-22.1.0" falso a2 -L pt --atualizar
  espera "--atualizar não dá git pull em outro repositório" nao_contem a2 "git pull"
fi

secao "--atualizar cuida de tudo"
atu() { HOME="$TMP/casa_a" PATH="$STUB:$GBREW:$TMP/sem:$PATH" G="$D/solto/grabit.sh" roda "$@"; }
mkdir -p "$TMP/casa_a/.deno/bin"; : > "$STUB_LOG"
STUB_JS="node-18.19.1 (unsupported)" STUB_SPEC="yt-dlp[curl-cffi,default]" STUB_VELHO=ffmpeg atu at1 -L pt --update
espera "sem runtime aceito, instala o Deno sem perguntar" contem "$STUB_LOG" "brew install deno"
espera "atualiza o yt-dlp e as dependências dele" contem "$STUB_LOG" "pipx upgrade --include-injected --pip-args=--upgrade-strategy=eager yt-dlp"
espera "atualiza o FFmpeg, se houver versão nova" contem "$STUB_LOG" "brew upgrade ffmpeg"
: > "$STUB_LOG"
printf '#!/bin/sh\nprintf "deno %%s\\n" "$*" >> "$STUB_LOG"\n' > "$TMP/casa_a/.deno/bin/deno"; chmod +x "$TMP/casa_a/.deno/bin/deno"
GRABIT_RELANCADO=1 STUB_JS="deno-2.9.8" STUB_SPEC="yt-dlp[curl-cffi,default]" atu at2 -L pt --update   # (a cópia solta não tem de onde se baixar)
espera "com o Deno instalado, atualiza o Deno" contem "$STUB_LOG" "deno upgrade"
espera "…sem instalar de novo" nao_contem "$STUB_LOG" "brew install"
espera "com o FFmpeg em dia, não mexe nele" nao_contem "$STUB_LOG" "brew upgrade"
espera "tudo certo, diz isso" contem at2 "Tudo na versão mais nova."
: > "$STUB_LOG"
STUB_JS="deno-2.9.8" STUB_SPEC="yt-dlp" atu at3 -L pt --update
espera "yt-dlp sem os extras é reinstalado com eles" contem "$STUB_LOG" "pipx install --force yt-dlp[default,curl-cffi]"
: > "$STUB_LOG"
STUB_JS="deno-2.9.8" STUB_SPEC="git+https://exemplo.invalid/yt-dlp" atu at4 -L pt --update
espera "yt-dlp instalado de um link fica como está" nao_contem "$STUB_LOG" "install --force"
: > "$STUB_LOG"
STUB_JS="bun-1.4.2" HOME="$TMP/casa_b" PATH="$TMP/bun:$STUB:$GBREW:$TMP/sem:$PATH" G="$D/solto/grabit.sh" roda at5 -L pt --update
espera "só com o Bun, que pode ser novo demais, instala o Deno" contem "$STUB_LOG" "brew install deno"
if ! command -v brew >/dev/null 2>&1; then     # num Mac, o brew de verdade viria antes do apt de mentira
  aptf() { HOME="$TMP/casa_c" PATH="$STUB:$GAPT:$TMP/sem:$PATH" G="$D/solto/grabit.sh" roda "$@"; }
  mkdir -p "$TMP/casa_c"
  STUB_JS="node-18.19.1 (unsupported)" STUB_CURL_FALHA=1 aptf ap1 -L pt --update
  espera "fora do brew, usa o instalador oficial; download que falha é falha" sh -c 'grep -A1 "instalar o Deno" "$1" | grep -q falhou' _ ap1
  : > "$STUB_LOG"
  STUB_JS="node-18.19.1 (unsupported)" STUB_VELHO=ffmpeg aptf ap2 -L pt --update
  espera "…e o download bom instala o Deno" test -x "$TMP/casa_c/.deno/bin/deno"
  espera "…sem atualizar o que acabou de chegar" nao_contem "$STUB_LOG" "deno upgrade"
  espera "apt: atualiza o FFmpeg com versão nova" contem "$STUB_LOG" "apt-get install -y --only-upgrade ffmpeg"
  if (( EUID != 0 )); then
    : > "$STUB_LOG"
    STUB_JS="deno-2.9.8" STUB_VELHO=ffmpeg STUB_SENHA=1 aptf ap3 -L pt --update </dev/null
    espera "sem terminal para a senha do sudo, avisa e não trava" contem ap3 "pede a senha do sudo"
    espera "…sem tentar instalar" nao_contem "$STUB_LOG" "--only-upgrade ffmpeg"
  fi
fi

secao "Comandos nas duas línguas, com ou sem os traços"
formas() {                                    # formas TEXTO PALAVRA... [-- ARGS...]: cada forma mostra o TEXTO
  local texto=$1 p f nomes=() args=()
  shift
  while (( $# )) && [[ $1 != -- ]]; do nomes+=("$1"); shift; done
  (( $# )) && { shift; args=("$@"); }
  for p in "${nomes[@]}"; do
    for f in "$p" "--$p"; do
      G="$D/solto/grabit.sh" STUB_JS="node-22.1.0" falso cmd -L pt "$f" "${args[@]}"
      espera "grabit $f" contem cmd "$texto"
    done
  done
}
formas "grabit.config" config
formas "Uso:  grabit" ajuda help
formas "instalação das dependências" instalar install -- -y
formas "GrabIt · atualização" atualizar update
formas "não existe" verificar check -- "$TMP/nao-existe"
formas "seção BAIXADOS" baixados downloaded -- -l "$L"
formas "cópia sem Git" versao versão version
formas "Diga o formato" converter convert
falso w1 -L pt -- update
espera "depois de -- a palavra não é comando" contem w1 "Nenhum link válido"
falso w2 -L pt -l update --config
espera "valor de opção não é comando" grep -qE 'ARQUIVO_LINKS +update' w2
: > "$STUB_LOG"
falso w3 -L pt http://a.invalid/w3 update
espera "só a primeira palavra pode ser comando" nao_contem w3 "atualização"
echo http://a.invalid/w4 > update
falso w4 -L pt ./update
espera "arquivo com nome de comando vale com ./" contem "$STUB_LOG" "a.invalid/w4"

secao "Várias conexões"
D="$TMP/conexoes"; mkdir -p "$D" "$TMP/comaria"; cd "$D" || exit 1
printf '#!/bin/sh\nexit 0\n' > "$TMP/comaria/aria2c"; chmod +x "$TMP/comaria/aria2c"
comaria() { HOME="$TMP/casa" PATH="$TMP/comaria:$STUB:$GBREW:$TMP/sem:$PATH" roda "$@"; }
pedido() { grep -F -- "$1" "$STUB_LOG" | tail -n 1 | grep -qF -- "$2"; }
sem_pedido() { ! pedido "$1" "$2"; }
: > "$STUB_LOG"
comaria c1 -L pt http://a.invalid/c1
espera "arquivo direto: abre 3 conexões pelo aria2c" pedido a.invalid/c1 "aria2c:-x3 -s3"
espera "…e os pedaços de um stream também vão com 3" pedido a.invalid/c1 "-N 3"
comaria c2 -L pt -c 5 http://a.invalid/c2
espera "-c muda o número" pedido a.invalid/c2 "aria2c:-x5 -s5"
comaria c3 -L pt -c 1 http://a.invalid/c3
espera "-c 1 dispensa o aria2c" sem_pedido a.invalid/c3 "--downloader"
comaria c4 -L pt https://www.youtube.com/watch?v=abc
espera "o YouTube fica no yt-dlp: ele limita quem pede pedaços grandes" sem_pedido youtube.com/watch "--downloader"
if ! command -v aria2c >/dev/null 2>&1; then
  falso c5 -L pt http://a.invalid/c5
  espera "sem aria2c, uma conexão por arquivo e nenhum erro" sem_pedido a.invalid/c5 "--downloader"
fi
: > "$STUB_LOG"; rm -f "$TMP/conc"
STUB_DORME=5 STUB_PROGRESSO=1 STUB_CONC="$TMP/conc" comaria c6 -L pt -j 4 http://b.invalid/1 http://b.invalid/2 http://b.invalid/3 http://b.invalid/4
espera "um site só não abre conexões sem fim: a soma para no dobro de -c" test "$(grep -c 'aria2c:-x3' "$STUB_LOG")" -eq 2
espera "…e os demais vão com uma" test "$(grep -- '-- http://b.invalid/' "$STUB_LOG" | grep -c -- '-N 1 ')" -eq 2
: > "$STUB_LOG"
STUB_RECUSA=1 comaria c7 -L pt -j 1 http://c.invalid/1 http://c.invalid/2
espera "site que recusa as conexões extras é avisado" contem c7 "recusou as conexões extras"
espera "…e o próximo vai com uma só" sem_pedido c.invalid/2 "--downloader"
: > "$STUB_LOG"
STUB_ARIA_FALHA=1 comaria c8 -L pt http://d.invalid/1
espera "o aria2c falhou: repete sem ele" sem_pedido d.invalid/1 "--downloader"
espera "…sem subir na cascata" sem_pedido d.invalid/1 "--referer"
espera "…sem gastar tentativa nem marcar o site como difícil" nao_contem "$XDG_DATA_HOME/grabit/metodos.txt" "d.invalid"
: > "$STUB_LOG"
STUB_LENTO=1 comaria c9 -L pt -j 1 http://e.invalid/1 http://e.invalid/2
espera "a sonda viu que uma conexão só rende mais: avisa" contem c9 "rende mais com uma conexão só"
espera "…e o site segue sem o aria2c" sem_pedido e.invalid/2 "--downloader"
mkdir -p "$TMP/falso-aria"; cat > "$TMP/falso-aria/aria2c" <<'EOF2'
#!/bin/sh
printf '[#a1b2c3 20MiB/60MiB(34%%) CN:3 DL:10MiB ETA:1m3s]\n'
printf 'Exception: errorCode=22 URI=http://x/\n  -> errorCode=22 The response status is not successful. status=429\n'
EOF2
chmod +x "$TMP/falso-aria/aria2c"
GRABIT_SONDAR=0 PATH="$TMP/falso-aria:$PATH" bash "$G" --baixa-partes --out 'Um titulo [abc].f137.mp4.part' -- http://x/ > traduzido 2>&1
ate grep -q 'HTTP Error 429' traduzido
espera "o progresso do aria2c vira a linha do painel" contem traduzido "$(printf '@@P@@20971520\x1f62914560\x1f10485760\x1f63\x1f\x1f\x1f?\x1f\x1f\x1f\x1fUm titulo')"
espera "…e a recusa, um aviso para o GrabIt" contem traduzido "[grabit] recusou 429"

secao "Formato do arquivo"
D="$TMP/formato"; mkdir -p "$D"; cd "$D" || exit 1
: > "$STUB_LOG"
falso f1 -L pt http://f.invalid/1
espera "padrão: MKV, com a capa pelo yt-dlp" pedido f.invalid/1 "--remux-video mkv"
espera "…e nenhum acabamento" sem_pedido f.invalid/1 "--acabamento"
for o in "-O" "--original"; do
  falso f2 -L pt "$o" "http://f.invalid/2$o"
  espera "$o não converte" sem_pedido "f.invalid/2$o" "--remux-video"
  espera "$o deixa a capa com o acabamento, que avisa o que não coube" pedido "f.invalid/2$o" "--acabamento original"
  espera "$o nem pede a capa embutida ao yt-dlp, que prenderia o vídeo na pasta temporária" sem_pedido "f.invalid/2$o" "--embed-thumbnail"
done
for o in "-e mp4" "-e .MP4" "--formato mp4" "--format=mp4" "--extensao mp4"; do
  read -ra a <<<"$o"
  falso f3 -L pt "${a[@]}" "http://f.invalid/3${a[0]}"
  espera "$o" pedido "f.invalid/3${a[0]}" "--acabamento mp4"
done
falso f4 -L pt -e mp4 http://f.invalid/4
espera "-e mp4: prefere as versões que já cabem" pedido f.invalid/4 "vext:mp4,aext:m4a"
espera "…sem abrir mão da resolução" pedido f.invalid/4 "-S res,fps,hdr:12"
FORMATO_SAIDA=original falso f5 -L pt http://f.invalid/5
espera "FORMATO_SAIDA no ambiente ou no grabit.config" pedido f.invalid/5 "--acabamento original"
falso f6 -L pt -e xyz http://f.invalid/6
espera "formato desconhecido é recusado" codigo "$RC" 2
falso f7 -L pt --formato
espera "--formato sem valor é recusado" codigo "$RC" 2
for o in "-k h264" "-k x264" "--codec avc" "--codec=h264"; do
  read -ra a <<<"$o"
  falso f8 -L pt "${a[@]}" "http://f.invalid/8${a[0]}"
  espera "$o prefere a versão que já está nesse codec" pedido "f.invalid/8${a[0]}" "vcodec:h264"
done
espera "-k não procura outro arquivo: ela escolheria pelos números" sem_pedido "f.invalid/8-k" "--procura-direto"
falso f9 -L pt -e av1 http://f.invalid/9
espera "-e av1: é um codec, não uma extensão, e funciona" pedido f.invalid/9 "vcodec:av01"
espera "…no MKV de sempre" pedido f.invalid/9 "--remux-video mkv"
falso f10 -L pt -k xyz http://f.invalid/10
espera "codec desconhecido é recusado" codigo "$RC" 2
falso f11 -L pt -x -O http://f.invalid/11
espera "só áudio: as opções de vídeo ficam de fora, com um aviso" contem f11 "valem para vídeo"
espera "…e nada de acabamento" sem_pedido f.invalid/11 "--acabamento"
falso f12 -L pt -O http://f.invalid/12
espera "o cabeçalho mostra a saída" contem f12 "o formato do site"
falso f13 -L pt converter
espera "converter sem formato nem codec explica o que falta" codigo "$RC" 2
falso f14 -L pt converter -e mp4
espera "…e sem arquivo também" contem f14 "Diga o arquivo"
falso f15 -L pt converter ./nao-existe.mp4 -e mkv
espera "…e arquivo que não existe, idem" contem f15 "Não encontrei"

secao "Novas tentativas por outro caminho"
D="$TMP/tentativas"; mkdir -p "$D"; cd "$D" || exit 1
tentou() { grep -F -- "$1" "$STUB_LOG" | grep -qF -- "$2"; }
vezes() { grep -cF -- "$1" "$STUB_LOG"; }
: > "$STUB_LOG"
STUB_ERRO="[generic] Got HTTP Error 403 caused by Cloudflare anti-bot challenge; try again" \
  STUB_ERRO2="[generic] x: Unable to download webpage: HTTP Error 403: Forbidden" falso t1 -L pt http://t.invalid/cf
espera "verificação anti-robô é explicada, mesmo com a 2ª tentativa dizendo só 403" contem t1 "verificação anti-robô"
espera "…e diz como baixar pelo navegador" contem t1 "Copiar como cURL"
espera "a nova tentativa manda o Referer" tentou t.invalid/cf "--referer http://t.invalid/cf"
espera "…sem perder o paralelismo à toa" nao_contem "$STUB_LOG" "-N 1 "
STUB_ERRO="unable to download fragment 3" falso t0 -L pt http://t.invalid/frag
espera "pedaço que não veio: a nova tentativa usa uma conexão por vez" tentou t.invalid/frag "-N 1"
STUB_ERRO="Unsupported URL: http://t.invalid/js" falso t2 -L pt http://t.invalid/js
espera "página sem vídeo reconhecido é explicada" contem t2 "nenhum vídeo reconhecido"
espera "…sem repetir à toa" test "$(vezes t.invalid/js)" -eq 1
espera "…e diz como baixar pelo navegador" contem t2 "Copiar como cURL"
STUB_ERRO="HTTP Error 429: Too Many Requests" falso t3 -L pt http://t.invalid/429
espera "429: a nova tentativa vai mais devagar" tentou t.invalid/429 "--sleep-requests 2"
STUB_ERRO="Connection reset by peer" falso t4 -L pt http://t.invalid/rede
espera "falha de rede: a nova tentativa usa IPv4" tentou t.invalid/rede "--force-ipv4"
STUB_ERRO="[SSL: UNSAFE_LEGACY_RENEGOTIATION_DISABLED] unsafe legacy renegotiation disabled" falso t5 -L pt http://t.invalid/ssl
espera "servidor antigo: a nova tentativa aceita a conexão dele" tentou t.invalid/ssl "--legacy-server-connect"
STUB_ERRO="This video is only available for registered users" falso t6 -L pt http://t.invalid/login
espera "login é explicado" contem t6 "precisa de login"
espera "…sem repetir à toa" test "$(vezes t.invalid/login)" -eq 1
STUB_ERRO="This video is DRM protected" falso t7 -L pt http://t.invalid/drm
espera "DRM é explicado" contem t7 "protegido por DRM"
espera "…sem sugerir outro caminho" nao_contem t7 "Copiar como cURL"
falso t8 -L pt http://t.invalid/ua -A "Navegador/1.0 (X11)"
espera "-A vira o User-Agent, em qualquer posição" tentou t.invalid/ua "--user-agent Navegador/1.0 (X11)"
OPCOES_YTDLP="--force-ipv4 --geo-bypass" falso t9 -L pt http://t.invalid/opcoes
espera "OPCOES_YTDLP chega ao yt-dlp" tentou t.invalid/opcoes "--force-ipv4 --geo-bypass"

if command -v python3 >/dev/null 2>&1; then
  secao "grabit curl"
  D="$TMP/curl"; mkdir -p "$D"; cd "$D" || exit 1
  cat > copiado.txt <<'EOF'
curl 'http://c.invalid/hls/master.m3u8?token=abc&x=1' --compressed \
  -H 'User-Agent: Navegador/1.0 (X11; Linux)' \
  -H 'Referer: http://c.invalid/player?temporada=7&episodio=1' \
  -H 'Range: bytes=0-' \
  -H 'Cookie: cf_clearance=abc; sessao=1'
EOF
  : > "$STUB_LOG"
  falso c1 -L pt curl copiado.txt
  espera "baixa o link do comando copiado" tentou "http://c.invalid/hls/master.m3u8?token=abc&x=1" "--add-header"
  espera "…com o User-Agent do navegador" contem "$STUB_LOG" "--add-header User-Agent:Navegador/1.0 (X11; Linux)"
  espera "…e o Referer" contem "$STUB_LOG" "--add-header Referer:http://c.invalid/player?temporada=7&episodio=1"
  espera "…sem o Range daquele pedido" nao_contem "$STUB_LOG" "Range:"
  espera "os cookies vão em arquivo" tentou c.invalid/hls "--cookies "
  espera "…e nunca na linha de comando" nao_contem "$STUB_LOG" "cf_clearance"
  espera "o nome do arquivo vem da página" contem "$STUB_LOG" "c.invalid - player temporada 7 episodio 1 ["
  espera "sem histórico, para o próximo master não parecer já baixado" nao_contem "$STUB_LOG" "--download-archive"
  espera "o cabeçalho conta o que veio" contem c1 "2 cabeçalho(s), 2 cookie(s)"
  falso c2 -L pt --curl - < copiado.txt
  espera "lê da entrada padrão" contem c2 "cURL do navegador"
  cp copiado.txt "$CLIP_ARQ"
  falso c3 -L pt curl
  espera "lê da área de transferência" contem c3 "cURL do navegador"
  echo "isto não é curl" > ruim.txt
  falso c4 -L pt curl ruim.txt
  espera "texto que não é cURL é recusado" codigo "$RC" 2
  espera "…com a explicação" contem c4 "não é um comando cURL"
  printf '%s\n' "curl 'file:///etc/passwd'" > ruim.txt
  falso c5 -L pt curl ruim.txt
  espera "só aceita http e https" codigo "$RC" 2
  rm -f links_falhos.txt
  STUB_ERRO="HTTP Error 404" falso c6 -L pt curl copiado.txt
  espera "link copiado que falha não vai para a lista de falhas" test ! -e links_falhos.txt
  espera "…e avisa que ele costuma expirar" contem c6 "costuma expirar"
  # como o navegador manda de verdade quando o vídeo está em outro domínio: só a origem no Referer
  : > "$STUB_LOG"
  falso c7 -L pt curl 'http://video.c.invalid/pt-BR/701/master.m3u8' --compressed -H 'Referer: http://c.invalid/' -H 'Origin: http://c.invalid' -L
  espera "o comando colado depois de grabit funciona" codigo "$RC" 0
  espera "…e leva os cabeçalhos dele" tentou video.c.invalid "--add-header Origin:http://c.invalid"
  espera "…sem tomar o -L dele pelo idioma" nao_contem c7 "Idioma desconhecido"
  espera "Referer só com a origem: o nome vem do caminho do vídeo" contem "$STUB_LOG" "c.invalid - pt-BR 701 ["
  : > "$STUB_LOG"
  falso c8 -L pt -o ./Pasta --curl 'http://c.invalid/filme.mp4' -H 'Referer: http://c.invalid/'
  espera "as opções do GrabIt vêm antes de curl" tentou c.invalid/filme.mp4 "-P ./Pasta"
  espera "…e o nome aproveita o arquivo, se ele disser algo" contem "$STUB_LOG" "c.invalid - filme ["
  : > "$CLIP_ARQ"
  falso c9 -L pt curl
  espera "área de transferência sem cURL explica o que fazer" contem c9 "colar o comando depois de grabit"
  if ! command -v wl-paste >/dev/null 2>&1; then
    WAYLAND_DISPLAY=wayland-9 falso c10 -L pt curl
    espera "no Wayland sem wl-paste, diz o que falta" contem c10 "precisa do wl-clipboard"
    falso c11 -L pt curl
    espera "…e fora do Wayland, não" nao_contem c11 "wl-clipboard"
    if ! command -v brew >/dev/null 2>&1; then
      : > "$STUB_LOG"
      D="$TMP/repos" WAYLAND_DISPLAY=wayland-9 STUB_JS="deno-2.9.8" aptf ap4 -L pt --update
      espera "--atualizar instala o wl-clipboard no Wayland, mesmo com o xclip" contem "$STUB_LOG" "apt-get install -y wl-clipboard"
    fi
  fi
fi

secao "Link sem https://"
D="$TMP/sem-esquema"; mkdir -p "$D"; cd "$D" || exit 1
: > "$STUB_LOG"
falso s1 -L pt 'site.invalid/player?temporada=7&episodio=1'
espera "site.com/caminho vira um link" contem "$STUB_LOG" "-- https://site.invalid/player?temporada=7&episodio=1"
falso s2 -L pt lista.txt
espera "lista.txt, sem caminho, não é um link" contem s2 "Nenhum link válido"
falso s3 -L pt pasta/arquivo.txt
espera "pasta/arquivo.txt também não" contem s3 "Nenhum link válido"

secao "Vídeo passado por engano como lista"
D="$TMP/nao-lista"; mkdir -p "$D"; cd "$D" || exit 1
printf 'ftypisom\0\0\0\1dados\nhttps://site.invalid/descricao\nmais dados\0\n' > video.mkv
cp video.mkv video.orig
: > "$STUB_LOG"
falso s1 -L pt video.mkv
espera "um arquivo binário é recusado" codigo "$RC" 2
espera "…explicado" contem s1 "não é uma lista de links"
espera "…com o comando certo" contem s1 "converter"
espera "…e o yt-dlp nem é chamado para o link de dentro dele" nao_contem "$STUB_LOG" "site.invalid/descricao"
espera "…e o arquivo fica intacto" cmp -s video.mkv video.orig
falso s2 -L pt -l video.mkv
espera "-l também recusa" codigo "$RC" 2
espera "…e não mexe no arquivo" cmp -s video.mkv video.orig
falso s3 -L pt https://site.invalid/outro video.mkv
espera "junto de um link bom, também" codigo "$RC" 2
espera "…e não baixa nada" nao_contem "$STUB_LOG" "site.invalid/outro"
falso s4 -L pt -l video.mkv --baixados limpar </dev/null
espera "--baixados também recusa" codigo "$RC" 2
espera "…e não mexe no arquivo" cmp -s video.mkv video.orig
printf '\377\376h\0t\0t\0p\0\n\0' > utf16.txt
falso s5 -L pt utf16.txt
espera "lista em UTF-16 é recusada com a explicação" contem s5 "UTF-16"
printf 'https://site.invalid/ok   # comentário çãõ\r\n\thttps://site.invalid/tab\r\n' > texto.txt
: > "$STUB_LOG"
falso s6 -L pt texto.txt
espera "lista de texto com acentos, tabulação e fim de linha do Windows continua valendo" contem "$STUB_LOG" "site.invalid/tab"

secao "Proxy"
D="$TMP/proxy"; mkdir -p "$D"; cd "$D" || exit 1
roda p1 -L pt --proxy http://user:s3nha@proxy.invalid:8080 --config
espera "--proxy aparece na configuração" grep -qE 'PROXY +http://•••@proxy.invalid:8080 +opção do comando' p1
espera "…sem mostrar a senha" nao_contem p1 "s3nha"
PROXY=proxy.invalid:3128 roda p2 -L pt --config
espera "host:porta vira http://" contem p2 "http://proxy.invalid:3128"
roda p3 -L pt --proxy 'ftp://x' --config
espera "endereço que não é de proxy é recusado" codigo "$RC" 2
OPCOES_YTDLP='--force-ipv4 --proxy http://p.invalid:1' roda p4 -L pt --config
espera "--proxy em OPCOES_YTDLP também vale para o resto" grep -qE 'PROXY +http://p.invalid:1' p4
https_proxy=http://amb.invalid:2 roda p5 -L pt --config
espera "o proxy do ambiente também" grep -qE 'PROXY +http://amb.invalid:2 +variável de ambiente' p5
: > "$STUB_LOG"
falso p6 -L pt --proxy http://user:s3nha@proxy.invalid:8080 http://a.invalid/p6
espera "a senha não vai na linha de comando do yt-dlp" nao_contem "$STUB_LOG" "s3nha"
espera "…e o início mostra o proxy" contem p6 "•••@proxy.invalid:8080"
: > "$STUB_LOG"
falso p7 -L pt --proxy socks5://proxy.invalid:1080 http://a.invalid/p7
espera "proxy SOCKS avisa o que fica de fora" contem p7 "não passam por ele"
espera "…nem a busca por arquivo direto nem o aria2c" nao_contem "$STUB_LOG" "--procura-direto"
espera "…e transmissão ao vivo não passa pelo ffmpeg" contem "$STUB_LOG" "m3u8:native"
if command -v aria2c >/dev/null 2>&1; then
  : > "$STUB_LOG"
  PATH="$(dirname "$(command -v aria2c)"):$PATH" falso p8 -L pt --proxy socks5://proxy.invalid:1080 http://a.invalid/p8
  espera "SOCKS: nenhum download pelo aria2c" nao_contem "$STUB_LOG" "--downloader http:"
fi

secao "Vídeo achado pelo navegador (Firefox de mentira)"
D="$TMP/navegador"; FF="$TMP/ff"; mkdir -p "$D" "$FF"; cd "$D" || exit 1
cat > "$FF/firefox" <<'EOF'
#!/bin/sh
printf 'firefox %s\n' "$*" >> "$STUB_LOG"
[ -z "${STUB_FF_FECHA:-}" ] || exit 0
trap 'echo "firefox fechado" >> "$STUB_LOG"; exit 0' TERM
cat > "$MOZ_LOG_FILE.moz_log" <<'LOG'
[Parent 1: Main Thread]: E/nsHttp uri=https://n.invalid/style.css
[Parent 1: Main Thread]: E/nsHttp   GET /style.css HTTP/1.1
[Parent 1: Main Thread]: E/nsHttp   Host: n.invalid
[Parent 1: Main Thread]: E/nsHttp ]
[Parent 1: Main Thread]: E/nsHttp uri=https://video.n.invalid/pt-BR/701/master.m3u8?t=1
[Parent 1: Main Thread]: E/nsHttp http request [
[Parent 1: Main Thread]: E/nsHttp   GET /pt-BR/701/master.m3u8?t=1 HTTP/1.1
[Parent 1: Main Thread]: E/nsHttp   Host: video.n.invalid
[Parent 1: Socket Thread]: E/nsHttp outra coisa no meio
[Parent 1: Main Thread]: E/nsHttp   User-Agent: Firefox/159.0 (X11; Linux)
[Parent 1: Main Thread]: E/nsHttp   Referer: https://n.invalid/
[Parent 1: Main Thread]: E/nsHttp   Origin: https://n.invalid
[Parent 1: Main Thread]: E/nsHttp   Cookie: cf_clearance=abc; a=1
[Parent 1: Main Thread]: E/nsHttp   Range: bytes=0-
[Parent 1: Main Thread]: E/nsHttp ]
LOG
while :; do sleep 1 & wait $!; done
EOF
chmod +x "$FF/firefox"
nav() { HOME="$TMP/casa" XDG_DATA_HOME="$TMP/navdados" USAR_NAVEGADOR=1 GRABIT_NAVEGADOR_OPCOES=--headless GRABIT_NAVEGADOR_ESPERA=15 PATH="$FF:$STUB:$GBREW:$TMP/sem:$PATH" roda "$@"; }
printf '%s\n' 'n.invalid/player?temporada=7&episodio=1' > links.txt
: > "$STUB_LOG"
STUB_ERRO="[generic] Got HTTP Error 403 caused by Cloudflare anti-bot challenge; try again" \
  STUB_ERRO2="[generic] x: Unable to download webpage: HTTP Error 403: Forbidden" nav n1 -L pt
espera "verificação anti-robô: abre o navegador, com o aviso" contem n1 "vou abrir o Firefox"
espera "…uma vez só" test "$(grep -c '^firefox --no-remote' "$STUB_LOG")" -eq 1
espera "…num perfil só do GrabIt" contem "$STUB_LOG" "--no-remote --profile $TMP/navdados/grabit/firefox/perfil"
espera "…na página do link" contem "$STUB_LOG" "https://n.invalid/player?temporada=7&episodio=1"
espera "…e fecha a janela quando acha o vídeo" contem "$STUB_LOG" "firefox fechado"
espera "baixa o vídeo que o navegador pediu" tentou "-- https://video.n.invalid/pt-BR/701/master.m3u8?t=1" "--no-download-archive"
espera "…com o Referer e o User-Agent dele" tentou video.n.invalid "--add-header User-Agent:Firefox/159.0 (X11; Linux) --add-header Referer:https://n.invalid/"
espera "…sem o Range daquele pedido" nao_contem "$STUB_LOG" "Range:"
espera "…com os cookies em arquivo" tentou video.n.invalid "--cookies "
espera "…e nunca na linha de comando" nao_contem "$STUB_LOG" "cf_clearance"
espera "…com o nome da página" tentou video.n.invalid "n.invalid - player temporada 7 episodio 1 ["
espera "o log do navegador, que tem cookies, é apagado" test -z "$(find "$TMP/navdados" -name 'http*')"
espera "o link vai para a seção BAIXADOS" grep -qE '^n\.invalid/player.*# ✔' links.txt
espera "e sai com código 0" codigo "$RC" 0
espera "o método que funcionou fica lembrado" grep -q '^n\.invalid 2 ' "$TMP/navdados/grabit/metodos.txt"
: > "$STUB_LOG"
nav n7 -L pt https://n.invalid/outro
espera "o próximo link do site vai direto ao navegador" nao_contem "$STUB_LOG" "-- https://n.invalid/outro"
espera "…e baixa" tentou video.n.invalid "--no-download-archive"
: > "$STUB_LOG"
STUB_FF_FECHA=1 nav n8 -L pt https://n.invalid/outra
espera "o método lembrado que falha é esquecido" nao_contem "$TMP/navdados/grabit/metodos.txt" "n.invalid"
: > "$STUB_LOG"
STUB_ERRO="Unsupported URL: https://j.invalid/js" nav n2 -L pt https://j.invalid/js
espera "player em JavaScript: vai direto ao navegador" test "$(grep -c -- '-- https://j.invalid/js' "$STUB_LOG")" -eq 1
espera "…e baixa" tentou video.n.invalid "--no-download-archive"
: > "$STUB_LOG"
STUB_ERRO="HTTP Error 404: Not Found" nav n3 -L pt https://o.invalid/404
espera "erro que um navegador não resolve não abre janela" nao_contem "$STUB_LOG" "firefox "
: > "$STUB_LOG"
STUB_ERRO="Unsupported URL: https://p.invalid/x" STUB_FF_FECHA=1 nav n4 -L pt https://p.invalid/x
espera "janela fechada sem vídeo: explica" contem n4 "nenhum vídeo apareceu no navegador"
espera "…sem insistir" test "$(grep -c '^firefox --no-remote' "$STUB_LOG")" -eq 1
espera "…e sai com código 1" codigo "$RC" 1
: > "$STUB_LOG"
STUB_ERRO="Unsupported URL: https://n.invalid/y" USAR_NAVEGADOR=0 GRABIT_NAVEGADOR_OPCOES=--headless PATH="$FF:$STUB:$GBREW:$TMP/sem:$PATH" HOME="$TMP/casa" roda n5 -L pt https://n.invalid/y
espera "USAR_NAVEGADOR=0: não abre" nao_contem "$STUB_LOG" "firefox "
: > "$STUB_LOG"
STUB_ERRO="Unsupported URL: https://n.invalid/z" USAR_NAVEGADOR=1 PATH="$FF:$STUB:$GBREW:$TMP/sem:$PATH" HOME="$TMP/casa" roda n6 -L pt https://n.invalid/z
espera "sem terminal nem tela, ninguém veria a janela: não abre" nao_contem "$STUB_LOG" "firefox "

if command -v python3 >/dev/null 2>&1; then
  : > "$STUB_LOG"
  STUB_ERRO="Unsupported URL: https://n.invalid/px" nav n-px -L pt --proxy socks5://u:s@proxy.invalid:1080 'https://n.invalid/px'
  USERJS="$TMP/navdados/grabit/firefox/perfil/user.js"
  espera "Firefox: o proxy vai para o perfil, sem a senha" contem "$USERJS" 'user_pref("network.proxy.socks", "proxy.invalid");'
  espera "…com a porta" contem "$USERJS" 'user_pref("network.proxy.socks_port", 1080);'
  espera "…e o DNS também passa por ele" contem "$USERJS" 'user_pref("network.proxy.socks_remote_dns", true);'
  espera "…sem perder o resto do perfil" contem "$USERJS" 'media.autoplay.default'
  STUB_ERRO="Unsupported URL: https://n.invalid/sem" nav n-sem -L pt 'https://n.invalid/sem'
  espera "…e sem proxy, ele sai do perfil" nao_contem "$USERJS" 'network.proxy'
  secao "Vídeo achado pelo navegador (Chrome de mentira)"
  FF2="$TMP/ff2"; mkdir -p "$FF2"
  cat > "$FF2/google-chrome" <<'EOF'
#!/bin/sh
printf 'chrome %s\n' "$*" >> "$STUB_LOG"
for a in "$@"; do case "$a" in --log-net-log=*) f=${a#--log-net-log=} ;; esac; done
trap 'echo "chrome fechado" >> "$STUB_LOG"; exit 0' TERM
cat > "$f" <<'LOG'
{"constants":{"logEventTypes":{"URL_REQUEST_START_JOB":10,"HTTP_TRANSACTION_SEND_REQUEST_HEADERS":20,"HTTP_TRANSACTION_HTTP2_SEND_REQUEST_HEADERS":21,"HTTP_TRANSACTION_TUNNEL_SEND_REQUEST_HEADERS":23}},
"events": [
{"params":{"method":"GET","url":"https://k.invalid/style.css"},"phase":1,"source":{"id":1,"type":1},"time":"1","type":10},
{"params":{"headers":["Host: k.invalid","User-Agent: Chrome/140"],"line":"GET /style.css HTTP/1.1\r\n"},"phase":0,"source":{"id":1,"type":1},"time":"2","type":20},
{"params":{"method":"GET","url":"https://video.n.invalid/hls/master.m3u8?t=2"},"phase":1,"source":{"id":2,"type":1},"time":"3","type":10},
{"params":{"headers":[":method: GET",":authority: video.n.invalid",":scheme: https",":path: /hls/master.m3u8?t=2","user-agent: Chrome/140 \"x\"","referer: https://k.invalid/","origin: https://k.invalid","cookie: cf_clearance=abc; a=1","range: bytes=0-"]},"phase":0,"source":{"id":2,"type":1},"time":"4","type":21},
{"params":{"headers":["pela me
LOG
while :; do sleep 1 & wait $!; done
EOF
  chmod +x "$FF2/google-chrome"
  : > "$STUB_LOG"
  PROGRAMA_NAVEGADOR="$FF2/google-chrome" STUB_ERRO="Unsupported URL: https://k.invalid/player" nav k1 -L pt 'https://k.invalid/player?ep=1'
  espera "abre o navegador que estiver instalado" contem k1 "vou abrir o Chrome"
  espera "…num perfil só do GrabIt" contem "$STUB_LOG" "--user-data-dir=$TMP/navdados/grabit/google-chrome/perfil"
  espera "…pedindo o log com os cabeçalhos" contem "$STUB_LOG" "--net-log-capture-mode=IncludeSensitive"
  espera "…e fecha a janela quando acha o vídeo" contem "$STUB_LOG" "chrome fechado"
  espera "baixa o vídeo que o navegador pediu, em HTTP/2" tentou "-- https://video.n.invalid/hls/master.m3u8?t=2" "--no-download-archive"
  espera "…com os cabeçalhos dele" tentou video.n.invalid '--add-header user-agent:Chrome/140 "x" --add-header referer:https://k.invalid/'
  espera "…sem o Range daquele pedido nem os pseudo-cabeçalhos" nao_contem "$STUB_LOG" "range:"
  espera "…com os cookies em arquivo" tentou video.n.invalid "--cookies "
  espera "…e nunca na linha de comando" nao_contem "$STUB_LOG" "cf_clearance"
  espera "…com o nome da página" tentou video.n.invalid "k.invalid - player ep 1 ["
  espera "o log do navegador, que tem cookies, é apagado" test -z "$(find "$TMP/navdados" -name 'http*')"
  : > "$STUB_LOG"
  PROGRAMA_NAVEGADOR="$FF2/google-chrome" STUB_ERRO="Unsupported URL: https://k.invalid/player" nav k-px -L pt --proxy socks5h://u:s@proxy.invalid:1080 'https://k.invalid/player?ep=9'
  espera "Chrome: o proxy vai na opção dele, sem a senha" contem "$STUB_LOG" "--proxy-server=socks5://proxy.invalid:1080"
fi

secao "A cascata lembra o que funcionou em cada site"
D="$TMP/memoria"; mkdir -p "$D"; cd "$D" || exit 1
M="$TMP/mem/grabit/metodos.txt"; export STUB_403="HTTP Error 403: Forbidden"
: > "$STUB_LOG"
XDG_DATA_HOME="$TMP/mem" STUB_ERRO=$STUB_403 STUB_SO_SEM_REFERER=1 falso m1 -L pt http://m.invalid/1
espera "só no 2º degrau deu certo: duas tentativas" test "$(vezes m.invalid/1)" -eq 2
espera "…e o site fica lembrado" grep -q '^m\.invalid 1 ' "$M"
XDG_DATA_HOME="$TMP/mem" STUB_ERRO=$STUB_403 STUB_SO_SEM_REFERER=1 falso m2 -L pt http://m.invalid/2
espera "o próximo link do site já começa no degrau certo" test "$(vezes m.invalid/2)" -eq 1
espera "…com o que ele precisa" tentou m.invalid/2 "--referer http://m.invalid/2"
XDG_DATA_HOME="$TMP/mem" falso m3 -L pt http://outro.invalid/1
espera "outro site continua pelo caminho direto" nao_contem "$STUB_LOG" "--referer http://outro.invalid/1"
printf 'velho.invalid 1 1000\n' > "$M"
XDG_DATA_HOME="$TMP/mem" falso m4 -L pt http://velho.invalid/1
espera "a memória vence: depois de 30 dias, volta ao caminho direto" nao_contem "$STUB_LOG" "--referer http://velho.invalid/1"
printf -v AGORA '%(%s)T' -1
printf 'falha.invalid 1 %s\nsumiu.invalid 1 %s\n' "$AGORA" "$AGORA" > "$M"
XDG_DATA_HOME="$TMP/mem" STUB_ERRO=$STUB_403 falso m5 -L pt http://falha.invalid/1
espera "o método lembrado que para de funcionar é esquecido" nao_contem "$M" "falha.invalid"
XDG_DATA_HOME="$TMP/mem" STUB_ERRO="HTTP Error 404: Not Found" falso m6 -L pt http://sumiu.invalid/1
espera "um link que sumiu (404) não apaga a memória do site" contem "$M" "sumiu.invalid"

secao "Distribuição entre os sites"
D="$TMP/freio"; mkdir -p "$D"; cd "$D" || exit 1
export STUB_CONC="$TMP/conc"
# Quem começou primeiro, em ordem alfabética: os downloads saem juntos e a ordem no log é uma corrida
primeiros() { grep -oE -- '-- http://[a-z0-9]+\.invalid/[0-9]+' "$STUB_LOG" | head -n "$1" | sed 's/^-- http:..//' | sort | tr '\n' ' '; }
falso z0 -L pt http://y.invalid/1 http://y.invalid/2 http://y.invalid/3 http://y.invalid/4 http://y.invalid/5
espera "4 downloads ao mesmo tempo por padrão" contem z0 "4 vídeo(s)"
: > "$STUB_LOG"
falso z2 -L pt -j 3 http://a.invalid/1 http://a.invalid/2 http://a.invalid/3 http://b.invalid/1 http://c.invalid/1
espera "as vagas se espalham entre os sites, mesmo com os links juntos na lista" test "$(primeiros 3)" = "a.invalid/1 b.invalid/1 c.invalid/1 "
espera "…sem perder a ordem dentro de cada site" test "$(primeiros 5 | tr ' ' '\n' | grep -c '^a')" -eq 3
espera "…e o cabeçalho conta os sites" contem z2 "3 sites"
: > "$STUB_LOG"
falso z3 -L pt -j 1 http://k.invalid/1 http://j.invalid/1 http://j.invalid/2 http://j.invalid/3
espera "no empate, vai primeiro o site com mais links esperando" test "$(primeiros 1)" = "j.invalid/1 "

secao "Ritmo por site"
: > "$STUB_CONC"
STUB_DORME=2 falso k1 -L pt -j 2 http://g.invalid/1 http://g.invalid/2
espera "site desconhecido começa com um download só" test "$(sed -n 2p "$STUB_CONC")" = fim
: > "$STUB_CONC"
STUB_DORME=3 STUB_PROGRESSO=1 falso k2 -L pt -j 2 http://h.invalid/1 http://h.invalid/2
espera "basta o download começar a chegar para abrir outra vaga" test "$(sed -n 2p "$STUB_CONC")" = ini
: > "$STUB_CONC"
STUB_DORME=2 falso k3 -L pt -F -j 2 http://i.invalid/1 http://i.invalid/2
espera "-F dispensa o começo devagar" test "$(sed -n 2p "$STUB_CONC")" = ini
: > "$STUB_LOG"
STUB_ERRO="HTTP Error 404: Not Found" falso k4 -L pt http://l.invalid/1 http://l.invalid/2 http://l.invalid/3 http://l.invalid/4 http://l.invalid/5
espera "links que sumiram não param o site" test "$(vezes l.invalid/5)" -eq 1
espera "…nem são repetidos" test "$(vezes l.invalid/1)" -eq 1

secao "Quando o site pede calma"
: > "$STUB_LOG"
INICIO=$SECONDS
GRABIT_ESPERA_BASE=2 STUB_429_UMA="$TMP/ja-pediu" falso p1 -L pt -j 2 http://c1.invalid/1 http://c2.invalid/1
espera "429: avisa" contem p1 "c1.invalid pediu para ir mais devagar"
espera "…espera antes de voltar ao site" test $(( SECONDS - INICIO )) -ge 2
espera "…o link tenta de novo" test "$(vezes c1.invalid/1)" -eq 2
espera "…e deu certo" codigo "$RC" 0
espera "os outros sites não esperam" test "$(primeiros 2)" = "c1.invalid/1 c2.invalid/1 "
espera "a espera fica guardada para a próxima execução" grep -qE '^c1\.invalid 0 [0-9]+ [0-9]+$' "$XDG_DATA_HOME/grabit/metodos.txt"
: > "$STUB_LOG"
STUB_ERRO="HTTP Error 429: Too Many Requests" falso p2 -L pt -j 1 http://q.invalid/1 http://q.invalid/2 http://q.invalid/3 http://q.invalid/4
espera "429 seguidos: para de insistir" test "$(vezes q.invalid/1)" -eq 4
espera "…os outros links do site nem chegam a pedir" test "$(vezes q.invalid/2)" -eq 0
espera "…avisa e conta os adiados" grep -qE 'Adiados +3' p2
espera "…eles ficam na lista de falhas" contem links_falhos.txt "q.invalid/4"
espera "…e sai com código 1" codigo "$RC" 1
: > "$STUB_LOG"
STUB_ERRO="HTTP Error 403: Forbidden" falso p3 -L pt -j 1 http://r.invalid/1 http://r.invalid/2 http://r.invalid/3 http://r.invalid/4 http://r.invalid/5
espera "3 links seguidos recusados: os que faltam ficam para depois" test "$(vezes r.invalid/4)" -eq 0
espera "…avisando" contem p3 "r.invalid está recusando"
mkdir -p "$TMP/esp/grabit"; printf -v AGORA '%(%s)T' -1
printf 's.invalid 0 %s %s\n' "$AGORA" "$(( AGORA + 3 ))" > "$TMP/esp/grabit/metodos.txt"
INICIO=$SECONDS
XDG_DATA_HOME="$TMP/esp" falso p4 -L pt http://s.invalid/1
espera "quem pediu calma há pouco continua esperando" contem p4 "s.invalid pediu calma há pouco"
espera "…de verdade" test $(( SECONDS - INICIO )) -ge 2
XDG_DATA_HOME="$TMP/esp" falso p5 -L pt -F http://s.invalid/2
espera "-F não espera" nao_contem p5 "pediu calma há pouco"
falso p6 -L pt 'http://$(touch${IFS}invadiu).invalid/1'
espera 'um link com "$(…)" no nome do site não executa nada' test ! -e invadiu

secao "Progresso salvo"
D="$TMP/salva"; mkdir -p "$D"; cd "$D" || exit 1
printf '%s\n' http://v.invalid/1 http://w.invalid/2 > links.txt
HOME="$TMP/casa" PATH="$STUB:$PATH" GRABIT_SALVA_A_CADA=1 STUB_DORME=6 STUB_DORME_SO=w.invalid bash "$G" -L pt > saida 2>&1 & P=$!
espera "o link baixado vai para a seção BAIXADOS antes de a lista terminar" ate grep -qF "v.invalid/1  # ✔" links.txt
espera "…com o outro ainda baixando" kill -0 "$P"
wait "$P" 2>/dev/null
espera "…e no fim vão todos" grep -qF "w.invalid/2  # ✔" links.txt

secao "Instalador: o opcional é perguntado"
D="$TMP/instalador"; mkdir -p "$D"; cd "$D" || exit 1
: > "$STUB_LOG"
STUB_JS="none" falso i1 -L pt install -y
espera "install -y não pergunta e instala o recomendado" contem "$STUB_LOG" "brew install deno"
command -v aria2c >/dev/null 2>&1 || espera "…inclusive o aria2, que abre várias conexões" grep -q '^brew install.*aria2' "$STUB_LOG"
espera "…e não chega a pedir confirmação" nao_contem i1 "[S/n]"
: > "$STUB_LOG"
PROGRAMA_NAVEGADOR=/nao/existe STUB_JS="node-22.1.0" falso i2 -L pt --install --yes
espera "-y sem navegador compatível instala o Firefox" contem "$STUB_LOG" "brew install firefox"
espera "…e nenhum outro" test "$(grep -c '^brew install' "$STUB_LOG")" -eq 1
: > "$STUB_LOG"
HOME="$TMP/casa" PATH="$FF:$STUB:$GBREW:$TMP/sem:$PATH" STUB_JS="node-22.1.0" roda i6 -L pt install -y
espera "-y com um navegador instalado não instala outro" nao_contem "$STUB_LOG" "install firefox"
: > "$STUB_LOG"
falso i7 -L pt install brave
espera "install NAVEGADOR instala a pedido" contem "$STUB_LOG" "brew install brave-browser"
HOME="$TMP/casa" PATH="$FF:$STUB:$GBREW:$TMP/sem:$PATH" roda i8 -L pt install firefox
espera "…e diz se ele já está instalado" contem i8 "já está instalado"
falso i9 -L pt instalar netscape
espera "navegador desconhecido é recusado" codigo "$RC" 2
if ! command -v brew >/dev/null 2>&1; then
  HOME="$TMP/casa" PATH="$STUB:$GAPT:$TMP/sem:$PATH" roda i10 -L pt install brave
  espera "fora dos repositórios, diz onde baixar" contem i10 "https://brave.com/download/"
fi
: > "$STUB_LOG"
PROGRAMA_NAVEGADOR=/nao/existe STUB_JS="node-22.1.0" G="$TMP/repos/solto/grabit.sh" falso i3 -L pt update
espera "update também não instala navegador" nao_contem "$STUB_LOG" "firefox"
HOME="$TMP/casa" PATH="$FF:$STUB:$GBREW:$TMP/sem:$PATH" STUB_JS="node-22.1.0" roda i4 -L pt install -y
espera "com um navegador instalado, nem o menciona" nao_contem i4 "Nenhum navegador"

if (( RAPIDO )); then
  printf '\n%d ok, %d falha(s)\n' "$N_OK" "${#FALHAS[@]}"
  (( ${#FALHAS[@]} == 0 ))
  exit
fi

# ───────────────────────────── Completos ───────────────────────────────────────
for p in yt-dlp ffmpeg ffprobe python3; do
  command -v "$p" >/dev/null 2>&1 || { printf '\nFalta %s para os testes completos (use --rapido).\n' "$p"; exit 1; }
done

secao "Contrato com o yt-dlp"
espera "o yt-dlp informa os runtimes no formato esperado" sh -c "yt-dlp -v --ignore-config 2>&1 | grep -qE '^\[debug\] JS runtimes: '"
if command -v pipx >/dev/null 2>&1 && pipx list --short 2>/dev/null | grep -q '^yt-dlp '; then
  espera "o pipx informa como o yt-dlp foi instalado" sh -c "pipx list --json | awk '/\"yt-dlp\": \{/ {y=1} y && /\"main_package\"/ {m=1} m && /\"package_or_url\"/ {print; exit}' | grep -q '\": \"yt-dlp'"
fi

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
mkdir -p "$W/referer" "$W/sessao"; cp "$W/curto.mp4" "$W/referer/"; cp "$W/curto.mp4" "$W/sessao/"
python3 - "$W/ruim.mp4" <<'EOF'
import random, sys
f = open(sys.argv[1], 'r+b'); t = f.seek(0, 2); r = random.Random(42)
for off in range(t // 3, t // 3 + 60000, 3000):   # estraga pedaços do meio, sempre iguais
    f.seek(off); f.write(bytes(r.randrange(256) for _ in range(200)))
EOF
hls p360 640x360; hls p720 1280x720
printf '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=400000,RESOLUTION=640x360\np360.m3u8\n#EXT-X-STREAM-INF:BANDWIDTH=900000,RESOLUTION=1280x720\np720.m3u8\n' > "$W/res/mestre.m3u8"
cp -R "$W/res" "$W/protegido"; cp -R "$W/res" "$W/bloq"; mkdir -p "$W/app"
cat > "$W/app/index.html" <<'EOF'
<!doctype html><html><head><title>App</title></head><body><div id="player"></div>
<script>fetch("/protegido/" + "mestre" + ".m3u8");</script></body></html>
EOF
cat > "$W/pagina/index.html" <<'EOF'
<!doctype html><html><head><title>Pagina de teste</title></head><body>
<video src="previa.mp4"></video><video src="principal.mp4"></video></body></html>
EOF
PORTA=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
cat > "$TMP/servidor.py" <<'EOF'
import functools, http.server, os, re, sys, time
class H(http.server.SimpleHTTPRequestHandler):      # /referer e /sessao imitam os vídeos protegidos
    def parcial(self):                               # pedidos parciais, como num servidor de verdade
        m = re.match(r"bytes=(\d+)-(\d*)$", self.headers.get("Range", ""))
        p = self.translate_path(self.path)
        if not m or not os.path.isfile(p):
            return False
        with open(os.path.join(self.directory, "pedidos.log"), "a") as f:
            f.write(f"{self.path} {m[0]}\n")
        if int(m[1]) > 0 and self.path.startswith("/recusa429/"):   # só as conexões extras são recusadas
            self.send_error(429)
            return True
        if int(m[1]) > 0 and self.path.startswith("/recusa403/"):
            self.send_error(403)
            return True
        t = os.path.getsize(p)
        ini, fim = int(m[1]), min(int(m[2] or t - 1), t - 1)
        if ini >= t:
            self.send_error(416)
            return True
        self.send_response(206)
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Last-Modified", self.date_time_string(int(os.path.getmtime(p))))
        self.send_header("Content-Type", self.guess_type(p))
        self.send_header("Content-Length", str(fim - ini + 1))
        self.send_header("Content-Range", f"bytes {ini}-{fim}/{t}")
        self.end_headers()
        with open(p, "rb") as f:
            f.seek(ini)
            try:
                self.wfile.write(f.read(fim - ini + 1))
            except OSError:
                pass
        return True
    def permitido(self):
        c = self.headers
        if self.path.startswith(("/referer/", "/protegido/")):
            return bool(c.get("Referer"))
        if self.path.startswith("/sessao/"):
            return "segredo=1" in c.get("Cookie", "") and c.get("User-Agent") == "Navegador/1.0" \
                and c.get("Referer", "").endswith("/player?ep=2")
        return True
    def do_GET(self):
        if self.path.startswith("/bloq/") and self.path.endswith(".ts"):
            return self.send_error(403)                  # a playlist abre, mas os pedaços são recusados
        if not self.permitido():
            return self.send_error(403)
        limita = self.path.startswith("/limita/") and self.headers.get("Want-Digest")   # limita só o aria2c
        lento = self.path.startswith("/lento/")            # /lento/: dá tempo de interromper no meio
        if limita or lento or self.path.startswith("/calmo/"):      # /calmo/: dá tempo de as outras conexões abrirem
            p = self.translate_path(self.path)
            t = os.path.getsize(p)
            ini, fim = 0, t - 1
            m = re.match(r"bytes=(\d+)-(\d*)$", self.headers.get("Range", ""))
            if m:
                ini, fim = int(m[1]), min(int(m[2] or t - 1), t - 1)
                with open(os.path.join(self.directory, "pedidos.log"), "a") as f:
                    f.write(f"{self.path} {m[0]}\n")
            bloco, pausa = (16384, 0.05) if limita else (65536, 0.02) if lento else (262144, 0.02)
            self.send_response(206 if m else 200)
            self.send_header("Accept-Ranges", "bytes")
            self.send_header("Last-Modified", self.date_time_string(int(os.path.getmtime(p))))
            self.send_header("Content-Length", str(fim - ini + 1))
            if m:
                self.send_header("Content-Range", f"bytes {ini}-{fim}/{t}")
            self.end_headers()
            with open(p, "rb") as f:
                f.seek(ini)
                r = fim - ini + 1
                try:
                    while r > 0 and (b := f.read(min(bloco, r))):
                        self.wfile.write(b)
                        r -= len(b)
                        time.sleep(pausa)
                except OSError:
                    pass
            return
        self.parcial() or super().do_GET()
    def do_HEAD(self):
        super().do_HEAD() if self.permitido() else self.send_error(403)
    def log_message(self, *a):
        pass
http.server.ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1])), functools.partial(H, directory=sys.argv[2])).serve_forever()
EOF
python3 "$TMP/servidor.py" "$PORTA" "$W" >/dev/null 2>&1 & SRV=$!
B="http://127.0.0.1:$PORTA"
for _ in 1 2 3 4 5 6 7 8 9 10; do python3 -c "import urllib.request; urllib.request.urlopen('$B/curto.mp4')" 2>/dev/null && break; sleep 0.3; done
export NO_PROXY="127.0.0.1,${NO_PROXY:-}" no_proxy="127.0.0.1,${no_proxy:-}"
altura() { ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 -- "$1" | cut -d, -f1; }
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
roda saida5 -L pt "$B/curto.mp4" -d -o ./Sub
espera "-d separa por site (e vale depois do link)" test -n "$(find Sub -path '*127.0.0.1*' -name '*.mkv')"

secao "Vídeos protegidos"
D="$TMP/d6"; mkdir -p "$D"; cd "$D" || exit 1
roda saida1 -L pt -o ./Ref "$B/referer/curto.mp4"
espera "vídeo que exige Referer baixa na nova tentativa" test -f "Ref/curto [curto].mkv"
roda saida2 -L pt -o ./Ses "$B/sessao/curto.mp4"
espera "vídeo que exige a sessão falha sem ela" codigo "$RC" 1
printf "curl '%s' --compressed -H 'User-Agent: Navegador/1.0' -H 'Referer: %s' -H 'Cookie: a=b; segredo=1' -H 'Range: bytes=0-'\n" \
  "$B/sessao/curto.mp4" "$B/player?ep=2" > copiado.txt
roda saida3 -L pt curl copiado.txt -o ./Ses
espera "…e baixa com o cURL copiado do navegador" test -n "$(find Ses -name '*player ep 2*.mkv')"
INICIO=$SECONDS
XDG_DATA_HOME="$TMP/bloqueio" roda saida5 -L pt -o ./Bloq "$B/bloq/p360.m3u8"
espera "pedaços recusados: desiste em menos de 1 minuto" test $(( SECONDS - INICIO )) -lt 60
espera "…e explica" contem saida5 "403"
for par in "firefox|--headless" "google-chrome|--headless=new --no-sandbox" "chromium|--headless=new --no-sandbox"; do
  prog=${par%%|*}
  command -v "$prog" >/dev/null 2>&1 || continue
  USAR_NAVEGADOR=1 PROGRAMA_NAVEGADOR=$prog GRABIT_NAVEGADOR_OPCOES=${par#*|} GRABIT_NAVEGADOR_ESPERA=90 XDG_DATA_HOME="$TMP/navreal-$prog" \
    roda "saida-$prog" -L pt -o "./App-$prog" "$B/app/index.html"
  espera "página em JavaScript com vídeo protegido: o $prog de verdade acha e o GrabIt baixa" \
    test -n "$(find "App-$prog" -name '*app index html*.mkv')"
  espera "…na melhor resolução" codigo "$(altura "$(find "App-$prog" -name '*.mkv' | head -n 1)")" 720
done

secao "O vídeo chega como o site entrega"
D="$TMP/d7"; mkdir -p "$D"; cd "$D" || exit 1
imagens() { ffmpeg -v error -i "$1" -map 0:v:0 -f framemd5 - | grep -v '^#' | awk -F, '{print $NF}' | cksum; }
roda saida1 -L pt -o ./V "$B/longo.mp4" "$B/res/p720.m3u8"
espera "arquivo direto: as imagens são idênticas, quadro a quadro" test "$(imagens "V/longo [longo].mkv")" = "$(imagens "$W/longo.mp4")"
ffmpeg -v error -y -i "$W/res/p720.m3u8" -c copy p720.ts
espera "stream: idem" test "$(imagens "$(find V -name '*p720*.mkv' | head -n 1)")" = "$(imagens p720.ts)"

secao "Arquivo direto melhor que o stream"
D="$TMP/d8"; mkdir -p "$D" "$W/dir"; cd "$D" || exit 1
video "$W/dir/video720.mp4" 1280x720 2
video "$W/dir/video180.mp4" 320x180 2
video "$W/dir/filme_inteiro.mp4" 1280x720 9
ffmpeg -loglevel error -y -i "$W/dir/video720.mp4" -an -c copy "$W/dir/mudo.mp4"
ffmpeg -loglevel error -y -f lavfi -i "testsrc2=size=640x360:rate=60:duration=2" -f lavfi -i "sine=duration=2" \
  -c:v libx264 -preset ultrafast -c:a aac -shortest "$W/dir/video60.mp4"
ffmpeg -loglevel error -y -f lavfi -i "testsrc2=size=160x90:rate=10:duration=31" -f lavfi -i "sine=duration=31" \
  -c:v libx264 -preset ultrafast -c:a aac -shortest "$W/dir/longo31.mp4"
pagina() {                                    # pagina NOME CORPO → $B/dir/NOME.html, com o stream de 360p
  printf '<!doctype html><html><head><title>Titulo: %s</title></head><body>%s</body></html>\n' "$1" "$2" > "$W/dir/$1.html"
}
printf '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=400000,RESOLUTION=640x360\np360.m3u8\n' > "$W/res/so360.m3u8"   # com a resolução informada
STREAM='<video controls src="/res/so360.m3u8"></video>'
pagina fontes '<video controls><source src="/dir/video720.mp4" type="video/mp4"><source src="/res/so360.m3u8" type="application/x-mpegURL"></video>'
pagina script "$STREAM<script>var p={\"file\":\"http:\\/\\/127.0.0.1:$PORTA\\/dir\\/video720.mp4\"};</script>"
pagina botao "$STREAM<a href=\"video720.mp4\" download>Baixar</a>"
pagina fps "$STREAM<a href=\"/dir/video60.mp4\">Baixar</a>"
pagina outro_video "$STREAM<a href=\"/dir/filme_inteiro.mp4\">Filme</a>"
pagina sem_audio "$STREAM<a href=\"/dir/mudo.mp4\">Baixar</a>"
pagina menor "$STREAM<a href=\"/dir/video180.mp4\">Baixar</a>"
pagina quebrado "$STREAM<a href=\"/dir/nao-existe.mp4\">Baixar</a>"
pagina comando "$STREAM<a href=\"/\$(touch invadiu)/\`touch invadiu\`.mp4\">Baixar</a>"
pagina so_script '<div id="player"></div><script>carrega("/dir/longo31.mp4")</script>'
pagina so_previa '<div id="player"></div><script>carrega("/dir/video720.mp4")</script>'
acha() { find "$1" -name '*.mkv' -print -quit; }
for c in fontes script botao; do
  XDG_DATA_HOME="$TMP/dir-$c" roda "s-$c" -L pt -o "./$c" "$B/dir/$c.html"
  espera "$c: baixa o .mp4 de 720p, não o stream de 360p" codigo "$(altura "$(acha "$c")")" 720
done
espera "da oferta do site: só muda o formato, e o histórico segue normal" contem fontes/.grabit-historico.txt "fontes"
espera "…avisa o que escolheu e por quê" contem s-botao "720p · 30 fps"
espera "…e mantém o título da página" contem s-botao "Titulo: botao"
espera "…também nos metadados" sh -c "ffprobe -v error -show_entries format_tags=title -of csv=p=0 \"\$(find botao -name '*.mkv' | head -n 1)\" | grep -q 'Titulo: botao'"
roda s-botao2 -L pt -o ./botao "$B/dir/botao.html"
espera "na próxima vez, a página já conta como baixada" contem s-botao2 "já baixado antes"
roda s-fps -L pt -o ./fps "$B/dir/fps.html"
espera "mesma resolução e mais quadros: fica com o .mp4" test "$(ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate -of csv=p=0 "$(acha fps)")" = 60/1
for c in outro_video sem_audio menor quebrado comando; do
  roda "s-$c" -L pt -o "./$c" "$B/dir/$c.html"
  case $c in
    outro_video) d="duração diferente: é outro vídeo" ;;
    sem_audio)   d="sem áudio: não serve" ;;
    menor)       d="resolução menor: não serve" ;;
    quebrado)    d="arquivo que não abre: fica o stream" ;;
    comando)     d='um "$(…)" no link da página não vira candidato' ;;
  esac
  espera "$d" codigo "$(altura "$(acha "$c")")" 360
done
espera "…nem executa nada" test ! -e invadiu
PROCURAR_ARQUIVO=0 roda s-desligado -L pt -o ./desligado "$B/dir/fontes.html"
espera "PROCURAR_ARQUIVO=0 não procura" codigo "$(altura "$(acha desligado)")" 360
roda s-midia -L pt -m -o ./midia "$B/dir/botao.html"
espera "a biblioteca do -m não troca: um arquivo solto não informa canal e data" codigo "$(altura "$(acha midia)")" 360
roda s-so -L pt -o ./so "$B/dir/so_script.html"
espera "página que o yt-dlp não abre, sem <video>: acha no script" codigo "$RC" 0
espera "…com o título da página" test -n "$(find so -name '*Titulo*so_script*.mkv')"
roda s-previa -L pt -o ./previa "$B/dir/so_previa.html"
espera "…mas um vídeo de poucos segundos pode ser só uma prévia: não basta" codigo "$RC" 1
mkdir -p "$TMP/cortado"; printf 'x\nx\nx\n' > cortado.site
bash "$G" --procura-direto "$PWD/marca" 0 "$PWD/cortado.site" "" 0 "$B/dir/botao.html" T generic a "$B/res/p360.m3u8" m3u8_native \
  360 640 30 400 2 SDR aac NA NA >/dev/null 2>&1
espera "site sem nada três vezes seguidas: não pede mais a página" test ! -e marca
bash "$G" --procura-direto "$PWD/marca" 0 "$PWD/vazio.site" "" 0 "$B/dir/botao.html" T generic a "$B/res/p360.m3u8" m3u8_native \
  360 640 30 400 2 SDR aac 5 NA >/dev/null 2>&1
espera "um vídeo de uma lista longa: não procura (a página fala de vários)" test ! -e marca

# Qualquer formato de arquivo vale, e o que decide é a medida
filme() { ffmpeg -loglevel error -y -f lavfi -i "testsrc2=size=1280x720:rate=25:duration=2" -f lavfi -i "sine=duration=2" "$@" </dev/null; }
filme -c:v mpeg4 -c:a mp2 "$W/dir/filme.avi"
filme -c:v wmv2 -c:a wmav2 "$W/dir/filme.wmv"
filme -c:v flv -c:a aac -ar 44100 "$W/dir/filme.flv"
filme -c:v mpeg2video -c:a mp2 "$W/dir/filme.mpg"
for e in mkv mov ts; do filme -c:v libx264 -preset ultrafast -c:a aac "$W/dir/filme.$e"; done
ln -f "$W/dir/filme.mkv" "$W/dir/GRANDE.MKV"
for e in avi wmv flv mpg mkv mov ts; do
  pagina "f_$e" "$STREAM<a href=\"/dir/filme.$e\">Baixar</a>"
  roda "s-f_$e" -L pt -o "./f_$e" "$B/dir/f_$e.html"
  espera ".$e citado na página: baixa o arquivo de 720p, em MKV" codigo "$(altura "$(acha "f_$e")")" 720
done
pagina maiuscula "$STREAM<a href=\"/dir/GRANDE.MKV\">Baixar</a>"
roda s-maiuscula -L pt -o ./maiuscula "$B/dir/maiuscula.html"
espera ".MKV em maiúsculas: idem" codigo "$(altura "$(find maiuscula -iname '*.mkv' -print -quit)")" 720
roda s-mpg -L pt -o ./mpg_direto "$B/dir/filme.mpg"
espera "um link direto para um .mpg também vira MKV" codigo "$(altura "$(acha mpg_direto)")" 720

for i in 144 240 270 360 480; do ln -f "$W/dir/video180.mp4" "$W/dir/qual_$i.mp4"; done
ln -f "$W/dir/video720.mp4" "$W/dir/qual_1080.mp4"
for i in 1 2 3 4; do ln -f "$W/dir/video180.mp4" "$W/dir/parte$i.mp4"; ln -f "$W/dir/filme.ts" "$W/dir/pedaco$i.ts"; done
ln -f "$W/dir/filme.mkv" "$W/dir/original.mkv"
pagina muitos "$STREAM<script>var f=[\"/dir/qual_144.mp4\",\"/dir/qual_240.mp4\",\"/dir/qual_270.mp4\",\"/dir/qual_360.mp4\",\"/dir/qual_480.mp4\",\"/dir/qual_1080.mp4\"]</script>"
pagina o_original "$STREAM<script>var f=[\"/dir/parte1.mp4\",\"/dir/parte2.mp4\",\"/dir/parte3.mp4\",\"/dir/parte4.mp4\",\"/dir/original.mkv\"]</script>"
pagina pedacos "$STREAM<script>var f=[\"/dir/pedaco1.ts\",\"/dir/pedaco2.ts\",\"/dir/pedaco3.ts\",\"/dir/pedaco4.ts\"]</script>"
ln -f "$W/dir/video720.mp4" "$W/dir/video720.mov"
pagina nome_de_site "$STREAM<script>var f=\"/dir/video720.mov/pagina.html\"</script>"
mkdir -p "$W/dir/baixar"; cp "$W/dir/video720.mp4" "$W/dir/baixar/123"; cp "$W/res/p720.m3u8" "$W/res/semext"
pagina sem_extensao "$STREAM<a href=\"/dir/baixar/123\" download>Baixar</a>"
pagina link_comum "$STREAM<a href=\"/dir/baixar/123\">Episódio</a>"
pagina outro_stream "$STREAM<a href=\"/res/semext\" download>Baixar</a>"
for c in muitos:720:"mais de 4 citados: mede antes o que promete ser o maior" \
         o_original:720:"…e o que se diz original, mesmo sendo o último" \
         pedacos:360:"vários .ts são pedaços de um stream, não um arquivo" \
         nome_de_site:360:".mov no meio do endereço não é arquivo" \
         sem_extensao:720:"botão de baixar sem extensão no endereço: mede e baixa" \
         link_comum:360:"…um link qualquer sem extensão não merece um pedido" \
         outro_stream:360:"…e um stream com cara de arquivo não conta"; do
  n=${c%%:*}; r=${c#*:}; e=${r%%:*}; d=${r#*:}
  roda "s-$n" -L pt -o "./$n" "$B/dir/$n.html"
  espera "$d" codigo "$(altura "$(acha "$n")")" "$e"
done

# Mesma imagem: só perde se for claramente mais leve (640x360, 30 fps e 2 s, como o stream informado)
ffmpeg -loglevel error -y -f lavfi -i "testsrc2=size=640x360:rate=30:duration=2" -f lavfi -i "sine=duration=2" \
  -c:v libx264 -preset ultrafast -c:a aac -shortest "$W/dir/igual.mp4"
pagina igual "$STREAM<a href=\"/dir/igual.mp4\">Baixar</a>"
KB=$(( $(ffprobe -v error -show_entries format=bit_rate -of csv=p=0 "$W/dir/igual.mp4") / 1000 ))
compara() {                                   # compara BITRATE_INFORMADO CODEC_INFORMADO
  rm -f marca
  bash "$G" --procura-direto "$PWD/marca" 0 "$PWD/compara.site" "" 0 "$B/dir/igual.html" T generic a "$B/res/p360.m3u8" m3u8_native \
    360 640 30 "$1" 2 SDR aac NA NA "$2" >/dev/null 2>&1
}
compara $(( KB * 100 / 80 )) avc1.64001f
espera "stream informa 25% acima (costuma ser o pico): fica o arquivo" test -s marca
compara $(( KB * 2 )) avc1.64001f
espera "stream com o dobro do bitrate: o arquivo é uma versão mais leve" test ! -e marca
compara 0 NA
espera "stream sem bitrate para comparar: fica o arquivo" test -s marca
compara $(( KB * 16 / 10 )) mp4v.20.2
espera "codec antigo no stream: o número maior não vale tanto" test -s marca
compara "$KB" hvc1.1.6.L93.B0
espera "HEVC no stream: o mesmo número vale mais" test ! -e marca
pronto() { printf '@@D@@360\x1f30\x1fSDR\x1fh264\x1faac\x1f%s\x1fCurto\x1fcurto\x1f%s' "$1" "$W/curto.mp4"; }
mkdir -p "$TMP/so-ytdlp"; ln -sf "$STUB/yt-dlp" "$TMP/so-ytdlp/yt-dlp"     # o ffprobe é o de verdade: é ele quem mede o arquivo
STUB_D=$(pronto 100) PATH="$TMP/so-ytdlp:$PATH" roda s-curto -L pt -o ./curto http://curto.invalid/1
espera "bem mais curto que o site informa: avisa" contem s-curto "mais curto"
STUB_D=$(pronto 2) PATH="$TMP/so-ytdlp:$PATH" roda s-igual -L pt -o ./igual http://curto.invalid/2
espera "…e não avisa à toa" nao_contem s-igual "mais curto"

secao "Formato do arquivo, de verdade"
D="$TMP/d9"; mkdir -p "$D" "$W/fmt"; cd "$D" || exit 1
ffmpeg -loglevel error -y -f lavfi -i "testsrc2=size=320x180:duration=1" -frames:v 1 "$W/fmt/capa.jpg"
video "$W/fmt/f.mp4" 640x360 2
ffmpeg -loglevel error -y -i "$W/fmt/f.mp4" -c copy "$W/fmt/f.mkv"
ffmpeg -loglevel error -y -i "$W/fmt/f.mp4" -c:v libvpx -deadline realtime -cpu-used 8 -c:a libopus "$W/fmt/f.webm"
for e in mp4 mkv webm; do
  printf '<!doctype html><html><head><title>Pagina %s</title><meta property="og:image" content="%s/fmt/capa.jpg"></head><body><video src="/fmt/f.%s"></video></body></html>\n' "$e" "$B" "$e" > "$W/fmt/p_$e.html"
done
faixas_de() { ffprobe -v error -show_entries stream=codec_name:stream_disposition=attached_pic -of csv=p=0 "$1" | tr '\n' ' '; }
so_um() { find "$1" -maxdepth 1 -type f -name "*.$2" -print -quit; }
tem_capa() { faixas_de "$1" | grep -q 'mjpeg,1'; }
roda s1 -L pt -O -o ./o1 "$B/fmt/p_mp4.html"
A=$(so_um o1 mp4)
espera "-O: o .mp4 continua .mp4" test -n "$A"
espera "…com as mesmas imagens" test "$(imagens "$A")" = "$(imagens "$W/fmt/f.mp4")"
espera "…com a capa dentro" tem_capa "$A"
espera "…sem a imagem sobrando na pasta" test -z "$(so_um o1 jpg)"
espera "…com o título" sh -c "ffprobe -v error -show_entries format_tags=title -of csv=p=0 \"\$1\" | grep -q Pagina" _ "$A"
espera "…sem nada a avisar" nao_contem s1 "não guarda"
roda s2 -L pt -O -o ./o2 "$B/fmt/p_webm.html"
espera "-O em .webm, que não aceita capa: o vídeo chega" test -n "$(so_um o2 webm)"
espera "…e a capa fica ao lado, com um aviso" contem s2 ".webm não guarda: capa"
espera "…sem virar erro" codigo "$RC" 0
espera "…a imagem está lá" test -n "$(so_um o2 jpg)"
roda s3 -L pt -e mp4 -o ./o3 "$B/fmt/p_mkv.html"
A=$(so_um o3 mp4)
espera "-e mp4 num .mkv: vira .mp4" test -n "$A"
espera "…e o .mkv não fica" test -z "$(so_um o3 mkv)"
espera "…com as mesmas imagens" test "$(imagens "$A")" = "$(imagens "$W/fmt/f.mkv")"
espera "…e com a capa" tem_capa "$A"
roda s4 -L pt -e webm -o ./o4 "$B/fmt/p_mp4.html"
A=$(so_um o4 mp4)
espera "-e webm com H.264, que não cabe: o vídeo não se perde" test -n "$A"
espera "…e o motivo aparece" contem s4 "não deu para deixar em .webm"
espera "…sem virar erro" codigo "$RC" 0
espera "…a capa entra no formato em que ele ficou" tem_capa "$A"
roda s5 -L pt -k h264 -o ./o5 "$B/fmt/p_webm.html"
A=$(so_um o5 mkv)
espera "-k h264 num .webm: recomprime depois de baixar" sh -c "ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 \"\$1\" | grep -q h264" _ "$A"
espera "…sem deixar a versão anterior" test "$(find o5 -maxdepth 1 -type f ! -name '.*' | wc -l)" -eq 1
espera "…e mantém a capa" tem_capa "$A"
espera "…e sai no resumo" contem s5 "Convertidos"
roda s6 -L pt -k h264 -O -o ./o6 "$B/fmt/p_mp4.html"
A=$(so_um o6 mp4)
espera "-k num vídeo já nesse codec: não recomprime" test "$(imagens "$A")" = "$(imagens "$W/fmt/f.mp4")"
espera "…nem fala em conversão como se tivesse feito" nao_contem s6 "Convertidos         1"

secao "Conversão de um vídeo já baixado"
D="$TMP/d10"; mkdir -p "$D"; cd "$D" || exit 1
roda sb -L pt -o ./base "$B/fmt/p_mp4.html"
V=$(so_um base mkv); cp "$V" "v [x].mkv"; REF=$(imagens "v [x].mkv")
intervalos() { ffprobe -v error -select_streams v:0 -show_entries packet=pts_time -of csv=p=0 "$1" | sort -n | awk 'NR>1 { printf "%.1f\n", ($1 - p) * 1000 } { p = $1 }' | sort -u | tr '\n' ' '; }
espera "o MKV arredonda o tempo de cada quadro (é o que motiva o resto)" test "$(intervalos "v [x].mkv")" = "33.0 34.0 "
roda c1 -L pt converter "v [x].mkv" -e mp4
espera "troca a extensão" test -f "v [x].mp4"
espera "…com as mesmas imagens" test "$(imagens "v [x].mp4")" = "$REF"
espera "…com o tempo exato de cada quadro de volta" test "$(intervalos "v [x].mp4")" = "33.3 "
espera "…e diz que restaurou" contem c1 "tempo de cada quadro restaurado"
espera "…com a capa" tem_capa "v [x].mp4"
espera "…e avisa o que o .mp4 não guarda" contem c1 ".mp4 não guarda: dados do site"
espera "o original fica" test -f "v [x].mkv"
roda c2 -L pt converter "v [x].mkv" -e mp4
espera "não sobrescreve o que já existe" contem c2 "já existe"
roda c3 -L pt converter "v [x].mp4" -e mp4
espera "já está nesse formato: nada a fazer" contem c3 "já está assim"
mkdir t; cp "v [x].mp4" t/a.mp4
roda c4 -L en convert t/a.mp4 --format mkv --replace
espera "ida e volta: as imagens continuam as mesmas" test "$(imagens t/a.mkv)" = "$REF"
espera "…a capa continua sendo capa" tem_capa t/a.mkv
espera "--replace tira o original" test ! -e t/a.mp4
espera "…e não deixa temporário" test -z "$(find t -name '*grabit-tmp*')"
for e in mov mkv mp4 ts; do
  case $e in ts) x=ts ;; *) x=$e ;; esac
  roda c5 -L pt converter t/a.* -e "$x" --substituir
  espera "de novo, em .$x: as imagens continuam as mesmas" test "$(imagens "t/a.$x")" = "$REF"
done
roda c6 -L pt converter "v [x].mp4" -e webm
espera "H.264 em .webm não existe sem recomprimir: é erro" codigo "$RC" 1
espera "…explicado" contem c6 "com -k, dá para recomprimir"
espera "…e nada fica pela metade" test -z "$(find . -name '*grabit-tmp*')"
roda c7 -L pt converter "v [x].mp4" -e webm -k vp9
espera "com -k, dá" sh -c "ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 'v [x].webm' | grep -q vp9"
roda c8 -L pt converter "v [x].mp4" -k h264
espera "recomprimir para o codec em que ele já está: não faz" contem c8 "já está assim"
roda c9 -L pt converter "v [x].webm" -k h264
espera "recomprime: um codec novo que não cabe na embalagem antiga vira .mp4" test -f "v [x].mp4"
espera "…sem sobrescrever o que já havia" contem c9 "já existe"
cp "v [x].webm" w.webm
roda c10 -L pt converter w.webm -k h264
espera "…e, sem nada no caminho, ele sai" sh -c "ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 w.mp4 | grep -q h264"
cp "v [x].mp4" m.mp4
roda c11 -L pt converter m.mp4 -k hevc
espera "recomprime na mesma embalagem: o original fica, e o novo leva o nome do codec" test -f m.hevc.mp4 -a -f m.mp4
roda c12 -L pt converter ./base -e mp4
espera "uma pasta inteira" contem c12 "Convertidos"

if command -v aria2c >/dev/null 2>&1; then
  secao "Várias conexões, de verdade"
  D="$TMP/d11"; mkdir -p "$D"; cd "$D" || exit 1
  ffmpeg -loglevel error -y -f lavfi -i "testsrc2=size=1280x720:rate=30:duration=45" -f lavfi -i "sine=duration=45" \
    -c:v libx264 -preset ultrafast -b:v 11M -c:a aac "$W/grande.mp4"
  for r in recusa429 recusa403 limita calmo; do ln -sfn . "$W/$r"; done
  REF=$(imagens "$W/grande.mp4")
  : > "$W/pedidos.log"
  roda s1 -L pt -O -o ./a "$B/calmo/grande.mp4"
  # (60 MiB, com o mínimo de 20 MiB por parte: a primeira conexão mais um pedido parcial)
  espera "um arquivo grande vem em várias partes" test "$(grep -c '^/calmo/grande.mp4 bytes=' "$W/pedidos.log")" -ge 1
  espera "…e chega inteiro, com as mesmas imagens" test "$(imagens "$(so_um a mp4)")" = "$REF"
  : > "$W/pedidos.log"
  roda s2 -L pt -O -c 1 -o ./b "$B/grande.mp4"
  espera "-c 1: nenhuma parte" test "$(grep -c '^/grande.mp4' "$W/pedidos.log")" -eq 0
  : > "$W/pedidos.log"
  roda s3 -L pt -O -o ./c1 "$B/curto.mp4"
  espera "um arquivo pequeno não se divide" test "$(grep -c '^/curto.mp4 bytes=[1-9]' "$W/pedidos.log")" -eq 0
  for c in 429 403; do
    : > "$W/pedidos.log"
    roda s4 -L pt -O -j 1 -o "./r$c" "$B/recusa$c/grande.mp4" "$B/recusa$c/curto.mp4"
    espera "site que recusa as partes ($c): o download termina nas conexões que sobraram" test "$(imagens "$(find "r$c" -maxdepth 1 -name 'grande*.mp4' -print -quit)")" = "$REF"
    espera "…sem erro" codigo "$RC" 0
    espera "…com um aviso" contem s4 "recusou as conexões extras"
  done
  roda s5 -L pt -O -o ./l "$B/limita/grande.mp4"
  espera "o site limita quem abre várias conexões: a sonda percebe" contem s5 "rende mais com uma conexão só"
  espera "…e o download sai sem elas" test "$(imagens "$(so_um l mp4)")" = "$REF"
  espera "…sem erro" codigo "$RC" 0
  espera "…e sem marcar o site como difícil" nao_contem "$XDG_DATA_HOME/grabit/metodos.txt" "127.0.0.1"
fi

secao "Proxy, de verdade"
# Um nome que só o proxy conhece: quem tentasse ir direto ao site nem acharia o endereço.
D="$TMP/d12"; mkdir -p "$D"; cd "$D" || exit 1
PORTA_P=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
cat > "$TMP/proxy.py" <<'EOF'
import http.server, shutil, sys, urllib.error, urllib.parse, urllib.request
porta, destino, log = int(sys.argv[1]), sys.argv[2], sys.argv[3]
direto = urllib.request.build_opener(urllib.request.ProxyHandler({}))
class P(http.server.BaseHTTPRequestHandler):
    def repassa(self):
        u = urllib.parse.urlsplit(self.path)
        with open(log, "a") as f:
            f.write(f"{self.command} {u.netloc} {u.path} {self.headers.get('User-Agent', '')}\n")
        c = {k: v for k, v in self.headers.items() if k.lower() not in ("host", "proxy-connection", "connection")}
        q = urllib.request.Request(destino + u.path + ("?" + u.query if u.query else ""), headers=c, method=self.command)
        try:
            r = direto.open(q)
        except urllib.error.HTTPError as e:
            r = e
        self.send_response(r.status)
        for k, v in r.headers.items():
            if k.lower() not in ("connection", "transfer-encoding", "server", "date"):
                self.send_header(k, v)
        self.end_headers()
        if self.command == "GET":
            try:
                shutil.copyfileobj(r, self.wfile)
            except OSError:
                pass
    do_GET = do_HEAD = repassa
    def log_message(self, *a):
        pass
http.server.ThreadingHTTPServer(("127.0.0.1", porta), P).serve_forever()
EOF
python3 "$TMP/proxy.py" "$PORTA_P" "$B" "$TMP/proxy.log" >/dev/null 2>&1 & SRV_P=$!
ate python3 -c "import socket; socket.create_connection(('127.0.0.1', $PORTA_P), 1)"
roda x1 -L pt -o ./a --proxy "http://127.0.0.1:$PORTA_P" http://so-pelo-proxy.invalid/dir/botao.html
espera "o vídeo vem pelo proxy" test -n "$(find a -name '*.mkv' -print -quit)"
espera "…a página é lida por ele" grep -qE '^GET so-pelo-proxy.invalid /dir/botao.html' "$TMP/proxy.log"
espera "…a medição do arquivo direto também" grep -qE 'so-pelo-proxy.invalid /dir/video720.mp4 Lavf' "$TMP/proxy.log"
espera "…e nada foi baixado do stream de 360p em vez dele" codigo "$(altura "$(find a -name '*.mkv' -print -quit)")" 720
kill "$SRV_P" 2>/dev/null

secao "Verificação da coleção (--verificar)"
D="$TMP/d5"; mkdir -p "$D"; cd "$D" || exit 1
roda saida1 -L pt -o ./Col "$B/curto.mp4" "$B/longo.mp4" "$B/res/mestre.m3u8"
python3 - "Col/longo [longo].mkv" <<'EOF2'
import random, sys
f = open(sys.argv[1], 'r+b'); t = f.seek(0, 2); r = random.Random(7)
for off in range(t // 3, t // 3 + 40000, 2500):
    f.seek(off); f.write(bytes(r.randrange(256) for _ in range(150)))
EOF2
# "incompleto": o info.json embutido passa a dizer 60 s, e o arquivo tem 2
F="Col/curto [curto].mkv"
ffmpeg -v quiet -y -dump_attachment:m:filename:info.json info.json -i "$F" 2>/dev/null
python3 -c "import json; d = json.load(open('info.json')); d['duration'] = 60; json.dump(d, open('info.json', 'w'))"
ffmpeg -v error -y -i "$F" -map 0 -map -0:t -c copy -attach info.json \
  -metadata:s:t:0 mimetype=application/json -metadata:s:t:0 filename=info.json Col/novo.mkv && mv Col/novo.mkv "$F"
cp "Col/mestre [mestre].mkv" Col/outro.m4v
roda saida2 -L pt --verificar Col
espera "com problemas, sai com código 1" codigo "$RC" 1
espera "acha o vídeo com defeito" grep -qE "longo .*com defeito" saida2
espera "acha o vídeo incompleto" grep -qE "curto .*incompleto" saida2
espera "…e diz quanto falta" contem saida2 "tem 00:02 de 01:00"
espera "o vídeo bom passa" grep -qE "✔ .*mestre" saida2
espera "outros formatos também são conferidos" grep -qE "✔ .*outro" saida2
espera "sem terminal, não baixa nada sozinho" test ! -e "Col/longo [longo].com-erros.mkv"
roda saida3 -L pt --verificar ./nao-existe
espera "pasta inexistente sai com código 1" codigo "$RC" 1

# ───────────────────────────── Resultado ───────────────────────────────────────
printf '\n%d ok, %d falha(s)\n' "$N_OK" "${#FALHAS[@]}"
(( ${#FALHAS[@]} == 0 ))
