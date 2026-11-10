#!/usr/bin/env bash
# ==============================================================================
#  Monta o pacote .deb do GrabIt e o repositório APT que o serve.
#
#    bash packaging/apt/construir.sh GRABIT_SH VERSÃO PASTA [CHAVE_GPG]
#
#  Em PASTA ficam grabit_VERSÃO_all.deb e, em PASTA/site, o repositório, pronto para
#  ir para um servidor estático como o GitHub Pages. Com CHAVE_GPG, ele é assinado.
#  Precisa de dpkg-deb, apt-ftparchive (pacote apt-utils) e gpg.
# ==============================================================================
set -euo pipefail

script=${1:?falta o grabit.sh}; versao=${2:?falta a versão}; saida=${3:?falta a pasta}; chave=${4:-}
raiz=$(cd -- "$(dirname -- "$0")/../.." && pwd)
url=${GRABIT_URL_APT:-https://canela-san.github.io/GrabIt}

mkdir -p "$saida"
saida=$(cd -- "$saida" && pwd)
pacote="$saida/pacote"
mkdir -p "$pacote/DEBIAN" "$pacote/usr/bin" "$pacote/usr/share/doc/grabit" \
  "$pacote/usr/share/bash-completion/completions" "$pacote/usr/share/zsh/vendor-completions" \
  "$pacote/usr/share/fish/vendor_completions.d" "$pacote/usr/share/man/man1" "$pacote/usr/share/man/pt/man1"

install -m 755 "$script" "$pacote/usr/bin/grabit"
install -m 644 "$raiz/LICENSE" "$pacote/usr/share/doc/grabit/copyright"
gzip -9nc "$raiz/CHANGELOG.md" > "$pacote/usr/share/doc/grabit/changelog.gz"
chmod 644 "$pacote/usr/share/doc/grabit/changelog.gz"

# O autocompletar é gerado na hora, pelo próprio GrabIt: assim ele vem no idioma de quem usa
printf 'eval "$(grabit completar bash)"\n' > "$pacote/usr/share/bash-completion/completions/grabit"
printf '#compdef grabit\neval "$(grabit completar zsh)"\n' > "$pacote/usr/share/zsh/vendor-completions/_grabit"
printf 'grabit completar fish | source\n' > "$pacote/usr/share/fish/vendor_completions.d/grabit.fish"
chmod 644 "$pacote"/usr/share/bash-completion/completions/grabit "$pacote"/usr/share/zsh/vendor-completions/_grabit \
  "$pacote"/usr/share/fish/vendor_completions.d/grabit.fish

# A página do man, feita da ajuda do próprio script: em inglês e, para quem usa o sistema em português, em português
GRABIT_CONFIG=/dev/null bash "$script" -L en manual | gzip -9n > "$pacote/usr/share/man/man1/grabit.1.gz"
GRABIT_CONFIG=/dev/null bash "$script" -L pt manual | gzip -9n > "$pacote/usr/share/man/pt/man1/grabit.1.gz"
chmod 644 "$pacote/usr/share/man/man1/grabit.1.gz" "$pacote/usr/share/man/pt/man1/grabit.1.gz"

# O yt-dlp fica de fora de propósito: o do apt costuma estar atrasado, e os sites mudam o tempo todo.
# Quem instala o mais novo é o "grabit install", pelo pipx.
tamanho=$(du -sk --exclude=DEBIAN "$pacote" | cut -f1)
cat > "$pacote/DEBIAN/control" <<EOF
Package: grabit
Version: $versao
Architecture: all
Maintainer: Canela-san <62998905+Canela-san@users.noreply.github.com>
Installed-Size: $tamanho
Depends: bash (>= 4.4), curl, ffmpeg
Recommends: aria2, pipx, python3
Suggests: wl-clipboard | xclip, firefox
Section: video
Priority: optional
Homepage: https://github.com/Canela-san/GrabIt
Description: Batch video downloader on top of yt-dlp, at the highest quality
 GrabIt downloads videos from almost any site, in batches, always at the
 highest quality the site offers, with a live panel in the terminal. After
 installing, run "grabit install" to get the newest yt-dlp.
EOF

deb="$saida/grabit_${versao}_all.deb"
dpkg-deb --root-owner-group --build "$pacote" "$deb" >/dev/null
rm -r -- "$pacote"

# ───── O repositório. O pacote serve para qualquer processador, mas o apt procura o índice do seu.
site="$saida/site"
mkdir -p "$site/pool/main/g/grabit"
cp "$deb" "$site/pool/main/g/grabit/"
cd "$site"
indice=$(apt-ftparchive packages pool)
for arq in amd64 arm64 armhf i386 all; do
  mkdir -p "dists/stable/main/binary-$arq"
  printf '%s\n' "$indice" > "dists/stable/main/binary-$arq/Packages"
  gzip -9nkf "dists/stable/main/binary-$arq/Packages"
done
apt-ftparchive \
  -o APT::FTPArchive::Release::Origin=GrabIt \
  -o APT::FTPArchive::Release::Label=GrabIt \
  -o APT::FTPArchive::Release::Suite=stable \
  -o APT::FTPArchive::Release::Codename=stable \
  -o APT::FTPArchive::Release::Components=main \
  -o "APT::FTPArchive::Release::Architectures=amd64 arm64 armhf i386 all" \
  release dists/stable > "$saida/Release"
mv "$saida/Release" dists/stable/Release

if [[ -n $chave ]]; then
  gpg --batch --yes --default-key "$chave" --clearsign -o dists/stable/InRelease dists/stable/Release
  gpg --batch --yes --default-key "$chave" -abs -o dists/stable/Release.gpg dists/stable/Release
  gpg --batch --yes --export "$chave" > grabit.gpg
fi

# ───── A página de quem abre o endereço no navegador
cat > index.html <<EOF
<!doctype html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>GrabIt: repositório APT</title>
<style>
  :root { color-scheme: light dark; }
  body { font: 16px/1.5 system-ui, sans-serif; max-width: 46rem; margin: 2rem auto; padding: 0 1rem; }
  pre { padding: 1rem; overflow-x: auto; background: rgba(127, 127, 127, .15); border-radius: .4rem; }
</style>
</head>
<body>
<h1>GrabIt</h1>
<p>Repositório APT para Debian, Ubuntu, Pop!_OS e derivados. Versão atual: <strong>$versao</strong>.</p>
<pre>curl -fsSL $url/grabit.gpg | sudo tee /usr/share/keyrings/grabit.gpg &gt; /dev/null
echo "deb [signed-by=/usr/share/keyrings/grabit.gpg] $url stable main" | sudo tee /etc/apt/sources.list.d/grabit.list
sudo apt update
sudo apt install grabit
grabit install</pre>
<p>Para atualizar: <code>sudo apt update &amp;&amp; sudo apt upgrade</code>.</p>
<p><a href="https://github.com/Canela-san/GrabIt">Código e documentação no GitHub</a></p>
</body>
</html>
EOF

printf '%s\n' "$deb"
