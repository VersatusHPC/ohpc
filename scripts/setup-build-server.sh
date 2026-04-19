#!/bin/bash
#
# setup-build-server.sh - Set up VersatusHPC OpenHPC build/publish servers
#
# This script is idempotent and supports the build roles we operate today:
#
#   ppc64le: RPM build server for EL10/openEuler and native Ubuntu 24.04 ppc64el DEB builder.
#   x86_64:  OBS Debian publisher for Ubuntu 24.04 amd64 packages.
#
# Usage:
#   sudo ./setup-build-server.sh
#
# Optional overrides:
#   SERVER_ROLE=rpm-builder|obs-deb-publisher
#   FETCH_KEYS=auto|never
#

set -euo pipefail

# Configuration
BUILDER_USER="${BUILDER_USER:-builder}"
BUILDER_HOME="${BUILDER_HOME:-/home/${BUILDER_USER}}"
OHPC_REPO="${OHPC_REPO:-git@github.com:VersatusHPC/ohpc.git}"
OHPC_UPSTREAM="${OHPC_UPSTREAM:-https://github.com/openhpc/ohpc.git}"
PORTING_BRANCH="${PORTING_BRANCH:-versatushpc/4.x}"
BASE_BRANCH="${BASE_BRANCH:-upstream-4.x}"
BASE_REF="${BASE_REF:-origin/4.x}"
WORKTREE_DIR="${WORKTREE_DIR:-${BUILDER_HOME}/ohpc-versatushpc-4.x}"

EL10_IMAGE="${EL10_IMAGE:-el10-ohpc-builder}"
OE2403_IMAGE="${OE2403_IMAGE:-oe2403-ohpc-builder}"
EL10_CONTAINER="${EL10_CONTAINER:-el10-builder}"
OE2403_CONTAINER="${OE2403_CONTAINER:-oe-builder}"

UBUNTU_PPC64EL_IMAGE="${UBUNTU_PPC64EL_IMAGE:-ubuntu2404-ppc64el-ohpc-builder}"
UBUNTU_PPC64EL_CONTAINER="${UBUNTU_PPC64EL_CONTAINER:-ubuntu2404-ppc64el-builder}"
UBUNTU_PPC64EL_WORK_ROOT="${UBUNTU_PPC64EL_WORK_ROOT:-${BUILDER_HOME}/ohpc-ubuntu-ppc64el}"

GPG_KEY_ID="${GPG_KEY_ID:-8AA9AD6940E37E91}"
GPG_KEY_NAME="${GPG_KEY_NAME:-VersatusHPC (Repository Signing Key) <support@versatushpc.com.br>}"
SSH_KEY="${SSH_KEY:-${BUILDER_HOME}/.ssh/id_ed25519_openhpc}"

REMOTE_USER="${REMOTE_USER:-reposync}"
REMOTE_HOST="${REMOTE_HOST:-172.21.1.40}"
REMOTE_PATH="${REMOTE_PATH:-/mnt/pool1/repos/openhpc/versatushpc-4}"

KEY_SOURCE_USER="${KEY_SOURCE_USER:-builder}"
KEY_SOURCE_HOST="${KEY_SOURCE_HOST:-power.local.versatushpc.com.br}"
KEY_SOURCE_KEY="${KEY_SOURCE_KEY:-/home/${KEY_SOURCE_USER}/.ssh/id_ed25519_openhpc}"
FETCH_KEYS="${FETCH_KEYS:-auto}"

OBS_CONTAINER="${OBS_CONTAINER:-obs-backend}"
OBS_REPO_PATH="${OBS_REPO_PATH:-/srv/obs/repos/VersatusHPC:/OHPC:/4/Ubuntu_24.04}"

# Helpers
info()  { echo "==> $*"; }
warn()  { echo "WARNING: $*" >&2; }
error() { echo "ERROR: $*" >&2; exit 1; }

run_as_builder() {
    sudo -u "${BUILDER_USER}" -H bash -lc "cd /tmp && $1"
}

run_as_invoker() {
    if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
        sudo -u "${SUDO_USER}" -H "$@"
    else
        "$@"
    fi
}

copy_remote_file() {
    local remote_path="$1"
    local dest="$2"
    local mode="$3"
    local tmpdir tmpfile

    tmpdir="$(mktemp -d)"
    tmpfile="${tmpdir}/$(basename "${remote_path}")"

    if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
        chown "${SUDO_USER}:$(id -gn "${SUDO_USER}")" "${tmpdir}"
    fi

    if run_as_invoker scp -q -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
        "${KEY_SOURCE_USER}@${KEY_SOURCE_HOST}:${remote_path}" "${tmpfile}"; then
        install -m "${mode}" -o "${BUILDER_USER}" -g "${BUILDER_USER}" "${tmpfile}" "${dest}"
        rm -rf "${tmpdir}"
        return 0
    fi

    rm -rf "${tmpdir}"
    return 1
}

remote_gpg_export() {
    run_as_invoker ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
        "${KEY_SOURCE_USER}@${KEY_SOURCE_HOST}" \
        "gpg --batch --armor --export-secret-keys '${GPG_KEY_ID}'"
}

detect_role() {
    ARCH="$(uname -m)"
    if [[ -z "${SERVER_ROLE:-}" ]]; then
        case "${ARCH}" in
            ppc64le) SERVER_ROLE="rpm-builder" ;;
            x86_64)  SERVER_ROLE="obs-deb-publisher" ;;
            *) error "Unsupported architecture: ${ARCH}" ;;
        esac
    fi

    case "${SERVER_ROLE}" in
        rpm-builder|obs-deb-publisher) ;;
        *) error "Unsupported SERVER_ROLE=${SERVER_ROLE}" ;;
    esac
}

# Phase 0: Preflight
phase_0_preflight() {
    info "Phase 0: Preflight checks"

    [[ $(id -u) -eq 0 ]] || error "Must run as root"
    [[ -f /etc/os-release ]] || error "Cannot detect OS"

    # shellcheck disable=SC1091
    . /etc/os-release
    case "${ID}" in
        almalinux|rocky|rhel|centos) ;;
        *) error "Unsupported OS: ${ID}. Expected EL-compatible host." ;;
    esac

    if [[ "${SERVER_ROLE}" == "rpm-builder" && "${ARCH}" != "ppc64le" ]]; then
        error "SERVER_ROLE=rpm-builder must run on ppc64le, not ${ARCH}"
    fi

    if [[ "${SERVER_ROLE}" == "obs-deb-publisher" && "${ARCH}" != "x86_64" ]]; then
        error "SERVER_ROLE=obs-deb-publisher must run on x86_64, not ${ARCH}"
    fi

    if ! dnf repolist &>/dev/null; then
        error "dnf cannot reach repositories; check internet connectivity"
    fi

    info "OK: ${PRETTY_NAME} on ${ARCH} as ${SERVER_ROLE}"
}

# Phase 1: Host Packages
phase_1_packages() {
    info "Phase 1: Installing host packages"

    dnf -y install podman git lftp gnupg2 openssh-clients tar

    if [[ "${SERVER_ROLE}" == "rpm-builder" ]]; then
        dnf -y install createrepo_c rpm-sign
    else
        dnf -y install podman-compose
    fi
}

# Phase 2: Builder User
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

    if ! grep -q "^${BUILDER_USER}:" /etc/subuid; then
        usermod --add-subuids 589824-655359 "${BUILDER_USER}"
        info "Added subuid range"
    fi

    if ! grep -q "^${BUILDER_USER}:" /etc/subgid; then
        usermod --add-subgids 589824-655359 "${BUILDER_USER}"
        info "Added subgid range"
    fi

    loginctl enable-linger "${BUILDER_USER}" 2>/dev/null || true
    install -d -m 700 -o "${BUILDER_USER}" -g "${BUILDER_USER}" "${BUILDER_HOME}/.ssh"
}

phase_2_ssh_key() {
    info "Phase 2b: Checking builder SSH key"

    if [[ -f "${SSH_KEY}" ]]; then
        info "SSH key present: ${SSH_KEY}"
    elif [[ "${FETCH_KEYS}" != "never" ]]; then
        info "Trying to fetch SSH key from ${KEY_SOURCE_USER}@${KEY_SOURCE_HOST}"
        if copy_remote_file "${KEY_SOURCE_KEY}" "${SSH_KEY}" 600; then
            info "Installed ${SSH_KEY}"
        else
            warn "Could not fetch ${KEY_SOURCE_KEY}; install ${SSH_KEY} manually"
        fi
    fi

    if [[ -f "${SSH_KEY}" && ! -f "${SSH_KEY}.pub" ]]; then
        run_as_builder "ssh-keygen -y -f '${SSH_KEY}' > '${SSH_KEY}.pub'"
        chmod 644 "${SSH_KEY}.pub"
        chown "${BUILDER_USER}:${BUILDER_USER}" "${SSH_KEY}.pub"
    elif [[ ! -f "${SSH_KEY}.pub" && "${FETCH_KEYS}" != "never" ]]; then
        copy_remote_file "${KEY_SOURCE_KEY}.pub" "${SSH_KEY}.pub" 644 || true
    fi
}

# Phase 3: Git Repos
phase_3_git_repos() {
    info "Phase 3: Setting up git repositories"

    local ssh_config="${BUILDER_HOME}/.ssh/config"
    if [[ ! -f "${ssh_config}" ]] || ! grep -q "Host github.com" "${ssh_config}" 2>/dev/null; then
        cat >> "${ssh_config}" <<'EOF'
Host github.com
    IdentityFile ~/.ssh/id_ed25519_openhpc
    StrictHostKeyChecking accept-new
EOF
        chown "${BUILDER_USER}:${BUILDER_USER}" "${ssh_config}"
        chmod 600 "${ssh_config}"
        info "Configured SSH for GitHub"
    fi

    if [[ ! -f "${SSH_KEY}" && ! -d "${BUILDER_HOME}/ohpc/.git" ]]; then
        error "Missing ${SSH_KEY}; cannot clone ${OHPC_REPO}"
    fi

    if [[ ! -d "${BUILDER_HOME}/ohpc/.git" ]]; then
        run_as_builder "git clone ${OHPC_REPO} ${BUILDER_HOME}/ohpc"
        info "Cloned ohpc repository"
    fi

    run_as_builder "cd ${BUILDER_HOME}/ohpc && git remote add upstream ${OHPC_UPSTREAM} 2>/dev/null || true"
    run_as_builder "cd ${BUILDER_HOME}/ohpc && git fetch --all"

    # Keep the base clone off the porting branch so the branch can be checked
    # out in the dedicated worktree, even when GitHub's default branch is the
    # porting branch.
    run_as_builder "cd ${BUILDER_HOME}/ohpc && if [[ \$(git branch --show-current) == '${PORTING_BRANCH}' ]]; then git switch -C ${BASE_BRANCH} ${BASE_REF}; fi"

    if [[ ! -e "${WORKTREE_DIR}" ]]; then
        if run_as_builder "cd ${BUILDER_HOME}/ohpc && git show-ref --verify --quiet refs/heads/${PORTING_BRANCH}"; then
            run_as_builder "cd ${BUILDER_HOME}/ohpc && git worktree add ${WORKTREE_DIR} ${PORTING_BRANCH}"
        else
            run_as_builder "cd ${BUILDER_HOME}/ohpc && git worktree add -B ${PORTING_BRANCH} ${WORKTREE_DIR} origin/${PORTING_BRANCH}"
        fi
        info "Created worktree at ${WORKTREE_DIR}"
    else
        run_as_builder "cd ${WORKTREE_DIR} && git pull --ff-only"
        info "Worktree already exists at ${WORKTREE_DIR}"
    fi
}

phase_3_git_signature_verification() {
    local invoker_signers=""

    if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
        invoker_signers="$(eval echo "~${SUDO_USER}")/.config/git/allowed_signers"
    fi

    if [[ -n "${invoker_signers}" && -f "${invoker_signers}" ]]; then
        install -d -m 700 -o "${BUILDER_USER}" -g "${BUILDER_USER}" "${BUILDER_HOME}/.config/git"
        install -m 644 -o "${BUILDER_USER}" -g "${BUILDER_USER}" \
            "${invoker_signers}" "${BUILDER_HOME}/.config/git/allowed_signers"
        run_as_builder "git config --global gpg.ssh.allowedSignersFile ${BUILDER_HOME}/.config/git/allowed_signers"
        info "Configured builder SSH signature verification"
    fi
}

# Phase 4a: ppc64le RPM builder containers
phase_4_rpm_containers() {
    info "Phase 4: Building ppc64le RPM builder containers"

    local build_context="${WORKTREE_DIR}"

    if ! run_as_builder "podman image exists ${EL10_IMAGE}"; then
        info "Building ${EL10_IMAGE} image..."
        run_as_builder "cd ${build_context} && podman build -t ${EL10_IMAGE} -f scripts/Containerfile.el10-builder ."
    else
        info "Image ${EL10_IMAGE} already exists"
    fi

    if ! run_as_builder "podman image exists ${OE2403_IMAGE}"; then
        info "Building ${OE2403_IMAGE} image..."
        run_as_builder "cd ${build_context} && podman build -t ${OE2403_IMAGE} -f scripts/Containerfile.oe2403-builder ."
    else
        info "Image ${OE2403_IMAGE} already exists"
    fi

    if ! run_as_builder "podman ps --format '{{.Names}}' | grep -q '^${EL10_CONTAINER}$'"; then
        run_as_builder "podman rm -f ${EL10_CONTAINER} 2>/dev/null || true"
        run_as_builder "podman run -d --name ${EL10_CONTAINER} --privileged -v ${WORKTREE_DIR}:/ohpc:Z ${EL10_IMAGE} sleep infinity"
        info "Started container ${EL10_CONTAINER}"
    else
        info "Container ${EL10_CONTAINER} already running"
    fi

    if ! run_as_builder "podman ps --format '{{.Names}}' | grep -q '^${OE2403_CONTAINER}$'"; then
        run_as_builder "podman rm -f ${OE2403_CONTAINER} 2>/dev/null || true"
        run_as_builder "podman run -d --name ${OE2403_CONTAINER} --privileged -v ${WORKTREE_DIR}:/ohpc:Z ${OE2403_IMAGE} sleep infinity"
        info "Started container ${OE2403_CONTAINER}"
    else
        info "Container ${OE2403_CONTAINER} already running"
    fi
}

# Phase 4b: native Ubuntu 24.04 ppc64el Debian builder image
phase_4_ubuntu_ppc64el_builder() {
    info "Phase 4b: Building Ubuntu 24.04 ppc64el DEB builder image"

    install -d -m 0755 -o "${BUILDER_USER}" -g "${BUILDER_USER}" "${UBUNTU_PPC64EL_WORK_ROOT}"

    if ! run_as_builder "podman image exists ${UBUNTU_PPC64EL_IMAGE}"; then
        info "Building ${UBUNTU_PPC64EL_IMAGE} image..."
        run_as_builder "cd ${WORKTREE_DIR} && podman build --arch ppc64le -t ${UBUNTU_PPC64EL_IMAGE} -f scripts/Containerfile.ubuntu2404-ppc64el-builder ."
    else
        info "Image ${UBUNTU_PPC64EL_IMAGE} already exists"
    fi

    info "Ubuntu ppc64el builds run with:"
    echo "  sudo -u ${BUILDER_USER} -H bash -lc 'cd ${WORKTREE_DIR} && WORK_ROOT=${UBUNTU_PPC64EL_WORK_ROOT} IMAGE=${UBUNTU_PPC64EL_IMAGE} CONTAINER=${UBUNTU_PPC64EL_CONTAINER} scripts/build-ubuntu-ppc64el.sh --resume --keep-going'"
    echo "  sudo -u ${BUILDER_USER} -H bash -lc 'cd ${WORKTREE_DIR} && WORK_ROOT=${UBUNTU_PPC64EL_WORK_ROOT} scripts/publish-ubuntu-ppc64el.sh --dry-run'"
}

# Phase 4c: x86_64 OBS Debian publisher integration
phase_4_obs_publisher() {
    info "Phase 4: Setting up OBS Debian publisher access"

    local sudoers="/etc/sudoers.d/versatushpc-builder-obs"
    cat > "${sudoers}" <<EOF
# Allow the local builder publisher to read the rootful OBS backend repository.
${BUILDER_USER} ALL=(root) NOPASSWD: /usr/bin/podman exec ${OBS_CONTAINER} *
EOF
    chmod 440 "${sudoers}"
    visudo -cf "${sudoers}" >/dev/null
    info "Installed ${sudoers}"
}

# Phase 5: GPG Key
phase_5_gpg_key() {
    info "Phase 5: GPG signing key check"

    if run_as_builder "gpg --list-secret-keys ${GPG_KEY_ID} &>/dev/null"; then
        info "GPG signing key present"
    elif [[ "${FETCH_KEYS}" != "never" ]]; then
        info "Trying to import GPG signing key from ${KEY_SOURCE_USER}@${KEY_SOURCE_HOST}"
        if remote_gpg_export | sudo -u "${BUILDER_USER}" -H gpg --batch --import; then
            info "Imported GPG signing key"
        else
            warn "Could not import GPG signing key from ${KEY_SOURCE_HOST}"
        fi
    fi

    if ! run_as_builder "gpg --list-secret-keys ${GPG_KEY_ID} &>/dev/null"; then
        warn "GPG signing key not found. Import it manually:"
        echo "  sudo -u ${BUILDER_USER} gpg --import /path/to/versatushpc-signing-key.asc"
        echo "  sudo -u ${BUILDER_USER} gpg --edit-key ${GPG_KEY_ID} trust  # set to ultimate"
    fi

    if [[ -f "${SSH_KEY}" ]]; then
        info "To back up the GPG key to TrueNAS, run as ${BUILDER_USER}:"
        echo "  gpg --export-secret-keys --armor ${GPG_KEY_ID} | \\"
        echo "    gpg --symmetric --cipher-algo AES256 -o /tmp/versatushpc-signing-key.asc.gpg"
        echo "  lftp -e \"set sftp:connect-program 'ssh -l ${REMOTE_USER} -i ${SSH_KEY} -o BatchMode=yes'; \\"
        echo "    open sftp://${REMOTE_HOST}; \\"
        echo "    put /tmp/versatushpc-signing-key.asc.gpg -o /mnt/pool1/backups/versatushpc-signing-key.asc.gpg; bye\""
    fi
}

# Phase 6: Verify
phase_6_verify() {
    info "Phase 6: Verification"

    local ok=true

    if id "${BUILDER_USER}" &>/dev/null; then
        echo "  [OK] User ${BUILDER_USER} exists"
    else
        echo "  [FAIL] User ${BUILDER_USER} missing"
        ok=false
    fi

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

    if [[ -f "${SSH_KEY}" ]]; then
        echo "  [OK] SSH key present"
    else
        echo "  [MISSING] SSH key: ${SSH_KEY}"
        ok=false
    fi

    if run_as_builder "gpg --list-secret-keys ${GPG_KEY_ID} &>/dev/null" 2>/dev/null; then
        echo "  [OK] GPG signing key present"
    else
        echo "  [MISSING] GPG signing key"
        ok=false
    fi

    if run_as_builder "timeout 15s lftp -e \"set net:timeout 5; set net:max-retries 1; set sftp:connect-program 'ssh -l ${REMOTE_USER} -i ${SSH_KEY} -o StrictHostKeyChecking=no -o BatchMode=yes'; open sftp://${REMOTE_HOST}; pwd; bye;\" >/dev/null" 2>/dev/null; then
        echo "  [OK] SFTP publish target reachable"
    else
        echo "  [FAIL] SFTP publish target not reachable"
        ok=false
    fi

    if [[ "${SERVER_ROLE}" == "rpm-builder" ]]; then
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

        if run_as_builder "podman image exists ${UBUNTU_PPC64EL_IMAGE}" 2>/dev/null; then
            echo "  [OK] Image ${UBUNTU_PPC64EL_IMAGE} exists"
        else
            echo "  [FAIL] Image ${UBUNTU_PPC64EL_IMAGE} missing"
            ok=false
        fi

        if [[ -x "${WORKTREE_DIR}/scripts/build-ubuntu-ppc64el.sh" ]]; then
            echo "  [OK] Ubuntu ppc64el build script executable"
        else
            echo "  [FAIL] Ubuntu ppc64el build script missing or not executable"
            ok=false
        fi
    else
        if sudo -u "${BUILDER_USER}" -H sudo -n podman exec "${OBS_CONTAINER}" test -f "${OBS_REPO_PATH}/Release" 2>/dev/null; then
            echo "  [OK] OBS repository readable through ${OBS_CONTAINER}"
        else
            echo "  [FAIL] OBS repository not readable through ${OBS_CONTAINER}"
            ok=false
        fi
    fi

    echo ""
    if [[ "${ok}" == "true" ]]; then
        info "All checks passed. Server is ready."
    else
        info "Some checks failed. See manual steps below."
    fi
}

print_manual_steps() {
    echo ""
    info "Manual steps (if not already done):"
    echo ""
    echo "  1. SSH key (GitHub + TrueNAS SFTP):"
    echo "     sudo -u ${BUILDER_USER} ssh-keygen -t ed25519 \\"
    echo "       -f ${SSH_KEY} -N '' -C 'VersatusHPC build key'"
    echo "     # Add public key to:"
    echo "     #   - GitHub: VersatusHPC/ohpc deploy keys"
    echo "     #   - TrueNAS: ${REMOTE_USER}@${REMOTE_HOST}:~/.ssh/authorized_keys"
    echo ""
    echo "  2. GPG signing key:"
    echo "     sudo -u ${BUILDER_USER} gpg --import /path/to/versatushpc-signing-key.asc"
    echo ""
    echo "  3. Test the pipeline:"
    if [[ "${SERVER_ROLE}" == "rpm-builder" ]]; then
        echo "     sudo -u ${BUILDER_USER} ${WORKTREE_DIR}/scripts/publish-rpms.sh --dry-run"
        echo "     sudo -u ${BUILDER_USER} -H bash -lc 'cd ${WORKTREE_DIR} && WORK_ROOT=${UBUNTU_PPC64EL_WORK_ROOT} scripts/build-ubuntu-ppc64el.sh --resume --keep-going'"
        echo "     sudo -u ${BUILDER_USER} -H bash -lc 'cd ${WORKTREE_DIR} && WORK_ROOT=${UBUNTU_PPC64EL_WORK_ROOT} scripts/publish-ubuntu-ppc64el.sh --dry-run'"
    else
        echo "     sudo -u ${BUILDER_USER} -H bash -lc 'cd ${WORKTREE_DIR} && scripts/publish-debs.sh --dry-run'"
    fi
    echo ""
}

main() {
    detect_role

    info "VersatusHPC OpenHPC server setup"
    echo ""

    phase_0_preflight
    phase_1_packages
    phase_2_user
    phase_2_ssh_key
    phase_3_git_repos
    phase_3_git_signature_verification

    if [[ "${SERVER_ROLE}" == "rpm-builder" ]]; then
        phase_4_rpm_containers
        phase_4_ubuntu_ppc64el_builder
    else
        phase_4_obs_publisher
    fi

    phase_5_gpg_key
    phase_6_verify
    print_manual_steps
}

main "$@"
