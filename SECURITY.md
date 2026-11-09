# Segurança

*[English below](#security-in-english)*

## Relatar uma falha

Em particular, pelo GitHub: **[Report a vulnerability](https://github.com/Canela-san/GrabIt/security/advisories/new)**. Nunca numa issue pública. A conversa fica entre você e o projeto até a correção sair.

Conta como falha, por exemplo:

- um link, uma página ou um nome de arquivo que faz o GrabIt rodar um comando ou escrever fora da pasta de destino;
- dados sensíveis (cookies, tokens, senhas) parando onde não deviam: tela, logs legíveis por outros, `ps`;
- o `grabit update` aceitando um arquivo que não é a versão publicada;
- os pacotes, o repositório APT ou a chave que assina as versões.

Recebe correção a versão publicada mais nova.

## Conferir uma versão

Cada versão publicada traz a soma SHA-256 (`grabit.sh.sha256`) e a assinatura (`grabit.sh.asc`), feita com a mesma chave do repositório APT. Impressão digital:

```
5C6A D0B8 426A 2108 51E1  052D 7CDE F048 0706 F310
```

```bash
curl -fsSL https://canela-san.github.io/GrabIt/grabit.gpg | gpg --import
gpg --verify grabit.sh.asc grabit.sh
```

O `grabit update` faz essa conferência sozinho quando o `gpg` está instalado, com a chave que vem dentro do próprio script, e não troca nada se ela falhar.

---

## Security in English

**Reporting:** privately, through GitHub: [Report a vulnerability](https://github.com/Canela-san/GrabIt/security/advisories/new). Never in a public issue. Examples: a link, page or file name that makes GrabIt run a command or write outside the destination folder; sensitive data (cookies, tokens, passwords) ending up on screen, in logs readable by others or in `ps`; `grabit update` accepting a file that isn't the published release; the packages, the APT repository or the signing key. The latest published version gets fixes.

**Verifying a release:** each release ships a SHA-256 sum (`grabit.sh.sha256`) and a signature (`grabit.sh.asc`), made with the same key as the APT repository, fingerprint `5C6A D0B8 426A 2108 51E1 052D 7CDE F048 0706 F310`. `grabit update` checks it on its own when `gpg` is installed, using the key embedded in the script, and replaces nothing if it fails.
