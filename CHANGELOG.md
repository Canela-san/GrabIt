# Mudanças

Só o que muda para quem usa. As versões seguem `MAIOR.MENOR.CORREÇÃO`.

## 1.1.1

### Comandos

- Todo comando vale em português, em inglês, com ou sem os traços e, agora, por uma letra: `grabit atualizar`, `update`, `--update` e `-N` são o mesmo. As letras: `-D` baixar, `-S` lista, `-I` instalar, `-N` atualizar, `-V` versão, `-G` config, `-K` verificar, `-T` converter, `-M` comparar, `-W` canais, `-R` curl, `-E` diagnóstico, `-P` manual, `-t` completar, `-X` desinstalar e `-h` ajuda. Nenhuma opção que já existia mudou.
- Dois comandos juntos (`grabit -V -G`) agora são um erro claro, em vez de um deles sumir calado. A ajuda vence qualquer outro.
- `grabit diagnostico` junta as versões, o sistema e o fim do último log que falhou, sem links (fica só o site), cookies, tokens, nomes de arquivo nem a pasta pessoal: pronto para colar num relato de bug.
- `man grabit`: a página do manual, em português e em inglês, vem nos pacotes e no `grabit install`. `grabit manual` a imprime.
- `--json`: a saída padrão traz só eventos JSON, um por linha (início, cada link, progresso, arquivos, resultado e fim), para uma interface gráfica ou um script acompanhar o lote. O resto vai para a saída de erro, sem o painel.

### Segurança

- As versões publicadas são assinadas. Com o `gpg` instalado, o `grabit update` só troca o script por um arquivo com a assinatura do projeto; sem ele, continua valendo a soma SHA-256, e o update avisa.

### Instalação

- No Arch, o pacote se chama `grabit-dl`: no AUR, `grabit` é outro programa. O update e o desinstalar passam a dizer o comando certo para ele.
- No Windows, o GrabIt roda pelo WSL, testado a cada mudança.

### Correções

- Em inglês, o comando sugerido para tentar de novo os links que falharam vinha com a opção em português (`--repetir`); agora vem `--retry`.
- A ajuda e o README diziam que o `grabit.config` fica sempre ao lado do `grabit.sh`. Instalado por um pacote (apt, Homebrew, Arch), ele fica em `~/.config/grabit`.
- `https://` sozinho, sem endereço, não é mais tratado como um link.
- A ajuda completa em inglês não tinha a linha do `download`.

## 1.1.0

### Lista de links

- O `links.txt` guarda tudo: os links que falham vão para uma seção `FALHARAM`, logo acima da `BAIXADOS`, com o motivo no fim da linha. O `links_falhos.txt` deixou de existir (o antigo pode ser apagado: os links dele continuam na sua lista).
- `grabit download --repetir` tenta de novo os da `FALHARAM`. Sem a opção, eles ficam de fora, e o fim da execução mostra o comando certo para continuar.
- O seu comentário numa linha nunca muda, em seção nenhuma: o GrabIt só acrescenta e tira o ✔ (ou o ✖), a data e a nota dele.
- `grabit lista` mostra o arquivo por partes, com os links numerados, e muda links de seção: `voltar`, `baixado`, `pular`, `limpar notas|falhas|baixados`, `organizar` e `editar` (o arquivo inteiro). Substitui o `grabit --baixados`, que continua funcionando.
- `grabit lista cursos.txt` vale para outro arquivo de links, além do `-l`. O autocompletar oferece os arquivos.
- Links adiados porque o site pediu calma, e os que pararam com o disco cheio, continuam na lista de baixar: não foram culpa do link.

### O vídeo certo

- Página de site sem extrator próprio com mais de um vídeo: fica só o dela, pelo código do vídeo no endereço, pela cara de prévia ou de anúncio e pela duração. Um pedaço de código que o yt-dlp tomava por vídeo deixa de dar erro, e o título perde o `(1)` e o nome do site no fim.
- Pelo navegador, depois da verificação, quem lê a página é o yt-dlp, com a sessão da janela: vem o vídeo certo, com o título. Antes, o GrabIt baixava o primeiro vídeo que a página pedia, muitas vezes um anúncio.
- Nos próximos links do site, a sessão guardada no perfil do GrabIt vale antes de abrir a janela: enquanto a verificação valer, nada de janela.
- Quando só o que a janela pediu resolve, o GrabIt junta tudo o que a página tocou, mede, e fica com o que vem do próprio site ou dura mais, deixando de fora anúncios e prévias. Endereços terminados em `.mp4/` também contam, e o que chega só vale se for vídeo de verdade.

### Correções

- Mudar a seção `BAIXADOS` sem conseguir gravar a lista (sem permissão, disco cheio) aparecia como feito; agora o GrabIt avisa que nada mudou.
- Numa lista salva pelo Bloco de Notas do Windows (com BOM), uma seção na primeira linha do arquivo deixava de ser reconhecida, e os links dela voltavam a ser conferidos a cada execução.
- A ajuda curta em inglês tinha uma linha de comando sobrando.

## 1.0.0

Primeira versão publicada.

### Correções

- Um vídeo passado por engano como lista de links (`grabit video.mkv`) podia ser regravado e destruído. Agora arquivos binários são recusados, e o comando certo aparece na mensagem.
- `--proxy` em `OPCOES_YTDLP` não chegava à busca por arquivo direto, à sonda de velocidade nem ao navegador, que iam direto ao site com o endereço real.
- Disco cheio durante um download pelo aria2c agora é reconhecido na hora, em vez de repetir o download para descobrir a mesma coisa.

### Uso

- `grabit` sozinho mostra a ajuda, que agora cabe numa tela (`grabit ajuda completa` mostra tudo). Para baixar a lista do `links.txt`: `grabit download`.
- O início mostra só o que muda o que vai acontecer; `--detalhes` mostra o resto.
- Terminal de fundo claro: as cores se ajustam sozinhas (`TEMA=auto`, `claro` ou `escuro`).
- O painel usa cerca de um quarto da CPU de antes e não apaga a tela a cada quadro. Ctrl+C não deixa mais o último quadro na tela, Ctrl+Z devolve o cursor ao shell, e uma janela mais baixa que o painel não enche o histórico de rolagem.

### Download

- Arquivo direto em várias conexões pelo aria2c (`-c`, padrão 3), com regulagem por site. Abaixo de 40 MiB não divide, e uma sonda compara com uma conexão simples.
- Arquivo direto de 50 MiB ou mais continua de onde parou depois de um Ctrl+C, um erro ou uma queda de energia, se ainda for o mesmo no site.
- `-O` mantém o formato do site, `-e` escolhe a extensão e `-k` o codec. O MKV segue como padrão. Fora do MKV, os metadados são embutidos no que couber, e o resumo avisa o que ficou de fora.
- `--simular` mostra o que seria baixado e quanto ocupa, sem baixar nada.
- `--desde`, `--max` e `--max-tamanho` filtram por data, quantidade e tamanho.
- `grabit canais` acompanha canais e baixa só o que for novo, à mão ou pelo cron.
- Perfis por site no `grabit.config`: uma seção `[youtube.com]` vale só para esse site.
- Links já registrados no histórico não gastam mais o intervalo do site: a mesma lista passa bem mais rápido.

### Vídeos já baixados

- `grabit converter` troca a extensão sem recomprimir, ou recomprime com `-k`, em um arquivo ou numa pasta.
- Ao recomprimir: `-q` escolhe a qualidade, `--gpu` usa a placa de vídeo (NVENC, VAAPI, Quick Sync, VideoToolbox), e um vídeo HDR em H.264 tem as cores convertidas para SDR.
- `grabit comparar A B` mede quanto dois arquivos do mesmo vídeo diferem aos olhos, com VMAF ou com SSIM e PSNR.
- `grabit verificar` também confere arquivos fora do MKV: acha os incompletos e oferece baixar de novo.

### Instalação e atualização

- O `grabit update` vai para a versão publicada mais nova, que já passou por todos os testes, e confere o arquivo baixado. Para seguir o repositório direto: `CANAL_ATUALIZACAO=main`.
- Autocompletar para fish, bash e zsh, instalado junto.
- `grabit desinstalar` tira o que o GrabIt pôs no sistema. Vídeos e listas ficam.
- Instalação pelo `apt` no Debian, no Ubuntu e no Pop!_OS, com atualização por `apt update && apt upgrade`. Também pelo Homebrew, e há um `PKGBUILD` para o AUR.
- Um comando digitado errado ganha uma sugestão, em vez de virar uma tentativa de baixar.

### Segurança e privacidade

- A lista de links é regravada de uma vez, com trava e cópia: uma queda de energia não a deixa pela metade.
- Os cabeçalhos do `grabit curl`, como um `Authorization`, não aparecem mais no `ps`.
- A pasta de logs, que guarda links, só o dono lê, e o que tem mais de 30 dias é apagado.
