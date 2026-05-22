#!/bin/bash
# ==============================================================================
#  ██████╗██╗  ██╗   ██╗██╗   ██╗ ██████╗     ██╗   ██╗███████╗████████╗
# ██╔════╝██║  ╚██╗ ██╔╝██║   ██║██╔═══██╗    ██║   ██║██╔════╝╚══██╔══╝
# ██║     ██║   ╚████╔╝ ██║   ██║██║   ██║    ██║   ██║█████╗     ██║
# ██║     ██║    ╚██╔╝  ╚██╗ ██╔╝██║   ██║    ╚██╗ ██╔╝██╔══╝     ██║
# ╚██████╗███████╗██║    ╚████╔╝ ╚██████╔╝     ╚████╔╝ ███████╗   ██║
#  ╚═════╝╚══════╝╚═╝     ╚═══╝   ╚═════╝       ╚═══╝  ╚══════╝   ╚═╝
#
# PROJETO   : ClyvoVet -- Infraestrutura em Nuvem para Clinicas Veterinarias
# DESCRICAO : Provisioner interativo para Azure VM com Docker, .NET 8 e Oracle DB
# STACK     : .NET 8 API | Oracle DB (gvenzl/oracle-free) | Docker Compose | Azure
# VERSAO    : 2.1.0
#
# HISTORICO DE CORRECOES (v2.1.0):
#   [FIX-1] Forcado encoding UTF-8 no Python/Azure CLI (PYTHONIOENCODING, PYTHONUTF8)
#   [FIX-2] Removidos caracteres non-ASCII (— . ·) do corpo do YAML gerado
#   [FIX-3] Heredoc externo trocado por 'CLOUDINIT_HEADER' (aspas) para evitar
#           expansao indesejada de variaveis bash dentro do YAML
#   [FIX-4] MOTD movido de runcmd (heredoc aninhado) para write_files
#   [FIX-5] iconv sanitiza o YAML final para ASCII puro antes de passar ao az vm create
#   [FIX-6] Validacao YAML via python3 com caminho de arquivo passado por argumento
#           (evita erro de encoding no open() do Python)
# ==============================================================================

# -- Modo estrito: aborta em erros, variaveis nao definidas e falhas em pipes --
set -euo pipefail

# ==============================================================================
# SECAO 1 -- CONSTANTES GLOBAIS
# ==============================================================================

readonly SCRIPT_VERSION="2.1.0"
readonly TEMP_DIR="$(mktemp -d /tmp/clyvovet-deploy.XXXXXX)"
readonly CLOUD_INIT_FILE="${TEMP_DIR}/cloud-init.yaml"
readonly CLOUD_INIT_SAFE="${TEMP_DIR}/cloud-init-safe.yaml"
readonly VM_OUTPUT_FILE="${TEMP_DIR}/vm-output.json"
readonly LOG_FILE="${TEMP_DIR}/deploy.log"

# Portas expostas pela aplicacao ClyvoVet
# 22   -> SSH (acesso admin)
# 80   -> HTTP (proxy/health check futuro)
# 5139 -> API .NET 8 (consumida pelo React Native)
readonly -a VM_PORTS=(22 80 5139)
readonly NSG_PRIORITY_BASE=1010

# Dependencias obrigatorias para execucao do script
readonly -a REQUIRED_CMDS=("az" "jq")

# -- Paleta de Cores ANSI -----------------------------------------------------
readonly C_RESET='\033[0m'
readonly C_BOLD='\033[1m'
readonly C_GREEN='\033[1;32m'
readonly C_BLUE='\033[1;34m'
readonly C_CYAN='\033[1;36m'
readonly C_YELLOW='\033[1;33m'
readonly C_RED='\033[1;31m'
readonly C_MAGENTA='\033[1;35m'
readonly C_WHITE='\033[1;37m'
readonly C_DIM='\033[2m'

# -- Simbolos do tema ClyvoVet ------------------------------------------------
readonly SYM_PAW="🐾"
readonly SYM_VET="🏥"
readonly SYM_SYRINGE="💉"
readonly SYM_CLOUD="☁️"
readonly SYM_ROCKET="🚀"
readonly SYM_LOCK="🔒"
readonly SYM_KEY="🔑"
readonly SYM_CHECK="✅"
readonly SYM_WARN="⚠️"
readonly SYM_GLOBE="🌐"

# ==============================================================================
# SECAO 1.5 -- FORCADO ENCODING UTF-8 PARA O AZURE CLI (Python)
#
# [FIX-1] O Azure CLI e escrito em Python. Em ambientes sem locale configurado,
# o Python usa latin-1 por padrao ao ler arquivos, causando o erro:
#   'latin-1' codec can't encode character '\uXXXX'
# As tres variaveis abaixo garantem UTF-8 em todo I/O do processo Python
# que o 'az' cria internamente, incluindo a leitura do --custom-data.
# ==============================================================================
export PYTHONIOENCODING="utf-8"
export PYTHONUTF8=1          # Python 3.7+ -- garante UTF-8 em todo I/O
export LANG="en_US.UTF-8"
export LC_ALL="en_US.UTF-8"

# ==============================================================================
# SECAO 2 -- FUNCOES UTILITARIAS (LOGGING E UI)
# ==============================================================================

# Escreve no terminal e anexa ao log file simultaneamente
_log_raw() { echo -e "$1" | tee -a "${LOG_FILE}"; }

log_info()    { _log_raw "  ${C_CYAN}[INFO]${C_RESET}    $1"; }
log_success() { _log_raw "  ${C_GREEN}[OK]${C_RESET}      $1"; }
log_warn()    { _log_raw "  ${C_YELLOW}[AVISO]${C_RESET}   $1"; }
log_error()   { _log_raw "  ${C_RED}[ERRO]${C_RESET}    $1" >&2; }

separator() {
    echo -e "${C_BLUE}$(printf '%0.s-' {1..64})${C_RESET}"
}

step_header() {
    local -r num="$1" title="$2"
    echo ""
    separator
    echo -e "  ${C_MAGENTA}${C_BOLD}ETAPA ${num}${C_RESET} ${C_DIM}|${C_RESET} ${C_WHITE}${title}${C_RESET}"
    separator
    echo ""
}

show_banner() {
    clear
    echo -e "${C_BLUE}"
    cat << 'BANNER'
  +==============================================================+
  |                                                              |
  |    ██████╗██╗  ██╗   ██╗██╗   ██╗ ██████╗                    |
  |   ██╔════╝██║  ╚██╗ ██╔╝██║   ██║██╔═══██╗                   |
  |   ██║     ██║   ╚████╔╝ ██║   ██║██║   ██║                   |
  |   ██║     ██║    ╚██╔╝  ╚██╗ ██╔╝██║   ██║                   |
  |   ╚██████╗███████╗██║    ╚████╔╝ ╚██████╔╝                   |
  |    ╚═════╝╚══════╝╚═╝     ╚═══╝   ╚═════╝                    |
  |                                                              |
  |  🐾  V E T  --  I N F R A  P R O V I S I O N E R  🐾         |
  |                                                              |
  +==============================================================+
BANNER
    echo -e "${C_RESET}"
    echo -e "  ${C_CYAN}Sistema de Gerenciamento para Clinicas Veterinarias${C_RESET}"
    echo -e "  ${C_WHITE}Stack: .NET 8 API | Oracle DB | Docker | Azure VM${C_RESET}"
    echo -e "  ${C_DIM}Versao ${SCRIPT_VERSION}  |  Log: ${LOG_FILE}${C_RESET}"
    separator
    echo ""
}

# ==============================================================================
# SECAO 3 -- GERENCIAMENTO DE ERROS E LIMPEZA
# ==============================================================================

cleanup() {
    rm -f "${CLOUD_INIT_FILE}" "${CLOUD_INIT_SAFE}" "${VM_OUTPUT_FILE}" 2>/dev/null || true
    log_info "${C_DIM}Arquivos temporarios removidos. Log preservado em: ${LOG_FILE}${C_RESET}"
}

abort() {
    local -r msg="${1:-"Erro desconhecido."}"
    echo ""
    separator
    log_error "${C_BOLD}Provisionamento abortado!${C_RESET}"
    log_error "${msg}"
    log_error "Consulte o log completo: ${C_BOLD}${LOG_FILE}${C_RESET}"
    separator
    echo ""
    exit 1
}

# ==============================================================================
# SECAO 4 -- VERIFICACAO DE DEPENDENCIAS E AUTENTICACAO AZURE
# ==============================================================================

check_dependencies() {
    step_header "01" "${SYM_CHECK}  Verificando Dependencias do Sistema"

    for cmd in "${REQUIRED_CMDS[@]}"; do
        if command -v "${cmd}" &>/dev/null; then
            log_success "Dependencia encontrada: ${C_BOLD}${cmd}${C_RESET} $(command -v "${cmd}")"
        else
            abort "Dependencia ausente: '${C_BOLD}${cmd}${C_RESET}'. Instale antes de continuar.\n  ${C_DIM}-> az:  https://docs.microsoft.com/cli/azure/install-azure-cli\n  -> jq:  apt install jq / brew install jq${C_RESET}"
        fi
    done

    # Verifica iconv (usado para sanitizar o YAML -- FIX-5)
    if ! command -v iconv &>/dev/null; then
        log_warn "iconv nao encontrado. A sanitizacao ASCII do cloud-init sera pulada."
        log_warn "Instale com: apt install libc-bin (Ubuntu) ou brew install libiconv (macOS)"
    else
        log_success "Dependencia encontrada: ${C_BOLD}iconv${C_RESET} $(command -v iconv)"
    fi
}

check_azure_auth() {
    step_header "02" "${SYM_LOCK}  Verificando Autenticacao na Azure"

    if ! az account show &>/dev/null 2>&1; then
        log_warn "Sessao Azure CLI nao encontrada. Iniciando login..."
        echo ""
        if ! az login --output none; then
            abort "Falha na autenticacao. Execute 'az login' manualmente e tente novamente."
        fi
    fi

    local account_name subscription_id tenant_id
    account_name=$(az account show    --query "user.name"   -o tsv)
    subscription_id=$(az account show --query "id"          -o tsv)
    tenant_id=$(az account show       --query "tenantId"    -o tsv)

    log_success "Autenticado como:   ${C_BOLD}${account_name}${C_RESET}"
    log_info    "Subscription ID:    ${C_BOLD}${subscription_id}${C_RESET}"
    log_info    "Tenant ID:          ${C_BOLD}${tenant_id}${C_RESET}"

    export AZURE_SUBSCRIPTION_ID="${subscription_id}"
}

# ==============================================================================
# SECAO 5 -- COLETA E VALIDACAO DE PARAMETROS
# ==============================================================================

_validate_password() {
    local -r password="$1"
    [[ ${#password} -ge 12 ]]         || return 1
    [[ "$password" =~ [A-Z] ]]        || return 1
    [[ "$password" =~ [a-z] ]]        || return 1
    [[ "$password" =~ [0-9] ]]        || return 1
    [[ "$password" =~ [^a-zA-Z0-9] ]] || return 1
    return 0
}

_prompt_password() {
    while true; do
        echo -e "\n  ${C_YELLOW}${SYM_LOCK} Senha Admin${C_RESET} ${C_DIM}(>=12 chars, maiuscula, minuscula, numero, especial):${C_RESET}"
        read -rsp "  > " ADMIN_PASSWORD
        echo ""

        if ! _validate_password "${ADMIN_PASSWORD}"; then
            log_warn "Senha nao atende aos requisitos de complexidade da Azure. Tente novamente."
            continue
        fi

        echo -e "  ${C_YELLOW}${SYM_LOCK} Confirme a senha:${C_RESET}"
        read -rsp "  > " password_confirm
        echo ""

        if [[ "${ADMIN_PASSWORD}" != "${password_confirm}" ]]; then
            log_warn "As senhas nao coincidem. Tente novamente."
            continue
        fi

        log_success "Senha validada com sucesso."
        break
    done

    export ADMIN_PASSWORD
}

collect_parameters() {
    step_header "03" "${SYM_PAW}  Configurando Parametros do Ambiente ClyvoVet"
    echo -e "  ${C_CYAN}Preencha os dados para o provisionamento:${C_RESET}\n"

    read -rp "  $(echo -e "${C_YELLOW}${SYM_CLOUD}  Resource Group${C_RESET} ${C_DIM}(ex: rg-clyvovet-prod):${C_RESET} ")" RG_NAME
    [[ -n "${RG_NAME}" ]] || abort "Resource Group nao pode ser vazio."

    read -rp "  $(echo -e "${C_YELLOW}${SYM_GLOBE}  Regiao Azure${C_RESET}    ${C_DIM}(ex: brazilsouth):${C_RESET}        ")" LOCATION
    [[ -n "${LOCATION}" ]] || abort "Regiao nao pode ser vazia."

    read -rp "  $(echo -e "${C_YELLOW}${SYM_VET}   Nome da VM${C_RESET}      ${C_DIM}(ex: vm-clyvovet-api):${C_RESET}     ")" VM_NAME
    [[ -n "${VM_NAME}" ]] || abort "Nome da VM nao pode ser vazio."

    read -rp "  $(echo -e "${C_YELLOW}${SYM_KEY}   Usuario Admin:${C_RESET}                                  ")" ADMIN_USER
    [[ -n "${ADMIN_USER}" ]] || abort "Usuario Admin nao pode ser vazio."

    _prompt_password

    export RG_NAME LOCATION VM_NAME ADMIN_USER

    echo ""
    log_info "Parametros coletados e validados."
}

# ==============================================================================
# SECAO 6 -- DESCOBERTA DINAMICA DE SKUs DE VM
# ==============================================================================

select_vm_size() {
    step_header "04" "${SYM_CLOUD}  Selecionando Tamanho da VM"
    log_info "Consultando SKUs disponiveis em '${C_BOLD}${LOCATION}${C_RESET}'..."

    local sku_list
    sku_list=$(az vm list-skus \
        --location "${LOCATION}" \
        --resource-type virtualMachines \
        --query "[?restrictions[0].reasonCode == null && (contains(name, 'Standard_B') || contains(name, 'Standard_D'))].name" \
        -o tsv 2>>"${LOG_FILE}" | head -n 10)

    if [[ -z "${sku_list}" ]]; then
        abort "Nenhuma SKU disponivel em '${LOCATION}'. Verifique a regiao e suas cotas de assinatura."
    fi

    echo ""
    echo -e "  ${C_CYAN}SKUs disponiveis em ${C_BOLD}${LOCATION}${C_RESET}:\n"

    select VM_SIZE in ${sku_list}; do
        if [[ -n "${VM_SIZE}" ]]; then
            log_success "Tamanho selecionado: ${C_BOLD}${VM_SIZE}${C_RESET}"
            break
        fi
        log_warn "Opcao invalida. Digite o numero correspondente."
    done

    export VM_SIZE
}

# ==============================================================================
# SECAO 7 -- GERACAO DO PAYLOAD CLOUD-INIT
#
# ESTRATEGIA DE HEREDOCS (evita os tres bugs anteriores):
#
# [FIX-3] Todos os heredocs que geram YAML usam delimitador com aspas simples
#         ('CLOUDINIT_XXX'), desabilitando expansao bash. Variaveis do bash que
#         precisam ser injetadas no YAML sao escritas via echo/printf separados.
#
# [FIX-4] O MOTD foi movido para write_files (nao usa mais heredoc aninhado
#         dentro do runcmd, que era a causa do parse quebrado no cloud-init v1).
#
# [FIX-2] Todos os caracteres non-ASCII foram removidos dos comentarios e
#         conteudos gerados: -- em vez de —, | em vez de ·, -> em vez de ->
# ==============================================================================

generate_cloud_init() {
    step_header "05" "${SYM_SYRINGE}  Gerando Payload cloud-init"

    # ---- Bloco 1: cabecalho + packages + runcmd (sem expansao bash) ----------
    cat > "${CLOUD_INIT_FILE}" << 'CLOUDINIT_HEADER'
#cloud-config
# ==============================================================================
# ClyvoVet - Configuracao Inicial da VM
# Gerado automaticamente por deploy-clyvovet.sh
# ==============================================================================

package_update: true
package_upgrade: true
packages:
  - apt-transport-https
  - ca-certificates
  - curl
  - gnupg
  - lsb-release
  - git
  - htop
  - unzip

runcmd:
  # -- Instalar Docker via script oficial -------------------------------------
  # Usar get.docker.com evita problemas de keyring/repo no cloud-init
  - curl -fsSL https://get.docker.com -o /tmp/install-docker.sh
  - sh /tmp/install-docker.sh
  - systemctl enable docker
  - systemctl start docker
CLOUDINIT_HEADER

    # ---- Injeta linhas que precisam de expansao bash -------------------------
    # [FIX-3] Unico ponto de expansao controlada -- apenas variaveis simples
    printf '  - usermod -aG docker %s\n'                "${ADMIN_USER}" >> "${CLOUD_INIT_FILE}"
    printf '  - mkdir -p /opt/clyvovet\n'                               >> "${CLOUD_INIT_FILE}"
    printf '  - chown -R %s:%s /opt/clyvovet\n'         "${ADMIN_USER}" "${ADMIN_USER}" >> "${CLOUD_INIT_FILE}"

    # ---- Bloco 2: write_files -- MOTD (sem expansao bash) -------------------
    # [FIX-4] MOTD via write_files elimina o heredoc aninhado no runcmd
    cat >> "${CLOUD_INIT_FILE}" << 'CLOUDINIT_MOTD'

write_files:

  - path: /etc/motd
    permissions: '0644'
    content: |

      ======================================================
         ClyvoVet - VM de Producao
         Stack: .NET 8 API / Oracle DB / Docker Compose

         Diretorio do projeto : /opt/clyvovet
         Iniciar stack        : cd /opt/clyvovet
                                cp .env.example .env
                                docker compose up -d
      ======================================================

CLOUDINIT_MOTD

    # ---- Bloco 3: docker-compose.yml (sem expansao bash) --------------------
    # As variaveis ${...} aqui sao do Docker Compose, NAO do bash --
    # o heredoc com aspas garante que o bash nao as expanda.
    cat >> "${CLOUD_INIT_FILE}" << 'CLOUDINIT_COMPOSE'
  - path: /opt/clyvovet/docker-compose.yml
    permissions: '0644'
    content: |
      name: clyvovet

      networks:
        clyvo-network:
          driver: bridge

      volumes:
        clyvovet_oracle_data:

      services:

        db-oracle:
          image: gvenzl/oracle-free:latest
          container_name: db-oracle
          restart: unless-stopped
          environment:
            ORACLE_PASSWORD: ${ORACLE_ROOT_PASSWORD}
            APP_USER: ${ORACLE_APP_USER}
            APP_USER_PASSWORD: ${ORACLE_APP_PASSWORD}
          volumes:
            - clyvovet_oracle_data:/opt/oracle/oradata
          networks:
            - clyvo-network
          ports:
            - "1521:1521"
          healthcheck:
            test: ["CMD", "healthcheck.sh"]
            interval: 30s
            timeout: 10s
            retries: 15
            start_period: 120s

        clyvo-api:
          image: ghcr.io/${GITHUB_ORG}/clyvovet-api:latest
          container_name: clyvo-api
          restart: unless-stopped
          user: app
          depends_on:
            db-oracle:
              condition: service_healthy
          environment:
            ASPNETCORE_ENVIRONMENT: Production
            ASPNETCORE_URLS: http://+:5139
            ConnectionStrings__OracleDb: >-
              Data Source=db-oracle:1521/FREEPDB1;
              User Id=${ORACLE_APP_USER};
              Password=${ORACLE_APP_PASSWORD};
          ports:
            - "5139:5139"
          networks:
            - clyvo-network
          healthcheck:
            test: ["CMD-SHELL", "curl -f http://localhost:5139/health || exit 1"]
            interval: 20s
            timeout: 5s
            retries: 5
            start_period: 30s

CLOUDINIT_COMPOSE

    # ---- Bloco 4: .env.example (owner precisa de expansao bash) -------------
    cat >> "${CLOUD_INIT_FILE}" << CLOUDINIT_ENV
  - path: /opt/clyvovet/.env.example
    owner: ${ADMIN_USER}:${ADMIN_USER}
    permissions: '0600'
    content: |
      # ClyvoVet - Variaveis de Ambiente
      # Copie para .env e preencha antes de rodar a stack.
      # NUNCA suba o arquivo .env para o repositorio.

      ORACLE_ROOT_PASSWORD=AlterEsseValor123!
      ORACLE_APP_USER=clyvovet_user
      ORACLE_APP_PASSWORD=AlterEsseValor456!
      GITHUB_ORG=sua-org-github
CLOUDINIT_ENV

    # ---- Validacao YAML via python3 -----------------------------------------
    # [FIX-6] Passa o caminho como argumento (sys.argv[1]) para evitar que o
    # open() do Python herde o encoding errado do ambiente ao ler o arquivo.
    if command -v python3 &>/dev/null; then
        if python3 - "${CLOUD_INIT_FILE}" << 'PYEOF' 2>>"${LOG_FILE}"
import sys, yaml
with open(sys.argv[1], encoding='utf-8') as f:
    yaml.safe_load(f)
PYEOF
        then
            log_success "Validacao YAML: OK"
        else
            abort "cloud-init.yaml invalido. Verifique: ${LOG_FILE}"
        fi
    else
        log_warn "python3 nao encontrado -- validacao YAML pulada."
    fi

    log_success "cloud-init.yaml gerado em: ${C_BOLD}${CLOUD_INIT_FILE}${C_RESET}"
    log_info    "Tamanho do arquivo: $(wc -c < "${CLOUD_INIT_FILE}") bytes"
}

# ==============================================================================
# SECAO 8 -- PROVISIONAMENTO DA INFRAESTRUTURA AZURE
# ==============================================================================

provision_resource_group() {
    log_info "Criando/verificando Resource Group '${C_BOLD}${RG_NAME}${C_RESET}' em '${C_BOLD}${LOCATION}${C_RESET}'..."

    if ! az group create \
            --name     "${RG_NAME}" \
            --location "${LOCATION}" \
            --output none 2>>"${LOG_FILE}"; then
        abort "Falha ao criar o Resource Group '${RG_NAME}'."
    fi

    log_success "Resource Group '${C_BOLD}${RG_NAME}${C_RESET}' pronto."
}

provision_virtual_machine() {
    log_info "Criando VM '${C_BOLD}${VM_NAME}${C_RESET}' (SKU: ${C_BOLD}${VM_SIZE}${C_RESET})..."
    log_info "${C_DIM}Isso pode levar alguns minutos. Por favor, aguarde...${C_RESET}"

    # [FIX-5] Sanitiza o cloud-init para ASCII puro via iconv antes de
    # passar ao Azure CLI. Garante que nenhum caracter non-ASCII (mesmo que
    # tenha escapado da geracao) quebre o codec do Python internamente no 'az'.
    if command -v iconv &>/dev/null; then
        iconv -f utf-8 -t ascii//TRANSLIT \
            "${CLOUD_INIT_FILE}" > "${CLOUD_INIT_SAFE}" 2>>"${LOG_FILE}" \
            || cp "${CLOUD_INIT_FILE}" "${CLOUD_INIT_SAFE}"
        log_info "cloud-init sanitizado via iconv: $(wc -c < "${CLOUD_INIT_SAFE}") bytes (ASCII puro)"
    else
        cp "${CLOUD_INIT_FILE}" "${CLOUD_INIT_SAFE}"
        log_warn "iconv ausente -- usando cloud-init sem sanitizacao ASCII."
    fi

    # [FIX-1] PYTHONIOENCODING=utf-8 repetido inline como camada extra de
    # seguranca, mesmo ja exportado globalmente na Secao 1.5
    if ! PYTHONIOENCODING=utf-8 az vm create \
            --resource-group   "${RG_NAME}" \
            --name             "${VM_NAME}" \
            --image            "Canonical:0001-com-ubuntu-server-jammy:22_04-lts:latest" \
            --size             "${VM_SIZE}" \
            --admin-username   "${ADMIN_USER}" \
            --admin-password   "${ADMIN_PASSWORD}" \
            --authentication-type password \
            --custom-data      "${CLOUD_INIT_SAFE}" \
            --output json > "${VM_OUTPUT_FILE}" 2>>"${LOG_FILE}"; then
        abort "Falha ao criar a VM.\n  ${C_DIM}Causas comuns:\n  -> Senha nao atende a politica de complexidade da Azure\n  -> Cota de vCPUs insuficiente para o SKU selecionado\n  -> Regiao sem disponibilidade para o tamanho escolhido\n  Consulte: ${LOG_FILE}${C_RESET}"
    fi

    log_success "VM '${C_BOLD}${VM_NAME}${C_RESET}' criada com sucesso."
}

configure_network_rules() {
    step_header "07" "${SYM_GLOBE}  Configurando Regras de Rede (NSG)"

    local priority=${NSG_PRIORITY_BASE}

    declare -A PORT_LABELS=(
        [22]="SSH (acesso admin)"
        [80]="HTTP (health check / proxy futuro)"
        [5139]="API ClyvoVet (.NET 8)"
    )

    for port in "${VM_PORTS[@]}"; do
        log_info "Liberando porta ${C_BOLD}${port}${C_RESET} -- ${PORT_LABELS[${port}]:-'servico'}..."

        if ! az vm open-port \
                --resource-group "${RG_NAME}" \
                --name           "${VM_NAME}" \
                --port           "${port}" \
                --priority       "${priority}" \
                --output none 2>>"${LOG_FILE}"; then
            log_warn "Nao foi possivel abrir a porta ${port} automaticamente. Verifique o NSG manualmente."
        else
            log_success "Porta ${C_BOLD}${port}${C_RESET} liberada (prioridade NSG: ${priority})."
        fi

        (( priority += 10 ))
    done
}

provision_infrastructure() {
    step_header "06" "${SYM_ROCKET}  Provisionando Infraestrutura na Azure"
    provision_resource_group
    provision_virtual_machine
}

# ==============================================================================
# SECAO 9 -- RESUMO FINAL DO PROVISIONAMENTO
# ==============================================================================

display_summary() {
    local public_ip
    public_ip=$(jq -r '.publicIpAddress // "N/A"' "${VM_OUTPUT_FILE}")

    echo ""
    echo -e "${C_GREEN}"
    cat << 'SUMMARY'
  +==============================================================+
  |                                                              |
  |  [OK] ClyvoVet -- Infraestrutura Provisionada com Sucesso!   |
  |  [OK] Sua clinica veterinaria ja esta na nuvem!              |
  |                                                              |
  +==============================================================+
SUMMARY
    echo -e "${C_RESET}"

    separator
    echo -e "  ${SYM_CLOUD} ${C_WHITE}${C_BOLD}Detalhes da VM${C_RESET}"
    separator
    echo -e "  ${C_CYAN}Resource Group :${C_RESET}  ${RG_NAME}"
    echo -e "  ${C_CYAN}VM Name        :${C_RESET}  ${VM_NAME}"
    echo -e "  ${C_CYAN}SKU            :${C_RESET}  ${VM_SIZE}"
    echo -e "  ${C_CYAN}Regiao         :${C_RESET}  ${LOCATION}"
    echo -e "  ${C_CYAN}IP Publico     :${C_RESET}  ${C_BOLD}${public_ip}${C_RESET}"
    echo -e "  ${C_CYAN}S.O.           :${C_RESET}  Ubuntu 22.04 LTS (Jammy)"
    echo ""
    separator
    echo -e "  ${SYM_GLOBE} ${C_WHITE}${C_BOLD}Endpoints da Aplicacao${C_RESET}"
    separator
    echo -e "  ${C_YELLOW}SSH Admin :${C_RESET}  ssh ${ADMIN_USER}@${public_ip}"
    echo -e "  ${C_YELLOW}API REST  :${C_RESET}  http://${public_ip}:5139"
    echo -e "  ${C_YELLOW}Oracle DB :${C_RESET}  ${public_ip}:1521  ${C_DIM}(FREEPDB1)${C_RESET}"
    echo ""
    separator
    echo -e "  ${SYM_PAW} ${C_WHITE}${C_BOLD}Proximos Passos (execute na VM via SSH)${C_RESET}"
    separator
    echo ""
    echo -e "  ${C_CYAN}1.${C_RESET} Aguarde ~5 min para o cloud-init finalizar"
    echo -e "     ${C_DIM}(instalacao do Docker + configuracao do ambiente)${C_RESET}"
    echo -e "     ${C_DIM}Acompanhe: sudo tail -f /var/log/cloud-init-output.log${C_RESET}"
    echo ""
    echo -e "  ${C_CYAN}2.${C_RESET} Acesse a VM:"
    echo -e "     ${C_GREEN}ssh ${ADMIN_USER}@${public_ip}${C_RESET}"
    echo ""
    echo -e "  ${C_CYAN}3.${C_RESET} Configure as variaveis de ambiente:"
    echo -e "     ${C_GREEN}cd /opt/clyvovet${C_RESET}"
    echo -e "     ${C_GREEN}cp .env.example .env && nano .env${C_RESET}"
    echo ""
    echo -e "  ${C_CYAN}4.${C_RESET} Inicie a stack ClyvoVet:"
    echo -e "     ${C_GREEN}docker compose pull${C_RESET}"
    echo -e "     ${C_GREEN}docker compose up -d${C_RESET}"
    echo ""
    echo -e "  ${C_CYAN}5.${C_RESET} Verifique a saude dos conteineres:"
    echo -e "     ${C_GREEN}docker compose ps${C_RESET}"
    echo -e "     ${C_GREEN}docker compose logs -f clyvo-api${C_RESET}"
    echo ""
    separator
    echo -e "  ${SYM_WARN}  ${C_YELLOW}O Oracle DB pode levar ate 2 min para inicializar na primeira vez.${C_RESET}"
    echo -e "  ${SYM_WARN}  ${C_YELLOW}A API aguardara o healthcheck do DB antes de subir (depends_on).${C_RESET}"
    separator
    echo ""
    log_info "Log completo: ${C_BOLD}${LOG_FILE}${C_RESET}"
    echo ""
}

# ==============================================================================
# SECAO 10 -- PONTO DE ENTRADA PRINCIPAL
# ==============================================================================

main() {
    trap cleanup EXIT
    trap 'echo ""; abort "Script interrompido pelo usuario (CTRL+C)."' INT TERM

    show_banner
    check_dependencies
    check_azure_auth
    collect_parameters
    select_vm_size
    generate_cloud_init
    provision_infrastructure
    configure_network_rules
    display_summary
}

main "$@"