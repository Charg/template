#!/usr/bin/env bash
# Render variants of the template and check each one: the expected files exist (and the files of
# flavours not chosen don't), `just lint` passes in its own dev shell with every chosen flavour's
# lint step running against a small fixture, each flavour's lint step fails on a broken fixture,
# and an immediate `copier update` changes nothing. Scenario variants check that a template change
# reaches a project through `copier update` without touching project-owned text, that a flavour
# can be added to an existing project, and that invalid answers are rejected.
#
#   hack/test.sh               every variant
#   hack/test.sh go update     only these (CI runs one variant per job)
#
# The template is rendered from a snapshot of this checkout (uncommitted changes included)
# committed to a scratch git repo: Copier records the template commit in .copier-answers.yml and
# `copier update` needs that commit to exist, which a dirty working tree can't give it.

# shellcheck source=hack/tools.sh
source "$(dirname "${BASH_SOURCE[0]}")/tools.sh"

require_tools copier git nix tar

ALL_VARIANTS=(github offline unstable go container-images helm-charts python combo update helm-unstable)
ALL_FLAVOURS=(go container-images helm-charts python)

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

expect_no_conflicts() {
  if grep -rq '^<<<<<<<' "$1" --exclude-dir=.git; then
    die "copier update left conflict markers in $1"
  fi
}

copier_update() {
  local dest="$1"
  shift
  (cd "${dest}" && copier update --quiet --defaults --vcs-ref=HEAD "$@")
}

# Render the snapshot (or ${template_src}) into $1 (extra args go to copier), then git init and
# stage it all.
render() {
  local dest="$1"
  shift
  copier copy --quiet --defaults --vcs-ref=HEAD \
    --data 'description=Template test project' "$@" "${template_src:-${snapshot}}" "${dest}"
  git -C "${dest}" init --quiet --initial-branch=main
  git -C "${dest}" add --all
}

# YAML flow sequence for copier's --data: flavours_data go helm-charts -> flavours=[go,helm-charts]
flavours_data() {
  local IFS=,
  printf 'flavours=[%s]' "$*"
}

# Run a command in the project's dev shell, output to $log (shown on failure).
in_shell() {
  local dest="$1"
  shift
  (cd "${dest}" && nix develop --command "$@") >"${log}" 2>&1
}

# --- per flavour: heading in AGENTS.md, config file, tools, lint marker, fixtures -------------

flavour_heading() {
  case "$1" in
    go) echo '## Go' ;;
    container-images) echo '## Container images' ;;
    helm-charts) echo '## Helm charts' ;;
    python) echo '## Python' ;;
  esac
}

flavour_config() {
  case "$1" in
    go) echo .golangci.yml ;;
    container-images) echo .hadolint.yaml ;;
    helm-charts) echo ct.yaml ;;
    python) echo ruff.toml ;;
  esac
}

# A .gitignore line only this flavour adds (empty when it adds none).
flavour_gitignore() {
  case "$1" in
    go) echo '*.test' ;;
    helm-charts) echo '*.tgz' ;;
    python) echo '__pycache__/' ;;
  esac
}

# Packages `just versions` must list.
flavour_tools() {
  case "$1" in
    go) echo go golangci-lint ;;
    container-images) echo hadolint docker-buildx ;;
    helm-charts) echo chart-testing kubeconform ;;
    python) echo ruff ;;
  esac
}

# A line the flavour's lint step logs, proving `just lint` ran it.
flavour_lint_marker() {
  case "$1" in
    go) echo '==> golangci-lint run' ;;
    container-images) echo '==> hadolint' ;;
    helm-charts) echo '==> kubeconform' ;;
    python) echo '==> ruff check' ;;
  esac
}

# Minimal sources the flavour's lint step passes on.
add_fixture() {
  local dest="$1"
  case "$2" in
    go)
      printf 'module example.invalid/demo\n\ngo 1.24\n' >"${dest}/go.mod"
      printf 'package main\n\nimport "fmt"\n\nfunc main() {\n\tfmt.Println("demo")\n}\n' >"${dest}/main.go"
      ;;
    container-images)
      printf 'FROM scratch\nCOPY README.md /\n' >"${dest}/Dockerfile"
      ;;
    helm-charts)
      mkdir -p "${dest}/charts/demo/templates" "${dest}/charts/demo/ci"
      cat >"${dest}/charts/demo/Chart.yaml" <<'EOF'
---
apiVersion: v2
name: demo
description: Template test chart
type: application
version: 0.1.0
appVersion: "1.0.0"
EOF
      printf -- '---\ngreeting: hello\n' >"${dest}/charts/demo/values.yaml"
      printf -- '---\ngreeting: bonjour\n' >"${dest}/charts/demo/ci/french-values.yaml"
      cat >"${dest}/charts/demo/templates/configmap.yaml" <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ .Release.Name }}-demo
data:
  greeting: {{ .Values.greeting | quote }}
EOF
      ;;
    python)
      printf 'print("demo")\n' >"${dest}/main.py"
      ;;
  esac
  git -C "${dest}" add --all
}

# A file (relative to the project) that makes the flavour's lint step fail.
broken_file() {
  case "$1" in
    go) echo broken.go ;;
    container-images) echo broken.Dockerfile ;;
    helm-charts) echo charts/demo/templates/broken.yaml ;;
    python) echo broken.py ;;
  esac
}

# What the flavour's lint step reports about broken_file, proving it failed for that reason.
broken_reason() {
  case "$1" in
    go) echo broken.go ;;
    container-images) echo DL3006 ;;
    helm-charts) echo bogus ;;
    python) echo F401 ;;
  esac
}

write_broken_file() {
  case "$1" in
    go) printf 'package main\n\nfunc   unformatted()  {}\n' ;;
    container-images) printf 'FROM alpine\n' ;;
    # helm lint accepts it; kubeconform -strict rejects the unknown field.
    helm-charts) printf 'apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: broken\nbogus: field\n' ;;
    python) printf 'import os\n' ;;
  esac
}

# Files, AGENTS.md section, Renovate preset and .gitignore block of one flavour, present or absent.
check_flavour() {
  local dest="$1" flavour="$2" want="$3" github="$4" heading config ignore
  heading="$(flavour_heading "${flavour}")"
  config="$(flavour_config "${flavour}")"
  ignore="$(flavour_gitignore "${flavour}")"
  if [ "${want}" = present ]; then
    expect_file "${dest}/hack/lint.d/${flavour}.sh"
    expect_file "${dest}/${config}"
    grep -qxF "${heading}" "${dest}/AGENTS.md" || die "AGENTS.md lacks '${heading}'"
    if [ -n "${ignore}" ]; then
      grep -qxF "${ignore}" "${dest}/.gitignore" || die ".gitignore lacks ${ignore}"
    fi
    if [ "${github}" = true ]; then
      grep -qF "//renovate/${flavour}.json5\"" "${dest}/.github/renovate.json5" ||
        die "renovate.json5 does not extend the ${flavour} preset"
    fi
  else
    expect_no_file "${dest}/hack/lint.d/${flavour}.sh"
    expect_no_file "${dest}/${config}"
    if grep -qxF "${heading}" "${dest}/AGENTS.md"; then
      die "AGENTS.md has '${heading}' without the ${flavour} flavour"
    fi
    if [ -n "${ignore}" ] && grep -qxF "${ignore}" "${dest}/.gitignore"; then
      die ".gitignore has ${ignore} without the ${flavour} flavour"
    fi
    if [ "${github}" = true ] && grep -qF "//renovate/${flavour}.json5\"" "${dest}/.github/renovate.json5"; then
      die "renovate.json5 extends the ${flavour} preset without the flavour"
    fi
  fi
}

# Inside the dev shell: the flavours' tools are there, `just lint` runs every flavour's lint step
# and passes, and each flavour's lint step fails on a broken fixture.
check_lint() {
  local dest="$1" name="$2" flavour tool broken
  shift 2
  for flavour in "$@"; do
    add_fixture "${dest}" "${flavour}"
  done

  log "[${name}] just versions lists the dev shell's packages"
  in_shell "${dest}" just versions || die "just versions failed: $(cat "${log}")"
  grep -q '^prek ' "${log}" || die "just versions did not list prek"
  for flavour in "$@"; do
    for tool in $(flavour_tools "${flavour}"); do
      grep -q "^${tool} " "${log}" || die "the dev shell lacks ${tool} (${flavour})"
    done
  done

  log "[${name}] just lint (in the rendered dev shell)"
  in_shell "${dest}" just lint || die "just lint failed: $(cat "${log}")"
  for flavour in "$@"; do
    grep -qF "$(flavour_lint_marker "${flavour}")" "${log}" ||
      die "just lint did not run the ${flavour} lint step: $(cat "${log}")"
  done

  for flavour in "$@"; do
    log "[${name}] the ${flavour} lint step fails on a broken fixture"
    broken="${dest}/$(broken_file "${flavour}")"
    write_broken_file "${flavour}" >"${broken}"
    if in_shell "${dest}" bash "hack/lint.d/${flavour}.sh"; then
      die "hack/lint.d/${flavour}.sh passed on a broken fixture: $(cat "${log}")"
    fi
    grep -qF "$(broken_reason "${flavour}")" "${log}" ||
      die "hack/lint.d/${flavour}.sh failed for another reason: $(cat "${log}")"
    rm -f "${broken}"
  done
}

# Render one plain variant, check it, lint it, and check `copier update` is a no-op.
run_render_variant() {
  local name="$1" github=true channel=nixos-26.05 flavours=() dest flavour
  case "${name}" in
    github) ;;
    offline) github=false ;;
    unstable) channel=nixos-unstable ;;
    go | container-images | helm-charts) flavours=("${name}") ;;
    # The python repos in mind are offline: covers flavours without .github/.
    python) github=false flavours=(python) ;;
    combo) flavours=(go container-images helm-charts python) ;;
  esac
  dest="${work}/demo-${name}"

  log "[${name}] render"
  render "${dest}" --data "github=${github}" --data "nixpkgs_channel=${channel}" \
    --data "$(flavours_data "${flavours[@]}")"

  log "[${name}] check files"
  for f in flake.nix .envrc justfile hack/tools.sh hack/lint.sh .gitignore .yamllint.yaml \
    .pre-commit-config.yaml AGENTS.md CLAUDE.md README.md .copier-answers.yml; do
    expect_file "${dest}/${f}"
  done
  grep -q '<!-- BEGIN TEMPLATE' "${dest}/AGENTS.md" || die "AGENTS.md has no template markers"
  grep -qx '@AGENTS.md' "${dest}/CLAUDE.md" || die "CLAUDE.md does not import AGENTS.md"
  grep -q 'project_name: demo-' "${dest}/.copier-answers.yml" || die "project name not defaulted from folder"
  if [ "${github}" = false ]; then
    expect_no_file "${dest}/.github"
    grep -q 'This repo is offline' "${dest}/AGENTS.md" || die "offline AGENTS.md lacks offline rules"
  else
    expect_file "${dest}/.github/renovate.json5"
    expect_file "${dest}/.github/workflows/ci.yaml"
    expect_file "${dest}/.github/workflows/flake-lock-diff.yaml"
  fi
  grep -q "nixpkgs/${channel}\"" "${dest}/flake.nix" || die "nixpkgs channel not applied"
  for flavour in "${ALL_FLAVOURS[@]}"; do
    if [[ " ${flavours[*]} " == *" ${flavour} "* ]]; then
      check_flavour "${dest}" "${flavour}" present "${github}"
    else
      check_flavour "${dest}" "${flavour}" absent "${github}"
    fi
  done

  check_lint "${dest}" "${name}" "${flavours[@]}"

  log "[${name}] copier update is a no-op"
  git -C "${dest}" add --all
  git_test -C "${dest}" commit --quiet --message "init"
  copier_update "${dest}"
  expect_clean "${dest}" "copier update changed ${dest}"
}

# A template change reaches the project, project-owned text survives, and a flavour can be added
# to the project later.
run_update() {
  local dest="${work}/demo-update"
  # A clone of the snapshot, so the template change below doesn't reach other variants.
  local template_src="${work}/template-update"
  git clone --quiet "${snapshot}" "${template_src}"

  log "[update] render"
  render "${dest}"
  git_test -C "${dest}" commit --quiet --message "init"

  log "[update] a template change reaches the project; project-owned text survives"
  # Project edits: a rule in AGENTS.md's Project section, a package in flake.nix, a README line.
  printf '\n- Project rule that must survive updates.\n' >>"${dest}/AGENTS.md"
  sed -i 's|            pkgs.git$|            pkgs.git\n            pkgs.jq|' "${dest}/flake.nix"
  printf '\nProject README line.\n' >>"${dest}/README.md"
  git_test -C "${dest}" commit --quiet --all --message "project edits"
  # Template edits: a new shared rule in AGENTS.md's template section, a new recipe, a README line
  # (README.md is project-owned after creation, so this one must not arrive).
  # shellcheck disable=SC2016 # the backticks are literal Markdown
  sed -i 's|^- Plans, tickets and throwaway output go in `.scratch/` (gitignored).$|&\n- Template rule added later.|' \
    "${template_src}/template/AGENTS.md.jinja"
  printf '\n# Added later.\nlater:\n    @true\n' >>"${template_src}/template/justfile.jinja"
  printf '\nTemplate README line.\n' >>"${template_src}/template/README.md.jinja"
  git_test -C "${template_src}" commit --quiet --all --message "template change"
  copier_update "${dest}"
  grep -q 'Template rule added later.' "${dest}/AGENTS.md" || die "template rule did not reach AGENTS.md"
  grep -q '^later:' "${dest}/justfile" || die "template recipe did not reach justfile"
  grep -q 'Project rule that must survive updates.' "${dest}/AGENTS.md" || die "project rule was lost"
  grep -q 'pkgs.jq' "${dest}/flake.nix" || die "project package was lost"
  grep -q 'Project README line.' "${dest}/README.md" || die "project README edit was lost"
  if grep -q 'Template README line.' "${dest}/README.md"; then
    die "README.md was updated, but it is project-owned"
  fi
  expect_no_conflicts "${dest}"
  git_test -C "${dest}" commit --quiet --all --message "template update"

  log "[update] copier update --data adds a flavour to an existing project"
  copier_update "${dest}" --data "$(flavours_data container-images)"
  expect_no_conflicts "${dest}"
  grep -qx -- '- container-images' "${dest}/.copier-answers.yml" || die "flavour not recorded in the answers"
  check_flavour "${dest}" container-images present true
  check_flavour "${dest}" go absent true
  grep -q 'pkgs.jq' "${dest}/flake.nix" || die "project package was lost adding a flavour"
  grep -q 'Project rule that must survive updates.' "${dest}/AGENTS.md" || die "project rule was lost adding a flavour"
  git -C "${dest}" add --all
  check_lint "${dest}" update container-images
  git -C "${dest}" add --all
  git_test -C "${dest}" commit --quiet --message "add container-images"
  copier_update "${dest}"
  expect_clean "${dest}" "copier update changed ${dest} after adding a flavour"
}

# helm-charts needs helm 3, which nixos-unstable no longer ships.
run_helm_unstable() {
  log "[helm-unstable] helm-charts on nixos-unstable is rejected"
  log="${work}/helm-unstable.log"
  if render "${work}/demo-helm-unstable" --data nixpkgs_channel=nixos-unstable \
    --data "$(flavours_data helm-charts)" >"${log}" 2>&1; then
    die "helm-charts with nixos-unstable rendered; it should be rejected"
  fi
  grep -q 'helm 4' "${log}" || die "rejection does not explain why: $(cat "${log}")"
}

# CI runs one job per variant; a variant missing from its matrix would never run there.
for variant in "${ALL_VARIANTS[@]}"; do
  grep -qx "          - ${variant}" "${REPO_ROOT}/.github/workflows/ci.yaml" ||
    die "variant ${variant} is missing from the test matrix in .github/workflows/ci.yaml"
done

variants=("$@")
if ((${#variants[@]} == 0)); then
  variants=("${ALL_VARIANTS[@]}")
fi
for variant in "${variants[@]}"; do
  [[ " ${ALL_VARIANTS[*]} " == *" ${variant} "* ]] || die "unknown variant: ${variant} (one of: ${ALL_VARIANTS[*]})"
done

log "snapshot the template into a scratch repo"
mkdir -p "${snapshot}"
repo_files . | tar -C "${REPO_ROOT}" --null --files-from=- -cf - | tar -C "${snapshot}" -xf -
git -C "${snapshot}" init --quiet --initial-branch=main
git -C "${snapshot}" add --all
git_test -C "${snapshot}" commit --quiet --message "snapshot"

for variant in "${variants[@]}"; do
  log="${work}/${variant}.log"
  case "${variant}" in
    update) run_update ;;
    helm-unstable) run_helm_unstable ;;
    *) run_render_variant "${variant}" ;;
  esac
done

log "all checks passed: ${variants[*]}"
