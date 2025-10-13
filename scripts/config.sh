#!/usr/bin/env bash
# Central configuration file for docker/ollama helper scripts.
# Edit these values to change container/model names and host<->container paths.
set -euo pipefail

# Name of the docker container that runs ollama
CONTAINER_NAME="${CONTAINER_NAME:-ollama}"

# Default model name used by scripts
MODEL_NAME="${MODEL_NAME:-Haku}"

# Host repository root (defaults to one level up from this config file)
HOST_REPO_DIR="${HOST_REPO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# Path inside the container where the repo will be mounted (default used by docker-run)
CONTAINER_REPO_DIR="${CONTAINER_REPO_DIR:-/root/.ollama}"

# Expose a small helper for looking up the path inside the container for a host path
host_to_container_path() {
    local host_path="$1"
    # If host path is inside HOST_REPO_DIR, map to CONTAINER_REPO_DIR
    case "$host_path" in
        "$HOST_REPO_DIR"* )
            printf "%s" "${CONTAINER_REPO_DIR}${host_path#$HOST_REPO_DIR}"
            ;;
        *) printf "%s" "$host_path" ;;
    esac
}

# Modelfile locations: prefer an explicit env override, otherwise look in the repo root,
# then `models/modelfiles/Modelfile` if you moved the file.
if [[ -n "${HOST_MODELF:-}" ]]; then
    : # keep user-specified value
else
    if [[ -f "$HOST_REPO_DIR/Modelfile" ]]; then
        HOST_MODELF="$HOST_REPO_DIR/Modelfile"
    elif [[ -f "$HOST_REPO_DIR/models/modelfiles/Modelfile" ]]; then
        HOST_MODELF="$HOST_REPO_DIR/models/modelfiles/Modelfile"
    else
        HOST_MODELF="$HOST_REPO_DIR/Modelfile"
    fi
fi

# container-side Modelfile path maps the host path into the container mount point
if [[ -n "${CONTAINER_MODELF:-}" ]]; then
    :
else
    CONTAINER_MODELF="$(host_to_container_path "$HOST_MODELF")"
fi

export CONTAINER_NAME MODEL_NAME HOST_REPO_DIR CONTAINER_REPO_DIR HOST_MODELF CONTAINER_MODELF
