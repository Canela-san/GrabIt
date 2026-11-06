# Pacotes

A cada versão publicada, a CI atualiza a versão e as somas destes arquivos e os grava na `main`.

## APT (Debian, Ubuntu, Pop!_OS)

O repositório fica no GitHub Pages, de graça, e é assinado com uma chave própria. A cada versão publicada, a CI monta o `.deb`, anexa à versão e publica o repositório: é o que faz `apt update && apt upgrade` trazer a versão nova.

Só uma coisa precisa ser feita à mão, uma vez, pelo dono do projeto, porque quem tem a chave pode publicar pacotes que os usuários instalam como root:

```bash
bash packaging/apt/criar-chave.sh
```

Ele cria a chave, guarda nos segredos do GitHub (`APT_GPG_KEY`), sem deixar cópia, liga o GitHub Pages e publica o repositório. Se um dia a chave vazar, apague o segredo, rode de novo, e quem já instalou precisa baixar a chave nova, com o primeiro comando da instalação.

Para testar o caminho inteiro numa máquina descartável, como root: `bash packaging/apt/testar.sh`.

## Homebrew

A fórmula fica em [`Formula/grabit.rb`](../Formula/grabit.rb), e o próprio repositório serve de tap:

```bash
brew tap Canela-san/grabit https://github.com/Canela-san/GrabIt
brew install grabit
```

## AUR

O AUR é um repositório à parte, com conta e chave SSH próprias. Para publicar a primeira vez:

```bash
git clone ssh://aur@aur.archlinux.org/grabit.git aur-grabit
cp packaging/aur/PKGBUILD packaging/aur/.SRCINFO aur-grabit/
cd aur-grabit
git add PKGBUILD .SRCINFO
git commit -m "grabit 1.0.0"
git push
```

Nas versões seguintes, é só repetir a cópia, o commit e o envio.
