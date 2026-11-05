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
espera "depois de -- nada é opção" grep -qE 'DOWNLOADS_SIMULTANEOS +2 ' "$TMP/pos3"

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
case " $* " in *" -N 1 "*) [ -z "${STUB_ERRO2:-}" ] || STUB_ERRO=$STUB_ERRO2 ;; esac   # a nova tentativa
case " $* " in *" -- https://video.n.invalid/"*) STUB_ERRO="" ;; esac                 # o vídeo achado pelo navegador
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
formas "instalação das dependências" instalar install
formas "GrabIt · atualização" atualizar update
formas "não existe" verificar check -- "$TMP/nao-existe"
formas "seção BAIXADOS" baixados downloaded -- -l "$L"
formas "cópia sem Git" versao versão version
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

secao "Novas tentativas por outro caminho"
D="$TMP/tentativas"; mkdir -p "$D"; cd "$D" || exit 1
tentou() { grep -F -- "$1" "$STUB_LOG" | grep -qF -- "$2"; }
vezes() { grep -cF -- "$1" "$STUB_LOG"; }
: > "$STUB_LOG"
STUB_ERRO="[generic] Got HTTP Error 403 caused by Cloudflare anti-bot challenge; try again" \
  STUB_ERRO2="[generic] x: Unable to download webpage: HTTP Error 403: Forbidden" falso t1 -L pt http://t.invalid/cf
espera "verificação anti-robô é explicada, mesmo com a 2ª tentativa dizendo só 403" contem t1 "verificação anti-robô"
espera "…e diz como baixar pelo navegador" contem t1 "Copiar como cURL"
espera "a nova tentativa usa uma conexão por vez" tentou t.invalid/cf "-N 1"
espera "…e manda o Referer" tentou t.invalid/cf "--referer http://t.invalid/cf"
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
: > "$STUB_LOG"
STUB_ERRO="Unsupported URL: https://n.invalid/js" nav n2 -L pt https://n.invalid/js
espera "player em JavaScript: vai direto ao navegador" test "$(grep -c -- '-- https://n.invalid/js' "$STUB_LOG")" -eq 1
espera "…e baixa" tentou video.n.invalid "--no-download-archive"
: > "$STUB_LOG"
STUB_ERRO="HTTP Error 404: Not Found" nav n3 -L pt https://n.invalid/404
espera "erro que um navegador não resolve não abre janela" nao_contem "$STUB_LOG" "firefox "
: > "$STUB_LOG"
STUB_ERRO="Unsupported URL: https://n.invalid/x" STUB_FF_FECHA=1 nav n4 -L pt https://n.invalid/x
espera "janela fechada sem vídeo: explica" contem n4 "nenhum vídeo apareceu no navegador"
espera "…sem insistir" test "$(grep -c '^firefox --no-remote' "$STUB_LOG")" -eq 1
espera "…e sai com código 1" codigo "$RC" 1
: > "$STUB_LOG"
STUB_ERRO="Unsupported URL: https://n.invalid/y" USAR_NAVEGADOR=0 GRABIT_NAVEGADOR_OPCOES=--headless PATH="$FF:$STUB:$GBREW:$TMP/sem:$PATH" HOME="$TMP/casa" roda n5 -L pt https://n.invalid/y
espera "USAR_NAVEGADOR=0: não abre" nao_contem "$STUB_LOG" "firefox "
: > "$STUB_LOG"
STUB_ERRO="Unsupported URL: https://n.invalid/z" USAR_NAVEGADOR=1 PATH="$FF:$STUB:$GBREW:$TMP/sem:$PATH" HOME="$TMP/casa" roda n6 -L pt https://n.invalid/z
espera "sem terminal nem tela, ninguém veria a janela: não abre" nao_contem "$STUB_LOG" "firefox "

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
cp -R "$W/res" "$W/protegido"; mkdir -p "$W/app"
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
import functools, http.server, sys
class H(http.server.SimpleHTTPRequestHandler):      # /referer e /sessao imitam os vídeos protegidos
    def permitido(self):
        c = self.headers
        if self.path.startswith(("/referer/", "/protegido/")):
            return bool(c.get("Referer"))
        if self.path.startswith("/sessao/"):
            return "segredo=1" in c.get("Cookie", "") and c.get("User-Agent") == "Navegador/1.0" \
                and c.get("Referer", "").endswith("/player?ep=2")
        return True
    def do_GET(self):
        super().do_GET() if self.permitido() else self.send_error(403)
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
if command -v firefox >/dev/null 2>&1; then
  USAR_NAVEGADOR=1 GRABIT_NAVEGADOR_OPCOES=--headless GRABIT_NAVEGADOR_ESPERA=90 XDG_DATA_HOME="$TMP/navreal" \
    roda saida4 -L pt -o ./App "$B/app/index.html"
  espera "página em JavaScript com vídeo protegido: o Firefox de verdade acha e o GrabIt baixa" \
    test -n "$(find App -name '*app index html*.mkv')"
  espera "…na melhor resolução" codigo "$(altura "$(find App -name '*.mkv' | head -n 1)")" 720
fi

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
