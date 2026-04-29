#!/bin/bash
#
# publish-debs.sh - Publish the VersatusHPC OpenHPC Ubuntu repository
#
# Stages the OBS-published Debian repository, signs APT metadata, copies the
# public key and source-list helper, and syncs the result to the mirror server.
#
# Usage:
#   scripts/publish-debs.sh [--dry-run] [--skip-stage] [--promote]
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Local staging settings.
LOCAL_USER="${LOCAL_USER:-builder}"
STAGING_ROOT="${STAGING_ROOT:-/home/${LOCAL_USER}/staging/versatushpc-4}"
STAGING_REPO="${STAGING_ROOT}/Ubuntu_24.04"

# OBS settings. The repository is read through the backend container so this
# works even when the OBS volume path differs across hosts.
OBS_CONTAINER="${OBS_CONTAINER:-obs-backend}"
OBS_REPO_PARENT="${OBS_REPO_PARENT:-/srv/obs/repos/VersatusHPC:/OHPC:/4}"
OBS_REPO_NAME="${OBS_REPO_NAME:-Ubuntu_24.04}"
OBS_REPO_PATH="${OBS_REPO_PARENT}/${OBS_REPO_NAME}"

# Repository signing settings.
GPG_KEY_NAME="${GPG_KEY_NAME:-VersatusHPC (Repository Signing Key) <support@versatushpc.com.br>}"
GPG_PUBLIC_KEY="${GPG_PUBLIC_KEY:-${REPO_ROOT}/RPM-GPG-KEY-VersatusHPC}"
APT_SOURCE_FILE="${APT_SOURCE_FILE:-${SCRIPT_DIR}/repo-files/Ubuntu_24.04/versatushpc-openhpc.list}"
LOCAL_REPO_SCRIPT="${LOCAL_REPO_SCRIPT:-${SCRIPT_DIR}/repo-files/Ubuntu_24.04/make_repo.sh}"
OHPC_VERSION="${OHPC_VERSION:-4.1}"
RELEASE_DIR="${RELEASE_DIR:-update.${OHPC_VERSION}}"
UPDATE_ALIAS="${UPDATE_ALIAS:-updates}"
DIST_DIR="${STAGING_REPO}/dist/${OHPC_VERSION}"
DIST_ARCHIVE="${DIST_ARCHIVE:-OpenHPC-${OHPC_VERSION}.${OBS_REPO_NAME}.x86_64.tar}"
SOURCE_SUBDIR="${SOURCE_SUBDIR:-source}"
MIN_AMD64_DEB_COUNT="${MIN_AMD64_DEB_COUNT:-290}"
MIN_ALL_DEB_COUNT="${MIN_ALL_DEB_COUNT:-21}"
MIN_SOURCE_DEB_COUNT="${MIN_SOURCE_DEB_COUNT:-280}"
MAINTAINER_EMAIL_FROM="${MAINTAINER_EMAIL_FROM:-packages@versatushpc.com.br}"
MAINTAINER_EMAIL_TO="${MAINTAINER_EMAIL_TO:-packages@versatushpc.com.br}"
PROMOTE_SCRIPT="${PROMOTE_SCRIPT:-${SCRIPT_DIR}/promote-update-release.sh}"

# Remote mirror settings.
REMOTE_USER="${REMOTE_USER:-reposync}"
# SFTP publish target used by the existing ppc64le/RPM publisher. The public
# web mirror fronts this content under repos.versatushpc.com.br.
REMOTE_HOST="${REMOTE_HOST:-172.21.1.40}"
REMOTE_PATH="${REMOTE_PATH:-/mnt/pool1/repos/openhpc/versatushpc-4}"
SSH_KEY="${SSH_KEY:-/home/${LOCAL_USER}/.ssh/id_ed25519_openhpc}"

DRY_RUN=""
SKIP_STAGE=""
PROMOTE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN="yes"
            shift
            ;;
        --skip-stage)
            SKIP_STAGE="yes"
            shift
            ;;
        --promote)
            PROMOTE="yes"
            shift
            ;;
        *)
            echo "Usage: $0 [--dry-run] [--skip-stage] [--promote]" >&2
            exit 2
            ;;
    esac
done

require_command() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "Error: required command not found: $1" >&2
        exit 1
    }
}

validate_remote_name() {
    local label="$1"
    local value="$2"

    if [[ ! "${value}" =~ ^[A-Za-z0-9._-]+$ ]]; then
        echo "Error: ${label} must match ^[A-Za-z0-9._-]+$: ${value}" >&2
        exit 2
    fi
}

require_command sudo
require_command podman
require_command tar
require_command xz
require_command xzgrep
require_command zstd
require_command ar
require_command tar
require_command readelf
require_command gpg
require_command ssh
require_command lftp

if [[ ! -f "${GPG_PUBLIC_KEY}" ]]; then
    echo "Error: public repository key not found: ${GPG_PUBLIC_KEY}" >&2
    exit 1
fi

if [[ ! -f "${APT_SOURCE_FILE}" ]]; then
    echo "Error: APT source file not found: ${APT_SOURCE_FILE}" >&2
    exit 1
fi

if [[ ! -f "${LOCAL_REPO_SCRIPT}" ]]; then
    echo "Error: local repository helper not found: ${LOCAL_REPO_SCRIPT}" >&2
    exit 1
fi

if [[ ! -x "${PROMOTE_SCRIPT}" ]]; then
    echo "Error: promotion helper is not executable: ${PROMOTE_SCRIPT}" >&2
    exit 1
fi

if [[ ! -f "${SSH_KEY}" ]]; then
    echo "Error: SSH key not found: ${SSH_KEY}" >&2
    echo "Set SSH_KEY=/path/to/reposync_key or install the mirror publish key." >&2
    exit 1
fi

if ! gpg --list-secret-keys "${GPG_KEY_NAME}" >/dev/null 2>&1; then
    echo "Error: GPG secret key not available: ${GPG_KEY_NAME}" >&2
    echo "Import the VersatusHPC repository signing secret key before publishing." >&2
    exit 1
fi

validate_remote_name "RELEASE_DIR" "${RELEASE_DIR}"
validate_remote_name "UPDATE_ALIAS" "${UPDATE_ALIAS}"
validate_remote_name "OBS_REPO_NAME" "${OBS_REPO_NAME}"

require_deb_count() {
    local label="$1"
    local directory="$2"
    local minimum="$3"
    local count

    if [[ ! -d "${directory}" ]]; then
        echo "Error: ${label} directory missing: ${directory}" >&2
        return 1
    fi

    count="$(find "${directory}" -maxdepth 1 -name '*.deb' | wc -l)"
    if (( count < minimum )); then
        echo "Error: ${label} contains ${count} .deb files; expected at least ${minimum}" >&2
        return 1
    fi
}

require_deb_package_version() {
    local packages_file="$1"
    local package="$2"
    local arch="$3"
    local version_prefix="$4"

    if ! awk -v want_package="${package}" -v want_arch="${arch}" -v want_version="${version_prefix}" '
        BEGIN { RS=""; FS="\n"; found=0 }
        {
            package=""; arch=""; version="";
            for (i = 1; i <= NF; i++) {
                if ($i ~ /^Package: /) package=substr($i, 10);
                if ($i ~ /^Architecture: /) arch=substr($i, 15);
                if ($i ~ /^Version: /) version=substr($i, 10);
            }
            if (package == want_package && arch == want_arch && index(version, want_version) == 1) {
                found=1;
            }
        }
        END { exit(found ? 0 : 1) }
    ' "${packages_file}"; then
        echo "Error: ${package}:${arch} version ${version_prefix}* not found in ${packages_file}" >&2
        return 1
    fi
}

validate_staged_deb_release() {
    local packages_file="${STAGING_REPO}/Packages"
    local source_count
    local stale_list

    if [[ ! -f "${packages_file}" ]]; then
        echo "Error: staged repository is missing Packages metadata: ${packages_file}" >&2
        exit 1
    fi

    stale_list="$(find "${STAGING_REPO}" -name '*.deb' \( \
        -name 'mvapich2-gnu15-ohpc_2.*.deb' -o \
        -name 'mpich-gnu15-ohpc_5.0.0-*.deb' -o \
        -name 'lmod-ohpc_9.0.5-*.deb' -o \
        -name 'ohpc-*_4.0-*.deb' \
    \) -print)"
    stale_list+="$(
        find "${STAGING_REPO}/${SOURCE_SUBDIR}" -maxdepth 1 -type f \( \
            -name 'mvapich2-gnu15-ohpc_2.*' -o \
            -name 'mpich-gnu15-ohpc_5.0.0-*' -o \
            -name 'lmod-ohpc_9.0.5-*' -o \
            -name 'ohpc-meta-packages_4.0-*' \
        \) -print 2>/dev/null
    )"
    if [[ -n "${stale_list}" ]]; then
        echo "Error: stale Debian artifacts found in staging; refusing to publish release artifacts" >&2
        printf '%s\n' "${stale_list}" >&2
        exit 1
    fi
    scan_stale_deb_elf_needed "${STAGING_REPO}" || exit 1

    require_deb_count "amd64 package directory" "${STAGING_REPO}/amd64" "${MIN_AMD64_DEB_COUNT}"
    require_deb_count "all package directory" "${STAGING_REPO}/all" "${MIN_ALL_DEB_COUNT}"

    source_count="$(grep -c '^Package: ' "${STAGING_REPO}/Sources" 2>/dev/null || echo 0)"
    if (( source_count < MIN_SOURCE_DEB_COUNT )); then
        echo "Error: staged source metadata contains ${source_count} packages; expected at least ${MIN_SOURCE_DEB_COUNT}" >&2
        exit 1
    fi

    require_deb_package_version "${packages_file}" ohpc-release all "1:${OHPC_VERSION}"
    require_deb_package_version "${packages_file}" ohpc-filesystem all "${OHPC_VERSION}"
    require_deb_package_version "${packages_file}" gnu15-compilers-ohpc amd64 "15.2.0"
    require_deb_package_version "${packages_file}" lmod-ohpc amd64 "9.2"
    require_deb_package_version "${packages_file}" mpich-gnu15-ohpc amd64 "5.0.1"
    require_deb_package_version "${packages_file}" mvapich2-gnu15-ohpc amd64 "${OHPC_VERSION}"
    require_deb_package_version "${packages_file}" openmpi5-gnu15-ohpc amd64 "5.0.10"
    require_deb_package_version "${packages_file}" ucx-ohpc amd64 "1.20.0"
    require_deb_package_version "${packages_file}" scalapack-gnu15-openmpi5-ohpc amd64 "2.2.3"
    require_deb_package_version "${packages_file}" petsc-gnu15-mpich-ohpc amd64 "3.25.0"
    require_deb_package_version "${packages_file}" petsc-gnu15-openmpi5-ohpc amd64 "3.25.0"
    require_deb_package_version "${packages_file}" slepc-gnu15-mpich-ohpc amd64 "3.25.0"
    require_deb_package_version "${packages_file}" slepc-gnu15-openmpi5-ohpc amd64 "3.25.0"
    require_deb_package_version "${packages_file}" mfem-gnu15-openmpi5-ohpc amd64 "4.9"
    for stack in mpich mvapich2 openmpi5 impi; do
        require_deb_package_version "${packages_file}" "mfem-gnu15-${stack}-ohpc" amd64 "4.9-1ohpc2"
        require_deb_package_version "${packages_file}" "mumps-gnu15-${stack}-ohpc" amd64 "5.8.2-1ohpc2"
        require_deb_package_version "${packages_file}" "mfem-intel-${stack}-ohpc" amd64 "4.9-1ohpc2"
        require_deb_package_version "${packages_file}" "mumps-intel-${stack}-ohpc" amd64 "5.8.2-1ohpc2"
    done
    require_deb_package_version "${packages_file}" r-gnu15-ohpc amd64 "4.5.3"
    require_deb_package_version "${packages_file}" mdtoc-ohpc amd64 "1.4.0"
}

extract_control_tar() {
    local control_archive="$1"
    local target_dir="$2"

    case "${control_archive}" in
        *.tar.zst)
            tar --zstd -xf "${control_archive}" -C "${target_dir}"
            ;;
        *.tar.xz)
            tar -xJf "${control_archive}" -C "${target_dir}"
            ;;
        *.tar.gz)
            tar -xzf "${control_archive}" -C "${target_dir}"
            ;;
        *.tar.bz2)
            tar -xjf "${control_archive}" -C "${target_dir}"
            ;;
        *)
            echo "Error: unsupported Debian control archive: ${control_archive}" >&2
            return 1
            ;;
    esac
}

compress_control_tar() {
    local input_tar="$1"
    local output_archive="$2"

    case "${output_archive}" in
        *.tar.zst)
            zstd -q -19 -f "${input_tar}" -o "${output_archive}"
            ;;
        *.tar.xz)
            xz -c -9 "${input_tar}" > "${output_archive}"
            ;;
        *.tar.gz)
            gzip -n -c -9 "${input_tar}" > "${output_archive}"
            ;;
        *.tar.bz2)
            bzip2 -c -9 "${input_tar}" > "${output_archive}"
            ;;
        *)
            echo "Error: unsupported Debian control archive: ${output_archive}" >&2
            return 1
            ;;
    esac
}

extract_data_tar() {
    local data_archive="$1"
    local target_dir="$2"

    case "${data_archive}" in
        *.tar.zst)
            tar --zstd -xf "${data_archive}" -C "${target_dir}"
            ;;
        *.tar.xz)
            tar -xJf "${data_archive}" -C "${target_dir}"
            ;;
        *.tar.gz)
            tar -xzf "${data_archive}" -C "${target_dir}"
            ;;
        *.tar.bz2)
            tar -xjf "${data_archive}" -C "${target_dir}"
            ;;
        *)
            echo "Error: unsupported Debian data archive: ${data_archive}" >&2
            return 1
            ;;
    esac
}

scan_stale_deb_elf_needed() {
    local repo="$1"
    local tmp_root deb data_member work data_archive elf needed
    local failed=0

    echo "==> Checking staged Debian ELF dependencies for stale PETSc/ScaLAPACK SONAMEs"
    tmp_root="$(mktemp -d)"
    while IFS= read -r deb; do
        data_member="$(ar t "${deb}" | awk '/^data\.tar\./ { print; exit }')"
        if [[ -z "${data_member}" ]]; then
            echo "Error: invalid Debian archive layout: ${deb}" >&2
            rm -rf "${tmp_root}"
            return 1
        fi

        work="$(mktemp -d "${tmp_root}/deb.XXXXXX")"
        data_archive="${work}/${data_member}"
        ar p "${deb}" "${data_member}" > "${data_archive}"
        mkdir -p "${work}/root"
        extract_data_tar "${data_archive}" "${work}/root"

        while IFS= read -r elf; do
            needed="$(readelf -d "${elf}" 2>/dev/null || true)"
            if printf '%s\n' "${needed}" | grep -Eq 'Shared library: \[(libpetsc\.so\.3\.24|libscalapack\.so\.2)\]'; then
                echo "Error: stale ELF dependency in ${deb#"${repo}"/}: ${elf#"${work}/root/"}" >&2
                printf '%s\n' "${needed}" | grep -E 'Shared library: \[(libpetsc\.so\.3\.24|libscalapack\.so\.2)\]' >&2
                failed=1
            fi
        done < <(find "${work}/root/opt/ohpc" -type f \( -perm /111 -o -name '*.so' -o -name '*.so.*' \) -print 2>/dev/null)
        rm -rf "${work}"
    done < <(find "${repo}" -type f -name '*.deb' | sort)
    rm -rf "${tmp_root}"

    if [[ "${failed}" != 0 ]]; then
        echo "Error: stale PETSc/ScaLAPACK ELF dependencies found; refusing to publish release artifacts" >&2
        return 1
    fi
}

normalize_deb_control_metadata() {
    local repo="$1"
    local normalized_debs=0
    local deb tmpdir control_member data_member control_path

    echo "==> Normalizing binary package control metadata"
    while IFS= read -r deb; do
        control_member="$(ar t "${deb}" | awk '/^control\.tar\./ { print; exit }')"
        data_member="$(ar t "${deb}" | awk '/^data\.tar\./ { print; exit }')"
        if [[ -z "${control_member}" || -z "${data_member}" ]]; then
            echo "Error: invalid Debian archive layout: ${deb}" >&2
            return 1
        fi

        tmpdir="$(mktemp -d)"
        ar p "${deb}" debian-binary > "${tmpdir}/debian-binary"
        ar p "${deb}" "${control_member}" > "${tmpdir}/${control_member}"
        mkdir -p "${tmpdir}/control"
        extract_control_tar "${tmpdir}/${control_member}" "${tmpdir}/control"

        control_path="${tmpdir}/control/control"
        if [[ ! -f "${control_path}" ]]; then
            echo "Error: Debian control file missing in ${deb}" >&2
            rm -rf "${tmpdir}"
            return 1
        fi

        if ! grep -Fq "${MAINTAINER_EMAIL_FROM}" "${control_path}"; then
            rm -rf "${tmpdir}"
            continue
        fi

        sed -i "s/${MAINTAINER_EMAIL_FROM}/${MAINTAINER_EMAIL_TO}/g" "${control_path}"
        (cd "${tmpdir}/control" && tar --sort=name --mtime='@0' \
            --owner=0 --group=0 --numeric-owner -cf "${tmpdir}/control.tar" .)
        rm -f "${tmpdir:?}/${control_member}"
        compress_control_tar "${tmpdir}/control.tar" "${tmpdir}/${control_member}"
        ar p "${deb}" "${data_member}" > "${tmpdir}/${data_member}"
        (cd "${tmpdir}" && ar cr "${deb}.tmp" debian-binary "${control_member}" "${data_member}")
        mv -f "${deb}.tmp" "${deb}"
        rm -rf "${tmpdir}"
        normalized_debs=$((normalized_debs + 1))
    done < <(find "${repo}" -type f -name '*.deb' | sort)
    echo "    normalized binary packages: ${normalized_debs}"
}

normalize_packages_metadata() {
    local repo="$1"

    [[ -f "${repo}/Packages" ]] || return 0

    awk -v repo="${repo}" \
        -v from="${MAINTAINER_EMAIL_FROM}" \
        -v to="${MAINTAINER_EMAIL_TO}" '
        function checksum(command, file,    output, parts) {
            command = command " \"" repo "/" file "\""
            command | getline output
            close(command)
            split(output, parts, /[[:space:]]+/)
            return parts[1]
        }
        function size(file,    command, output) {
            command = "stat -c %s \"" repo "/" file "\""
            command | getline output
            close(command)
            return output
        }
        /^Filename:/ {
            filename = $2
            print
            next
        }
        /^Maintainer:/ {
            gsub(from, to)
            print
            next
        }
        /^Size:/ && filename != "" {
            printf "Size: %s\n", size(filename)
            next
        }
        /^MD5sum:/ && filename != "" {
            printf "MD5sum: %s\n", checksum("md5sum", filename)
            next
        }
        /^SHA1:/ && filename != "" {
            printf "SHA1: %s\n", checksum("sha1sum", filename)
            next
        }
        /^SHA256:/ && filename != "" {
            printf "SHA256: %s\n", checksum("sha256sum", filename)
            next
        }
        /^$/ {
            filename = ""
            print
            next
        }
        { print }
    ' "${repo}/Packages" > "${repo}/Packages.tmp"
    mv "${repo}/Packages.tmp" "${repo}/Packages"
}


normalize_source_metadata() {
    local repo="$1"
    local source_dir="$2"

    [[ -f "${repo}/Sources" ]] || return 0

    echo "==> Moving Debian source artifacts into ${source_dir}/"
    (
        cd "${repo}"
        mkdir -p "${source_dir}"

        awk '
            /^[[:space:]][0-9A-Fa-f]+[[:space:]]+[0-9]+[[:space:]]+[^[:space:]]+$/ {
                file = $3
                if (file ~ /\.(dsc|tar\.(gz|xz|bz2)|orig\.tar\.(gz|xz|bz2)|debian\.tar\.(gz|xz|bz2)|diff\.gz)$/) {
                    print file
                }
            }
        ' Sources | sort -u > .source-files

        while IFS= read -r file; do
            [[ -n "${file}" && -f "${file}" ]] || continue
            mv -f "${file}" "${source_dir}/${file}"
        done < .source-files
        rm -f .source-files

        # OBS also leaves importer-side .tar.gz files in the published tree.
        # They are not referenced by Sources or .dsc, so keep them private.
        find . -maxdepth 1 -type f \( \
            -name '*.dsc' -o \
            -name '*.tar.gz' -o \
            -name '*.tar.xz' -o \
            -name '*.tar.bz2' -o \
            -name '*.orig.tar.*' -o \
            -name '*.debian.tar.*' -o \
            -name '*.diff.gz' \
        \) -delete

        local normalized_archives=0
        while IFS= read -r archive; do
            if ! xzgrep -a -F -q "${MAINTAINER_EMAIL_FROM}" "${archive}"; then
                continue
            fi

            tmpdir="$(mktemp -d)"
            tar -xJf "${archive}" -C "${tmpdir}"
            match_file="${tmpdir}/.email-matches"
            grep -Rsl "${MAINTAINER_EMAIL_FROM}" "${tmpdir}" > "${match_file}" || true
            if [[ -s "${match_file}" ]]; then
                xargs -r sed -i "s/${MAINTAINER_EMAIL_FROM}/${MAINTAINER_EMAIL_TO}/g" < "${match_file}"
            fi
            rm -f "${match_file}"
            mapfile -t archive_entries < <(find "${tmpdir}" -mindepth 1 -maxdepth 1 \
                -printf '%f\n' | sort)
            tar -C "${tmpdir}" -cJf "${archive}.tmp" "${archive_entries[@]}"
            mv -f "${archive}.tmp" "${archive}"
            rm -rf "${tmpdir}"
            normalized_archives=$((normalized_archives + 1))
        done < <(find "${source_dir}" -maxdepth 1 -type f -name '*.tar.xz' | sort)
        echo "    normalized source archives: ${normalized_archives}"

        find "${source_dir}" -maxdepth 1 -type f -name '*.dsc' \
            -exec sed -i "s/${MAINTAINER_EMAIL_FROM}/${MAINTAINER_EMAIL_TO}/g" {} +

        for dsc in "${source_dir}"/*.dsc; do
            [[ -f "${dsc}" ]] || continue
            awk -v dir="${source_dir}" '
                function checksum(command, file,    output, parts) {
                    command = command " \"" dir "/" file "\""
                    command | getline output
                    close(command)
                    split(output, parts, /[[:space:]]+/)
                    return parts[1]
                }
                function size(file,    command, output) {
                    command = "stat -c %s \"" dir "/" file "\""
                    command | getline output
                    close(command)
                    return output
                }
                /^Files:/ {
                    section = "Files"
                    print
                    next
                }
                /^Checksums-Sha1:/ {
                    section = "Checksums-Sha1"
                    print
                    next
                }
                /^Checksums-Sha256:/ {
                    section = "Checksums-Sha256"
                    print
                    next
                }
                /^[^[:space:]]/ {
                    section = ""
                }
                /^[[:space:]][0-9A-Fa-f]+[[:space:]]+[0-9]+[[:space:]]+[^[:space:]]+$/ {
                    file = $3
                    file_size = size(file)
                    if (section == "Files") {
                        printf " %s %s %s\n", checksum("md5sum", file), file_size, file
                    } else if (section == "Checksums-Sha1") {
                        printf " %s %s %s\n", checksum("sha1sum", file), file_size, file
                    } else if (section == "Checksums-Sha256") {
                        printf " %s %s %s\n", checksum("sha256sum", file), file_size, file
                    } else {
                        print
                    }
                    next
                }
                { print }
            ' "${dsc}" > "${dsc}.tmp"
            mv "${dsc}.tmp" "${dsc}"
        done

        awk -v dir="${source_dir}" \
            -v from="${MAINTAINER_EMAIL_FROM}" \
            -v to="${MAINTAINER_EMAIL_TO}" '
            function checksum(command, file,    output, parts) {
                command = command " \"" dir "/" file "\""
                command | getline output
                close(command)
                split(output, parts, /[[:space:]]+/)
                return parts[1]
            }
            function size(file,    command, output) {
                command = "stat -c %s \"" dir "/" file "\""
                command | getline output
                close(command)
                return output
            }
            /^Maintainer:/ {
                gsub(from, to)
                print
                next
            }
            /^Directory:/ {
                print "Directory: " dir
                next
            }
            /^Files:/ {
                section = "Files"
                print
                next
            }
            /^Checksums-Sha1:/ {
                section = "Checksums-Sha1"
                print
                next
            }
            /^Checksums-Sha256:/ {
                section = "Checksums-Sha256"
                print
                next
            }
            /^[^[:space:]]/ {
                section = ""
            }
            /^[[:space:]][0-9A-Fa-f]+[[:space:]]+[0-9]+[[:space:]]+[^[:space:]]+$/ {
                file = $3
                file_size = size(file)
                if (section == "Files") {
                    printf " %s %s %s\n", checksum("md5sum", file), file_size, file
                } else if (section == "Checksums-Sha1") {
                    printf " %s %s %s\n", checksum("sha1sum", file), file_size, file
                } else if (section == "Checksums-Sha256") {
                    printf " %s %s %s\n", checksum("sha256sum", file), file_size, file
                } else {
                    print
                }
                next
            }
            { print }
        ' Sources > Sources.tmp
        mv Sources.tmp Sources
    )
}

if [[ -z "${SKIP_STAGE}" ]]; then
    echo "==> Staging OBS Debian repository from ${OBS_CONTAINER}:${OBS_REPO_PATH}"
    rm -rf "${STAGING_REPO}"
    mkdir -p "${STAGING_ROOT}"

    sudo podman exec "${OBS_CONTAINER}" test -f "${OBS_REPO_PATH}/Release"
    sudo podman exec "${OBS_CONTAINER}" test -f "${OBS_REPO_PATH}/Packages.gz"
    sudo podman exec "${OBS_CONTAINER}" bash -lc \
        "find '${OBS_REPO_PATH}' -type f -name '*.deb' | grep -q ."

    sudo podman exec "${OBS_CONTAINER}" tar -C "${OBS_REPO_PARENT}" -cf - "${OBS_REPO_NAME}" \
        | tar -C "${STAGING_ROOT}" -xf -
else
    echo "==> Reusing existing staged repository: ${STAGING_REPO}"
fi

if [[ ! -f "${STAGING_REPO}/Release" ]]; then
    echo "Error: staged repository does not contain Release: ${STAGING_REPO}" >&2
    exit 1
fi

echo "==> Installing public key and APT source helper into staging"
cp "${GPG_PUBLIC_KEY}" "${STAGING_ROOT}/RPM-GPG-KEY-VersatusHPC"
cp "${GPG_PUBLIC_KEY}" "${STAGING_REPO}/RPM-GPG-KEY-VersatusHPC"
rm -f "${STAGING_ROOT}"/versatushpc*.gpg
gpg --dearmor --yes --output "${STAGING_ROOT}/versatushpc.gpg" "${GPG_PUBLIC_KEY}"
cp "${STAGING_ROOT}/versatushpc.gpg" "${STAGING_REPO}/versatushpc.gpg"
cp "${APT_SOURCE_FILE}" "${STAGING_REPO}/versatushpc-openhpc.list"
cp "${LOCAL_REPO_SCRIPT}" "${STAGING_REPO}/make_repo.sh"
chmod 0755 "${STAGING_REPO}/make_repo.sh"

normalize_deb_control_metadata "${STAGING_REPO}"
normalize_packages_metadata "${STAGING_REPO}"
normalize_source_metadata "${STAGING_REPO}" "${SOURCE_SUBDIR}"
rm -f "${STAGING_REPO}/Packages.gz" "${STAGING_REPO}/Sources.gz"

validate_staged_deb_release

echo "==> Adding xz-compressed APT indexes"
(
    cd "${STAGING_REPO}"
    xz -c -9 Packages > Packages.xz
    if [[ -f Sources ]]; then
        xz -c -9 Sources > Sources.xz
    fi

    tmp_release="$(mktemp)"
    awk '/^(MD5Sum|SHA1|SHA256):/ { skip=1; next } skip && /^[[:space:]]/ { next } { skip=0; print }' \
        Release > "${tmp_release}"

    index_files=(Packages Packages.xz)
    if [[ -f Sources ]]; then
        index_files+=(Sources)
    fi
    if [[ -f Sources.xz ]]; then
        index_files+=(Sources.xz)
    fi

    {
        cat "${tmp_release}"
        echo "MD5Sum:"
        for f in "${index_files[@]}"; do
            printf " %s %16d %s\n" "$(md5sum "${f}" | awk '{print $1}')" "$(stat -c %s "${f}")" "${f}"
        done
        echo "SHA1:"
        for f in "${index_files[@]}"; do
            printf " %s %16d %s\n" "$(sha1sum "${f}" | awk '{print $1}')" "$(stat -c %s "${f}")" "${f}"
        done
        echo "SHA256:"
        for f in "${index_files[@]}"; do
            printf " %s %16d %s\n" "$(sha256sum "${f}" | awk '{print $1}')" "$(stat -c %s "${f}")" "${f}"
        done
    } > Release
    rm -f "${tmp_release}"
)

echo "==> Signing APT Release metadata with: ${GPG_KEY_NAME}"
(
    cd "${STAGING_REPO}"
    rm -f InRelease Release.gpg
    gpg --batch --yes --local-user "${GPG_KEY_NAME}" \
        --digest-algo SHA256 --clearsign --output InRelease Release
    gpg --batch --yes --local-user "${GPG_KEY_NAME}" \
        --digest-algo SHA256 --armor --detach-sign --output Release.gpg Release
)

echo "==> Creating local repository tarball"
mkdir -p "${DIST_DIR}"
rm -f "${DIST_DIR}/${DIST_ARCHIVE}"
tar -C "${STAGING_ROOT}" --exclude="${OBS_REPO_NAME}/dist" -cf "${DIST_DIR}/${DIST_ARCHIVE}" \
    "${OBS_REPO_NAME}" RPM-GPG-KEY-VersatusHPC versatushpc.gpg

REMOTE_RELEASE_PATH="${REMOTE_PATH}/${RELEASE_DIR}"
if [[ -n "${DRY_RUN}" ]]; then
    LFTP_COMMANDS="
cls -la ${REMOTE_PATH};
"
    echo "*** DRY RUN - no files will be transferred ***"
else
    LFTP_COMMANDS="
cd ${REMOTE_PATH};
mkdir -pf ${RELEASE_DIR}/${OBS_REPO_NAME};
mirror --reverse --delete --verbose \
    ${STAGING_REPO}/ ${RELEASE_DIR}/${OBS_REPO_NAME}/;
rm -f versatushpc*.gpg;
put -O . ${STAGING_ROOT}/RPM-GPG-KEY-VersatusHPC;
put -O . ${STAGING_ROOT}/versatushpc.gpg;
mkdir -pf ${RELEASE_DIR}/${OBS_REPO_NAME}/dist/${OHPC_VERSION};
mirror --reverse --delete --verbose \
    ${DIST_DIR}/ ${RELEASE_DIR}/${OBS_REPO_NAME}/dist/${OHPC_VERSION}/;
"
fi

echo "==> Syncing to ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_RELEASE_PATH} via SFTP"
lftp -e "
set cmd:fail-exit yes;
set sftp:connect-program 'ssh -l ${REMOTE_USER} -i ${SSH_KEY} -o StrictHostKeyChecking=no -o BatchMode=yes';
open sftp://${REMOTE_HOST};
${LFTP_COMMANDS}
bye;
"

if [[ -n "${PROMOTE}" ]]; then
    promote_args=()
    if [[ -n "${DRY_RUN}" ]]; then
        promote_args+=(--dry-run)
    fi
    OHPC_VERSION="${OHPC_VERSION}" \
    RELEASE_DIR="${RELEASE_DIR}" \
    UPDATE_ALIAS="${UPDATE_ALIAS}" \
    REMOTE_USER="${REMOTE_USER}" \
    REMOTE_HOST="${REMOTE_HOST}" \
    REMOTE_PATH="${REMOTE_PATH}" \
    SSH_KEY="${SSH_KEY}" \
        "${PROMOTE_SCRIPT}" "${promote_args[@]}"
fi

echo ""
echo "==> Done. Debian repository summary:"
echo "    Staged repository: ${STAGING_REPO}"
echo "    Release tree:      sftp://${REMOTE_USER}@${REMOTE_HOST}${REMOTE_RELEASE_PATH}/${OBS_REPO_NAME}/"
echo "    Updates alias:     ${UPDATE_ALIAS} -> ${RELEASE_DIR} (run with --promote after the full matrix is present)"
echo "    Total size:        $(du -sh "${STAGING_REPO}" | awk '{print $1}')"
echo "    .deb packages:     $(find "${STAGING_REPO}" -type f -name '*.deb' | wc -l)"
echo "    amd64 packages:    $(find "${STAGING_REPO}/amd64" -type f -name '*.deb' 2>/dev/null | wc -l)"
echo "    all packages:      $(find "${STAGING_REPO}/all" -type f -name '*.deb' 2>/dev/null | wc -l)"
echo "    source packages:   $(grep -c '^Package: ' "${STAGING_REPO}/Sources" 2>/dev/null || echo 0)"
echo "    source artifacts:  $(find "${STAGING_REPO}/${SOURCE_SUBDIR}" -maxdepth 1 -type f 2>/dev/null | wc -l)"
echo "    Metadata:          Release InRelease Release.gpg Packages Packages.xz Sources Sources.xz"
echo "    Local mirror tar:  ${DIST_DIR}/${DIST_ARCHIVE}"
echo ""
echo "    Users enable the repo with:"
echo "      curl -fsSLO https://repos.versatushpc.com.br/openhpc/versatushpc-4/${UPDATE_ALIAS}/Ubuntu_24.04/all/ohpc-release_4.1-1ohpc1~noble_all.deb"
echo "      sudo apt -y install ./ohpc-release_4.1-1ohpc1~noble_all.deb"
echo "      sudo apt update"
