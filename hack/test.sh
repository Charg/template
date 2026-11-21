#!/usr/bin/env bash
# Render every variant of the template and check each one: the expected files exist, `just lint`
# passes in its own dev shell, and an immediate `copier update` changes nothing. Then check that a
# template change reaches a project through `copier update` without touching project-owned text.
#
# The template is rendered from a snapshot of this checkout (uncommitted changes included)
# committed to a scratch git repo: Copier records the template commit in .copier-answers.yml and
# `copier update` needs that commit to exist, which a dirty working tree can't give it.

# shellcheck source=hack/tools.sh
source "$(dirname "${BASH_SOURCE[0]}")/tools.sh"

require_tools copier git nix tar

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
snapshot="${work}/template"

git_test() {
  git -c user.name=template-test -c user.email=template-test@example.invalid \
    -c commit.gpgsign=false "$@"
}

expect_file() {
  [ -e "$1" ] || die "expected $1 to exist"
}

expect_no_file() {
  [ ! -e "$1" ] || die "expected $1 not to exist"
}

expect_clean() {
  if [ -n "$(git -C "$1" status --porcelain)" ]; then
    git -C "$1" status --short >&2
    git -C "$1" diff >&2
    die "$2"
  fi
}

copier_update() {
  (cd "$1" && copier update --quiet --defaults --vcs-ref=HEAD)
}

log "snapshot the template into a scratch repo"
mkdir -p "${snapshot}"
repo_files . | tar -C "${REPO_ROOT}" --null --files-from=- -cf - | tar -C "${snapshot}" -xf -
git -C "${snapshot}" init --quiet --initial-branch=main
git -C "${snapshot}" add --all
git_test -C "${snapshot}" commit --quiet --message "snapshot"

for variant in github offline unstable; do
  dest="${work}/demo-${variant}"
  args=()
  case "${variant}" in
    github) args=(--data github=true) ;;
    offline) args=(--data github=false) ;;
    unstable) args=(--data github=true --data nixpkgs_channel=nixos-unstable) ;;
  esac

  log "[${variant}] render"
  copier copy --quiet --defaults --vcs-ref=HEAD \
    --data 'description=Template test project' "${args[@]}" "${snapshot}" "${dest}"
  git -C "${dest}" init --quiet --initial-branch=main
  git -C "${dest}" add --all

  log "[${variant}] check files"
  for f in flake.nix .envrc justfile hack/tools.sh hack/lint.sh .gitignore .yamllint.yaml \
    .pre-commit-config.yaml AGENTS.md CLAUDE.md README.md .copier-answers.yml; do
    expect_file "${dest}/${f}"
  done
  grep -q '<!-- BEGIN TEMPLATE' "${dest}/AGENTS.md" || die "AGENTS.md has no template markers"
  grep -qx '@AGENTS.md' "${dest}/CLAUDE.md" || die "CLAUDE.md does not import AGENTS.md"
  grep -q 'project_name: demo-' "${dest}/.copier-answers.yml" || die "project name not defaulted from folder"
  if [ "${variant}" = "offline" ]; then
    expect_no_file "${dest}/.github"
    grep -q 'This repo is offline' "${dest}/AGENTS.md" || die "offline AGENTS.md lacks offline rules"
  else
    expect_file "${dest}/.github/renovate.json5"
    expect_file "${dest}/.github/workflows/ci.yaml"
    expect_file "${dest}/.github/workflows/flake-lock-diff.yaml"
  fi
  if [ "${variant}" = "unstable" ]; then
    grep -q 'nixpkgs/nixos-unstable"' "${dest}/flake.nix" || die "nixpkgs channel not applied"
  fi

  log "[${variant}] just lint (in the rendered dev shell)"
  (cd "${dest}" && nix develop --command just lint)

  log "[${variant}] copier update is a no-op"
  git -C "${dest}" add --all
  git_test -C "${dest}" commit --quiet --message "init"
  copier_update "${dest}"
  expect_clean "${dest}" "copier update changed ${dest}"
done

log "[update] a template change reaches the project; project-owned text survives"
dest="${work}/demo-github"
# Project edits: a rule in AGENTS.md's Project section, a package in flake.nix, a README line.
printf '\n- Project rule that must survive updates.\n' >>"${dest}/AGENTS.md"
sed -i 's|            pkgs.git$|            pkgs.git\n            pkgs.jq|' "${dest}/flake.nix"
printf '\nProject README line.\n' >>"${dest}/README.md"
git_test -C "${dest}" commit --quiet --all --message "project edits"
# Template edits: a new shared rule in AGENTS.md's template section, a new recipe, a README line
# (README.md is project-owned after creation, so this one must not arrive).
# shellcheck disable=SC2016 # the backticks are literal Markdown
sed -i 's|^- Plans, tickets and throwaway output go in `.scratch/` (gitignored).$|&\n- Template rule added later.|' \
  "${snapshot}/template/AGENTS.md.jinja"
printf '\n# Added later.\nlater:\n    @true\n' >>"${snapshot}/template/justfile.jinja"
printf '\nTemplate README line.\n' >>"${snapshot}/template/README.md.jinja"
git_test -C "${snapshot}" commit --quiet --all --message "template change"
copier_update "${dest}"
grep -q 'Template rule added later.' "${dest}/AGENTS.md" || die "template rule did not reach AGENTS.md"
grep -q '^later:' "${dest}/justfile" || die "template recipe did not reach justfile"
grep -q 'Project rule that must survive updates.' "${dest}/AGENTS.md" || die "project rule was lost"
grep -q 'pkgs.jq' "${dest}/flake.nix" || die "project package was lost"
grep -q 'Project README line.' "${dest}/README.md" || die "project README edit was lost"
if grep -q 'Template README line.' "${dest}/README.md"; then
  die "README.md was updated, but it is project-owned"
fi
if grep -rq '^<<<<<<<' "${dest}" --exclude-dir=.git; then
  die "copier update left conflict markers"
fi
(cd "${dest}" && nix develop --command just lint)

log "all checks passed"
