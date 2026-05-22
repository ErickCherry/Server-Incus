#!/usr/bin/env bash
# Carga secretos locales (no versionados)
_LAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -f "$_LAB_ROOT/secrets/lab.secrets.env" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "$_LAB_ROOT/secrets/lab.secrets.env"
  set +a
fi
