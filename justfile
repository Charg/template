# Project template: dev tasks. Every recipe assumes the nix toolchain is on PATH: run inside the
# dev shell (`nix develop`, or direnv via .envrc), or one-shot as `nix develop -c just <recipe>`.

set shell := ["bash", "-euo", "pipefail", "-c"]

# List available recipes.
_default:
    @just --list --unsorted

# Generate a new project at <path> (asks the template's questions; extra args go to copier).
[positional-arguments]
new path *args:
    hack/new.sh "$@"

# Pull template changes into an existing project (extra args go to copier update).
[positional-arguments]
update path *args:
    hack/update.sh "$@"

# Render every variant of the template (or the named ones), lint each, and check `copier update`.
[positional-arguments]
test *variants:
    hack/test.sh "$@"

# Lint this repo: yamllint, shellcheck, nixfmt, actionlint, zizmor.
lint:
    hack/lint.sh

# Install the prek git hooks from .pre-commit-config.yaml (once per clone).
install-hooks:
    prek install

# List the dev shell's packages and the versions flake.lock pins them to.
versions:
    @nix eval --raw ".#devShells.$(nix eval --impure --raw --expr builtins.currentSystem).default.nativeBuildInputs" \
      --apply 'ps: builtins.concatStringsSep "" (map (p: "${p.pname or p.name} ${p.version or "-"}\n") ps)'
