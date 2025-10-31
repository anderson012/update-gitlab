#!/usr/bin/env bash
# ============================================================
# Script de atualização do GitLab (container Docker)
# ------------------------------------------------------------
# Autor: Anderson
# Descrição: Atualiza a instância GitLab rodando em Docker,
#            listando versões disponíveis no Docker Hub e
#            permitindo escolher qual versão aplicar.
# https://docs.gitlab.com/update/upgrade_paths/
# Uso: ./update-gitlab.sh
# ============================================================

set -euo pipefail
IFS=$'\n\t'

# --- CONFIGURAÇÕES GERAIS ---
MAIN_DOMAIN="example.com.br"
CONTAINER_NAME="gitlab"
NEW_CONTAINER="gitlab-new"
IMAGE_BASE="gitlab/gitlab-ce"
DOMAIN="gitlab.${MAIN_DOMAIN}"
SSH_DOMAIN="gitssh.${MAIN_DOMAIN}"
WAIT_TIME=120
HEALTH_URL="https://${DOMAIN}/-/health"

# --- CORES ---
GREEN="\033[1;32m"
RED="\033[1;31m"
YELLOW="\033[1;33m"
NC="\033[0m" # No color

# --- FUNÇÕES DE LOG ---
log_info()  { echo -e "${GREEN}[INFO]${NC} $1" >&2; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1" >&2; }
log_error() { echo -e "${RED}[ERRO]${NC} $1" >&2; }

# --- FUNÇÕES AUXILIARES ---

check_prerequisites() {
  command -v docker >/dev/null 2>&1 || { log_error "Docker não está instalado."; exit 1; }
  command -v curl >/dev/null 2>&1 || { log_error "curl não está instalado."; exit 1; }
  command -v jq >/dev/null 2>&1   || { log_error "jq não está instalado."; exit 1; }

  if [[ -z "${GITLAB_HOME:-}" ]]; then
    log_error "A variável GITLAB_HOME não foi definida."
    exit 1
  fi
}

check_existing_container() {
  if ! docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}\$"; then
    log_error "Não foi encontrado nenhum container chamado '${CONTAINER_NAME}'."
    exit 1
  fi
}

get_current_version() {
  local image_tag
  image_tag=$(docker inspect --format='{{.Config.Image}}' "${CONTAINER_NAME}")
  echo "$image_tag" | sed -E 's|.*:([0-9]+\.[0-9]+\.[0-9]+)-ce\.0|\1|'
}

fetch_available_versions() {
  local current_version="$1"
  log_info "Versão atual: ${current_version}"
  log_info "Consultando tags disponíveis no Docker Hub..."

  local tags filtered
  tags=$(curl -s "https://registry.hub.docker.com/v2/repositories/${IMAGE_BASE}/tags/?page_size=200" \
    | jq -r '.results[].name' \
    | grep -E '^[0-9]+\.[0-9]+\.[0-9]+-ce\.0$' \
    | sed -E 's/-ce\.0$//' \
    | sort -V | uniq)

  [[ -z "$tags" ]] && { log_error "Não foi possível obter a lista de versões."; exit 1; }

  # Filtra versões maiores que a atual e extrai primeira e última de cada minor
  filtered=$(echo "$tags" | awk -v curr="$current_version" '
    function version_greater(v1, v2) {
      split(v1,a,"."); split(v2,b,".");
      for (i=1;i<=3;i++) if (a[i]>b[i]) return 1; else if (a[i]<b[i]) return 0;
      return 0;
    }
    {
      if (version_greater($0, curr)) {
        split($0, v, ".");
        key=v[1]"."v[2];
        if (!(key in first)) first[key]=$0;
        last[key]=$0;
      }
    }
    END {
      for (k in first) {
        print first[k];
        if (last[k] != first[k]) print last[k];
      }
    }' | sort -V)

  echo "$filtered"
}

choose_version() {
  local versions=("$@")
  echo
  log_info "Selecione a versão desejada:"
  local i=1
  for v in "${versions[@]}"; do
    echo "  [$i] $v"
    ((i++))
  done
  echo
  local choice
  read -rp "Digite o número da versão: " choice

  if ! [[ "$choice" =~ ^[0-9]+$ ]] || ((choice < 1 || choice > ${#versions[@]})); then
    log_error "Opção inválida."
    exit 1
  fi
  chosen_version=${versions[$((choice-1))]}
}

download_image() {
  local version="$1"
  local image="${IMAGE_BASE}:${version}-ce.0"
  log_info "Baixando imagem ${image}..."
  docker pull "$image"
}

stop_and_backup() {
  log_info "Parando containers existentes..."
  docker stop "$CONTAINER_NAME" "$NEW_CONTAINER" 2>/dev/null || true

  log_info "Renomeando container antigo..."
  docker rename "$CONTAINER_NAME" "${CONTAINER_NAME}-old" 2>/dev/null || true
}

create_new_container() {
  local version="$1"
  local image="${IMAGE_BASE}:${version}-ce.0"

  log_info "Criando novo container ${NEW_CONTAINER}..."
  docker run --detach \
    --hostname "$DOMAIN" \
    --publish 4443:443 \
    --publish 8080:80 \
    --publish 222:22 \
    --name "$NEW_CONTAINER" \
    --restart always \
    --env GITLAB_OMNIBUS_CONFIG="external_url 'https://${DOMAIN}'; gitlab_rails['gitlab_shell_ssh_port'] = 222; gitlab_rails['gitlab_ssh_host'] = '${SSH_DOMAIN}'; letsencrypt['enable'] = false" \
    --env EXTERNAL_URL="https://${DOMAIN}" \
    --volume "$GITLAB_HOME/config:/etc/gitlab" \
    --volume "$GITLAB_HOME/logs:/var/log/gitlab" \
    --volume "$GITLAB_HOME/data:/var/opt/gitlab" \
    --shm-size 256m \
    "$image"

  log_info "Aguardando ${WAIT_TIME}s para o GitLab iniciar..."
  sleep "${WAIT_TIME}"
}

check_health() {
  log_info "Verificando status de saúde do GitLab..."
  for attempt in {1..5}; do
    local response
    response=$(curl -sk --max-time 10 "$HEALTH_URL" || true)
    if [[ "$response" == "GitLab OK" ]]; then
      log_info "GitLab respondeu com sucesso!"
      return 0
    fi
    log_warn "Tentativa ${attempt} falhou. Aguardando 30s antes de tentar novamente..."
    sleep 30
  done
  log_error "O GitLab não respondeu corretamente após 5 tentativas."
  return 1
}

confirm_rollback() {
  echo
  read -rp "Deseja executar rollback para a versão anterior? (s/N): " answer
  [[ "$answer" =~ ^[sS]$ ]]
}

rollback() {
  log_warn "Executando rollback..."
  docker stop "$NEW_CONTAINER" 2>/dev/null || true
  docker rm "$NEW_CONTAINER" 2>/dev/null || true
  docker rename "${CONTAINER_NAME}-old" "$CONTAINER_NAME" 2>/dev/null || true
  log_info "Rollback concluído. O container antigo foi restaurado."
}

# --- FUNÇÃO PARA LIMPAR IMAGENS ANTIGAS ---
cleanup_old_images() {
  log_info "Removendo imagens antigas do GitLab..."
  local keep_image="${IMAGE_BASE}:${chosen_version}-ce.0"
  # lista todas as imagens do gitlab/gitlab-ce
  local images
  images=$(docker images --format '{{.Repository}}:{{.Tag}} {{.ID}}' | grep "^${IMAGE_BASE}:" || true)
  while read -r img; do
    local img_tag img_id
    img_tag=$(echo "$img" | awk '{print $1}')
    img_id=$(echo "$img" | awk '{print $2}')
    if [[ "$img_tag" != "$keep_image" ]]; then
      log_info "Removendo imagem $img_tag ($img_id)..."
      docker rmi -f "$img_id" || true
    fi
  done <<< "$images"
}

finalize_update() {
  log_info "Finalizando atualização..."
  docker rename "$NEW_CONTAINER" "$CONTAINER_NAME"
  docker rm -f "${CONTAINER_NAME}-old" 2>/dev/null || true
  cleanup_old_images
  log_info "Atualização concluída com sucesso!"

}

# --- EXECUÇÃO PRINCIPAL ---
main() {
  local start_time;
  start_time=$(date +%s)

  check_prerequisites
  check_existing_container

  local current_version
  current_version=$(get_current_version)

  local available_versions_raw
  available_versions_raw=$(fetch_available_versions "$current_version")

  IFS=$'\n' read -r -d '' -a available_versions <<< "$(echo -e "${available_versions_raw}\n")" || true
  if [[ ${#available_versions[@]} -eq 0 ]]; then
    log_warn "Nenhuma versão mais recente encontrada."
    exit 0
  fi

  choose_version "${available_versions[@]}"
  log_info "Versão selecionada: ${chosen_version}"

  # 1️⃣ Baixa imagem antes de parar o GitLab (reduz downtime)
  download_image "$chosen_version"

  # 2️⃣ Stop/rename containers e sobe o novo
  stop_and_backup
  create_new_container "$chosen_version"

  # 3️⃣ Health check duplo + rollback opcional
  if ! check_health; then
    if confirm_rollback; then
      rollback
    else
      log_warn "Rollback cancelado."
    fi
    exit 1
  fi

  finalize_update

  local end_time;
  end_time=$(date +%s)

  local duration=$((end_time - start_time))
  log_info "Tempo total: ${duration}s"
}

main "$@"
