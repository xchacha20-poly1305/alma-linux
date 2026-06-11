# Agent Guidelines

This file applies to the whole repository.

## Repository Purpose

This repository repackages upstream Alma Linux releases. The normal pipeline is:

1. Fetch upstream `latest-linux.yml`.
2. Download and checksum the upstream amd64 DEB.
3. Run `scripts/extract-deb.sh` to create `extracted/`.
4. Run `scripts/apply-patches.sh` against the extracted Alma app.
5. Run `scripts/determine-electron.sh`.
6. Run `scripts/build-packages.sh <version> <electron-major>`.
7. Run `scripts/generate-latest-yml.sh` for release metadata.

Prefer proving changes against the real upstream DEB whenever the failure came from an upstream bundle change. Synthetic fixtures are useful guardrails, but they do not replace a real `app.asar` preflight.

## Generated Files

- Treat `extracted/`, `dist/`, downloaded `*.deb` files, `latest-linux.yml`, temporary logs, and ad hoc `app.asar` extraction directories as generated local state.
- Do not commit generated package artifacts unless the user explicitly asks.
- `scripts/extract-deb.sh` deletes and recreates `extracted/`; that is expected for local verification.

## Patch Pipeline Rules

- Keep all maintained upstream app mutations in `scripts/patches/NNN-*.sh` and run them through `scripts/apply-patches.sh`.
- `app.asar` patches are in-place byte edits. Preserve byte-for-byte replacement length unless you deliberately change the archive handling strategy.
- Do not repack `app.asar` casually. Repacking can lose or alter unpacked-file metadata and offsets.
- Upstream Alma ships minified JavaScript. Do not key patches on one release's minified variable names. Match stable semantics and capture aliases by regex where needed.
- Patch scripts must detect all of these states explicitly: unpatched, already patched, duplicate marker, and partial patch.
- Keep patch scripts idempotent. A second run against the same extracted app must skip cleanly.
- When replacement text contains JavaScript syntax that is meaningful to Perl or the shell, pass it through environment variables and Perl `BEGIN` variables instead of fragile inline quoting.

## Inspecting `app.asar`

- The real target after extraction is `extracted/data/$(cat extracted/APP_PATH)/resources/app.asar`.
- For compiled Electron app inspection, extract once with `asar extract` into a temp directory and inspect `out/main/index.js`.
- Do not load the whole `app.asar` into a Node or Perl string as UTF-8 for broad inspection. Use `perl -0ne`, `grep -abo`, or small byte windows around known markers.
- Avoid grepping the whole archive blindly when the issue is known to live in the main process bundle.

## Packaging Rules

- The supported packager is `nfpm`; do not reintroduce `fpm`.
- CI installs `nfpm` and generic archive tools. It does not need `rpm` or `makepkg` for package creation.
- Standalone outputs are RPM, Pacman, and DEB.
- System Electron outputs are RPM and Pacman only. Do not add a system-Electron DEB unless the packaging model is intentionally redesigned.
- System packages must not assume a random system Electron is acceptable. `metadata/alma-wrapper.sh` must only run an Electron executable whose `--version` reports the required major version.
- For Arch packages with `nfpm`, keep explicit top-level `contents` entries. Do not map the entire tree to `dst: /`.

## Reproducibility

- Normalize timestamps after all content mutations, including patching and generated system-package content.
- Prefer `SOURCE_DATE_EPOCH` from the upstream release date in CI. Locally, `scripts/build-packages.sh` falls back to `git log -1 --format=%ct`.
- If using a fixed timestamp only for validation, label it as validation-only. Do not document it as the production default.

## Verification

Use the narrowest command that proves the changed behavior, then broaden only when the change affects the package pipeline.

Common checks:

```bash
bash scripts/test-patches.sh
./scripts/extract-deb.sh ./alma-<version>-linux-amd64.deb
./scripts/apply-patches.sh "extracted/data/$(cat extracted/APP_PATH)"
./scripts/apply-patches.sh "extracted/data/$(cat extracted/APP_PATH)"
./scripts/determine-electron.sh
SOURCE_DATE_EPOCH=<release-epoch> ./scripts/build-packages.sh <version> <electron-major>
./scripts/generate-latest-yml.sh <version> <release-date> <owner> <repo> "<notes>"
git diff --check
```

For patch drift fixes, at minimum run:

1. `bash scripts/test-patches.sh`
2. `./scripts/extract-deb.sh <real-upstream.deb>`
3. `./scripts/apply-patches.sh "extracted/data/$(cat extracted/APP_PATH)"`
4. The same `apply-patches.sh` command a second time to prove idempotence

Run the full package build when the change touches `scripts/build-packages.sh`, `metadata/alma-wrapper.sh`, `.github/workflows/package.yml`, package metadata, or any patch used by production builds.

## Documentation

- Keep `README.md` and `README_zh.md` aligned when user-visible package behavior changes.
- Release notes in `.github/workflows/package.yml` describe package variants, auto-update behavior, and the Activity Recorder default. Update them when those contracts change.

## Known Fragile Areas

- Activity Recorder defaults are patched at build time so first-run Linux installs do not immediately start recording.
- Auto-update support depends on resolving `app-update.yml` from the packaged app directory, not blindly from `process.resourcesPath`, because system Electron launches point `process.resourcesPath` at Electron's own resources directory.
- Upstream minified bundle drift is expected. Treat missing marker counts as a real compatibility signal, then inspect the current bundle before editing the patch.
