# Mudanças

Só o que muda para quem usa. As versões seguem `MAIOR.MENOR.CORREÇÃO`.

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
- Instalação pelo Homebrew e `PKGBUILD` para o AUR.
- Um comando digitado errado ganha uma sugestão, em vez de virar uma tentativa de baixar.

### Segurança e privacidade

- A lista de links é regravada de uma vez, com trava e cópia: uma queda de energia não a deixa pela metade.
- Os cabeçalhos do `grabit curl`, como um `Authorization`, não aparecem mais no `ps`.
- A pasta de logs, que guarda links, só o dono lê, e o que tem mais de 30 dias é apagado.
