#!/usr/bin/env bash
# Generate a new project from this template, then get it to a lintable state:
#
#   just new <path> [copier args...]
#
# The template source defaults to gh:Charg/template, so the project's .copier-answers.yml points
# at GitHub and `copier update` works from any machine. TEMPLATE_SRC overrides it (e.g. `.` to
# render this checkout, uncommitted changes included).

# shellcheck source=hack/tools.sh
source "$(dirname "${BASH_SOURCE[0]}")/tools.sh"

require_tools copier git nix

(($# >= 1)) || die "usage: just new <path> [copier args...]"
dest="$1"
shift

if [ -e "${dest}" ] && [ -n "$(ls -A "${dest}")" ]; then
  die "${dest} exists and is not empty"
fi

src="${TEMPLATE_SRC:-gh:Charg/template}"
if [ "${src}" = "." ]; then
  src="${REPO_ROOT}"
fi

log "rendering ${src} into ${dest}"
copier copy "$@" "${src}" "${dest}"

cd "${dest}"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  log "initialising git repository"
  git init --quiet --initial-branch=main
fi
# Flakes only see files git knows about.
git add --all

log "locking the flake"
nix flake lock
git add flake.lock

log "installing git hooks"
nix develop --command prek install

log "linting"
nix develop --command just lint

cat >&2 <<EOF

Created $(pwd). Next:
  - fill in the Project section of AGENTS.md
  - review and commit: git commit -m "feat: init project from template"
  - if it's on GitHub: gh repo create, enable auto-merge + squash merges, add a main ruleset
    requiring the \`ci\` check, then run \`gh actions-lock --no-narrow\` to create actions.lock
EOF
