#!/bin/bash
#
# setup-build-server.sh — Set up the VersatusHPC OpenHPC ppc64le build server
#
# Takes a fresh AlmaLinux 10 ppc64le system and configures it as a build
# server with a dedicated builder user and containerized build environments
# for both EL10 and openEuler 24.03.
#
# Usage: sudo ./setup-build-server.sh
#
# This script is idempotent — safe to re-run at any time.
#

set -euo pipefail

# ── Configuration ────────────────────────────────────────────────────
BUILDER_USER="builder"
BUILDER_HOME="/home/${BUILDER_USER}"
OHPC_REPO="git@github.com:VersatusHPC/ohpc.git"
OHPC_UPSTREAM="https://github.com/openhpc/ohpc.git"
PORTING_BRANCH="versatushpc/4.x"
WORKTREE_DIR="${BUILDER_HOME}/ohpc-versatushpc-4.x"

EL10_IMAGE="el10-ohpc-builder"
OE2403_IMAGE="oe2403-ohpc-builder"
EL10_CONTAINER="el10-builder"
OE2403_CONTAINER="oe-builder"

GPG_KEY_ID="8AA9AD6940E37E91"
GPG_KEY_NAME="VersatusHPC (Repository Signing Key) <support@versatushpc.com.br>"
SSH_KEY="${BUILDER_HOME}/.ssh/id_ed25519_openhpc"

REMOTE_USER="reposync"
REMOTE_HOST="172.21.1.40"

# ── Helpers ──────────────────────────────────────────────────────────
info()  { echo "==> $*"; }
warn()  { echo "WARNING: $*" >&2; }
error() { echo "ERROR: $*" >&2; exit 1; }

run_as_builder() {
    sudo -u "${BUILDER_USER}" -H bash -c "$1"
}

# ── Phase 0: Preflight ──────────────────────────────────────────────
phase_0_preflight() {
    info "Phase 0: Preflight checks"

    [[ $(id -u) -eq 0 ]] || error "Must run as root"
    [[ $(uname -m) == "ppc64le" ]] || error "This script is for ppc64le only"

    if [[ ! -f /etc/os-release ]]; then
        error "Cannot detect OS"
    fi

    # shellcheck disable=SC1091
    . /etc/os-release
    case "${ID}" in
        almalinux|rocky|rhel|centos) ;;
        *) error "Unsupported OS: ${ID}. Expected EL10-compatible." ;;
    esac

    if ! dnf repolist &>/dev/null; then
        error "dnf cannot reach repositories — check internet connectivity"
    fi

    info "OK: ${PRETTY_NAME} on $(uname -m)"
}

# ── Phase 1: Host Packages ──────────────────────────────────────────
phase_1_packages() {
    info "Phase 1: Installing host packages"

    dnf -y install podman git createrepo_c lftp gnupg2 rpm-sign
}

# ── Phase 2: Builder User ───────────────────────────────────────────
phase_2_user() {
    info "Phase 2: Setting up builder user"

    if ! id "${BUILDER_USER}" &>/dev/null; then
        useradd -m -s /bin/bash "${BUILDER_USER}"
        info "Created user ${BUILDER_USER}"
    fi

    if [[ ! -d "${BUILDER_HOME}" ]]; then
        mkhomedir_helper "${BUILDER_USER}"
        info "Created home directory ${BUILDER_HOME}"
    fi

    # Ensure subuid/subgid for rootless podman
    if ! grep -q "^${BUILDER_USER}:" /etc/subuid; then
        usermod --add-subuids 589824-655359 "${BUILDER_USER}"
        info "Added subuid range"
    fi
    if ! grep -q "^${BUILDER_USER}:" /etc/subgid; then
        usermod --add-subgids 589824-655359 "${BUILDER_USER}"
        info "Added subgid range"
    fi

    # Enable linger for persistent containers after logout
    loginctl enable-linger "${BUILDER_USER}" 2>/dev/null || true

    # Create .ssh directory
    if [[ ! -d "${BUILDER_HOME}/.ssh" ]]; then
        install -d -m 700 -o "${BUILDER_USER}" -g "${BUILDER_USER}" "${BUILDER_HOME}/.ssh"
    fi
}

# ── Phase 3: Git Repos ──────────────────────────────────────────────
phase_3_git_repos() {
    info "Phase 3: Setting up git repositories"

    # Check SSH key exists (needed for git clone)
    if [[ ! -f "${SSH_KEY}" ]]; then
        warn "SSH key ${SSH_KEY} not found — git clone may fail"
        warn "Copy the key first or generate a new one"
    fi

    # Configure SSH to use the openhpc key for GitHub
    local ssh_config="${BUILDER_HOME}/.ssh/config"
    if [[ ! -f "${ssh_config}" ]] || ! grep -q "github.com" "${ssh_config}" 2>/dev/null; then
        cat >> "${ssh_config}" <<'EOF'
Host github.com
    IdentityFile ~/.ssh/id_ed25519_openhpc
    StrictHostKeyChecking accept-new
EOF
        chown "${BUILDER_USER}:${BUILDER_USER}" "${ssh_config}"
        chmod 600 "${ssh_config}"
        info "Configured SSH for GitHub"
    fi

    # Clone main repo
    if [[ ! -d "${BUILDER_HOME}/ohpc/.git" ]]; then
        run_as_builder "git clone ${OHPC_REPO} ${BUILDER_HOME}/ohpc"
        run_as_builder "cd ${BUILDER_HOME}/ohpc && git remote add upstream ${OHPC_UPSTREAM} 2>/dev/null || true"
        run_as_builder "cd ${BUILDER_HOME}/ohpc && git fetch --all"
        info "Cloned ohpc repository"
    else
        run_as_builder "cd ${BUILDER_HOME}/ohpc && git fetch --all"
        info "Repository already exists, fetched latest"
    fi

    # Create worktree for porting branch
    if [[ ! -d "${WORKTREE_DIR}" ]]; then
        run_as_builder "cd ${BUILDER_HOME}/ohpc && git worktree add ${WORKTREE_DIR} ${PORTING_BRANCH}"
        info "Created worktree at ${WORKTREE_DIR}"
    else
        info "Worktree already exists at ${WORKTREE_DIR}"
    fi
}

# ── Phase 4: Container Images ───────────────────────────────────────
phase_4_containers() {
    info "Phase 4: Building container images"

    local build_context="${WORKTREE_DIR}"

    # Build EL10 builder image
    if ! run_as_builder "podman image exists ${EL10_IMAGE}"; then
        info "Building ${EL10_IMAGE} image..."
        run_as_builder "cd ${build_context} && podman build -t ${EL10_IMAGE} -f scripts/Containerfile.el10-builder ."
    else
        info "Image ${EL10_IMAGE} already exists"
    fi

    # Build openEuler builder image
    if ! run_as_builder "podman image exists ${OE2403_IMAGE}"; then
        info "Building ${OE2403_IMAGE} image..."
        run_as_builder "cd ${build_context} && podman build -t ${OE2403_IMAGE} -f scripts/Containerfile.oe2403-builder ."
    else
        info "Image ${OE2403_IMAGE} already exists"
    fi

    # Create/recreate EL10 container
    if ! run_as_builder "podman ps --format '{{.Names}}' | grep -q '^${EL10_CONTAINER}$'"; then
        run_as_builder "podman rm -f ${EL10_CONTAINER} 2>/dev/null || true"
        run_as_builder "podman run -d --name ${EL10_CONTAINER} --privileged \
            -v ${WORKTREE_DIR}:/ohpc:Z \
            ${EL10_IMAGE} sleep infinity"
        info "Started container ${EL10_CONTAINER}"
    else
        info "Container ${EL10_CONTAINER} already running"
    fi

    # Create/recreate openEuler container
    if ! run_as_builder "podman ps --format '{{.Names}}' | grep -q '^${OE2403_CONTAINER}$'"; then
        run_as_builder "podman rm -f ${OE2403_CONTAINER} 2>/dev/null || true"
        run_as_builder "podman run -d --name ${OE2403_CONTAINER} --privileged \
            -v ${WORKTREE_DIR}:/ohpc:Z \
            ${OE2403_IMAGE} sleep infinity"
        info "Started container ${OE2403_CONTAINER}"
    else
        info "Container ${OE2403_CONTAINER} already running"
    fi
}

# ── Phase 5: GPG Key Backup ─────────────────────────────────────────
phase_5_gpg_backup() {
    info "Phase 5: GPG key check"

    if run_as_builder "gpg --list-secret-keys ${GPG_KEY_ID} &>/dev/null"; then
        info "GPG signing key present"

        # Offer to back up to TrueNAS
        if [[ -f "${SSH_KEY}" ]]; then
            info "To back up the GPG key to TrueNAS, run as ${BUILDER_USER}:"
            echo "  gpg --export-secret-keys --armor ${GPG_KEY_ID} | \\"
            echo "    gpg --symmetric --cipher-algo AES256 -o /tmp/versatushpc-signing-key.asc.gpg"
            echo "  lftp -e \"set sftp:connect-program 'ssh -l ${REMOTE_USER} -i ${SSH_KEY} -o BatchMode=yes'; \\"
            echo "    open sftp://${REMOTE_HOST}; \\"
            echo "    put /tmp/versatushpc-signing-key.asc.gpg -o /mnt/pool1/backups/versatushpc-signing-key.asc.gpg; bye\""
        fi
    else
        warn "GPG signing key not found. Import it manually:"
        echo "  sudo -u ${BUILDER_USER} gpg --import /path/to/versatushpc-signing-key.asc"
        echo "  sudo -u ${BUILDER_USER} gpg --edit-key ${GPG_KEY_ID} trust  # set to ultimate"
    fi
}

# ── Phase 6: Verify ─────────────────────────────────────────────────
phase_6_verify() {
    info "Phase 6: Verification"

    local ok=true

    # Check builder user
    if id "${BUILDER_USER}" &>/dev/null; then
        echo "  [OK] User ${BUILDER_USER} exists"
    else
        echo "  [FAIL] User ${BUILDER_USER} missing"
        ok=false
    fi

    # Check git repos
    if [[ -d "${BUILDER_HOME}/ohpc/.git" ]]; then
        echo "  [OK] Git repo cloned"
    else
        echo "  [FAIL] Git repo not cloned"
        ok=false
    fi

    if [[ -d "${WORKTREE_DIR}/.git" ]] || [[ -f "${WORKTREE_DIR}/.git" ]]; then
        echo "  [OK] Worktree at ${WORKTREE_DIR}"
    else
        echo "  [FAIL] Worktree missing"
        ok=false
    fi

    # Check containers
    if run_as_builder "podman ps --format '{{.Names}}' | grep -q '^${EL10_CONTAINER}$'" 2>/dev/null; then
        echo "  [OK] Container ${EL10_CONTAINER} running"
    else
        echo "  [FAIL] Container ${EL10_CONTAINER} not running"
        ok=false
    fi

    if run_as_builder "podman ps --format '{{.Names}}' | grep -q '^${OE2403_CONTAINER}$'" 2>/dev/null; then
        echo "  [OK] Container ${OE2403_CONTAINER} running"
    else
        echo "  [FAIL] Container ${OE2403_CONTAINER} not running"
        ok=false
    fi

    # Check SSH key
    if [[ -f "${SSH_KEY}" ]]; then
        echo "  [OK] SSH key present"
    else
        echo "  [MISSING] SSH key — copy or generate id_ed25519_openhpc"
        ok=false
    fi

    # Check GPG key
    if run_as_builder "gpg --list-secret-keys ${GPG_KEY_ID} &>/dev/null" 2>/dev/null; then
        echo "  [OK] GPG signing key present"
    else
        echo "  [MISSING] GPG signing key — import manually"
        ok=false
    fi

    echo ""
    if [[ "${ok}" == "true" ]]; then
        info "All checks passed. Build server is ready."
        echo ""
        echo "  Test with:"
        echo "    sudo -u ${BUILDER_USER} ${WORKTREE_DIR}/scripts/publish-rpms.sh --dry-run"
    else
        info "Some checks failed. See manual steps below."
    fi
}

# ── Print Manual Steps ───────────────────────────────────────────────
print_manual_steps() {
    echo ""
    info "Manual steps (if not already done):"
    echo ""
    echo "  1. SSH key (for GitHub + TrueNAS SFTP):"
    echo "     sudo -u ${BUILDER_USER} ssh-keygen -t ed25519 \\"
    echo "       -f ${SSH_KEY} -N '' -C 'VersatusHPC build key'"
    echo "     # Add public key to:"
    echo "     #   - GitHub: VersatusHPC/ohpc → Settings → Deploy Keys"
    echo "     #   - TrueNAS: reposync@${REMOTE_HOST}:~/.ssh/authorized_keys"
    echo ""
    echo "  2. GPG signing key:"
    echo "     sudo -u ${BUILDER_USER} gpg --import /path/to/versatushpc-signing-key.asc"
    echo ""
    echo "  3. Test the pipeline:"
    echo "     sudo -u ${BUILDER_USER} ${WORKTREE_DIR}/scripts/publish-rpms.sh --dry-run"
    echo ""
}

# ── Main ─────────────────────────────────────────────────────────────
main() {
    info "VersatusHPC OpenHPC ppc64le Build Server Setup"
    echo ""

    phase_0_preflight
    phase_1_packages
    phase_2_user
    phase_3_git_repos
    phase_4_containers
    phase_5_gpg_backup
    phase_6_verify
    print_manual_steps
}

main "$@"
