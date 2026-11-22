# AGENTS.md

The [Copier](https://copier.readthedocs.io/) template every Charg project is generated from, plus
the shared Renovate preset those projects extend. See `README.md` for usage.

## Layout

```
copier.yml               questions, Jinja delimiters, skip/exclude rules
template/                what Copier renders into a project (*.jinja files are templated)
renovate/default.json5   shared Renovate preset; projects extend it, never copy it
renovate/<flavour>.json5 each flavour's Renovate rules, extended next to default.json5
hack/new.sh, update.sh   `just new` / `just update`
hack/test.sh             `just test [variant...]`: renders variants, lints each, checks updates
hack/tools.sh, lint.sh   symlinks into template/hack/: this repo lints itself with the same scripts
.yamllint.yaml, .pre-commit-config.yaml   symlinks into template/, for the same reason
```

## Ground rules

- **The toolchain is the nix flake.** Run everything inside `nix develop`, or one-shot as
  `nix develop -c just <recipe>`. `just` is the only interface; recipes call scripts in `hack/`.
- **Jinja delimiters are `[[ ]]`, `[% %]` and `[# #]`**, not the defaults: GitHub Actions and just
  both use `{{ }}`. Only files ending in `.jinja` are templated. Keep bash `[[ ]]` tests out of
  `.jinja` files, and drop the `.jinja` suffix from any file that needs no variables.
- **Every template change must pass `just test`** (it needs network for nixpkgs on first run) and
  `just lint`. If you add a question, add a variant or assertion for it in `hack/test.sh`.
- **Projects pull changes with `copier update`**, a 3-way merge. Keep shared files easy to merge:
  stable line order, new content in new lines or sections rather than rewrites, and clear places
  for projects to extend (packages list in `flake.nix`, recipes in `justfile`, steps in `lint.sh`).
- In `template/AGENTS.md.jinja`, only the text between the TEMPLATE markers is template-owned;
  `## Project` below it belongs to each project. `README.md` and `CLAUDE.md` are in
  `_skip_if_exists`: rendered once, then owned by the project.
- **Flavours** (`flavours` in `copier.yml`) are toolchain layers. A flavour shows up as
  `[% if 'go' in flavours %]` blocks in shared `.jinja` files and as whole files gated by
  `_exclude` (its config and `hack/lint.d/<flavour>.sh`), plus `renovate/<flavour>.json5`. Keep
  flavours thin: only what holds for every repo using them, no repo layouts or release pipelines.
  Insert flavour blocks mid-file (before the project's usual append point) so they merge cleanly
  into projects that appended their own lines. A new flavour needs a variant and the per-flavour
  cases in `hack/test.sh`, and a line in the CI test matrix.
- Policy that can be referenced rather than copied goes in the Renovate preset
  (`renovate/default.json5`). Changes there reach every project on Renovate's next run with no PR,
  so treat them as a change to every repo at once.

## GitHub Actions

- Workflows start with `permissions: {}` and grant each job only what it needs. Check out with
  `persist-credentials: false`.
- Pin every `uses:` to a full commit SHA with a version comment, in `.github/workflows/` and in
  `template/.github/workflows/` alike.
- After adding or bumping an action, regenerate `.github/workflows/actions.lock` with
  `gh actions-lock --no-narrow`. Without `--no-narrow` it rewrites SHA pins to tags, which zizmor's
  `unpinned-uses` audit rejects.

## Commits

Conventional commits (`feat:`, `fix:`, `chore:`, `ci:`, `docs:`), scoped where it helps
(`feat(template): ...`, `chore(renovate): ...`). Work on a branch and open a PR. Commit only when
asked.
