#!/usr/bin/env bash

build_deploy_ssh_args() {
  DEPLOY_SSH_ARGS=(-o "ConnectTimeout=${DEPLOY_CONNECT_TIMEOUT:-10}")

  local ip_family="${DEPLOY_IP_FAMILY:-4}"

  case "${ip_family}" in
    4)
      DEPLOY_SSH_ARGS+=(-4)
      ;;
    6)
      DEPLOY_SSH_ARGS+=(-6)
      ;;
    *)
      echo "Invalid DEPLOY_IP_FAMILY='${DEPLOY_IP_FAMILY}'. Use 4 or 6." >&2
      return 1
      ;;
  esac

  if [[ -n "${DEPLOY_SSH_FLAGS:-}" ]]; then
    local extra_args=()
    read -r -a extra_args <<<"${DEPLOY_SSH_FLAGS}"
    DEPLOY_SSH_ARGS+=("${extra_args[@]}")
  fi
}
