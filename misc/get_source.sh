#!/bin/bash

if [ $# -ne 1 ]; then
	echo "${0} requires the name of the spec file as parameter."
	exit 1
fi

# If running on Fedora special defines are needed
DISTRO=$(rpm --eval '0%{?fedora}')

if [ "${DISTRO}" != "0" ]; then
	FLAGS=(--undefine fedora --define "rhel 8")
fi

PATTERN=${1}

IFS=$'\n'

cached_source_is_usable() {
	local url=${1}
	local dest=${2}
	local local_size
	local remote_size

	[[ -s ${dest} ]] || return 1
	[[ -z ${OHPC_REFRESH_SOURCES:-} ]] || return 1

	if [[ ${OHPC_VERIFY_SOURCE_CACHE:-1} != "0" ]] && ! cached_source_archive_is_valid "${dest}"; then
		echo "Cached ${dest} failed archive integrity check; refreshing"
		rm -f "${dest}"
		return 1
	fi

	if [[ ${OHPC_VERIFY_SOURCE_SIZE:-0} == "1" && ${url} != *"#"* ]] && command -v curl >/dev/null 2>&1; then
		if remote_size=$(curl -fsSLI --max-time "${OHPC_WGET_TIMEOUT:-120}" "${url}" 2>/dev/null |
			awk 'tolower($1) == "content-length:" { value=$2 } END { gsub("\r", "", value); print value }'); then
			if [[ ${remote_size} =~ ^[0-9]+$ && ${remote_size} -gt 1024 ]]; then
				local_size=$(wc -c < "${dest}" | tr -d '[:space:]')
				if [[ ${local_size} != "${remote_size}" ]]; then
					echo "Cached ${dest} size ${local_size} does not match remote Content-Length ${remote_size}; refreshing"
					rm -f "${dest}"
					return 1
				fi
			fi
		fi
	fi

	return 0
}

cached_source_archive_is_valid() {
	local dest=${1}

	case "${dest}" in
		*.tar.gz | *.tgz | *.gz)
			command -v gzip >/dev/null 2>&1 || return 0
			gzip -t "${dest}" >/dev/null 2>&1
			;;
		*.tar.xz | *.txz | *.xz)
			command -v xz >/dev/null 2>&1 || return 0
			xz -t "${dest}" >/dev/null 2>&1
			;;
		*.tar.bz2 | *.tbz2 | *.bz2)
			command -v bzip2 >/dev/null 2>&1 || return 0
			bzip2 -t "${dest}" >/dev/null 2>&1
			;;
		*.zip)
			command -v unzip >/dev/null 2>&1 || return 0
			unzip -tq "${dest}" >/dev/null 2>&1
			;;
		*.tar)
			# Uncompressed tarballs, plus GitHub "#/"-fragment URLs whose cached
			# name ends in .tar while the body is actually gzip: tar -tf detects
			# and decodes either form, so a .tar that fails to list is corrupt.
			command -v tar >/dev/null 2>&1 || return 0
			tar -tf "${dest}" >/dev/null 2>&1
			;;
		*)
			# Unknown archive type: refuse to vouch for content we cannot inspect.
			# Returning 1 forces a re-download rather than silently trusting a
			# stale/corrupt cached file of the right name. Every Source0 in this
			# tree is .tar.gz/.tar.bz2/.tar.xz/.tar, so this never rejects a real
			# source; it only guards against an unexpected/new extension.
			echo "Cannot verify cached archive of unrecognized type: ${dest}" >&2
			return 1
			;;
	esac
}

find . -name "${PATTERN}" -print0 | while IFS= read -r -d '' file
do
	if [ ! -f "${file}" ]; then
		echo "${file} is not a file. Skipping."
		continue
	fi

	echo "${file}"

	DIR=$(dirname "${file}")
	pushd "${DIR}" > /dev/null || exit 1

	# .../SOURCES/get_source.sh is an optional "plugin" that could build/fetch component's sources on the fly
	if [ -f ../SOURCES/get_source.sh ]; then
		bash ../SOURCES/get_source.sh
	fi

	BASE=$(basename "${file}")

	SOURCES=$(rpmspec --parse --define '_sourcedir ../../..' "${FLAGS[@]}" "${BASE}" | grep Source)
	for u in ${SOURCES}; do
		echo "${u}"
		if [[ "${u}" != *"http"* ]]; then
			continue
		fi
		u=$(awk '{ print $2 }' <<< "${u}")
		echo "Trying to get ${u}"
		dest="../SOURCES/$(basename "${u}")"
		if cached_source_is_usable "${u}" "${dest}"; then
			echo "Using existing ${dest}"
			continue
		fi
		# Try to download only if newer
		if ! WGET=$(wget -N -nv -T "${OHPC_WGET_TIMEOUT:-120}" --tries "${OHPC_WGET_TRIES:-3}" -P ../SOURCES "${u}" 2>&1); then
			echo "${WGET}" >&2
			exit 1
		fi
		# Handling for github URLs with #/ or #$/
		if grep -E "#[$]?/" <<< "${u}"; then
			MV_SOURCE=$(echo "${WGET}" | tail -1 | cut -d\  -f6 | sed -e 's/^"//' -e 's/"$//')
			MV_DEST=../SOURCES/$(basename "${u}")
			mv "${MV_SOURCE}" "${MV_DEST}"
		fi
	done

	popd > /dev/null || exit 1
done
