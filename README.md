# distrobox-typesetting

Automates building a [distrobox](https://distrobox.it/) container pre-loaded with a
typesetting and music-engraving toolchain:

- [TeX Live](https://tug.org/texlive/) — installed under `/opt/texlive` via the official TUG
  network installer.
- [LilyPond](https://lilypond.org/) — installed under `/opt/lilypond`, preferring the official
  precompiled binary on x86_64 glibc systems and building from source everywhere else
  (including musl/Alpine, where a binary isn't offered).
- [Gregorio](https://gregorio-project.github.io/) — built from source from
  [lbssousa/gregorio](https://github.com/lbssousa/gregorio) and wired into TeX Live
  (`gregoriotex`), independently of TeX Live's own package manager.
- [Inkscape](https://inkscape.org/), [svg2tikz](https://github.com/xyz2tex/svg2tikz),
  [Neovim](https://neovim.io/), [Zathura](https://pwmt.org/projects/zathura/),
  [Starship](https://starship.rs/) (shell prompt).

TeX Live's bundled fonts are registered with fontconfig at build time, so LilyPond, Inkscape,
and any other fontconfig-aware tool in the container can use them.

## Prerequisites

- [distrobox](https://distrobox.it/) installed on the host.
- Podman or Docker installed on the host (used to build the container image; distrobox itself
  then creates the container from that image).

## Usage

```sh
cp typesetting.env.example typesetting.env   # optional, edit as needed
./distrobox-typesetting
distrobox enter typesetting
```

Configuration is resolved in this order (later wins): built-in defaults →
`typesetting.env` (current directory, then this project's directory) → CLI flags. Run
`./distrobox-typesetting --help` for the full flag list. Options:

| Option | Config key | CLI flag | Default |
|---|---|---|---|
| Base image | `BASE_IMAGE` | `--base-image` | `alpine:latest` |
| TeX Live release | `TEXLIVE_RELEASE` | `--texlive-release` | `latest` |
| TeX Live scheme | `TEXLIVE_SCHEME` | `--texlive-scheme` | `minimal`\* |
| Extra TeX Live packages | `TEXLIVE_PACKAGES` | `--texlive-packages` | see below\* |
| TeX Live mirror | `TEXLIVE_MIRROR` | `--texlive-mirror` | `https://linorg.usp.br` |
| LilyPond version | `LILYPOND_VERSION` | `--lilypond-version` | `2.26.0` |
| Gregorio ref (lbssousa/gregorio) | `GREGORIO_REF` | `--gregorio-ref` | `playground-2026-08-27` |
| Container name | `CONTAINER_NAME` | `--name` | `typesetting` |
| Container engine | `ENGINE` | `--engine` | `auto` (podman, fallback docker) |

\* Temporarily trimmed down from a `full` scheme while iterating on the build (a full scheme
rebuild is slow to iterate on). The default `TEXLIVE_PACKAGES` (and the default
`TEXLIVE_MIRROR`) come from
[AISCGre-BR/Eugene-Cardine-Primeiro-Ano-de-Semiologia-Gregoriana](https://github.com/AISCGre-BR/Eugene-Cardine-Primeiro-Ano-de-Semiologia-Gregoriana)'s
`.devcontainer/devcontainer.json`, plus the individual packages MusiXTeX needs
(`musixtex`, `musixtex-fonts`). Revert `TEXLIVE_SCHEME` to `full` (and clear `TEXLIVE_PACKAGES`)
once the rest of the pipeline is stable.

Example, building on Debian with a minimal TeX Live scheme plus a couple of extra packages:

```sh
./distrobox-typesetting \
    --base-image debian:bookworm-slim \
    --texlive-scheme minimal \
    --texlive-packages "latexmk biber"
```

Re-running the script rebuilds the `distrobox-typesetting:local` image but does **not**
recreate an already-existing container with the same name. To pick up a rebuilt image, remove
the old container first (`distrobox rm <name>`) and re-run the script.

## TeX Live download cache

Installing a large TeX Live scheme (e.g. `full`) downloads several GB, and the build can die
half-way if the connection to the mirror drops. To avoid starting over, the build keeps every
TeX Live package it downloads in a persistent build cache (`RUN --mount=type=cache`, which
survives failed builds), so simply re-running `./distrobox-typesetting` reuses what was already
fetched and only downloads the rest. Downloads are also retried and resumed automatically.
The cache is keyed by each package's checksum, so it stays valid across mirrors (you can switch
`--texlive-mirror` between attempts) and never serves outdated packages: an updated package is
downloaded again. Entries unused for 30 days are pruned after a successful install, and the
build log ends with a summary line such as
`TeX Live download cache: 3120 reused, 415 downloaded`.

This needs podman, or docker with BuildKit (the default since docker 23). To wipe the cache
manually: with podman, `podman unshare rm -rf /var/tmp/buildah-cache-$(id -u)` (that folder is
shared by all podman build caches); with docker, `docker builder prune`.

## Updating an existing container

These helpers are installed inside the container (`/usr/local/bin`) and self-elevate with
`sudo` when needed:

- `update-texlive` — runs `tlmgr update --self --all`.
- `update-system` — upgrades OS packages via the container's native package manager
  (`apk`/`apt`/`dnf`).
- `update-lilypond <version>` — rebuilds LilyPond at the given version, reusing the same
  install logic used at image build time.
- `update-gregorio [ref]` — rebuilds Gregorio from `lbssousa/gregorio` at the given ref
  (defaults to `playground-2026-08-27`).

## Project layout

- `Containerfile` — the parameterized image build recipe.
- `distrobox-typesetting` — the CLI script that builds the image and creates the container.
- `typesetting.env.example` — configuration template (copy to `typesetting.env`, gitignored).
- `scripts/` — one install script per component, plus `scripts/lib/common.sh` with shared
  OS-detection and package-manager helpers and `scripts/lib/texlive-cached-download.sh`, the
  caching/retrying downloader used by `install-texlive.sh`. Kept inside the built image at
  `/opt/distrobox-typesetting/scripts/` so the `update-*` helpers can reuse them.
- `container-bin/` — the `update-*` helper scripts, copied into the image's `/usr/local/bin`.

The TeX Live, LilyPond, and Gregorio install scripts are adapted from
[aiscgre-br/devcontainer-features](https://github.com/aiscgre-br/devcontainer-features).

## Known limitations

- svg2tikz's Inkscape GUI extension registration is best-effort: it depends on the pip
  package still bundling `.inx`/`.py` extension files at a discoverable path. If registration
  is skipped, the `svg2tikz` CLI command is still installed and usable directly.
- Starship is wired up via `/etc/profile.d/starship.sh`, which only login shells read. If
  `distrobox enter` (or your terminal) starts a non-login shell and the prompt doesn't appear,
  add `eval "$(starship init bash)"` (or `zsh`) to your own `~/.bashrc`/`~/.zshrc`.
