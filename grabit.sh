#!/usr/bin/env bash
# ==============================================================================
#  GrabIt (grabit.sh)  —  yt-dlp em lote · máxima qualidade · terminal limpo
#  https://github.com/Canela-san/GrabIt
#  Copyright (c) 2026 Gabriel Canela (Canela-san) · Licença MIT (veja LICENSE)
#  SPDX-License-Identifier: MIT
#
#  Ajuda: grabit -h  ·  Help in English: grabit -L en -h
# ==============================================================================

if [ -z "${BASH_VERSION:-}" ] || [ "${BASH_VERSINFO[0]}" -lt 4 ] ||
   { [ "${BASH_VERSINFO[0]}" -eq 4 ] && [ "${BASH_VERSINFO[1]}" -lt 4 ]; }; then
  echo "O GrabIt precisa do Bash 4.4 ou superior (execute com: bash grabit.sh)." >&2
  echo "GrabIt needs Bash 4.4 or newer (run it with: bash grabit.sh)." >&2
  echo "macOS: brew install bash" >&2
  exit 1
fi

set -uo pipefail
shopt -s extglob

# O idioma do sistema é lido antes de forçar o UTF-8 logo abaixo
LOCALE_ORIGINAL=${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}

# Garante UTF-8 (necessário para os símbolos e para medir a largura do texto)
if [[ "$(locale charmap 2>/dev/null)" != "UTF-8" ]]; then
  for loc in C.UTF-8 en_US.UTF-8 pt_BR.UTF-8; do
    if [[ "$(LC_ALL=$loc locale charmap 2>/dev/null)" == "UTF-8" ]]; then export LC_ALL=$loc; break; fi
  done
fi
export PYTHONUNBUFFERED=1 PYTHONIOENCODING=utf-8

# Modo auxiliar da verificação completa (-v): o yt-dlp chama o GrabIt assim depois de
# cada vídeo (--exec). O ffmpeg decodifica o arquivo inteiro e qualquer erro reprova o
# vídeo: ele é guardado com outro nome (para não contar como "já baixado") e, com o
# código 86, o yt-dlp não o registra no histórico. O painel lê as linhas @@V@@.
if [[ ${1:-} == --verificar-arquivo ]]; then
  sufixo=$2 arq=$3 dur=${4%%.*}
  [[ $dur =~ ^[1-9][0-9]*$ ]] || dur=$(ffprobe -v error -show_entries format=duration -of csv=p=0 -- "$arq" 2>/dev/null)
  dur=${dur%%.*}; [[ $dur =~ ^[0-9]+$ ]] || dur=0
  ruim="${arq%.*}${sufixo}.${arq##*.}"
  erros=$(mktemp) || exit 1
  # Ctrl+C chega a todos os processos: um ffmpeg interrompido (ou reclamando do cano
  # fechado) não pode ser confundido com um arquivo com defeito.
  trap 'rm -f -- "$erros"; exit 130' INT TERM HUP
  ffmpeg -nostdin -hide_banner -v error -i "$arq" -map '0:v?' -map '0:a?' \
         -f null -progress pipe:1 -nostats - 2>"$erros" |
    while IFS='=' read -r k v; do
      [[ $k == out_time_us && $v =~ ^[0-9]+$ ]] && printf '@@V@@%d\x1f%d\n' $(( v / 1000000 )) "$dur"
    done
  (( PIPESTATUS[0] == 255 )) && { rm -f -- "$erros"; exit 130; }   # o ffmpeg recebeu um sinal
  if [[ -s $erros ]]; then
    printf '@@V@@ERRO %s\n' "$(head -c 400 "$erros" | tr '\r\n' '  ' | sed -E 's/\[[^]]* @ 0x[0-9a-f]+\] //g')"
    rm -f -- "$erros"; mv -f -- "$arq" "$ruim"
    exit 86
  fi
  rm -f -- "$erros" "$ruim"                   # passou: some a cópia ruim de uma tentativa anterior
  exit 0
fi

# ───────────────────────────── Configuração ───────────────────────────────────
# Onde o GrabIt mora de verdade (seguindo links simbólicos, como ~/.local/bin/grabit):
# é ali, ao lado do script, que fica o grabit.config.
resolve_caminho() {                           # resolve_caminho ARQUIVO → CAMINHO_REAL
  local f=$1 alvo dir
  while [[ -L $f ]]; do
    alvo=$(readlink -- "$f"); dir=$(cd -P -- "$(dirname -- "$f")" && pwd)
    if [[ $alvo == /* ]]; then f=$alvo; else f="$dir/$alvo"; fi
  done
  dir=$(cd -P -- "$(dirname -- "$f")" && pwd)
  CAMINHO_REAL="$dir/${f##*/}"
}
resolve_caminho "$0"
GRABIT_SCRIPT=$CAMINHO_REAL
GRABIT_DIR=${GRABIT_SCRIPT%/*}
CONFIG_ARQ="${GRABIT_CONFIG:-$GRABIT_DIR/grabit.config}"

# Chaves aceitas no grabit.config (e como variáveis de ambiente). Prioridade, da menor
# para a maior: padrão do script < grabit.config < variável de ambiente < opção do comando.
CHAVES_CONFIG=(IDIOMA ARQUIVO_LINKS PASTA_SAIDA RESOLUCAO_MAXIMA RESOLUCAO_ALERTA DOWNLOADS_SIMULTANEOS CONEXOES_POR_VIDEO TENTATIVAS
  IDIOMAS_LEGENDAS LEGENDAS_AUTOMATICAS SPONSORBLOCK SEM_PLAYLIST SO_PRINCIPAL VERIFICAR COOKIES_NAVEGADOR
  USAR_HISTORICO ARQUIVO_FALHAS)
declare -A DO_AMBIENTE=() ORIGEM=()
for k in "${CHAVES_CONFIG[@]}"; do [[ -v $k ]] && DO_AMBIENTE[$k]=${!k}; done

IDIOMA=auto                                   # pt, en ou auto (pelo idioma do sistema)
ARQUIVO_LINKS=links.txt
PASTA_SAIDA=./Downloads
RESOLUCAO_MAXIMA=0                            # altura máxima (1080, 2160…); 0 = sem limite
RESOLUCAO_ALERTA=720                          # avisa quando o melhor disponível é menor; 0 = nunca
DOWNLOADS_SIMULTANEOS=2                       # vídeos ao mesmo tempo
CONEXOES_POR_VIDEO=4                          # fragmentos por vídeo
TENTATIVAS=2                                  # tentativas por link (1 = sem repetir)
IDIOMAS_LEGENDAS='pt.*,en.*'                  # "all" para todas
LEGENDAS_AUTOMATICAS=0                        # 1 = inclui legendas automáticas
SPONSORBLOCK=0                                # 1 = marca patrocínios/intros como capítulos
SEM_PLAYLIST=0                                # 1 = link vídeo+playlist baixa só o vídeo
SO_PRINCIPAL=0                                # 1 = página com vários vídeos baixa só o principal
VERIFICAR=0                                   # 1 = decodifica cada vídeo inteiro para achar defeitos
COOKIES_NAVEGADOR=                            # ex.: firefox, chrome, brave
USAR_HISTORICO=1                              # 0 = não pula o que já foi baixado antes
ARQUIVO_FALHAS=links_falhos.txt
ARQUIVO_HISTORICO="${ARQUIVO_HISTORICO:-}"    # padrão: <pasta de saída>/.grabit-historico.txt
TEMPLATE_SAIDA='%(title).180B [%(id)s].%(ext)s'
CONFIG_CRIADO=0; AVISOS_CONFIG=(); N_AJUSTES_CONFIG=0

# carrega_config: lê CHAVE=valor do grabit.config (sem executar nada do arquivo). Valores
# podem vir entre aspas; "# comentário" no fim da linha é ignorado.
carrega_config() {
  local linha chave valor n=0
  [[ -f $CONFIG_ARQ && -r $CONFIG_ARQ ]] || return 0
  while IFS= read -r linha || [[ -n $linha ]]; do
    n=$(( n + 1 ))
    linha=${linha%$'\r'}
    [[ $linha =~ ^[[:space:]]*(#|$) ]] && continue
    if [[ $linha =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
      chave=${BASH_REMATCH[1]}; valor=${BASH_REMATCH[2]}
      valor=${valor%%[[:space:]]#*}
      valor=${valor%"${valor##*[![:space:]]}"}
      if [[ $valor == \"*\" || $valor == \'*\' ]] && (( ${#valor} >= 2 )); then valor=${valor:1:-1}; fi
      if [[ " ${CHAVES_CONFIG[*]} " == *" $chave "* ]]; then
        printf -v "$chave" '%s' "$valor"; ORIGEM[$chave]=config
        N_AJUSTES_CONFIG=$(( N_AJUSTES_CONFIG + 1 ))
      else
        AVISOS_CONFIG+=("$n: $chave")
      fi
    else
      AVISOS_CONFIG+=("$n: $linha")
    fi
  done < "$CONFIG_ARQ"
}
carrega_config
for k in "${!DO_AMBIENTE[@]}"; do printf -v "$k" '%s' "${DO_AMBIENTE[$k]}"; ORIGEM[$k]=ambiente; done

# ───────────────────────────── Idioma ─────────────────────────────────────────
# -L é lido antes do getopts, para que até os erros nas opções saiam no idioma certo.
# Percorre as opções como o getopts faria (aceita -L en, -Len e -sL en).
for (( i = 1; i <= $#; i++ )); do
  a=${!i}
  [[ $a == -- ]] && break
  [[ $a == --* ]] && continue                   # --config, --help…
  [[ $a == -?* ]] || break                      # primeiro link/arquivo: fim das opções
  for (( c = 1; c < ${#a}; c++ )); do
    case ${a:c:1} in
      L)         j=$(( i + 1 )); IDIOMA=${a:c+1}; [[ -z $IDIOMA ]] && { IDIOMA=${!j:-}; i=$j; }
                 ORIGEM[IDIOMA]=opção; break ;;
      [lojcbr])  [[ -z ${a:c+1} ]] && i=$(( i + 1 )); break ;;   # o valor é o próximo argumento
    esac
  done
done
unset a c i j

# resolve_idioma VALOR → LINGUA (pt|en); "auto" segue o sistema (sem idioma definido: pt)
IDIOMA_INVALIDO=""
resolve_idioma() {
  case ${1,,} in
    pt|pt-br|pt_br|portugues|português) LINGUA=pt ;;
    en|en-us|en_us|english|ingles|inglês) LINGUA=en ;;
    auto|"")
      case ${LOCALE_ORIGINAL,,} in
        pt*|""|c|c.*|posix) LINGUA=pt ;;
        *)                  LINGUA=en ;;
      esac ;;
    *) IDIOMA_INVALIDO=$1; resolve_idioma auto ;;
  esac
}
resolve_idioma "$IDIOMA"

declare -A T=()
# t CHAVE [ARGS...] → TXT: o texto no idioma atual (com ARGS, a frase é um formato do printf)
t() {
  local f=${T[$1]-$1}
  shift
  # shellcheck disable=SC2059
  if (( $# )); then printf -v TXT "$f" "$@"; else TXT=$f; fi
}

idioma_pt() {
  T=(
    [titulo]="GrabIt  ·  Downloader em lote  ·  Máxima qualidade (MKV)"
    [titulo_curto]="GrabIt · Downloader em lote"
    [opcao_invalida]="Opção inválida: %s"
    [opcao_valor]="A opção -%s precisa de um valor."
    [idioma_invalido]="Idioma desconhecido: '%s' (use pt ou en). Usando: %s."
    [origem_opção]="opção do comando"
    [origem_config]="grabit.config"
    [origem_ambiente]="variável de ambiente"
    [origem_padrão]="padrão"
    [val_numero]="%s precisa ser um número inteiro maior que zero (recebi '%s', de: %s)."
    [val_01]="%s precisa ser 0 ou 1 (recebi '%s', de: %s)."
    [val_resolucao]="%s precisa ser uma altura como 720, 1080 ou 2160, ou 0 para não limitar (recebi '%s', de: %s)."
    [cfg_criado]="(criado agora)"
    [cfg_inexistente]="(não existe e não pôde ser criado)"
    [cfg_linha]="grabit.config, linha %s: ignorada (chave desconhecida ou sem \"=\"):%s"
    [kv_links]="Links"
    [kv_destino]="Destino"
    [kv_config]="Config"
    [kv_historico]="Histórico"
    [kv_paralelo]="Paralelo"
    [kv_extras]="Extras"
    [kv_ferramentas]="Ferramentas"
    [kv_recursos]="Recursos"
    [kv_resolucao]="Resolução"
    [kv_res_ate]="até %dp"
    [kv_res_origem]=" (%s) · -F ignora o limite"
    [kv_res_forcado]="%ssem limite (-F)%s · ignorando o limite de %dp (%s)"
    [kv_config_criado]="%scriado agora%s em %s — edite para mudar os padrões"
    [kv_config_ajustes]="grabit.config · %d ajuste(s) · grabit --config mostra tudo"
    [kv_hist_on]="%s vídeo(s) registrados · os já baixados são pulados"
    [kv_hist_off]="%signorado (-i)%s: confere arquivo por arquivo"
    [kv_paralelo_v]="%d vídeo(s) × %d conexões"
    [kv_tentativas]=" · até %d tentativas"
    [kv_legendas]="legendas %s"
    [kv_automaticas]=" (+automáticas)"
    [kv_extras_resto]=", capa, capítulos, metadados"
    [kv_principal]=", só o vídeo principal de cada página"
    [kv_verificar]=", verificação completa"
    [imp_indisp]="indisponível"
    [imp_retry]="nas novas tentativas"
    [imp_off]="desligado (TENTATIVAS=1)"
    [js_nenhum]="nenhum"
    [links_ignorados]=" · ignorados:%s"
    [links_repetidos]=" %d repetido(s)"
    [links_sem_link]=" %d linha(s) sem link"
    [links_na_secao]=" · %d já na seção BAIXADOS"
    [fonte_stdin]="entrada padrão"
    [fonte_cli]="linha de comando"
    [av_linhas]="Terminal com só %s linhas: limitei a %d download(s) simultâneo(s)."
    [av_linhas2]="     (pedido: %d — aumente a janela para ver todos no painel)"
    [av_ytdlp]="Seu yt-dlp (%s) está desatualizado: os sites mudam o tempo todo."
    [av_ytdlp2]="     Atualize:  %s   (ou:  %s)"
    [av_curl]="curl_cffi ausente: sites com proteção anti-robô podem falhar."
    [av_curl2]="     Instale com:  %s"
    [av_js]="Sem runtime JavaScript: o YouTube pode falhar ou vir em qualidade menor."
    [av_js2]="     Instale o Deno (https://deno.com) e mantenha o yt-dlp atualizado."
    [dica_ctrlc]="Ctrl+C cancela · o que estiver pela metade recomeça do zero"
    [dep_faltando]="Faltando: %s"
    [dep_instale]="instale '%s' pelo gerenciador de pacotes do sistema"
    [sem_arquivo]="O arquivo '%s' não foi encontrado."
    [sem_arquivo2]="     Crie-o com um link por linha, use  -l CAMINHO  ou passe os links no próprio comando."
    [nada_1]="Nada para baixar: o único link de %s já está na seção BAIXADOS."
    [nada_n]="Nada para baixar: os %d links de %s já estão na seção BAIXADOS."
    [sem_links]="Nenhum link válido (http/https) em: %s."
    [nada]="nada"
    [marca]="# ==================== BAIXADOS ===================="
    [marca_desc]="# Links já baixados com sucesso. O GrabIt ignora tudo daqui para baixo."
    [tentativa_n]="%dª tentativa · "
    [ni_tentativa]="(%dª tentativa)"
    [log_tentativa]="# ── tentativa %d ──"
    [tipo_legendas]="legendas"
    [tipo_audio]="áudio"
    [tipo_video]="vídeo"
    [total]="Total"
    [et_finalizando]="finalizando"
    [et_mesclando]="mesclando vídeo e áudio"
    [et_mkv]="convertendo para MKV"
    [et_metadados]="gravando metadados"
    [et_legendas_emb]="embutindo legendas"
    [et_capa_emb]="embutindo a capa"
    [et_capitulos]="processando capítulos"
    [et_fixup]="corrigindo o arquivo"
    [et_legendas]="baixando legendas"
    [et_capa]="baixando a capa"
    [et_hist]="já baixado antes (histórico)"
    [et_existe]="arquivo já existe"
    [et_iniciando]="iniciando download"
    [et_principal]="procurando o vídeo principal da página"
    [et_verificando]="verificando o arquivo"
    [et_processando]="processando"
    [et_item]="obtendo informações · item %s/%s"
    [et_info]="obtendo informações"
    [r_ja_existia]="já existia"
    [r_ja_baixado]="já baixado antes"
    [r_n_ja_baixados]="%d já baixados antes"
    [r_concluido]="concluído"
    [r_aviso]="aviso:"
    [r_av_capa]="a capa não converteu para JPG e foi embutida no formato original"
    [r_av_sponsor]="não deu para consultar o SponsorBlock"
    [r_av_outro]="uma etapa de acabamento falhou (detalhes no log)"
    [r_av_completo]="%s — o vídeo está completo"
    [r_parcial]="parcial"
    [r_falhou]="falhou"
    [r_falhou_n]="falhou %d×"
    [r_codigo]="yt-dlp terminou com código %d"
    [d_privado]="vídeo privado"
    [d_idade]="restrito por idade — use -b NAVEGADOR"
    [d_bot]="o YouTube pediu login — use -b NAVEGADOR"
    [d_membros]="exclusivo para membros"
    [d_regiao]="bloqueado na sua região"
    [d_removido]="vídeo indisponível ou removido"
    [d_url]="link não suportado"
    [d_live]="a live/estreia ainda não começou"
    [d_404]="não encontrado (404)"
    [d_disco]="disco cheio"
    [d_invalido]="o arquivo baixado não é um vídeo válido"
    [d_fragmento]="um pedaço do vídeo não baixou"
    [d_403]="acesso negado (403)"
    [d_429]="muitas requisições (429)"
    [d_rede]="falha de rede"
    [d_resolucao]="nenhuma versão até %dp — use -F para baixar mesmo assim"
    [d_resolucao_r]="nenhuma versão até %dp (-r)"
    [nota_n]="%d vídeos · %s e outros"
    [nota_n0]="%d vídeos"
    [sufixo_ruim]=".com-erros"
    [d_verificacao]="o arquivo tem defeitos (ficou com %s no nome)"
    [r_baixa]="resolução baixa:"
    [r_baixa_det]="%dp era a melhor versão disponível (com login, -b, às vezes há mais)"
    [s_baixa]="Baixa resolução"
    [s_baixa_det]="%d vídeo(s) abaixo de %dp"
    [s_resumo]="Resumo"
    [s_resumo_parcial]="Resumo parcial"
    [s_baixados]="Baixados"
    [s_ja]="Já existiam"
    [s_erro]="Links com erro"
    [s_aviso]="Com aviso"
    [s_aviso_det]="(arquivos completos · logs em %s/)"
    [s_tempo]="Tempo"
    [s_baixado_agora]="Baixado agora"
    [s_media]="(média de %s/s)"
    [s_pasta]="Pasta"
    [s_lista]="Lista"
    [s_movidos]="%d link(s) movidos para a seção BAIXADOS"
    [f_todos_ok]="Todos os links de %s deram certo — arquivo removido."
    [f_nao_gravou]="Não consegui gravar '%s'."
    [f_com_erro]="com erro"
    [f_erro_pend]="com erro ou pendentes"
    [f_pend]="pendentes"
    [f_salvos]="%d link(s) %s salvos em %s"
    [f_logs]=" — logs em %s/"
    [f_continuar]="     Para continuar:  %s"
    [c_cancelado]="Cancelado."
    [c_descartado]=" O que estava pela metade foi descartado e recomeça do zero na próxima vez."
    [tmp_falhou]="Não consegui criar a pasta temporária."
    [pasta_falhou]="Não consegui criar a pasta '%s'."
  )
  T[ajuda]=$(cat <<'EOF'
Uso:  grabit [opções] [LINK ou ARQUIVO ...]

  -l ARQUIVO    arquivo com os links ("-" = entrada padrão)  (padrão: links.txt)
  -o PASTA      pasta onde os vídeos serão salvos            (padrão: ./Downloads)
  -j N          downloads simultâneos                        (padrão: 2)
  -c N          conexões (fragmentos) por vídeo              (padrão: 4)
  -r ALTURA     resolução máxima: 720, 1080, 2160, 4k…       (padrão: sem limite)
  -F            força: ignora os limites do grabit.config (resolução máxima…)
  -b NAVEGADOR  usa os cookies do navegador (firefox, chrome, brave…)
  -p            só o vídeo, se o link tiver vídeo + playlist
  -u            só o vídeo principal (o mais longo) de páginas com vários vídeos
  -a            inclui legendas automáticas (a manual continua tendo prioridade)
  -s            marca patrocínios/intros como capítulos (SponsorBlock)
  -i            ignora o histórico de baixados (confere arquivo por arquivo)
  -v            verificação completa: decodifica cada vídeo inteiro atrás de defeitos
  -L pt|en      idioma das mensagens (Language)
  -h            mostra esta ajuda

  --config      mostra o grabit.config e os valores em uso

• Links e arquivos de links também podem vir direto no comando (aí o
  links.txt só é lido se você passar -l):
      grabit https://youtu.be/xxxx outra_lista.txt
• Nos arquivos: linhas vazias e comentários (# …, inclusive no fim da linha)
  são ignorados, assim como texto em volta do link; repetidos são descartados.
• Links baixados com sucesso vão para a seção "# ===== BAIXADOS =====" no fim
  do próprio arquivo. Tudo nessa seção é ignorado: vira o seu histórico de links.
• Cada vídeo baixado entra no histórico (Downloads/.grabit-historico.txt): da
  próxima vez ele é pulado na hora, sem acessar o site nem mexer no arquivo.
  Apagou um vídeo e quer baixá-lo de novo? Use -i ou apague a linha dele lá.
• Link que falha por motivo passageiro (rede, 403…) ganha nova tentativa no
  fim da fila, imitando um navegador (--impersonate) se houver curl_cffi.
• Links que falharem vão para links_falhos.txt, prontos para reexecutar:
      grabit -l links_falhos.txt
• Download que não terminou (Ctrl+C, erro) recomeça do zero na próxima vez:
  retomar pedaços não garante a qualidade. A pasta Downloads/.parciais só existe
  enquanto o GrabIt roda.

Configurações permanentes ficam no grabit.config, ao lado do grabit.sh (criado
na primeira execução, com todos os padrões comentados): grabit --config
Prioridade: grabit.config < variável de ambiente < opção do comando, ex.:
    DOWNLOADS_SIMULTANEOS=3 grabit        grabit -j 3
EOF
)
  T[modelo_config]=$(cat <<'EOF'
# ==============================================================================
#  grabit.config — configurações do GrabIt
#
#  Criado automaticamente na primeira execução, com todos os padrões comentados.
#  Para mudar um valor, tire o "#" do começo da linha e edite. Para voltar ao
#  padrão, comente a linha de novo (ou apague este arquivo: ele é recriado).
#
#  Prioridade: este arquivo < variáveis de ambiente < opções do comando.
#  Veja os valores em uso com: grabit --config
# ==============================================================================

# Idioma das mensagens: pt, en ou auto (pelo idioma do sistema) (-L)
#IDIOMA=auto

# Lista de links lida quando você roda só "grabit"
#ARQUIVO_LINKS=links.txt

# Pasta onde os vídeos são salvos
#PASTA_SAIDA=./Downloads

# Resolução máxima: 720, 1080, 1440, 2160 (ou 4k)…; 0 = sem limite (-r). Vale para o
# lado menor da imagem: um vídeo vertical de 1080×1920 conta como 1080p. Vídeo sem
# nenhuma versão dentro do limite falha com um aviso; -F ignora o limite numa execução.
#RESOLUCAO_MAXIMA=0

# Avisa quando a melhor versão que o site oferece fica abaixo desta resolução (0 = nunca)
#RESOLUCAO_ALERTA=720

# Quantos vídeos baixar ao mesmo tempo (-j) e conexões por vídeo (-c)
#DOWNLOADS_SIMULTANEOS=2
#CONEXOES_POR_VIDEO=4

# Tentativas por link quando a falha é passageira (1 = não tentar de novo)
#TENTATIVAS=2

# Idiomas das legendas ("all" = todas) e se inclui as automáticas (-a)
#IDIOMAS_LEGENDAS=pt.*,en.*
#LEGENDAS_AUTOMATICAS=0

# Marca patrocínios/intros como capítulos com o SponsorBlock (-s)
#SPONSORBLOCK=0

# Link de vídeo dentro de playlist: baixar só o vídeo (-p)
#SEM_PLAYLIST=0

# Página com vários vídeos (prévias, relacionados…): baixar só o principal, o mais longo (-u)
#SO_PRINCIPAL=0

# Verificação completa: decodifica cada vídeo baixado do começo ao fim e, se achar um
# defeito, baixa de novo do zero. Garante o arquivo perfeito, mas usa CPU e tempo (-v)
#VERIFICAR=0

# Usar os cookies (login) de um navegador: firefox, chrome, brave… (-b)
#COOKIES_NAVEGADOR=

# Pular na hora os vídeos já baixados antes (0 = conferir sempre; o mesmo que -i)
#USAR_HISTORICO=1

# Onde salvar os links que falharam
#ARQUIVO_FALHAS=links_falhos.txt
EOF
)
}

idioma_en() {
  T=(
    [titulo]="GrabIt  ·  Batch downloader  ·  Maximum quality (MKV)"
    [titulo_curto]="GrabIt · Batch downloader"
    [opcao_invalida]="Invalid option: %s"
    [opcao_valor]="Option -%s needs a value."
    [idioma_invalido]="Unknown language: '%s' (use pt or en). Using: %s."
    [origem_opção]="command-line option"
    [origem_config]="grabit.config"
    [origem_ambiente]="environment variable"
    [origem_padrão]="default"
    [val_numero]="%s must be a whole number greater than zero (got '%s', from: %s)."
    [val_01]="%s must be 0 or 1 (got '%s', from: %s)."
    [val_resolucao]="%s must be a height like 720, 1080 or 2160, or 0 for no limit (got '%s', from: %s)."
    [cfg_criado]="(just created)"
    [cfg_inexistente]="(missing and could not be created)"
    [cfg_linha]="grabit.config, line %s: ignored (unknown key or no \"=\"):%s"
    [kv_links]="Links"
    [kv_destino]="Destination"
    [kv_config]="Config"
    [kv_historico]="History"
    [kv_paralelo]="Parallel"
    [kv_extras]="Extras"
    [kv_ferramentas]="Tools"
    [kv_recursos]="Features"
    [kv_resolucao]="Resolution"
    [kv_res_ate]="up to %dp"
    [kv_res_origem]=" (%s) · -F ignores the limit"
    [kv_res_forcado]="%sno limit (-F)%s · ignoring the %dp limit (%s)"
    [kv_config_criado]="%sjust created%s at %s — edit it to change the defaults"
    [kv_config_ajustes]="grabit.config · %d setting(s) · grabit --config shows all"
    [kv_hist_on]="%s video(s) recorded · already downloaded ones are skipped"
    [kv_hist_off]="%signored (-i)%s: checks file by file"
    [kv_paralelo_v]="%d video(s) × %d connections"
    [kv_tentativas]=" · up to %d attempts"
    [kv_legendas]="subtitles %s"
    [kv_automaticas]=" (+automatic)"
    [kv_extras_resto]=", cover, chapters, metadata"
    [kv_principal]=", only each page's main video"
    [kv_verificar]=", full check"
    [imp_indisp]="unavailable"
    [imp_retry]="on retries"
    [imp_off]="off (TENTATIVAS=1)"
    [js_nenhum]="none"
    [links_ignorados]=" · ignored:%s"
    [links_repetidos]=" %d duplicate(s)"
    [links_sem_link]=" %d line(s) without a link"
    [links_na_secao]=" · %d already in the DOWNLOADED section"
    [fonte_stdin]="standard input"
    [fonte_cli]="command line"
    [av_linhas]="The terminal has only %s rows: limited to %d simultaneous download(s)."
    [av_linhas2]="     (requested: %d — enlarge the window to see them all)"
    [av_ytdlp]="Your yt-dlp (%s) is outdated: websites change all the time."
    [av_ytdlp2]="     Update:  %s   (or:  %s)"
    [av_curl]="curl_cffi is missing: sites with anti-bot protection may fail."
    [av_curl2]="     Install it with:  %s"
    [av_js]="No JavaScript runtime: YouTube may fail or come in lower quality."
    [av_js2]="     Install Deno (https://deno.com) and keep yt-dlp up to date."
    [dica_ctrlc]="Ctrl+C cancels · anything half-done starts over from scratch"
    [dep_faltando]="Missing: %s"
    [dep_instale]="install '%s' with your system's package manager"
    [sem_arquivo]="File '%s' not found."
    [sem_arquivo2]="     Create it with one link per line, use  -l PATH  or pass the links on the command line."
    [nada_1]="Nothing to download: the only link in %s is already in the DOWNLOADED section."
    [nada_n]="Nothing to download: all %d links in %s are already in the DOWNLOADED section."
    [sem_links]="No valid (http/https) links in: %s."
    [nada]="nothing"
    [marca]="# ==================== DOWNLOADED ===================="
    [marca_desc]="# Successfully downloaded links. GrabIt ignores everything below this line."
    [tentativa_n]="attempt %d · "
    [ni_tentativa]="(attempt %d)"
    [log_tentativa]="# ── attempt %d ──"
    [tipo_legendas]="subtitles"
    [tipo_audio]="audio"
    [tipo_video]="video"
    [total]="Total"
    [et_finalizando]="finishing"
    [et_mesclando]="merging video and audio"
    [et_mkv]="converting to MKV"
    [et_metadados]="writing metadata"
    [et_legendas_emb]="embedding subtitles"
    [et_capa_emb]="embedding the cover"
    [et_capitulos]="processing chapters"
    [et_fixup]="fixing the file"
    [et_legendas]="downloading subtitles"
    [et_capa]="downloading the cover"
    [et_hist]="already downloaded (history)"
    [et_existe]="file already exists"
    [et_iniciando]="starting download"
    [et_principal]="looking for the page's main video"
    [et_verificando]="checking the file"
    [et_processando]="processing"
    [et_item]="fetching info · item %s/%s"
    [et_info]="fetching info"
    [r_ja_existia]="already existed"
    [r_ja_baixado]="already downloaded"
    [r_n_ja_baixados]="%d already downloaded"
    [r_concluido]="done"
    [r_aviso]="warning:"
    [r_av_capa]="the cover couldn't be converted to JPG and was embedded as is"
    [r_av_sponsor]="couldn't reach SponsorBlock"
    [r_av_outro]="a finishing step failed (see the log)"
    [r_av_completo]="%s — the video is complete"
    [r_parcial]="partial"
    [r_falhou]="failed"
    [r_falhou_n]="failed %d×"
    [r_codigo]="yt-dlp exited with code %d"
    [d_privado]="private video"
    [d_idade]="age-restricted — use -b BROWSER"
    [d_bot]="YouTube asked you to sign in — use -b BROWSER"
    [d_membros]="members only"
    [d_regiao]="blocked in your region"
    [d_removido]="video unavailable or removed"
    [d_url]="unsupported link"
    [d_live]="the live stream/premiere hasn't started yet"
    [d_404]="not found (404)"
    [d_disco]="disk full"
    [d_invalido]="the downloaded file isn't a valid video"
    [d_fragmento]="a piece of the video failed to download"
    [d_403]="access denied (403)"
    [d_429]="too many requests (429)"
    [d_rede]="network failure"
    [d_resolucao]="no version up to %dp — use -F to download it anyway"
    [d_resolucao_r]="no version up to %dp (-r)"
    [nota_n]="%d videos · %s and others"
    [nota_n0]="%d videos"
    [sufixo_ruim]=".with-errors"
    [d_verificacao]="the file has defects (kept with %s in its name)"
    [r_baixa]="low resolution:"
    [r_baixa_det]="%dp was the best version available (logged in, -b, there may be more)"
    [s_baixa]="Low resolution"
    [s_baixa_det]="%d video(s) below %dp"
    [s_resumo]="Summary"
    [s_resumo_parcial]="Partial summary"
    [s_baixados]="Downloaded"
    [s_ja]="Already had"
    [s_erro]="Failed links"
    [s_aviso]="With warnings"
    [s_aviso_det]="(files complete · logs in %s/)"
    [s_tempo]="Time"
    [s_baixado_agora]="Downloaded now"
    [s_media]="(average %s/s)"
    [s_pasta]="Folder"
    [s_lista]="List"
    [s_movidos]="%d link(s) moved to the DOWNLOADED section"
    [f_todos_ok]="Every link in %s succeeded — file removed."
    [f_nao_gravou]="Couldn't write '%s'."
    [f_com_erro]="failed"
    [f_erro_pend]="failed or pending"
    [f_pend]="pending"
    [f_salvos]="%d %s link(s) saved to %s"
    [f_logs]=" — logs in %s/"
    [f_continuar]="     To continue:  %s"
    [c_cancelado]="Canceled."
    [c_descartado]=" Anything half-done was discarded and will start over next time."
    [tmp_falhou]="Couldn't create the temporary folder."
    [pasta_falhou]="Couldn't create folder '%s'."
  )
  T[ajuda]=$(cat <<'EOF'
Usage:  grabit [options] [LINK or FILE ...]

  -l FILE       file with the links ("-" = stdin)    (default: links.txt)
  -o FOLDER     where videos are saved               (default: ./Downloads)
  -j N          simultaneous downloads               (default: 2)
  -c N          connections (fragments) per video    (default: 4)
  -r HEIGHT     maximum resolution: 720, 1080, 4k…   (default: no limit)
  -F            force: ignore the grabit.config limits (maximum resolution…)
  -b BROWSER    use the browser's cookies (firefox, chrome, brave…)
  -p            only the video, when the link is video + playlist
  -u            only the main video (the longest) of pages with several videos
  -a            include automatic subtitles (manual ones still win)
  -s            mark sponsors/intros as chapters (SponsorBlock)
  -i            ignore the download history (check file by file)
  -v            full check: decode every video end to end looking for defects
  -L pt|en      language of the messages
  -h            show this help

  --config      show grabit.config and the values in use

• Links and link files can also go straight on the command line (then
  links.txt is only read if you pass -l):
      grabit https://youtu.be/xxxx another_list.txt
• In the files: empty lines and comments (# …, also at the end of a line)
  are ignored, as is any text around the link; duplicates are dropped.
• Successfully downloaded links move to the "# ===== DOWNLOADED =====" section
  at the end of the same file. Everything there is ignored: it becomes your
  link history.
• Every downloaded video goes into the history
  (Downloads/.grabit-historico.txt): next time it is skipped right away,
  without touching the site or the file.
  Deleted a video and want it again? Use -i or delete its line there.
• A link that fails for a temporary reason (network, 403…) gets another try at
  the end of the queue, impersonating a browser (--impersonate) if curl_cffi
  is installed.
• Failed links go to links_falhos.txt, ready to run again:
      grabit -l links_falhos.txt
• A download that didn't finish (Ctrl+C, error) starts over from scratch next
  time: resuming pieces doesn't guarantee quality. The Downloads/.parciais
  folder only exists while GrabIt runs.

Permanent settings live in grabit.config, next to grabit.sh (created on the
first run, with every default commented out): grabit --config
Priority: grabit.config < environment variable < command-line option, e.g.:
    DOWNLOADS_SIMULTANEOS=3 grabit        grabit -j 3
EOF
)
  T[modelo_config]=$(cat <<'EOF'
# ==============================================================================
#  grabit.config — GrabIt settings
#
#  Created automatically on the first run, with every default commented out.
#  To change a value, remove the "#" at the start of the line and edit it. To go
#  back to the default, comment the line again (or delete this file: it is
#  recreated).
#
#  Priority: this file < environment variables < command-line options.
#  See the values in use with: grabit --config
# ==============================================================================

# Language of the messages: pt, en or auto (follows the system) (-L)
#IDIOMA=auto

# Link list read when you run just "grabit"
#ARQUIVO_LINKS=links.txt

# Folder where videos are saved
#PASTA_SAIDA=./Downloads

# Maximum resolution: 720, 1080, 1440, 2160 (or 4k)…; 0 = no limit (-r). It applies to
# the shorter side of the picture: a 1080×1920 vertical video counts as 1080p. A video
# with no version within the limit fails with a notice; -F ignores the limit for a run.
#RESOLUCAO_MAXIMA=0

# Warn when the best version a site offers is below this resolution (0 = never)
#RESOLUCAO_ALERTA=720

# How many videos to download at once (-j) and connections per video (-c)
#DOWNLOADS_SIMULTANEOS=2
#CONEXOES_POR_VIDEO=4

# Attempts per link when the failure is temporary (1 = don't retry)
#TENTATIVAS=2

# Subtitle languages ("all" = every one) and whether to include automatic ones (-a)
#IDIOMAS_LEGENDAS=pt.*,en.*
#LEGENDAS_AUTOMATICAS=0

# Mark sponsors/intros as chapters with SponsorBlock (-s)
#SPONSORBLOCK=0

# Video link inside a playlist: download only the video (-p)
#SEM_PLAYLIST=0

# Page with several videos (previews, related…): download only the main one, the longest (-u)
#SO_PRINCIPAL=0

# Full check: decode every downloaded video from start to end and, if a defect shows
# up, download it again from scratch. Guarantees a flawless file, but costs CPU and time (-v)
#VERIFICAR=0

# Use a browser's cookies (login): firefox, chrome, brave… (-b)
#COOKIES_NAVEGADOR=

# Skip videos already downloaded before (0 = always check; same as -i)
#USAR_HISTORICO=1

# Where to save the links that failed
#ARQUIVO_FALHAS=links_falhos.txt
EOF
)
}
"idioma_$LINGUA"

# ───────────────────────────── Cores e terminal ───────────────────────────────
ESC=$'\033'
INTERATIVO=0
[[ -t 1 && ${TERM:-dumb} != dumb ]] && INTERATIVO=1

if (( INTERATIVO )) && [[ -z "${NO_COLOR:-}" ]]; then
  R="${ESC}[0m";            NEG="${ESC}[1m"
  DIM="${ESC}[38;5;245m";   CINZA="${ESC}[38;5;238m"
  VERDE="${ESC}[38;5;78m";  VERMELHO="${ESC}[38;5;203m"
  AMARELO="${ESC}[38;5;221m"; CIANO="${ESC}[38;5;81m"; ACENTO="${ESC}[38;5;141m"
else
  R=""; NEG=""; DIM=""; CINZA=""; VERDE=""; VERMELHO=""; AMARELO=""; CIANO=""; ACENTO=""
fi

erro()  { printf '  %s✖%s %s\n' "$VERMELHO" "$R" "$*" >&2; }
aviso() { printf '  %s⚠%s %s\n' "$AMARELO" "$R" "$*"; }
uso()   { printf '%s\n' "${T[ajuda]}"; }

# Primeira execução: cria o grabit.config, com os padrões comentados, no idioma atual
if [[ ! -e $CONFIG_ARQ && -w ${CONFIG_ARQ%/*} ]]; then
  printf '%s\n' "${T[modelo_config]}" > "$CONFIG_ARQ" 2>/dev/null && CONFIG_CRIADO=1
fi

# Comandos longos (--config, --help) saem da lista antes do getopts
COMANDO=""; ARGS_CURTOS=()
for a in "$@"; do
  case $a in
    --config)       COMANDO=config ;;
    --help|--ajuda) COMANDO=ajuda ;;
    --)             ARGS_CURTOS+=("$a") ;;
    --*)            t opcao_invalida "$a"; erro "$TXT"; uso; exit 2 ;;
    *)              ARGS_CURTOS+=("$a") ;;
  esac
done
set -- "${ARGS_CURTOS[@]}"

OPCOES=(); LISTA_EXPLICITA=0; FORCAR=0
while getopts ":l:o:j:c:b:r:L:pausivFh" op; do
  case $op in
    l) ARQUIVO_LINKS=$OPTARG; LISTA_EXPLICITA=1; ORIGEM[ARQUIVO_LINKS]=opção; continue ;;
    o) PASTA_SAIDA=$OPTARG;            ORIGEM[PASTA_SAIDA]=opção ;;
    j) DOWNLOADS_SIMULTANEOS=$OPTARG;  ORIGEM[DOWNLOADS_SIMULTANEOS]=opção ;;
    c) CONEXOES_POR_VIDEO=$OPTARG;     ORIGEM[CONEXOES_POR_VIDEO]=opção ;;
    b) COOKIES_NAVEGADOR=$OPTARG;      ORIGEM[COOKIES_NAVEGADOR]=opção ;;
    r) RESOLUCAO_MAXIMA=$OPTARG;       ORIGEM[RESOLUCAO_MAXIMA]=opção ;;
    F) FORCAR=1 ;;
    L) ;;                              # já tratado acima, antes de carregar os textos
    p) SEM_PLAYLIST=1;                 ORIGEM[SEM_PLAYLIST]=opção ;;
    u) SO_PRINCIPAL=1;                 ORIGEM[SO_PRINCIPAL]=opção ;;
    a) LEGENDAS_AUTOMATICAS=1;         ORIGEM[LEGENDAS_AUTOMATICAS]=opção ;;
    s) SPONSORBLOCK=1;                 ORIGEM[SPONSORBLOCK]=opção ;;
    i) USAR_HISTORICO=0;               ORIGEM[USAR_HISTORICO]=opção ;;
    v) VERIFICAR=1;                    ORIGEM[VERIFICAR]=opção ;;
    h) COMANDO=ajuda ;;
    :) t opcao_valor "$OPTARG"; erro "$TXT"; exit 2 ;;
    *) t opcao_invalida "-$OPTARG"; erro "$TXT"; uso; exit 2 ;;
  esac
  OPCOES+=("-$op" ${OPTARG+"$OPTARG"})        # guardadas para sugerir o comando de nova tentativa
done
shift $(( OPTIND - 1 ))
ARGS_LINKS=("$@")
[[ -z $ARQUIVO_HISTORICO ]] && ARQUIVO_HISTORICO="$PASTA_SAIDA/.grabit-historico.txt"

[[ $COMANDO == ajuda ]] && { uso; exit 0; }

if [[ -n $IDIOMA_INVALIDO ]]; then t idioma_invalido "$IDIOMA_INVALIDO" "$LINGUA"; aviso "$TXT"; fi
origem_txt() { FMT=${T[origem_${ORIGEM[$1]:-padrão}]}; }  # origem_txt CHAVE → FMT: de onde veio o valor
for nome in DOWNLOADS_SIMULTANEOS CONEXOES_POR_VIDEO TENTATIVAS; do
  if ! [[ ${!nome} =~ ^[1-9][0-9]*$ ]]; then
    origem_txt "$nome"; t val_numero "$nome" "${!nome}" "$FMT"; erro "$TXT"
    exit 2
  fi
done
for nome in LEGENDAS_AUTOMATICAS SPONSORBLOCK SEM_PLAYLIST SO_PRINCIPAL VERIFICAR USAR_HISTORICO; do
  if ! [[ ${!nome} =~ ^[01]$ ]]; then
    origem_txt "$nome"; t val_01 "$nome" "${!nome}" "$FMT"; erro "$TXT"
    exit 2
  fi
done
# Resolução: "1080", "1080p", "4k" e "8k" viram a altura; vazio ou 0 = desligado
for nome in RESOLUCAO_MAXIMA RESOLUCAO_ALERTA; do
  case ${!nome,,} in
    "") printf -v "$nome" 0 ;;
    4k) printf -v "$nome" 2160 ;;
    8k) printf -v "$nome" 4320 ;;
    *)
      if [[ ${!nome,,} =~ ^([0-9]{1,5})p?$ ]]; then
        printf -v "$nome" '%d' $(( 10#${BASH_REMATCH[1]} ))
      else
        origem_txt "$nome"; t val_resolucao "$nome" "${!nome}" "$FMT"; erro "$TXT"
        exit 2
      fi ;;
  esac
done

# --config: onde está o arquivo e os valores em uso, com a origem de cada um
mostra_config() {
  local k v pad
  printf '\n  %sgrabit.config%s  %s' "$NEG" "$R" "$CONFIG_ARQ"
  if (( CONFIG_CRIADO )); then printf '  %s%s%s\n\n' "$VERDE" "${T[cfg_criado]}" "$R"
  elif [[ -f $CONFIG_ARQ ]]; then printf '\n\n'
  else printf '  %s%s%s\n\n' "$AMARELO" "${T[cfg_inexistente]}" "$R"; fi
  for k in "${CHAVES_CONFIG[@]}"; do
    v=${!k:-—}; origem_txt "$k"
    pad=""; (( ${#v} < 22 )) && printf -v pad '%*s' $(( 22 - ${#v} )) ''   # por caracteres: "—" ocupa 3 bytes
    printf '  %-22s %s%s%s%s %s%s%s\n' "$k" "$NEG" "$v" "$R" "$pad" "$DIM" "$FMT" "$R"
  done
  for v in "${AVISOS_CONFIG[@]}"; do t cfg_linha "${v%%:*}" "${v#*:}"; aviso "$TXT"; done
  printf '\n'
}
[[ $COMANDO == config ]] && { mostra_config; exit 0; }

# -F: os limites que vieram do grabit.config (ou do ambiente) não valem nesta execução;
# os passados no próprio comando continuam valendo.
LIMITE_IGNORADO=0
if (( FORCAR && RESOLUCAO_MAXIMA > 0 )) && [[ ${ORIGEM[RESOLUCAO_MAXIMA]:-} != opção ]]; then
  LIMITE_IGNORADO=$RESOLUCAO_MAXIMA; RESOLUCAO_MAXIMA=0
fi
# Alerta de baixa resolução: nunca acima do limite escolhido (com limite de 480p,
# avisar de tudo abaixo de 720p seria só ruído)
ALERTA=$RESOLUCAO_ALERTA
(( RESOLUCAO_MAXIMA > 0 && RESOLUCAO_MAXIMA < ALERTA )) && ALERTA=$RESOLUCAO_MAXIMA

# ───────────────────────────── Estado global ──────────────────────────────────
J=0; TOTAL=0; COLS=100; TICK=0; LIVE_H=0; CANCELADO=0; SINAL=""; STTY_SAVE=""; TMP=""
N_OK=0; N_JA=0; N_ERRO=0; N_AVISOS=0; N_FATAIS=0; N_COSMETICOS=0; AVISO_CTX=""; BYTES_NOVOS=0; FINALIZADOS=0; DUPLICADOS=0; INVALIDAS=0
VEL_TOTAL=0; EM_REPETICAO=0; PROXIMO=1; REDIM=1; JANELA=""; TITULO_EMPILHADO=0; COMECOU=0
ULTIMO_PID=0; IMPERSONATE=""; JS_RUNTIME=""; JS_PATH=""; YTDLP_VER=""; FFMPEG_VER=""; TEM_JS_RUNTIMES=0
S_H=0; S_FPS=0; S_HDR="SDR"; S_VC=""; S_AC=""; S_CANAIS=0; S_DUR=0; S_TAM=0
FMT=""; LARG=0; LINHA=""; BARRA=""; META=""; NUM=0; ETAPA=""; MOTIVO=""; DICA=""; REPETE=1; ARQUIVO_RUIM=0
FORMATO='bv*+ba/b'; PRINCIPAL=0; HOJE=""
FONTE_LINKS=""; LOG_DIR=""; DIR_TEMP=""; TEMP_REL=""; N_NA_SECAO=0; N_MOVIDOS=0; N_BAIXA_RES=0
MARCA_BAIXADOS=${T[marca]}
LINKS=(); SLOT_IDX=(); SLOT_PID=(); PERM=(); LIVE=(); FALHAS=(); YTDLP_ARGS=(); REPETIR=()
TENTATIVA=(); FEITO=(); REBAIXAR=(); SUCESSO=(); NOTA=(); ARQUIVOS_ENTRADA=(); PALAVRAS_LINK=()
declare -A TITULO=() CACHE_CORTA=()
SEP=$'\x1f'                                  # separador de campos nos logs
SPIN=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
UNID=(B KiB MiB GiB TiB)

# ───────────────────────────── Formatação ─────────────────────────────────────
# Todas devolvem o resultado em variável global (evita subshells a 5 quadros/s)

num() {                                       # NUM = parte inteira, ou 0
  local v=${1%%.*}
  if [[ $v =~ ^[0-9]+$ ]]; then NUM=$v; else NUM=0; fi
}

fmt_bytes() {                                 # 1536000 → "1.5 MiB"
  local b=${1:-0} i=0 d=1 v
  [[ $b =~ ^[0-9]+$ ]] || b=0
  while (( b >= d * 1024 && i < 4 )); do d=$(( d * 1024 )); i=$(( i + 1 )); done
  if (( i == 0 )); then
    FMT="${b} B"
  else
    v=$(( b * 10 / d ))
    FMT="$(( v / 10 )).$(( v % 10 )) ${UNID[$i]}"
  fi
}

fmt_tempo() {                                 # 3725 → 01:02:05
  local s=${1:-0}
  printf -v FMT '%02d:%02d:%02d' $(( s / 3600 )) $(( s % 3600 / 60 )) $(( s % 60 ))
}

fmt_dur() {                                   # 125 → 02:05 · 3725 → 1:02:05
  local s=${1:-0}
  if (( s >= 3600 )); then
    printf -v FMT '%d:%02d:%02d' $(( s / 3600 )) $(( s % 3600 / 60 )) $(( s % 60 ))
  else
    printf -v FMT '%02d:%02d' $(( s / 60 )) $(( s % 60 ))
  fi
}

# corta(texto, colunas) → FMT (com reticências se não couber) e LARG (colunas que
# FMT ocupa). Mede colunas, não caracteres: emoji e CJK ocupam 2, acentos
# combinantes 0 — senão títulos como "🔥 测试" empurram o fim da linha para fora.
corta() {
  local s=$1 n=$2 i c cp cw w=0 corte=0 w_corte=0 chave
  if (( n < 1 )); then FMT=""; LARG=0; return; fi
  if [[ $s != *[![:ascii:]]* ]]; then         # só ASCII: 1 caractere = 1 coluna
    if (( ${#s} > n )); then FMT="${s:0:n-1}…"; else FMT=$s; fi
    LARG=${#FMT}; return
  fi
  chave="$n$SEP$s"
  if [[ -n ${CACHE_CORTA[$chave]:-} ]]; then
    LARG=${CACHE_CORTA[$chave]%%"$SEP"*}; FMT=${CACHE_CORTA[$chave]#*"$SEP"}; return
  fi
  for (( i = 0; i < ${#s}; i++ )); do
    c=${s:i:1}
    printf -v cp '%d' "'$c"
    if (( cp < 0x300 )); then cw=1
    elif (( (cp >= 0x300 && cp <= 0x36F) || (cp >= 0x200B && cp <= 0x200F) || (cp >= 0xFE00 && cp <= 0xFE0F) ||
            cp == 0x20E3 || (cp >= 0x1F3FB && cp <= 0x1F3FF) )); then cw=0
    elif (( (cp >= 0x1100 && cp <= 0x115F) || (cp >= 0x2E80 && cp <= 0xA4CF && cp != 0x303F) ||
            (cp >= 0xAC00 && cp <= 0xD7A3) || (cp >= 0xF900 && cp <= 0xFAFF) || (cp >= 0xFE30 && cp <= 0xFE4F) ||
            (cp >= 0xFF00 && cp <= 0xFF60) || (cp >= 0xFFE0 && cp <= 0xFFE6) || (cp >= 0x1F300 && cp <= 0x1F64F) ||
            (cp >= 0x1F680 && cp <= 0x1F6FF) || (cp >= 0x1F900 && cp <= 0x1FAFF) || (cp >= 0x20000 && cp <= 0x3FFFD) ||
            cp == 0x231A || cp == 0x231B || (cp >= 0x23E9 && cp <= 0x23EC) || cp == 0x23F0 || cp == 0x23F3 ||
            cp == 0x2614 || cp == 0x2615 || (cp >= 0x2648 && cp <= 0x2653) || cp == 0x26A1 || cp == 0x26BD ||
            cp == 0x26BE || cp == 0x2705 || cp == 0x270A || cp == 0x270B || cp == 0x2728 || cp == 0x274C ||
            (cp >= 0x2753 && cp <= 0x2757) || (cp >= 0x2795 && cp <= 0x2797) || cp == 0x2B50 || cp == 0x2B55 )); then cw=2
    else cw=1
    fi
    if (( w + cw > n - 1 && corte == 0 )); then corte=$i; w_corte=$w; fi
    w=$(( w + cw ))
    (( w > n )) && break
  done
  if (( w <= n )); then FMT=$s; LARG=$w; else FMT="${s:0:corte}…"; LARG=$(( w_corte + 1 )); fi
  (( ${#CACHE_CORTA[@]} > 2000 )) && CACHE_CORTA=()
  CACHE_CORTA[$chave]="$LARG$SEP$FMT"
}

barra() {                                     # barra(preenchido, largura) → BARRA
  local fill=$1 w=$2 a b
  (( fill > w )) && fill=$w
  (( fill < 0 )) && fill=0
  printf -v a '%*s' "$fill" ''
  printf -v b '%*s' "$(( w - fill ))" ''
  BARRA="${VERDE}${a// /━}${R}${CINZA}${b// /━}${R}"
}

nome_codec() {                                # avc1.640028 → h264
  case "${1%%.*}" in
    avc1|avc3)  FMT=h264 ;;
    hev1|hvc1)  FMT=hevc ;;
    vp09)       FMT=vp9  ;;
    av01)       FMT=av1  ;;
    mp4a)       FMT=aac  ;;
    ec-3)       FMT=eac3 ;;
    ac-3)       FMT=ac3  ;;
    none|""|"?") FMT=""  ;;
    *)          FMT="${1%%.*}" ;;
  esac
}

montar_meta() {                               # h fps hdr vcodec acodec canais duração bytes → META
  local h fps hdr=$3 res="" vc ac cod="" p=() i
  num "$1"; h=$NUM; num "$2"; fps=$NUM
  if (( h > 0 )); then
    res="${h}p"
    (( fps > 30 )) && res+="$fps"
    [[ -n $hdr && $hdr != SDR && $hdr != NA ]] && res+=" $hdr"
    p+=("$res")
  fi
  nome_codec "$4"; vc=$FMT
  nome_codec "$5"; ac=$FMT
  if [[ -n $ac ]]; then                       # som surround merece destaque
    num "$6"
    case $NUM in 6) ac+=" 5.1" ;; 8) ac+=" 7.1" ;; esac
  fi
  cod=$vc
  [[ -n $vc && -n $ac ]] && cod+="+"
  cod+=$ac
  [[ -n $cod ]] && p+=("$cod")
  num "$8"; if (( NUM > 0 )); then fmt_bytes "$NUM"; p+=("$FMT"); fi
  num "$7"; if (( NUM > 0 )); then fmt_dur "$NUM"; p+=("$FMT"); fi
  META=""
  for i in "${!p[@]}"; do
    (( i > 0 )) && META+=" · "
    META+=${p[$i]}
  done
}

# linha_resultado GLIFO COR IDX TITULO META → LINHA (com pontilhado até a meta)
linha_resultado() {
  local g=$1 cor=$2 idx=$3 t=$4 m=$5 dots pad avail fixo
  fixo=$(( 2 + 1 + 1 + ${#idx} + 2 ))                      # "  ✔ 1/4  "
  avail=$(( COLS - fixo - ${#m} - 4 ))
  if (( avail < 24 )); then                                # terminal estreito: meta vai para a linha de baixo
    corta "$t" $(( COLS - fixo - 1 )); t=$FMT
    corta "$m" $(( COLS - fixo - 1 )); m=$FMT
    printf -v pad '%*s' "$fixo" ''
    LINHA="  ${cor}${g}${R} ${DIM}${idx}${R}  ${t}"$'\n'"${pad}${CIANO}${m}${R}"
    return
  fi
  corta "$t" "$avail"; t=$FMT
  pad=$(( avail - LARG + 1 ))
  (( pad < 1 )) && pad=1
  printf -v dots '%*s' "$pad" ''
  LINHA="  ${cor}${g}${R} ${DIM}${idx}${R}  ${t} ${DIM}${dots// /·}${R} ${CIANO}${m}${R}"
}

atualiza_largura() {                          # relê o tamanho do terminal (no início e a cada SIGWINCH)
  (( INTERATIVO && REDIM )) || return 0
  REDIM=0
  COLS=$(tput cols 2>/dev/null) || COLS=80
  [[ $COLS =~ ^[0-9]+$ ]] || COLS=80
  (( COLS < 50 )) && COLS=50
  return 0
}

# ───────────────────────────── Erros do yt-dlp ────────────────────────────────
# analisa_log LOG → N_FATAIS, N_COSMETICOS, MOTIVO (último erro fatal) e AVISO_CTX.
# Um ERROR seguido de @@D@@ (o arquivo final foi entregue mesmo assim) foi só
# cosmético — ex.: a capa não converteu. Fatal é o erro de um item que nunca
# chegou ao fim. O yt-dlp sai com código 1 nos dois casos.
analisa_log() {
  local r=()
  mapfile -t r < <(awk '
    /^ERROR:/                         { if (!pend) ctx = ant; pend = 1; msg = $0; next }
    /^\[download\] Downloading item / { if (pend) { fatais++; fatal = msg } pend = 0 }
    /^@@D@@/                          { if (pend) { cosm++; avctx = ctx } pend = 0 }
    !/^(@@P@@|WARNING:)/              { ant = $0 }
    END {
      if (pend) { fatais++; fatal = msg }
      print fatais + 0; print cosm + 0; print fatal; print avctx
    }' "$1" 2>/dev/null)
  N_FATAIS=${r[0]:-0}; N_COSMETICOS=${r[1]:-0}; MOTIVO=${r[2]:-}; AVISO_CTX=${r[3]:-}
  [[ -z $MOTIVO ]] && MOTIVO=$(grep -av -e '^@@' -e '^WARNING:' "$1" 2>/dev/null | tail -n 1)
  if [[ $MOTIVO == *"error code 86" ]]; then  # reprovado na verificação (-v): mostra o que o ffmpeg achou
    MOTIVO=$(grep -a '^@@V@@ERRO ' "$1" 2>/dev/null | tail -n 1)
    MOTIVO="ERROR: [Verify] ${MOTIVO#@@V@@ERRO }"
  fi
  MOTIVO=${MOTIVO//[[:cntrl:]]/ }
}

# classifica_erro TEXTO → DICA (explicação curta), REPETE (0 = não adianta tentar de
# novo) e ARQUIVO_RUIM (1 = o arquivo baixado está corrompido: refazer do zero)
classifica_erro() {
  DICA=""; REPETE=1; ARQUIVO_RUIM=0
  case ${1,,} in
    *"[verify]"*)                                           t d_verificacao "${T[sufixo_ruim]}"; DICA=$TXT ;;
    *"private video"*)                                      DICA=${T[d_privado]}; REPETE=0 ;;
    *"confirm your age"*|*"age-restricted"*|*"inappropriate for some users"*)
                                                            DICA=${T[d_idade]}; REPETE=0 ;;
    *"not a bot"*)                                          DICA=${T[d_bot]}; REPETE=0 ;;
    *"members-only"*|*"join this channel"*)                 DICA=${T[d_membros]}; REPETE=0 ;;
    *"not available in your country"*|*"geo restrict"*|*"geo-restrict"*)
                                                            DICA=${T[d_regiao]}; REPETE=0 ;;
    *"video unavailable"*|*"has been removed"*|*"no longer available"*)
                                                            DICA=${T[d_removido]}; REPETE=0 ;;
    *"unsupported url"*|*"is not a valid url"*)             DICA=${T[d_url]}; REPETE=0 ;;
    *"live event will begin"*|*"premieres in"*)             DICA=${T[d_live]}; REPETE=0 ;;
    *"http error 404"*|*"http error 410"*)                  DICA=${T[d_404]}; REPETE=0 ;;
    *"no space left"*)                                      DICA=${T[d_disco]}; REPETE=0 ;;
    *"requested format is not available"*)                  REPETE=0
      if (( RESOLUCAO_MAXIMA > 0 )); then
        if [[ ${ORIGEM[RESOLUCAO_MAXIMA]:-} == opção ]]; then t d_resolucao_r "$RESOLUCAO_MAXIMA"
        else t d_resolucao "$RESOLUCAO_MAXIMA"; fi
        DICA=$TXT
      fi ;;
    *"invalid data found when processing input"*|*"moov atom not found"*|*"ebml header parsing failed"*)
                                                            DICA=${T[d_invalido]}; ARQUIVO_RUIM=1 ;;
    *"fragment"*"not found"*|*"unable to download fragment"*) DICA=${T[d_fragmento]} ;;
    *"http error 403"*)                                     DICA=${T[d_403]} ;;
    *"http error 429"*|*"too many requests"*)               DICA=${T[d_429]} ;;
    *"timed out"*|*"connection reset"*|*"name resolution"*|*"name or service not known"*|*"network is unreachable"*)
                                                            DICA=${T[d_rede]} ;;
  esac
}

# ───────────────────────────── Painel ao vivo ─────────────────────────────────
etapa_da_linha() {                            # o que uma linha do log diz sobre a etapa → ETAPA ("" = nada)
  ETAPA=""
  case $1 in
    *"aren't any"*|*"are no "*|*"Not remuxing"*|"Deleting original"*|WARNING:*) ;;   # "nada a fazer"
    @@D@@*|"[MoveFiles]"*)                                         ETAPA=${T[et_finalizando]} ;;
    "[grabit] principal"*)                                         ETAPA=${T[et_principal]} ;;
    "[Exec]"*)                                                     ETAPA=${T[et_verificando]} ;;
    "[Merger]"*)                                                   ETAPA=${T[et_mesclando]} ;;
    "[VideoRemuxer]"*)                                             ETAPA=${T[et_mkv]} ;;
    "[Metadata]"*|"[EmbedInfoJson]"*)                              ETAPA=${T[et_metadados]} ;;
    "[EmbedSubtitle]"*|"[SubtitlesConvertor]"*)                    ETAPA=${T[et_legendas_emb]} ;;
    "[EmbedThumbnail]"*|"[ThumbnailsConvertor]"*)                  ETAPA=${T[et_capa_emb]} ;;
    "[SponsorBlock]"*|"[ModifyChapters]"*)                         ETAPA=${T[et_capitulos]} ;;
    "[Fixup"*)                                                     ETAPA=${T[et_fixup]} ;;
    *"Downloading subtitles"*|*"Writing video subtitles"*)         ETAPA=${T[et_legendas]} ;;
    *"Downloading video thumbnail"*|*"Writing video thumbnail"*)   ETAPA=${T[et_capa]} ;;
    *" has already been recorded in the archive")                  ETAPA=${T[et_hist]} ;;
    *" has already been downloaded")                               ETAPA=${T[et_existe]} ;;
    "[download] Destination"*|"[info] "*" format(s): "*|"[hlsnative]"*|"[dashsegments]"*)
                                                                   ETAPA=${T[et_iniciando]} ;;
    @@P@@*)                                                        ETAPA=${T[et_processando]} ;;
    "[download] Downloading item "*)
      if [[ $1 =~ item\ ([0-9]+)\ of\ ([0-9]+) ]]; then
        t et_item "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"; ETAPA=$TXT
      fi ;;
  esac
}

bloco_job() {                                 # monta as 2 linhas de um slot (slot livre não aparece)
  local s=$1
  local idx=${SLOT_IDX[$s]}
  (( idx == 0 )) && return

  local log="$TMP/$idx.log" ult=() linha="" k idxs spin titulo pre="" pre_txt="" l1 l2 seps tent
  mapfile -t ult < <(tail -n 30 "$log" 2>/dev/null)
  for (( k = ${#ult[@]} - 1; k >= 0; k-- )); do
    linha=${ult[$k]}
    [[ $linha == WARNING:* ]] && continue
    if [[ $linha == @@P@@* ]]; then           # linha de progresso pela metade (ainda sendo escrita)? usa a anterior
      seps=${linha//[!$SEP]/}
      (( ${#seps} == 10 )) || continue
    fi
    break
  done
  (( k < 0 )) && linha=""

  printf -v idxs "%0${#TOTAL}d/%d" "$idx" "$TOTAL"
  spin=${SPIN[$(( TICK % ${#SPIN[@]} ))]}
  titulo=${TITULO[$idx]:-${LINKS[$(( idx - 1 ))]}}
  tent=${TENTATIVA[$idx]:-1}
  if (( tent > 1 )); then t tentativa_n "$tent"; pre_txt=$TXT; pre="${AMARELO}${pre_txt}${R}"; fi

  if [[ $linha == @@P@@* ]]; then
    local baixado total vel eta pidx pn vcod alt fps ext ttl tipo bw p10 pct detalhe fb ft resto parte vs="" es=""
    IFS=$SEP read -r baixado total vel eta pidx pn vcod alt fps ext ttl <<<"${linha#@@P@@}"
    ttl=${ttl//[[:cntrl:]]/ }
    if [[ -n $ttl && $ttl != "?" ]]; then TITULO[$idx]=$ttl; titulo=$ttl; fi
    num "$baixado"; baixado=$NUM
    num "$total";   total=$NUM
    num "$vel";     vel=$NUM
    num "$eta";     eta=$NUM
    VEL_TOTAL=$(( VEL_TOTAL + vel ))
    if [[ $pidx =~ ^[0-9]+$ ]]; then pre_txt+="item ${pidx}${pn:+/$pn} · "; pre+="${DIM}item ${pidx}${pn:+/$pn} · ${R}"; fi
    case $ext in
      vtt|srt|ass|ssa|ttml|dfxp|srv[123]|json3|lrc) tipo=${T[tipo_legendas]} ;;
      *)
        if [[ $vcod == none ]]; then
          tipo=${T[tipo_audio]}
        else                                  # ex.: "vídeo 2160p60" — dá para ver a qualidade chegando
          tipo=${T[tipo_video]}; num "$alt"
          if (( NUM > 0 )); then tipo+=" ${NUM}p"; num "$fps"; (( NUM > 30 )) && tipo+="$NUM"; fi
        fi ;;
    esac

    corta "$titulo" $(( COLS - (2 + 1 + 1 + ${#idxs} + 2) - ${#pre_txt} - 2 ))
    l1="  ${ACENTO}${spin}${R} ${DIM}${idxs}${R}  ${pre}${FMT}"

    # A largura da barra depende só da largura do terminal (não do conteúdo), para
    # ela não "pular" entre quadros; os detalhes à direita entram enquanto couberem.
    bw=$(( COLS - 76 ))
    (( bw > 30 )) && bw=30
    (( bw < 10 )) && bw=10
    resto=$(( COLS - 14 - bw ))                 # "     " + barra + "  " + "100.0%" + margem
    fmt_bytes "$baixado"; fb=$FMT
    if (( total > 0 )); then
      p10=$(( baixado * 1000 / total )); (( p10 > 1000 )) && p10=1000
      printf -v pct '%3d.%d%%' $(( p10 / 10 )) $(( p10 % 10 ))
      fmt_bytes "$total"; ft=$FMT
      detalhe="  ${fb} / ${ft}"
    else
      p10=0; pct="  ··· "
      detalhe="  ${fb}"
    fi
    if (( vel > 0 )); then fmt_bytes "$vel"; vs="${FMT}/s"; fi
    if (( eta > 0 )); then fmt_dur "$eta";  es="ETA ${FMT}"; fi
    for parte in "$vs" "$es" "$tipo"; do
      [[ -n $parte ]] || continue
      (( ${#detalhe} + 2 + ${#parte} <= resto )) || break
      detalhe+="  ${parte}"
    done
    barra $(( p10 * bw / 1000 )) "$bw"
    l2="     ${BARRA}  ${NEG}${pct}${R}${DIM}${detalhe}${R}"
  elif [[ $linha == @@V@@*"$SEP"* ]]; then      # verificação completa (-v): quanto já foi decodificado
    local pos dur bw p10 pct det
    IFS=$SEP read -r pos dur <<<"${linha#@@V@@}"
    num "$pos"; pos=$NUM; num "$dur"; dur=$NUM
    corta "$titulo" $(( COLS - (2 + 1 + 1 + ${#idxs} + 2) - ${#pre_txt} - 2 ))
    l1="  ${ACENTO}${spin}${R} ${DIM}${idxs}${R}  ${pre}${FMT}"
    bw=$(( COLS - 76 )); (( bw > 30 )) && bw=30; (( bw < 10 )) && bw=10
    if (( dur > 0 )); then
      p10=$(( pos * 1000 / dur )); (( p10 > 1000 )) && p10=1000
      printf -v pct '%3d.%d%%' $(( p10 / 10 )) $(( p10 % 10 ))
    else
      p10=0; pct="  ··· "
    fi
    fmt_dur "$pos"; det="  ${T[et_verificando]} · ${FMT}"
    if (( dur > 0 )); then fmt_dur "$dur"; det+=" / ${FMT}"; fi
    corta "$det" $(( COLS - 14 - bw )); det=$FMT
    barra $(( p10 * bw / 1000 )) "$bw"
    l2="     ${BARRA}  ${NEG}${pct}${R}${DIM}${det}${R}"
  else
    # Sem progresso agora: a linha informativa mais recente do log diz a etapa
    # (extraindo, baixando legendas, mesclando, embutindo…).
    ETAPA=""
    for (( k = ${#ult[@]} - 1; k >= 0; k-- )); do
      etapa_da_linha "${ult[$k]}"
      [[ -n $ETAPA ]] && break
    done
    [[ -z $ETAPA ]] && ETAPA=${T[et_info]}
    corta "$titulo" $(( COLS - (2 + 1 + 1 + ${#idxs} + 2) - ${#pre_txt} - 2 ))
    l1="  ${ACENTO}${spin}${R} ${DIM}${idxs}${R}  ${pre}${FMT}"
    l2="     ${DIM}↳ ${ETAPA}…${R}"
  fi
  LIVE+=("$l1" "$l2")
}

monta_live() {
  LIVE=(); VEL_TOTAL=0
  local s larg reg bw l w i plano partes=() cores=()
  for (( s = 0; s < J; s++ )); do bloco_job "$s"; done

  larg=$(( COLS - 4 )); (( larg > 78 )) && larg=78
  printf -v reg '%*s' "$larg" ''
  LIVE+=("  ${CINZA}${reg// /─}${R}")

  # barra total com largura fixa por terminal; some em terminal estreito
  l="  ${NEG}${T[total]}${R} "; w=$(( 3 + ${#T[total]} ))
  bw=$(( COLS - 76 )); (( bw > 24 )) && bw=24
  if (( bw >= 6 )); then
    barra $(( FINALIZADOS * bw / TOTAL )) "$bw"
    l+="${BARRA}  "; w=$(( w + bw + 2 ))
  fi
  plano="${FINALIZADOS}/${TOTAL}  ✔ ${N_OK}  ↷ ${N_JA}  ✖ ${N_ERRO}"
  l+="${NEG}${FINALIZADOS}/${TOTAL}${R}  ${VERDE}✔ ${N_OK}${R}  ${AMARELO}↷ ${N_JA}${R}  ${VERMELHO}✖ ${N_ERRO}${R}"
  w=$(( w + ${#plano} ))
  # o resto entra enquanto couber, do mais para o menos importante
  if (( EM_REPETICAO > 0 )); then partes+=("↻ ${EM_REPETICAO}"); cores+=("$AMARELO"); fi
  fmt_tempo "$SECONDS";     partes+=("◷ ${FMT}"); cores+=("$DIM")
  fmt_bytes "$BYTES_NOVOS"; partes+=("▣ ${FMT}"); cores+=("$DIM")
  if (( VEL_TOTAL > 0 )); then fmt_bytes "$VEL_TOTAL"; partes+=("⇣ ${FMT}/s"); cores+=("$CIANO"); fi
  for i in "${!partes[@]}"; do
    (( w + 2 + ${#partes[$i]} < COLS )) || break
    l+="  ${cores[$i]}${partes[$i]}${R}"; w=$(( w + 2 + ${#partes[$i]} ))
  done
  LIVE+=("$l")
}

# desenha [final] — imprime as linhas permanentes pendentes e redesenha o painel
desenha() {
  local out="" l j
  TICK=$(( TICK + 1 ))
  # DEC 2026 (synchronized output): terminais que suportam só mostram o quadro
  # pronto; os que não suportam ignoram a sequência.
  (( INTERATIVO )) && out+="${ESC}[?2026h"
  if (( INTERATIVO && LIVE_H > 0 )); then
    out+="${ESC}[${LIVE_H}A"$'\r'"${ESC}[J"
    LIVE_H=0
  fi
  for l in "${PERM[@]}"; do out+="$l"$'\n'; done
  PERM=()
  if (( INTERATIVO )) && [[ ${1:-} != final ]]; then
    monta_live
    for l in "${LIVE[@]}"; do out+="$l"$'\n'; done
    LIVE_H=${#LIVE[@]}
    j="${FINALIZADOS}/${TOTAL} · GrabIt"           # título da janela/aba do terminal
    if [[ $j != "$JANELA" ]]; then out+="${ESC}]0;${j}"$'\a'; JANELA=$j; fi
  fi
  [[ ${1:-} == final ]] && (( INTERATIVO )) && out+="${ESC}[?7h"   # religa a quebra de linha
  (( INTERATIVO )) && out+="${ESC}[?2026l"
  printf '%s' "$out"
}

# ───────────────────────────── Resultado de cada link ─────────────────────────
salva_log() {                                 # guarda o log de todas as tentativas (sem o spam de progresso)
  local idx=$1 t tent=${TENTATIVA[$1]:-1} nome
  mkdir -p "$LOG_DIR" 2>/dev/null || return 0
  printf -v nome '%s/%0*d.log' "$LOG_DIR" "${#TOTAL}" "$idx"
  {
    printf '# %s\n' "${LINKS[$(( idx - 1 ))]}"
    for (( t = 1; t <= tent; t++ )); do
      if (( tent > 1 )); then t log_tentativa "$t"; printf '\n%s\n' "$TXT"; fi
      if (( t < tent )); then grep -av '^@@P@@' "$TMP/$idx.t$t.log"; else grep -av '^@@P@@' "$TMP/$idx.log"; fi
    done
  } > "$nome" 2>/dev/null
}

processa_resultado() {                        # processa_resultado IDX CÓDIGO_DE_SAÍDA
  local idx=$1 rc=$2 url idxs d n_done n_ja n_hist t tent logs=() dones=() hist=()
  local tipo h fps hdr vc ac canais dur titulo vid caminho tam glifo cor det l hid filtrados=()
  local nota="" n_nota=0
  local -A baixados=()
  url=${LINKS[$(( idx - 1 ))]}
  tent=${TENTATIVA[$idx]:-1}
  printf -v idxs "%0${#TOTAL}d/%d" "$idx" "$TOTAL"
  for (( t = 1; t < tent; t++ )); do logs+=("$TMP/$idx.t$t.log"); done
  logs+=("$TMP/$idx.log")

  # Cada vídeo concluído deixa uma linha @@D@@ (em qualquer tentativa). Ele "já
  # existia" só se o yt-dlp avisou "<arquivo final> has already been downloaded"
  # e nenhuma tentativa desta execução o baixou de fato. Compara pelo nome do
  # arquivo: o aviso usa caminho relativo e o @@D@@, absoluto; e pedaços .fNNN
  # deixados por uma execução cancelada não contam.
  mapfile -t dones < <(cat "${logs[@]}" 2>/dev/null | awk -v S="$SEP" '
    index($0, "[download] ") == 1 && / has already been downloaded$/ {
      p = substr($0, 12, length($0) - 39); sub(/.*\//, "", p); ja[p] = 1; next
    }
    /^@@D@@/ {
      d = substr($0, 6); n = split(d, f, S); p = f[n]; sub(/.*\//, "", p); novo = !(p in ja)
      if (!(p in st)) { ordem[++k] = p; st[p] = novo } else if (novo) st[p] = 1
      dado[p] = d; ruim[p] = 0; ult = p
    }
    /^@@V@@ERRO/ { if (ult != "") { ruim[ult] = 1; delete ja[ult] } }   # reprovado na verificação (-v): o próximo é novo
    END { for (i = 1; i <= k; i++) if (!ruim[ordem[i]]) print (st[ordem[i]] ? "N" : "J") S dado[ordem[i]] }')
  n_done=${#dones[@]}

  for d in "${dones[@]}"; do
    IFS=$SEP read -r tipo h fps hdr vc ac dur titulo vid caminho <<<"$d"
    [[ -n $vid ]] && baixados[$vid]=1
    titulo=${titulo//[[:cntrl:]]/ }
    n_nota=$(( n_nota + 1 )); [[ -z $nota ]] && nota=$titulo
    canais=0; tam=0
    # os dados do arquivo gravado (ffprobe) valem mais que os do extrator
    if sonda "$caminho"; then h=$S_H; fps=$S_FPS; hdr=$S_HDR; vc=$S_VC; ac=$S_AC; canais=$S_CANAIS; dur=$S_DUR; tam=$S_TAM; fi
    if (( tam == 0 )); then                     # sem ffprobe: stat do GNU (Linux) ou do BSD (macOS)
      tam=$(stat -c %s -- "$caminho" 2>/dev/null || stat -f %z -- "$caminho" 2>/dev/null)
      num "$tam"; tam=$NUM
    fi
    montar_meta "$h" "$fps" "$hdr" "$vc" "$ac" "$canais" "$dur" "$tam"
    if [[ $tipo == J ]]; then
      glifo="↷"; cor=$AMARELO; N_JA=$(( N_JA + 1 ))
      META="${T[r_ja_existia]}${META:+ · $META}"
    else
      glifo="✔"; cor=$VERDE; N_OK=$(( N_OK + 1 )); BYTES_NOVOS=$(( BYTES_NOVOS + tam ))
    fi
    linha_resultado "$glifo" "$cor" "$idxs" "$titulo" "$META"
    PERM+=("$LINHA")
    # Baixou, mas o melhor que o site tinha é pouco: talvez com login (-b) haja mais
    num "$h"
    if [[ $tipo == N ]] && (( ALERTA > 0 && NUM > 0 && NUM < ALERTA )); then
      N_BAIXA_RES=$(( N_BAIXA_RES + 1 ))
      t r_baixa_det "$NUM"; corta "$TXT" $(( COLS - 13 - ${#T[r_baixa]} ))
      PERM+=("         ${AMARELO}↳ ${T[r_baixa]}${R}${DIM} ${FMT}${R}")
    fi
  done

  # Pulados pelo histórico: o yt-dlp nem abre o vídeo, então não há @@D@@.
  # A linha é "<id>: has already…" (pulado antes de acessar o site) ou
  # "<id>: <título> has already…" (pulado depois de ler a página).
  mapfile -t hist < <(cat "${logs[@]}" 2>/dev/null | grep -a 'has already been recorded in the archive$' | sort -u)
  # Um vídeo baixado na 1ª tentativa aparece como "já no histórico" na 2ª: não conta duas vezes.
  for l in "${hist[@]}"; do
    hid=${l#\[download\] }; hid=${hid%%: *}
    [[ -n ${baixados[$hid]:-} ]] || filtrados+=("$l")
  done
  hist=("${filtrados[@]}")
  n_hist=${#hist[@]}
  if (( n_hist > 0 )); then
    N_JA=$(( N_JA + n_hist )); n_nota=$(( n_nota + n_hist ))
    if (( n_done == 0 && n_hist == 1 )); then
      titulo=${hist[0]#\[download\] }
      titulo=${titulo% has already been recorded in the archive}
      if [[ $titulo == *": "* ]]; then titulo=${titulo#*: }; else titulo=""; fi
      titulo=${titulo//[[:cntrl:]]/ }
      nota=${titulo:-${TITULO[$idx]:-}}
      linha_resultado "↷" "$AMARELO" "$idxs" "${titulo:-${TITULO[$idx]:-$url}}" "${T[r_ja_baixado]}"
    else
      t r_n_ja_baixados "$n_hist"; linha_resultado "↷" "$AMARELO" "$idxs" "$url" "$TXT"
    fi
    PERM+=("$LINHA")
  fi

  if (( n_done == 0 && n_hist == 0 && rc == 0 )); then
    titulo=${TITULO[$idx]:-$url}
    nota=${TITULO[$idx]:-}
    n_ja=$(cat "${logs[@]}" 2>/dev/null | grep -ac 'has already been downloaded')
    if (( n_ja > 0 )); then
      N_JA=$(( N_JA + 1 ))
      linha_resultado "↷" "$AMARELO" "$idxs" "$titulo" "${T[r_ja_existia]}"
    else
      N_OK=$(( N_OK + 1 ))
      linha_resultado "✔" "$VERDE" "$idxs" "$titulo" "${T[r_concluido]}"
    fi
    PERM+=("$LINHA")
  fi

  if (( rc != 0 )); then
    analisa_log "$TMP/$idx.log"
    if (( N_FATAIS == 0 && N_COSMETICOS > 0 && n_done > 0 )); then
      # Tudo foi entregue; só um acabamento falhou. Aviso, não falha.
      case $AVISO_CTX in
        "[ThumbnailsConvertor]"*) det=${T[r_av_capa]} ;;
        "[SponsorBlock]"*)        det=${T[r_av_sponsor]} ;;
        *)                        det=${T[r_av_outro]} ;;
      esac
      t r_av_completo "$det"; corta "$TXT" $(( COLS - 13 - ${#T[r_aviso]} ))
      PERM+=("         ${AMARELO}↳ ${T[r_aviso]}${R}${DIM} ${FMT}${R}")
      N_AVISOS=$(( N_AVISOS + 1 ))
      salva_log "$idx"
      rc=0
    fi
  fi

  if (( rc != 0 )); then
    classifica_erro "$MOTIVO"
    MOTIVO=$(sed -E 's/^ERROR: //; s/^\[[^]]+\] //; s/^[^ :]+: //; s/ \(caused by .*$//; s/; please report this issue.*$//' <<<"$MOTIVO")
    if (( n_done > 0 || n_hist > 0 )); then
      linha_resultado "⚠" "$AMARELO" "$idxs" "${TITULO[$idx]:-$url}" "${T[r_parcial]}"
    elif (( tent > 1 )); then
      t r_falhou_n "$tent"; linha_resultado "✖" "$VERMELHO" "$idxs" "${TITULO[$idx]:-$url}" "$TXT"
    else
      linha_resultado "✖" "$VERMELHO" "$idxs" "${TITULO[$idx]:-$url}" "${T[r_falhou]}"
    fi
    if [[ -n $DICA ]]; then                     # "↳ dica no idioma do usuário · mensagem original"
      corta "$MOTIVO" $(( COLS - 15 - ${#DICA} ))
      det="${VERMELHO}↳ ${DICA}${R}"
      (( LARG >= 10 )) && det+="${DIM} · ${FMT}${R}"
    else
      t r_codigo "$rc"; corta "${MOTIVO:-$TXT}" $(( COLS - 12 ))
      det="${VERMELHO}↳ ${FMT}${R}"
    fi
    PERM+=("$LINHA" "         $det")
    FALHAS+=("$url")
    N_ERRO=$(( N_ERRO + 1 ))
    salva_log "$idx"
  fi
  if (( rc == 0 )); then
    SUCESSO[$idx]=1
    if (( n_nota > 1 )); then
      if [[ -n $nota ]]; then t nota_n "$n_nota" "$nota"; else t nota_n0 "$n_nota"; fi
      nota=$TXT
    fi
    NOTA[$idx]=$nota                           # vai junto com o link para a seção BAIXADOS
  fi

  FEITO[$idx]=1
  FINALIZADOS=$(( FINALIZADOS + 1 ))
}

# ───────────────────────────── Execução dos jobs ──────────────────────────────
lanca_job() {                                 # lanca_job IDX
  local i=$1 url=${LINKS[$(( $1 - 1 ))]} tent=${TENTATIVA[$1]:-1} extra=() idxs
  # Só a nova tentativa força a imitação de navegador: o próprio yt-dlp avisa que
  # forçá-la sempre pode deixar os downloads mais lentos e instáveis.
  (( tent > 1 )) && [[ -n $IMPERSONATE ]] && extra=(--impersonate "$IMPERSONATE")
  # O arquivo da tentativa anterior veio corrompido: sem isso o yt-dlp o reaproveitaria
  # ("has already been downloaded") e falharia igual. Itens já concluídos estão no
  # histórico e continuam sendo pulados.
  (( ${REBAIXAR[$i]:-0} )) && extra+=(--force-overwrites)
  baixa_link "$url" "${extra[@]}" </dev/null >"$TMP/$i.log" 2>&1 &
  ULTIMO_PID=$!
  if (( ! INTERATIVO )); then                  # sem painel (saída redirecionada): avisa o início
    printf -v idxs "%0${#TOTAL}d/%d" "$i" "$TOTAL"
    if (( tent > 1 )); then t ni_tentativa "$tent"; PERM+=("  ↻ ${idxs}  ${url}  $TXT"); else PERM+=("  ▶ ${idxs}  ${url}"); fi
  fi
}

# baixa_link URL [OPÇÕES EXTRAS…]: roda em segundo plano, com a saída indo para o log.
# Com -u, antes descobre qual é o vídeo principal da página e pede só ele.
baixa_link() {
  local url=$1 escolha=()
  shift
  if (( SO_PRINCIPAL )); then
    printf '[grabit] principal\n'
    escolhe_principal "$url" "$@" && escolha=(--playlist-items "$PRINCIPAL")
  fi
  exec yt-dlp "${YTDLP_ARGS[@]}" "$@" "${escolha[@]}" -- "$url"
}

# escolhe_principal URL [OPÇÕES…] → PRINCIPAL: o item mais longo da página (empate: o de
# maior resolução, depois o primeiro). O yt-dlp lista os vídeos de uma página na ordem
# em que os acha, não na ordem da página; e prévias e relacionados costumam ser curtos.
# Quando o site não informa a duração, o ffprobe lê só o cabeçalho do vídeo.
# Falha (= baixa o link como está) se não houver mais de um vídeo para comparar.
escolhe_principal() {
  local url=$1 idx dur alt link n=0 melhor=0 melhor_dur=-1 melhor_alt=-1 args=()
  shift
  [[ -n $COOKIES_NAVEGADOR ]] && args+=(--cookies-from-browser "$COOKIES_NAVEGADOR")
  (( TEM_JS_RUNTIMES )) && [[ -n $JS_RUNTIME ]] && args+=(--js-runtimes "$JS_RUNTIME:$JS_PATH")
  (( SEM_PLAYLIST )) && args+=(--no-playlist)
  while IFS=$SEP read -r idx dur alt link; do
    num "$idx"; idx=$NUM
    (( idx > 0 )) || continue
    n=$(( n + 1 ))
    num "$dur"; dur=$NUM
    if (( dur == 0 )) && [[ $link == http* ]] && command -v ffprobe >/dev/null 2>&1; then
      dur=$(ffprobe -v error -rw_timeout 15000000 -show_entries format=duration -of csv=p=0 -- "$link" 2>/dev/null)
      num "$dur"; dur=$NUM
    fi
    num "$alt"; alt=$NUM
    if (( dur > melhor_dur || (dur == melhor_dur && alt > melhor_alt) )); then
      melhor=$idx; melhor_dur=$dur; melhor_alt=$alt
    fi
  done < <(yt-dlp --ignore-config --no-warnings --simulate --playlist-items 1:20 -f "$FORMATO" \
             --print "%(playlist_index|0)s${SEP}%(duration|0)s${SEP}%(height|0)s${SEP}%(requested_formats.0.url,url|)s" \
             "${args[@]}" "$@" -- "$url" 2>/dev/null)
  (( n > 1 )) || return 1
  PRINCIPAL=$melhor
  printf '[grabit] principal: item %d de %d\n' "$PRINCIPAL" "$n"
}

# vale_repetir IDX: falhou por algo passageiro e ainda há tentativas? Se sim,
# guarda o log desta tentativa e põe o link no fim da fila.
vale_repetir() {
  local idx=$1 tent=${TENTATIVA[$1]:-1}
  (( tent < TENTATIVAS )) || return 1
  analisa_log "$TMP/$idx.log"
  (( N_FATAIS == 0 && N_COSMETICOS > 0 )) && return 1   # o vídeo saiu inteiro: repetir não muda nada
  classifica_erro "$MOTIVO"
  (( REPETE )) || return 1
  (( ARQUIVO_RUIM )) && REBAIXAR[$idx]=1
  mv -f "$TMP/$idx.log" "$TMP/$idx.t$tent.log"
  (( tent == 1 )) && EM_REPETICAO=$(( EM_REPETICAO + 1 ))
  TENTATIVA[$idx]=$(( tent + 1 ))
  REPETIR+=("$idx")
}

mata_arvore() {                               # mata o processo e seus filhos (ffmpeg…)
  local pid=$1 filho
  if command -v pgrep >/dev/null 2>&1; then
    for filho in $(pgrep -P "$pid" 2>/dev/null); do mata_arvore "$filho"; done
  fi
  kill -TERM "$pid" 2>/dev/null
}

mata_jobs() {
  local s
  for (( s = 0; s < J; s++ )); do
    (( ${SLOT_IDX[$s]:-0} > 0 )) && mata_arvore "${SLOT_PID[$s]}"
  done
  # espera até 2 s eles saírem (e recolhe os processos); o que sobrar leva SIGKILL
  local i restantes
  for (( i = 0; i < 20; i++ )); do
    restantes=$(jobs -pr)
    [[ -z $restantes ]] && break
    sleep 0.1
  done
  [[ -n $restantes ]] && kill -KILL $restantes 2>/dev/null
  wait 2>/dev/null
  return 0
}

comando_repetir() {                           # → FMT: o mesmo comando, só com os links do arquivo de falhas
  local eu=$0 nome=${0##*/} p txt=""
  if [[ $(command -v -- "$nome" 2>/dev/null) -ef $eu ]]; then eu=$nome   # instalado no PATH: basta o nome
  elif [[ $eu != */* ]]; then eu="./$eu"; fi
  [[ $eu == */* && ! -x $eu ]] && txt="bash "
  for p in "$eu" "${OPCOES[@]}" -l "$ARQUIVO_FALHAS"; do
    if [[ $p =~ ^[[:alnum:]_./:=@%+,-]+$ ]]; then txt+="$p "; else txt+="${p@Q} "; fi
  done
  FMT=${txt% }
}

salva_falhas() {                              # grava links_falhos.txt (+ o que faltava, se cancelado)
  local lista=("${FALHAS[@]}") i n_pend=0 f era_falhas=0 o_que=${T[f_com_erro]}
  if (( CANCELADO )); then
    for (( i = 1; i <= TOTAL; i++ )); do
      [[ -n ${FEITO[$i]:-} ]] && continue
      lista+=("${LINKS[$(( i - 1 ))]}"); n_pend=$(( n_pend + 1 ))
    done
  fi
  for f in "${ARQUIVOS_ENTRADA[@]}"; do [[ $f -ef $ARQUIVO_FALHAS ]] && era_falhas=1; done

  if (( ${#lista[@]} == 0 )); then
    # tudo certo: se a lista de entrada era o próprio arquivo de falhas, ele cumpriu o papel
    if (( era_falhas )) && rm -f -- "$ARQUIVO_FALHAS"; then
      t f_todos_ok "$ARQUIVO_FALHAS"; printf '\n  %s✔%s  %s\n' "$VERDE" "$R" "$TXT"
    fi
    return 0
  fi
  if ! printf '%s\n' "${lista[@]}" > "$ARQUIVO_FALHAS"; then
    t f_nao_gravou "$ARQUIVO_FALHAS"; erro "$TXT"
    return 0
  fi
  (( n_pend > 0 && N_ERRO > 0 )) && o_que=${T[f_erro_pend]}
  (( n_pend > 0 && N_ERRO == 0 )) && o_que=${T[f_pend]}
  t f_salvos "${#lista[@]}" "$o_que" "${NEG}${ARQUIVO_FALHAS}${R}"
  printf '\n  %s⚠%s  %s' "$AMARELO" "$R" "$TXT"
  if (( N_ERRO > 0 )); then t f_logs "$LOG_DIR"; printf '%s\n' "$TXT"; else printf '\n'; fi
  comando_repetir
  t f_continuar "${CIANO}${FMT}${R}"; printf '%s\n' "$TXT"
}

linha_resumo() {                              # linha_resumo GLIFO COR RÓTULO VALOR (alinha por caracteres)
  local pad
  printf -v pad '%*s' $(( 18 - ${#3} )) ''
  printf '  %s%s%s  %s%s%s\n' "$2" "$1" "$R" "$3" "$pad" "$4"
}

resumo() {
  (( INTERATIVO )) && printf '%s' "${ESC}[?7h"     # religa a quebra de linha para o texto final
  local t b media="" titulo_r=${T[s_resumo]}
  fmt_tempo "$SECONDS"; t=$FMT
  fmt_bytes "$BYTES_NOVOS"; b=$FMT
  if (( BYTES_NOVOS > 0 && SECONDS > 0 )); then
    fmt_bytes $(( BYTES_NOVOS / SECONDS )); t s_media "$FMT"; media="  ${DIM}${TXT}${R}"
  fi
  (( CANCELADO )) && titulo_r=${T[s_resumo_parcial]}
  printf '\n  %s── %s ─────────────────────────────────────%s\n' "$DIM" "$titulo_r" "$R"
  linha_resumo "✔" "$VERDE"    "${T[s_baixados]}" "${NEG}${N_OK}${R}"
  linha_resumo "↷" "$AMARELO"  "${T[s_ja]}"       "${NEG}${N_JA}${R}"
  linha_resumo "✖" "$VERMELHO" "${T[s_erro]}"     "${NEG}${N_ERRO}${R}"
  if (( N_AVISOS > 0 )); then
    t s_aviso_det "$LOG_DIR"; linha_resumo "⚠" "$AMARELO" "${T[s_aviso]}" "${NEG}${N_AVISOS}${R}  ${DIM}${TXT}${R}"
  fi
  if (( N_BAIXA_RES > 0 )); then
    t s_baixa_det "$N_BAIXA_RES" "$ALERTA"; linha_resumo "▾" "$AMARELO" "${T[s_baixa]}" "$TXT"
  fi
  linha_resumo "◷" "$DIM" "${T[s_tempo]}"         "$t"
  linha_resumo "▣" "$DIM" "${T[s_baixado_agora]}" "${b}${media}"
  linha_resumo "▸" "$DIM" "${T[s_pasta]}"         "$PASTA_SAIDA"
  if (( N_MOVIDOS > 0 )); then
    t s_movidos "$N_MOVIDOS"; linha_resumo "✎" "$DIM" "${T[s_lista]}" "$TXT"
  fi
  salva_falhas
  printf '\n'
}

limpa() {                                     # trap EXIT: sempre devolve o terminal limpo
  local rc=$?
  trap - EXIT INT TERM HUP WINCH
  mata_jobs
  descarta_parciais
  if (( CANCELADO && COMECOU )); then
    move_baixados
    desenha final
    printf '\n  %s⚠ %s%s%s\n' "$AMARELO" "${T[c_cancelado]}" "$R" "${T[c_descartado]}"
    resumo
  elif (( CANCELADO )); then
    printf '\n  %s⚠ %s%s\n\n' "$AMARELO" "${T[c_cancelado]}" "$R"
  fi
  if (( INTERATIVO )); then
    printf '%s' "${ESC}[?7h${ESC}[?25h"
    (( TITULO_EMPILHADO )) && printf '%s' "${ESC}[23;0t"     # devolve o título original da janela
    [[ -n $STTY_SAVE ]] && stty "$STTY_SAVE" 2>/dev/null
  fi
  [[ -n $TMP ]] && rm -rf "$TMP"
  # Morre pelo mesmo sinal recebido: assim um laço que chamou o script (ex.:
  # "for l in ...; do grabit ...; done") também para no Ctrl+C.
  if [[ -n $SINAL ]]; then trap - "$SINAL"; kill -s "$SINAL" "$$"; fi
  exit "$rc"
}

# Pasta temporária desta execução: .parciais/<pid>-<data>. Como nada é retomado entre
# execuções, o que sobrou de execuções anteriores é lixo e vai embora — menos a pasta de
# outro GrabIt que esteja rodando agora na mesma pasta de destino.
prepara_parciais() {
  local raiz="$PASTA_SAIDA/.parciais" item
  if [[ -d $raiz ]]; then
    for item in "$raiz"/* "$raiz"/.[!.]*; do
      [[ -e $item ]] || continue
      if [[ -d $item && ${item##*/} =~ ^([0-9]+)- ]] && kill -0 "${BASH_REMATCH[1]}" 2>/dev/null; then
        continue
      fi
      rm -rf -- "$item"
    done
  fi
  printf -v TEMP_REL '.parciais/%s-%(%Y%m%d%H%M%S)T' "$$" -1
  DIR_TEMP="$PASTA_SAIDA/$TEMP_REL"
}

descarta_parciais() {                         # apaga a pasta temporária desta execução
  [[ -n $TEMP_REL && -d $DIR_TEMP ]] && rm -rf -- "$DIR_TEMP"
  rmdir -- "$PASTA_SAIDA/.parciais" 2>/dev/null
  return 0
}

# ───────────────────────────── Verificações iniciais ──────────────────────────
cabecalho() {
  local t=${T[titulo]} w h
  w=$(( ${#t} + 4 ))
  if (( COLS < w + 4 )); then                   # terminal estreito: título simples, sem moldura
    printf '\n  %s%s%s\n\n' "$NEG" "${T[titulo_curto]}" "$R"
    return
  fi
  printf -v h '%*s' "$w" ''
  printf '\n  %s╭%s╮%s\n  %s│%s  %s%s%s  %s│%s\n  %s╰%s╯%s\n\n' \
    "$ACENTO" "${h// /─}" "$R"  "$ACENTO" "$R" "$NEG" "$t" "$R" "$ACENTO" "$R"  "$ACENTO" "${h// /─}" "$R"
}

kv() {                                        # kv RÓTULO VALOR (o valor pode ter cores)
  local v=$2 plano=${2//$'\e['+([0-9;])m/}
  # não cabe? corta com reticências (sem as cores) em vez de quebrar no meio da palavra
  if (( ${#plano} > COLS - 16 )); then corta "$plano" $(( COLS - 16 )); v=$FMT; fi
  local pad                                   # alinha por caracteres: o %-12s do printf conta bytes ("ó" = 2)
  printf -v pad '%*s' $(( 12 - ${#1} )) ''
  printf '  %s%s%s%s %s\n' "$DIM" "$1" "$R" "$pad" "$v"
}

comando_instalar() {                          # comando_instalar PACOTE → FMT (conforme o sistema)
  local g
  for g in brew apt dnf pacman zypper apk; do command -v "$g" >/dev/null 2>&1 && break; g=""; done
  case $g in
    brew)   FMT="brew install $1" ;;
    apt)    FMT="sudo apt install $1" ;;
    dnf)    FMT="sudo dnf install $1" ;;
    pacman) FMT="sudo pacman -S $1" ;;
    zypper) FMT="sudo zypper install $1" ;;
    apk)    FMT="sudo apk add $1" ;;
    *)      t dep_instale "$1"; FMT=$TXT ;;
  esac
}

verifica_dependencias() {
  local faltando=() par bin nome p1 p2 p3
  command -v yt-dlp >/dev/null 2>&1 || faltando+=("yt-dlp")
  command -v ffmpeg >/dev/null 2>&1 || faltando+=("ffmpeg")
  if (( ${#faltando[@]} )); then
    t dep_faltando "${faltando[*]}"; erro "$TXT"
    comando_instalar ffmpeg
    printf '\n     %syt-dlp%s  →  pipx install "yt-dlp[default,curl-cffi]"\n' "$CIANO" "$R"
    printf '     %sffmpeg%s  →  %s\n\n' "$CIANO" "$R" "$FMT"
    exit 1
  fi
  # cada consulta ao yt-dlp leva quase 1 s (é Python): roda as três em paralelo
  yt-dlp --version                  >"$TMP/versao" 2>/dev/null & p1=$!
  yt-dlp --help                     >"$TMP/ajuda"  2>/dev/null & p2=$!
  yt-dlp --list-impersonate-targets >"$TMP/alvos"  2>/dev/null & p3=$!
  FFMPEG_VER=$(ffmpeg -version 2>/dev/null | awk 'NR==1{print $3}')
  wait "$p1" "$p2" "$p3"
  YTDLP_VER=$(head -n 1 "$TMP/versao")
  grep -q -- '--js-runtimes' "$TMP/ajuda" && TEM_JS_RUNTIMES=1

  # --impersonate só funciona com curl_cffi instalado; senão o yt-dlp aborta
  if grep -i '^[[:space:]]*chrome' "$TMP/alvos" | grep -viq 'unavailable'; then
    IMPERSONATE="chrome"
  fi

  # YouTube precisa de um runtime JavaScript externo. O yt-dlp só liga o Deno
  # sozinho; node/quickjs/bun precisam de --js-runtimes (feito em monta_args_ytdlp).
  JS_RUNTIME=""; JS_PATH=""
  for par in deno:deno node:node node:nodejs quickjs:qjs quickjs:quickjs bun:bun; do
    nome=${par%%:*}; bin=${par#*:}
    if JS_PATH=$(command -v "$bin" 2>/dev/null) && [[ -n $JS_PATH ]]; then
      JS_RUNTIME=$nome
      break
    fi
    JS_PATH=""
  done
}

idade_ytdlp() {                               # meses desde a versão do yt-dlp (AAAA.MM.DD) → NUM (-1 = ?)
  local hoje
  NUM=-1
  [[ $YTDLP_VER =~ ^([0-9]{4})\.([0-9]{2})\. ]] || return 0
  printf -v hoje '%(%Y %m)T' -1
  NUM=$(( ${hoje% *} * 12 + 10#${hoje#* } - BASH_REMATCH[1] * 12 - 10#${BASH_REMATCH[2]} ))
}

# sonda ARQUIVO → S_H S_FPS S_HDR S_VC S_AC S_CANAIS S_DUR S_TAM, lidos do arquivo final
# com ffprobe (é o que realmente foi gravado, não o que o site prometeu). Retorna 1 se falhar.
sonda() {
  S_H=0; S_FPS=0; S_HDR="SDR"; S_VC=""; S_AC=""; S_CANAIS=0; S_DUR=0; S_TAM=0
  command -v ffprobe >/dev/null 2>&1 || return 1
  local saida linha campo tipo ok=1 a b w h fr
  local -A c=()
  local -a campos=()
  saida=$(ffprobe -v error -of compact \
    -show_entries stream=codec_type,codec_name,width,height,avg_frame_rate,r_frame_rate,color_transfer,channels:stream_disposition=attached_pic:format=duration,size \
    -- "$1" 2>/dev/null) || return 1
  while IFS= read -r linha; do
    c=(); IFS='|' read -ra campos <<<"$linha"
    for campo in "${campos[@]:1}"; do c[${campo%%=*}]=${campo#*=}; done
    tipo=${campos[0]:-}
    if [[ $tipo == stream ]]; then
      if [[ ${c[codec_type]:-} == video && -z $S_VC && ${c[disposition:attached_pic]:-0} != 1 ]]; then
        S_VC=${c[codec_name]:-}
        # a "qualidade" é o lado menor: um vídeo vertical 1080×1920 é 1080p, não 1920p
        num "${c[width]:-0}"; w=$NUM; num "${c[height]:-0}"; h=$NUM
        if (( w > 0 && w < h )); then S_H=$w; else S_H=$h; fi
        fr=${c[avg_frame_rate]:-0/0}
        [[ $fr == 0/0 ]] && fr=${c[r_frame_rate]:-0/0}
        a=${fr%%/*}; b=${fr##*/}
        if [[ $a =~ ^[0-9]+$ && $b =~ ^[0-9]+$ ]] && (( b > 0 )); then
          S_FPS=$(( (a + b / 2) / b ))
        fi
        case ${c[color_transfer]:-} in
          smpte2084)     S_HDR="HDR10" ;;
          arib-std-b67)  S_HDR="HLG" ;;
        esac
        ok=0
      elif [[ ${c[codec_type]:-} == audio && -z $S_AC ]]; then
        S_AC=${c[codec_name]:-}; num "${c[channels]:-0}"; S_CANAIS=$NUM; ok=0
      fi
    elif [[ $tipo == format ]]; then
      num "${c[duration]:-0}"; S_DUR=$NUM
      num "${c[size]:-0}";     S_TAM=$NUM
    fi
  done <<<"$saida"
  return $ok
}

# A seção BAIXADOS de um arquivo de links começa numa linha como
#   # ==================== BAIXADOS ====================   (ou DOWNLOADED, em inglês)
# e vai até o fim do arquivo: o GrabIt ignora tudo o que estiver nela.
eh_marca_baixados() {
  local l=${1%$'\r'}
  [[ ${l,,} =~ ^[[:space:]]*#[[:space:]]*=+[[:space:]]*(baixados|downloaded)[[:space:]]*=+[[:space:]]*$ ]]
}

# links_da_linha LINHA → PALAVRAS_LINK: os links da linha, sem o comentário do fim
# ("www." vira "https://www.")
links_da_linha() {
  local palavras=() p
  PALAVRAS_LINK=()
  IFS=$' \t\r' read -ra palavras <<<"${1#$'﻿'}"
  for p in "${palavras[@]}"; do
    [[ $p == \#* ]] && break
    [[ $p == www.* ]] && p="https://$p"
    [[ $p =~ ^https?:// ]] && PALAVRAS_LINK+=("$p")
  done
  return 0
}

# le_lista ARQUIVO: as linhas antes da seção BAIXADOS vão para "bruto" (de ler_links);
# os links dentro da seção só são contados
le_lista() {
  local conteudo=() linha secao=0
  mapfile -t conteudo < "$1"
  for linha in "${conteudo[@]}"; do
    if (( secao )); then
      links_da_linha "$linha"; N_NA_SECAO=$(( N_NA_SECAO + ${#PALAVRAS_LINK[@]} ))
    elif eh_marca_baixados "$linha"; then
      secao=1
    else
      bruto+=("$linha")
    fi
  done
}

# Junta os links do arquivo (-l), dos argumentos e dos arquivos passados como argumento.
ler_links() {
  local bruto=() fontes=() a linha palavra palavras=() soltos=0
  local -A visto=()
  if (( ${#ARGS_LINKS[@]} == 0 || LISTA_EXPLICITA )); then
    if [[ $ARQUIVO_LINKS == - ]]; then
      le_lista /dev/stdin; fontes+=("${T[fonte_stdin]}")
    elif [[ -f $ARQUIVO_LINKS && -r $ARQUIVO_LINKS ]]; then
      le_lista "$ARQUIVO_LINKS"; fontes+=("$ARQUIVO_LINKS"); ARQUIVOS_ENTRADA+=("$ARQUIVO_LINKS")
    else
      t sem_arquivo "$ARQUIVO_LINKS"; erro "$TXT"
      printf '%s\n\n' "${T[sem_arquivo2]}"
      exit 1
    fi
  fi
  for a in "${ARGS_LINKS[@]}"; do
    if [[ -f $a ]]; then
      le_lista "$a"; fontes+=("$a"); ARQUIVOS_ENTRADA+=("$a")
    else
      bruto+=("$a"); soltos=1
    fi
  done
  (( soltos )) && fontes+=("${T[fonte_cli]}")

  for linha in "${bruto[@]}"; do
    IFS=$' \t\r' read -ra palavras <<<"${linha#$'﻿'}"   # ﻿ do Bloco de Notas do Windows
    (( ${#palavras[@]} )) || continue
    [[ ${palavras[0]} == \#* ]] && continue
    links_da_linha "$linha"
    if (( ${#PALAVRAS_LINK[@]} == 0 )); then INVALIDAS=$(( INVALIDAS + 1 )); continue; fi
    for palavra in "${PALAVRAS_LINK[@]}"; do
      if [[ -n ${visto[$palavra]:-} ]]; then DUPLICADOS=$(( DUPLICADOS + 1 ))
      else visto[$palavra]=1; LINKS+=("$palavra"); fi
    done
  done
  TOTAL=${#LINKS[@]}
  FONTE_LINKS=$(IFS=,; printf '%s' "${fontes[*]}"); FONTE_LINKS=${FONTE_LINKS//,/, }
  if (( TOTAL == 0 )); then
    if (( N_NA_SECAO > 0 )); then
      if (( N_NA_SECAO == 1 )); then t nada_1 "$FONTE_LINKS"; else t nada_n "$N_NA_SECAO" "$FONTE_LINKS"; fi
      printf '  %s✔%s %s\n\n' "$VERDE" "$R" "$TXT"
      exit 0
    fi
    t sem_links "${FONTE_LINKS:-${T[nada]}}"; erro "$TXT"
    exit 1
  fi
}

# move_baixados: nos arquivos de links usados, as linhas cujos links terminaram todos com
# sucesso saem da parte de cima e vão para o fim da seção BAIXADOS (criada se preciso).
# O arquivo é relido agora: o que você acrescentou durante a execução não se perde.
move_baixados() {
  local -A ok=() nota=()
  local i arq
  printf -v HOJE '%(%Y-%m-%d)T' -1
  for (( i = 1; i <= TOTAL; i++ )); do
    [[ -n ${SUCESSO[$i]:-} ]] || continue
    ok[${LINKS[$(( i - 1 ))]}]=1; nota[${LINKS[$(( i - 1 ))]}]=${NOTA[$i]:-}
  done
  (( ${#ok[@]} )) || return 0
  for arq in "${ARQUIVOS_ENTRADA[@]}"; do
    [[ -f $arq && -w $arq ]] || continue
    [[ $arq -ef $ARQUIVO_FALHAS ]] && continue          # esse é regravado a cada execução
    move_no_arquivo "$arq"
  done
  return 0
}

# anota LINHA NOTA → FMT: a linha com a data e o título do que foi baixado, ex.:
#   https://site/video  # ✔ 2026-10-24 · Título do vídeo
# Se a linha já tem um comentário seu, a anotação entra no fim dele (sem outro "#").
ANOTACAO_ANTIGA='^(.*[^[:space:]])[[:space:]]+(#[[:space:]]*)?✔ [0-9]{4}-[0-9]{2}-[0-9]{2}( · .*)?$'
anota() {
  local l=$1 n=${2//[[:cntrl:]]/ } cr=""
  [[ $l == *$'\r' ]] && { cr=$'\r'; l=${l%$'\r'}; }
  # link que voltou da seção para ser baixado de novo: troca a anotação antiga
  [[ $l =~ $ANOTACAO_ANTIGA ]] && l=${BASH_REMATCH[1]}
  (( ${#n} > 120 )) && n="${n:0:119}…"
  if [[ $l =~ (^|[[:space:]])# ]]; then FMT="$l  ✔ $HOJE"; else FMT="$l  # ✔ $HOJE"; fi
  [[ -n $n ]] && FMT+=" · $n"
  FMT+=$cr
}

move_no_arquivo() {                           # move_no_arquivo ARQUIVO (usa "ok" e "nota" de move_baixados)
  local arq=$1 linha p todos secao=0 bom="" eol="" n
  local conteudo=() ativa=() resto=() movidas=()
  mapfile -t conteudo < "$arq" || return 0
  (( ${#conteudo[@]} )) || return 0
  if [[ ${conteudo[0]} == $'﻿'* ]]; then bom=$'﻿'; conteudo[0]=${conteudo[0]#$'﻿'}; fi
  [[ ${conteudo[0]} == *$'\r' ]] && eol=$'\r'          # mantém o fim de linha do Windows
  for linha in "${conteudo[@]}"; do
    if (( secao )); then resto+=("$linha"); continue; fi
    if eh_marca_baixados "$linha"; then secao=1; resto+=("$linha"); continue; fi
    links_da_linha "$linha"
    todos=$(( ${#PALAVRAS_LINK[@]} > 0 ))
    for p in "${PALAVRAS_LINK[@]}"; do [[ -n ${ok[$p]:-} ]] || { todos=0; break; }; done
    if (( todos )); then
      n=""
      for p in "${PALAVRAS_LINK[@]}"; do [[ -n ${nota[$p]:-} ]] && n+="${n:+ | }${nota[$p]}"; done
      anota "$linha" "$n"; movidas+=("$FMT")
    else
      ativa+=("$linha")
    fi
  done
  (( ${#movidas[@]} )) || return 0
  if (( ! secao )); then
    (( ${#ativa[@]} )) && [[ -n ${ativa[-1]//[[:space:]]/} ]] && resto+=("$eol")
    resto+=("${MARCA_BAIXADOS}${eol}" "${T[marca_desc]}${eol}")
  fi
  { printf '%s' "$bom"; printf '%s\n' "${ativa[@]}" "${resto[@]}" "${movidas[@]}"; } > "$arq.grabit-tmp" &&
    cat "$arq.grabit-tmp" > "$arq"
  rm -f -- "$arq.grabit-tmp"
  N_MOVIDOS=$(( N_MOVIDOS + ${#movidas[@]} ))
}

monta_args_ytdlp() {
  local langs=$IDIOMAS_LEGENDAS n=$RESOLUCAO_MAXIMA cmd
  FORMATO='bv*+ba/b'
  # Com limite, vale o lado menor da imagem: a altura em vídeos deitados e a largura nos
  # verticais. Dimensão desconhecida passa (o "?"); se nada couber, o vídeo falha.
  if (( n > 0 )); then
    FORMATO="(bv*[height<=?$n][aspect_ratio>=?1]/bv*[width<=?$n][aspect_ratio<1])+ba"
    FORMATO+="/b[height<=?$n][aspect_ratio>=?1]/b[width<=?$n][aspect_ratio<1]"
  fi
  # "all" incluiria o chat ao vivo: um JSON enorme que nem dá para embutir
  [[ ,$langs, == *,all,* && $langs != *live_chat* ]] && langs+=",-live_chat"
  YTDLP_ARGS=(
    --ignore-config --color never --newline --no-quiet --no-simulate --progress
    --progress-delta 0.5

    # Linhas "máquina" lidas pelo painel (ficam só no log, nunca no terminal)
    --progress-template "download:@@P@@%(progress.downloaded_bytes|0)s${SEP}%(progress.total_bytes,progress.total_bytes_estimate|0)s${SEP}%(progress.speed|0)s${SEP}%(progress.eta|0)s${SEP}%(info.playlist_index|)s${SEP}%(info.n_entries|)s${SEP}%(info.vcodec|?)s${SEP}%(info.height|)s${SEP}%(info.fps|)s${SEP}%(info.ext|)s${SEP}%(info.title|?)s"
    --print "after_move:@@D@@%(height|0)s${SEP}%(fps|0)s${SEP}%(dynamic_range|SDR)s${SEP}%(vcodec|?)s${SEP}%(acodec|?)s${SEP}%(duration|0)s${SEP}%(title|?)s${SEP}%(id)s${SEP}%(filepath)s"

    # Destino: os temporários ficam em .parciais/<esta execução> e só o arquivo final
    # vai para a pasta
    -P "$PASTA_SAIDA" -P "temp:$TEMP_REL" -o "$TEMPLATE_SAIDA"

    # Qualidade máxima: melhor vídeo + melhor áudio, empacotados em MKV
    -f "$FORMATO" --merge-output-format mkv --remux-video mkv

    # Tudo o que o yt-dlp encontrar vai para dentro do arquivo
    --embed-metadata --embed-chapters --embed-info-json
    # Capa em JPG (a mais compatível), menos AVIF: para converter, o yt-dlp força o
    # leitor "image2" do ffmpeg, que não abre AVIF — ela é embutida como veio.
    --embed-thumbnail --convert-thumbnails 'webp>jpg/png>jpg/gif>jpg/bmp>jpg'
    --embed-subs --sub-langs "$langs"

    # Velocidade e resiliência (com espera crescente entre as repetições)
    -N "$CONEXOES_POR_VIDEO"
    --retries 10 --fragment-retries 10 --extractor-retries 3
    --retry-sleep exp=1:30 --retry-sleep fragment:exp=1:30
    # Qualidade garantida: nunca pula um fragmento que falhou (por padrão o yt-dlp pula
    # em silêncio e entrega o vídeo com um salto) e nunca retoma pedaços de um download
    # interrompido (a retomada pode deixar buracos); nesses casos, recomeça do zero.
    --abort-on-unavailable-fragments --no-continue
    --socket-timeout 30 --throttled-rate 100K
  )
  # Com --write-auto-subs o yt-dlp para de pedir as legendas manuais sozinho:
  # pede as duas (a manual tem prioridade) e apaga os .vtt depois de embutir.
  (( LEGENDAS_AUTOMATICAS )) && YTDLP_ARGS+=(--write-subs --write-auto-subs --compat-options no-keep-subs)
  (( SPONSORBLOCK ))         && YTDLP_ARGS+=(--sponsorblock-mark all)
  (( SEM_PLAYLIST ))         && YTDLP_ARGS+=(--no-playlist)
  if (( VERIFICAR )); then                    # o "%" do caminho viraria campo do modelo do yt-dlp
    printf -v cmd 'bash %q --verificar-arquivo %q' "${GRABIT_SCRIPT//%/%%}" "${T[sufixo_ruim]}"
    YTDLP_ARGS+=(--exec "after_move:$cmd %(filepath)q %(duration|0)q")
  fi
  # Histórico: o que já foi baixado é pulado antes de tudo (na maioria dos sites,
  # sem nem acessar a página). Sem ele, o yt-dlp reextrai o vídeo, baixa a capa de
  # novo e reescreve o arquivo inteiro só para dizer que ele já existe.
  (( USAR_HISTORICO ))       && YTDLP_ARGS+=(--download-archive "$ARQUIVO_HISTORICO")
  [[ -n $COOKIES_NAVEGADOR ]] && YTDLP_ARGS+=(--cookies-from-browser "$COOKIES_NAVEGADOR")
  (( TEM_JS_RUNTIMES ))       && [[ -n $JS_RUNTIME ]] && YTDLP_ARGS+=(--js-runtimes "$JS_RUNTIME:$JS_PATH")
  return 0
}

# ───────────────────────────── Principal ──────────────────────────────────────
trap 'CANCELADO=1; SINAL=INT;  exit 130' INT
trap 'CANCELADO=1; SINAL=TERM; exit 143' TERM
trap 'CANCELADO=1; SINAL=HUP;  exit 129' HUP
trap limpa EXIT

atualiza_largura
cabecalho
TMP=$(mktemp -d "${TMPDIR:-/tmp}/grabit.XXXXXX") || { erro "${T[tmp_falhou]}"; exit 1; }
verifica_dependencias
ler_links

mkdir -p "$PASTA_SAIDA" || { t pasta_falhou "$PASTA_SAIDA"; erro "$TXT"; exit 1; }
printf -v LOG_DIR '%s/logs/%(%Y-%m-%d_%H%M%S)T' "$PASTA_SAIDA" -1
prepara_parciais

J=$DOWNLOADS_SIMULTANEOS
(( J > TOTAL )) && J=$TOTAL
LIMITE_J=0
if (( INTERATIVO )); then                       # o painel (2 linhas por vídeo + 2) precisa caber na tela
  linhas=$(tput lines 2>/dev/null); [[ $linhas =~ ^[0-9]+$ ]] || linhas=24
  max_j=$(( (linhas - 3) / 2 )); (( max_j < 1 )) && max_j=1
  if (( J > max_j )); then LIMITE_J=$J; J=$max_j; fi
fi
for (( s = 0; s < J; s++ )); do SLOT_IDX[$s]=0; SLOT_PID[$s]=0; done
monta_args_ytdlp

extras=""
(( DUPLICADOS > 0 )) && { t links_repetidos "$DUPLICADOS"; extras+=$TXT; }
(( INVALIDAS  > 0 )) && { t links_sem_link "$INVALIDAS"; extras+="${extras:+,}$TXT"; }
[[ -n $extras ]] && { t links_ignorados "$extras"; extras=$TXT; }
(( N_NA_SECAO > 0 )) && { t links_na_secao "$N_NA_SECAO"; extras+=$TXT; }
t kv_legendas "$IDIOMAS_LEGENDAS"; txt_extras=$TXT
(( LEGENDAS_AUTOMATICAS )) && txt_extras+=${T[kv_automaticas]}
txt_extras+=${T[kv_extras_resto]}
(( SO_PRINCIPAL )) && txt_extras+=${T[kv_principal]}
(( VERIFICAR ))    && txt_extras+=${T[kv_verificar]}
(( SPONSORBLOCK )) && txt_extras+=", SponsorBlock"
if [[ -z $IMPERSONATE ]]; then txt_imp="${AMARELO}${T[imp_indisp]}${R}"
elif (( TENTATIVAS > 1 )); then txt_imp=${T[imp_retry]}
else txt_imp=${T[imp_off]}; fi

kv "${T[kv_links]}"   "${NEG}${TOTAL}${R}${DIM} · ${FONTE_LINKS}${extras}${R}"
kv "${T[kv_destino]}" "$PASTA_SAIDA"
if (( RESOLUCAO_MAXIMA > 0 )); then
  t kv_res_ate "$RESOLUCAO_MAXIMA"; txt_res=$TXT
  if [[ ${ORIGEM[RESOLUCAO_MAXIMA]:-} != opção ]]; then
    origem_txt RESOLUCAO_MAXIMA; t kv_res_origem "$FMT"; txt_res+=$TXT
  fi
  kv "${T[kv_resolucao]}" "$txt_res"
elif (( LIMITE_IGNORADO > 0 )); then
  origem_txt RESOLUCAO_MAXIMA; t kv_res_forcado "$AMARELO" "$R" "$LIMITE_IGNORADO" "$FMT"; kv "${T[kv_resolucao]}" "$TXT"
fi
if (( CONFIG_CRIADO )); then
  t kv_config_criado "$VERDE" "$R" "${CONFIG_ARQ/#$HOME/\~}"; kv "${T[kv_config]}" "$TXT"
elif [[ -f $CONFIG_ARQ ]]; then
  t kv_config_ajustes "$N_AJUSTES_CONFIG"; kv "${T[kv_config]}" "$TXT"
fi
if (( USAR_HISTORICO )); then
  n_registrados=$(grep -c '' "$ARQUIVO_HISTORICO" 2>/dev/null) || n_registrados=0
  t kv_hist_on "$n_registrados"; kv "${T[kv_historico]}" "$TXT"
else
  t kv_hist_off "$AMARELO" "$R"; kv "${T[kv_historico]}" "$TXT"
fi
t kv_paralelo_v "$J" "$CONEXOES_POR_VIDEO"; txt_paralelo=$TXT
(( TENTATIVAS > 1 )) && { t kv_tentativas "$TENTATIVAS"; txt_paralelo+=$TXT; }
kv "${T[kv_paralelo]}" "$txt_paralelo"
kv "${T[kv_extras]}"   "$txt_extras"
FFMPEG_VER=${FFMPEG_VER:-?}
kv "${T[kv_ferramentas]}" "yt-dlp ${YTDLP_VER:-?} · ffmpeg ${FFMPEG_VER%%-*}"
kv "${T[kv_recursos]}"    "impersonate: ${txt_imp} · js: ${JS_RUNTIME:-${AMARELO}${T[js_nenhum]}${R}}"
printf '\n'
for a in "${AVISOS_CONFIG[@]}"; do t cfg_linha "${a%%:*}" "${a#*:}"; aviso "$TXT"; done
if (( LIMITE_J > 0 )); then
  t av_linhas "$linhas" "$J"; aviso "$TXT"
  t av_linhas2 "$LIMITE_J"; printf '%s\n' "$TXT"
fi
idade_ytdlp
if (( NUM >= 3 )) || (( ! TEM_JS_RUNTIMES )); then
  t av_ytdlp "${YTDLP_VER:-?}"; aviso "$TXT"
  t av_ytdlp2 "${CIANO}yt-dlp -U${R}" "${CIANO}pipx upgrade yt-dlp${R}"; printf '%s\n' "$TXT"
fi
if [[ -z $IMPERSONATE ]]; then
  aviso "${T[av_curl]}"
  t av_curl2 "${CIANO}pipx inject yt-dlp curl-cffi${R}"; printf '%s\n' "$TXT"
fi
if [[ -z $JS_RUNTIME ]]; then
  aviso "${T[av_js]}"
  printf '%s\n' "${T[av_js2]}"
fi
printf '  %s%s%s\n\n' "$DIM" "${T[dica_ctrlc]}" "$R"

# Redimensionou a janela? O painel se ajusta no próximo quadro. (O trap só entra
# agora: antes ele interromperia o "wait" das consultas ao yt-dlp.)
REDIM=1
trap 'REDIM=1' WINCH
COMECOU=1
SECONDS=0
if (( INTERATIVO )); then
  printf '%s' "${ESC}[?25l${ESC}[?7l${ESC}[22;0t"   # esconde o cursor, desliga a quebra de linha, guarda o título
  TITULO_EMPILHADO=1
  if [[ -t 0 ]]; then
    STTY_SAVE=$(stty -g 2>/dev/null) && stty -echo 2>/dev/null
  fi
fi

while (( FINALIZADOS < TOTAL )); do
  atualiza_largura

  # 1) recolhe quem terminou (e devolve à fila quem merece outra tentativa)
  for (( s = 0; s < J; s++ )); do
    idx=${SLOT_IDX[$s]}
    (( idx > 0 )) || continue
    kill -0 "${SLOT_PID[$s]}" 2>/dev/null && continue
    wait "${SLOT_PID[$s]}" 2>/dev/null; rc=$?
    SLOT_IDX[$s]=0
    if (( rc != 0 )) && vale_repetir "$idx"; then continue; fi
    (( ${TENTATIVA[$idx]:-1} > 1 )) && EM_REPETICAO=$(( EM_REPETICAO - 1 ))
    processa_resultado "$idx" "$rc"
  done

  # 2) ocupa os slots livres: primeiro os links novos, depois as novas tentativas
  for (( s = 0; s < J; s++ )); do
    (( SLOT_IDX[$s] == 0 )) || continue
    if (( PROXIMO <= TOTAL )); then
      idx=$PROXIMO; PROXIMO=$(( PROXIMO + 1 ))
    elif (( ${#REPETIR[@]} )); then
      idx=${REPETIR[0]}; REPETIR=("${REPETIR[@]:1}")
    else
      break
    fi
    lanca_job "$idx"
    SLOT_IDX[$s]=$idx
    SLOT_PID[$s]=$ULTIMO_PID
  done

  desenha
  sleep 0.2
done

desenha final
descarta_parciais
move_baixados
resumo
(( N_ERRO > 0 )) && exit 1
exit 0
