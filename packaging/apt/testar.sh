#!/usr/bin/env bash
# ==============================================================================
#  Testa o caminho inteiro do apt numa máquina descartável (contêiner ou CI), como root:
#  chave própria, repositório assinado num servidor local, apt install e apt upgrade.
#
#    bash packaging/apt/testar.sh
#
#  A rede só é usada no começo, e só se faltar alguma ferramenta do teste. Depois, o apt só enxerga o
#  repositório local do GrabIt: um servidor do Ubuntu fora do ar não trava o teste, e o apt upgrade não
#  baixa o sistema inteiro. GRABIT_ESPELHO_APT troca o servidor do Ubuntu dessa primeira parte.
# ==============================================================================
set -euo pipefail

raiz=$(cd -- "$(dirname -- "$0")/../.." && pwd)
export DEBIAN_FRONTEND=noninteractive
if [[ -n ${GRABIT_ESPELHO_APT:-} && -f /etc/apt/sources.list.d/ubuntu.sources ]]; then
  sed -i -E "s#https?://(archive|security)\.ubuntu\.com/ubuntu/?#$GRABIT_ESPELHO_APT#g" /etc/apt/sources.list.d/ubuntu.sources
fi
# As ferramentas do teste: só o que faltar (um contêiner limpo não tem nenhuma; o runner da CI tem todas)
falta=0
for p in apt-ftparchive gpg python3 curl; do command -v "$p" >/dev/null 2>&1 || falta=1; done
if (( falta )); then
  rede=(-o Acquire::Retries=3 -o Acquire::http::Timeout=20 -o Acquire::https::Timeout=20)
  apt-get "${rede[@]}" update -qq
  apt-get "${rede[@]}" install -y -qq --no-install-recommends apt-utils gnupg python3 curl ca-certificates >/dev/null
fi

trabalho=$(mktemp -d)

# Daqui em diante, nada de rede. O FFmpeg de verdade traz centenas de pacotes, e o que se testa aqui é o
# pacote do GrabIt e o repositório: um FFmpeg de mentira satisfaz a dependência. Os recomendados (aria2,
# pipx) ficam de fora sem erro, porque nenhum repositório os oferece.
mkdir -p "$trabalho/ffmpeg/DEBIAN"
printf 'Package: ffmpeg\nVersion: 99:0\nArchitecture: all\nMaintainer: Teste <teste@teste.invalid>\nDescription: FFmpeg de mentira, so para o teste\n' \
  > "$trabalho/ffmpeg/DEBIAN/control"
dpkg-deb --build "$trabalho/ffmpeg" "$trabalho/ffmpeg.deb" >/dev/null
dpkg -i "$trabalho/ffmpeg.deb" >/dev/null
mkdir -p "$trabalho/fontes-fora"
for f in /etc/apt/sources.list.d/*.sources /etc/apt/sources.list.d/*.list /etc/apt/sources.list; do
  [[ -f $f ]] && mv -- "$f" "$trabalho/fontes-fora/"
done
export GNUPGHOME="$trabalho/gnupg"
mkdir -m 700 "$GNUPGHOME"
gpg --batch --quiet --pinentry-mode loopback --passphrase '' --quick-generate-key 'Teste <teste@teste.invalid>' ed25519 sign never

porta=18770
export GRABIT_URL_APT="http://127.0.0.1:$porta"
versao=$(sed -n 's/^GRABIT_VERSAO=//p' "$raiz/grabit.sh")
bash "$raiz/packaging/apt/construir.sh" "$raiz/grabit.sh" "$versao" "$trabalho/v1" 'Teste' >/dev/null
# (o contêiner do Ubuntu não instala páginas do man: confere dentro do .deb)
dpkg-deb -c "$trabalho/v1/grabit_${versao}_all.deb" | grep -q 'usr/share/man/man1/grabit.1.gz'
dpkg-deb -c "$trabalho/v1/grabit_${versao}_all.deb" | grep -q 'usr/share/man/pt/man1/grabit.1.gz'

( cd "$trabalho/v1/site" && exec python3 -m http.server "$porta" --bind 127.0.0.1 >/dev/null 2>&1 ) &
servidor=$!
trap 'kill "$servidor" 2>/dev/null || true' EXIT
for _ in 1 2 3 4 5 6 7 8 9 10; do curl -fsS "$GRABIT_URL_APT/grabit.gpg" -o /dev/null 2>/dev/null && break; sleep 0.5; done

ok() { printf '  ✔ %s\n' "$1"; }
ok "o .deb traz a página do man, em inglês e em português"
# diz TEXTO COMANDO...: a saída do comando tem o texto? (um grep no fim de um pipe mataria o comando pelo meio)
diz() { local s; s=$("${@:2}" 2>&1) || true; [[ $s == *"$1"* ]]; }
falha() { printf '  ✖ %s\n' "$1"; exit 1; }

# Os comandos que o README manda rodar
curl -fsSL "$GRABIT_URL_APT/grabit.gpg" | tee /usr/share/keyrings/grabit.gpg > /dev/null
echo "deb [signed-by=/usr/share/keyrings/grabit.gpg] $GRABIT_URL_APT stable main" | tee /etc/apt/sources.list.d/grabit.list > /dev/null
apt-get update -qq
apt-get install -y -qq grabit >/dev/null
ok "apt install grabit"

[[ $(command -v grabit) == /usr/bin/grabit ]] || falha "o comando grabit fica em /usr/bin"
ok "o comando fica em /usr/bin/grabit"
diz 'grabit download' grabit -L pt || falha "grabit mostra a ajuda"
ok "grabit mostra a ajuda"
diz "$HOME/.config/grabit/grabit.config" grabit -L pt --config || falha "a configuração fica na pasta pessoal"
ok "a configuração fica na pasta pessoal"
[[ ! -e /usr/bin/grabit.config ]] || falha "nada de configuração em /usr/bin"
diz 'sudo apt update && sudo apt upgrade' grabit -L pt update || falha "grabit update aponta para o apt"
cmp -s /usr/bin/grabit "$raiz/grabit.sh" || falha "o grabit update não mexe no script"
ok "grabit update aponta para o apt e não mexe no script"
diz 'sudo apt remove grabit' grabit -L pt desinstalar -y || falha "grabit desinstalar aponta para o apt"
ok "grabit desinstalar aponta para o apt"
bash -c 'source /usr/share/bash-completion/completions/grabit; declare -F _grabit' >/dev/null || falha "autocompletar do bash"
ok "autocompletar do bash"

# Uma versão nova chega pelo apt upgrade
nova=99.0.0
sed "s/^GRABIT_VERSAO=.*/GRABIT_VERSAO=$nova/" "$raiz/grabit.sh" > "$trabalho/novo.sh"
kill "$servidor"; wait "$servidor" 2>/dev/null || true
bash "$raiz/packaging/apt/construir.sh" "$trabalho/novo.sh" "$nova" "$trabalho/v2" 'Teste' >/dev/null
( cd "$trabalho/v2/site" && exec python3 -m http.server "$porta" --bind 127.0.0.1 >/dev/null 2>&1 ) &
servidor=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do curl -fsS "$GRABIT_URL_APT/grabit.gpg" -o /dev/null 2>/dev/null && break; sleep 0.5; done
apt-get update -qq
apt-get upgrade -y -qq >/dev/null
[[ $(dpkg-query -W -f='${Version}' grabit) == "$nova" ]] || falha "apt upgrade traz a versão nova"
grep -qx "GRABIT_VERSAO=$nova" /usr/bin/grabit || falha "o script novo está no lugar"
ok "apt update && apt upgrade trazem a versão nova"

# Um índice adulterado é recusado: quem assina é o InRelease, o que o apt lê primeiro. O apt avisa e
# continua usando o índice anterior, que era válido
sed -i 's/^Origin: GrabIt/Origin: Falso/' "$trabalho/v2/site/dists/stable/InRelease"
LC_ALL=C diz 'signature verification' apt-get update || falha "índice adulterado é recusado"
ok "índice adulterado é recusado"

apt-get remove -y -qq grabit >/dev/null
[[ ! -e /usr/bin/grabit ]] || falha "apt remove tira o comando"
ok "apt remove tira o comando"
