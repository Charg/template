#!/usr/bin/env bash
# python flavour: ruff's linter and formatter check (ruff.toml) over every Python file.

# shellcheck source=hack/tools.sh
source "$(dirname "${BASH_SOURCE[0]}")/../tools.sh"

require_tools ruff

cd "${REPO_ROOT}"

mapfile -d '' python_files < <(repo_files '*.py' '*.pyi')
if ((${#python_files[@]} > 0)); then
  log "ruff check"
  ruff check "${python_files[@]}"
  log "ruff format --check"
  ruff format --check "${python_files[@]}"
fi
