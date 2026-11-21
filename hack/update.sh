#!/usr/bin/env bash
# Pull template changes into an existing project:
#
#   just update <path> [copier args...]
#
# Copier does a 3-way merge: template changes land, project edits stay, and overlapping edits are
# left as conflict markers to resolve. Questions answered before are not asked again; new ones are.

# shellcheck source=hack/tools.sh
source "$(dirname "${BASH_SOURCE[0]}")/tools.sh"

require_tools copier git

(($# >= 1)) || die "usage: just update <path> [copier args...]"
dest="$1"
shift

[ -f "${dest}/.copier-answers.yml" ] || die "${dest} has no .copier-answers.yml: not generated from this template"
if [ -n "$(git -C "${dest}" status --porcelain)" ]; then
  die "${dest} has uncommitted changes; commit or stash them first"
fi

copier update --skip-answered "$@" "${dest}"

log "review the result: git -C ${dest} diff"
