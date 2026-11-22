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
- the toolchain layers of the [flavours](#flavours) it picks
- on GitHub: a `ci` workflow, a flake.lock closure diff on PRs, and a `renovate.json5` that extends
  [`renovate/default.json5`](renovate/default.json5) (7-day release age, automerge on green,
  majors manual, weekly lock maintenance)

## Usage

Everything runs in this repo's dev shell (`nix develop`, or direnv).

```sh
just new ~/code/my-project       # asks the questions, renders, git init, flake lock, hooks, lint
just update ~/code/my-project    # pull template changes into an existing project (3-way merge)
just test                        # render every variant, lint each, check update is a no-op
just test go update              # only the named variants (CI runs one per job)
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
| `flavours` | none | toolchain layers to add (multiselect), see below |

## Flavours

A flavour is a toolchain layer any project can opt into: its tools in the flake, a lint step in
`hack/lint.d/<flavour>.sh` (which `hack/lint.sh` runs), its config file, `.gitignore` entries, an
`AGENTS.md` section, and a Renovate preset `renovate/<flavour>.json5` that the project's
`renovate.json5` extends next to `default.json5`. Flavours hold only what is true for every repo that
uses them: repo layouts and release pipelines stay in the repos.

| Flavour | Tools | Lint step | Config |
|---|---|---|---|
| `go` | go, golangci-lint (`just test`) | golangci-lint run + fmt check per module | `.golangci.yml` |
| `container-images` | docker CLI, buildx, hadolint | hadolint on every Dockerfile/Containerfile | `.hadolint.yaml` |
| `helm-charts` | helm 3 + helm-unittest, chart-testing, kubeconform | ct lint, kubeconform on each `charts/<name>/` | `ct.yaml` |
| `python` | `python3.withPackages`, ruff | ruff check + format check | `ruff.toml` |

`helm-charts` needs `nixpkgs_channel` `nixos-26.05`: nixos-unstable ships helm 4.

Add a flavour to an existing project with `copier update --data 'flavours=[go,helm-charts]'`
(list every flavour it should have), then review the diff.

## Renovate preset

Projects extend it rather than copying it:

```json5
{ extends: ["github>Charg/template//renovate/default.json5"] }
```

Renovate has to be able to read this repo: keep it public, or give the Renovate app access to it.
Platform automerge also needs "Allow auto-merge" and squash merges enabled on each repo, plus a
`main` ruleset that requires the `ci` check (the gate job in each `ci.yaml`).
