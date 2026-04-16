# VersatusHPC OpenHPC ppc64le Port

## Branch model

- `4.x` — upstream reference branch for release-integration work. Do not commit here directly.
- `versatushpc/4.x` — our fork with ppc64le patches. All work goes here.
- Upstream remote push is disabled (`PUSH_DISABLED_TO_PREVENT_ACCIDENTS`). NEVER push to upstream.

## Build approach

- No gcc-toolset or SCL. Only native EL10 system packages + OpenHPC's own compiler ecosystem.
- Build chain: system GCC bootstraps OpenHPC GCC (gnu15) → `module load gnu15` → all packages built against OpenHPC compilers.
- Builds run on a local ppc64le server under the `builder` user (uid 3000), containerized (Containerfile.el10-builder, Containerfile.oe2403-builder).
- Compiler flags: `-mcpu=power9 -mtune=power9` (set in `components/OHPC_setup_compiler`).

## CI/CD

- GitHub Action `.github/workflows/upstream-release-sync.yml` runs daily:
  - Watches upstream `v4.*.GA` release tags
  - Ignores normal upstream commits between releases
  - Fails with a change summary when a new upstream release is not yet merged into `versatushpc/4.x`
- Merges are never automatic — ~19 patched spec files will conflict on upstream updates.
- OBS does not work for ppc64le. Do not suggest it.

## RPM publishing

- RPMs published to `repos.versatushpc.com.br/openhpc/versatushpc-4/` via SFTP (lftp).
- SSH key: `id_ed25519_openhpc`. GPG key ID: `8AA9AD6940E37E91`.
- Publish script: `scripts/publish-rpms.sh`.

## Directory layout (build server)

- `/home/builder/ohpc` — main clone (tracks upstream `4.x`)
- `/home/builder/ohpc-versatushpc-4.x` — worktree for `versatushpc/4.x`
- Use `ohpc-` prefix for any new directories under `/home/builder/`.
