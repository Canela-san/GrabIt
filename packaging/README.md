# Pacotes

A cada versão publicada, a CI atualiza a versão e as somas destes arquivos e os grava na `main`.

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
