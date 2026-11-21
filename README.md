# Project Template

The [Copier](https://copier.readthedocs.io/) template for new projects, and the shared Renovate
preset they extend.

A generated project gets:

- a nix flake dev shell (`forAllSystems`, nixpkgs stable by default) with `.envrc` for direnv
- a `justfile` whose recipes are one-line shims over `hack/*.sh`, with `hack/tools.sh` helpers
- `just lint`: yamllint, shellcheck, nixfmt, actionlint, zizmor
- prek hooks: whitespace/EOF/YAML/TOML checks, private keys, betterleaks, `just lint`
- `AGENTS.md` (shared rules between TEMPLATE markers, a `## Project` section of its own) and
  `CLAUDE.md` importing it
- on GitHub: a `ci` workflow, a flake.lock closure diff on PRs, and a `renovate.json5` that extends
  [`renovate/default.json5`](renovate/default.json5) (7-day release age, automerge on green,
  majors manual, weekly lock maintenance)

## Usage

Everything runs in this repo's dev shell (`nix develop`, or direnv).

```sh
just new ~/code/my-project       # asks the questions, renders, git init, flake lock, hooks, lint
just update ~/code/my-project    # pull template changes into an existing project (3-way merge)
just test                        # render every variant, lint each, check update is a no-op
just lint
```

`just new` renders from `gh:Charg/template`, so the project's `.copier-answers.yml` points at GitHub
and `copier update` works anywhere. To try uncommitted template changes, use
`TEMPLATE_SRC=. just new <path>`.

Without this checkout: `nix run nixpkgs#copier -- copy gh:Charg/template <path>`, and
`nix run nixpkgs#copier -- update` inside a project.

## Questions

| Question | Default | Effect |
|---|---|---|
| `project_name` | folder name | justfile header, README title |
| `description` | (required) | flake description, README, `AGENTS.md` |
| `github` | `true` | `false` drops `.github/` and switches `AGENTS.md` to offline, commit-to-main rules |
| `nixpkgs_channel` | `nixos-26.05` | the dev shell's nixpkgs branch (`nixos-unstable` for newer tools) |

## Renovate preset

Projects extend it rather than copying it:

```json5
{ extends: ["github>Charg/template//renovate/default.json5"] }
```

Renovate has to be able to read this repo: keep it public, or give the Renovate app access to it.
Platform automerge also needs "Allow auto-merge" and squash merges enabled on each repo, plus a
`main` ruleset that requires the `ci` check (the gate job in each `ci.yaml`).
