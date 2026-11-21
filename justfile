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

# Render every variant of the template, lint each one, and check `copier update` is a no-op.
test:
    hack/test.sh

# Lint this repo: yamllint, shellcheck, nixfmt, actionlint, zizmor.
lint:
    hack/lint.sh

# Install the prek git hooks from .pre-commit-config.yaml (once per clone).
install-hooks:
    prek install
