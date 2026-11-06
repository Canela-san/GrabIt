#!/usr/bin/env bash
# ==============================================================================
#  Prepara o repositório APT do GrabIt. Roda uma vez só, na máquina do dono do projeto.
#
#    bash packaging/apt/criar-chave.sh
#
#  Quem tem esta chave pode publicar pacotes que os usuários instalam como root. Por isso
#  ela é criada aqui, vai direto para os segredos do GitHub e não fica em lugar nenhum:
#  nem no disco, nem na tela. Depois, o script liga o GitHub Pages e publica o repositório.
# ==============================================================================
set -euo pipefail

repo=Canela-san/GrabIt
identidade='GrabIt APT <62998905+Canela-san@users.noreply.github.com>'

for prog in gh gpg gpgconf; do
  command -v "$prog" >/dev/null 2>&1 || { printf 'Falta o programa: %s\n' "$prog" >&2; exit 1; }
done
gh auth status >/dev/null 2>&1 || { printf 'Entre no GitHub primeiro: gh auth login\n' >&2; exit 1; }

if gh secret list --repo "$repo" | grep -q '^APT_GPG_KEY[[:space:]]'; then
  printf '✔ A chave já existe nos segredos do repositório: nada a criar.\n'
else
  casa=$(mktemp -d)
  trap 'gpgconf --homedir "$casa" --kill all 2>/dev/null || true; rm -rf -- "$casa"' EXIT
  chmod 700 "$casa"
  export GNUPGHOME=$casa
  gpg --batch --quiet --pinentry-mode loopback --passphrase '' --quick-generate-key "$identidade" ed25519 sign never
  gpg --batch --armor --export-secret-keys "$identidade" | gh secret set APT_GPG_KEY --repo "$repo"
  printf '✔ Chave criada e guardada nos segredos do repositório.\n'
  gpg --batch --fingerprint "$identidade" | sed -n '2p' | sed 's/^ */  Impressão digital: /'
fi

# O Pages publica o que o workflow mandar (409 = já estava ligado)
if gh api --silent -X POST "repos/$repo/pages" -f build_type=workflow 2>/dev/null; then
  printf '✔ GitHub Pages ligado.\n'
else
  gh api --silent -X PUT "repos/$repo/pages" -f build_type=workflow
  printf '✔ GitHub Pages já estava ligado.\n'
fi

if gh release view --repo "$repo" >/dev/null 2>&1; then
  gh workflow run repositorio-apt.yml --repo "$repo" --ref main
  printf '✔ Publicação do repositório iniciada: leva poucos minutos.\n'
  printf '  Acompanhe em: https://github.com/%s/actions/workflows/repositorio-apt.yml\n' "$repo"
else
  printf '… Ainda não há versão publicada: o repositório sai junto com a primeira.\n'
fi
