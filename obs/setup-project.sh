#!/bin/bash
# Setup the VersatusHPC OBS project after the server is running.
#
# Prerequisites:
#   - OBS running at http://localhost:3000
#   - osc (OBS command line) installed
#   - First login done via web UI
#
# Usage: bash obs/setup-project.sh

set -e

OBS_API="https://localhost:3000"
OBS_USER="admin"
OBS_PASS="opensuse"

# Configure osc
mkdir -p ~/.config/osc
cat > ~/.config/osc/oscrc << EOF
[general]
apiurl = $OBS_API

[$OBS_API]
user = $OBS_USER
pass = $OBS_PASS
credentials_mgr_class=osc.credentials.PlaintextConfigFileCredentialsManager
sslcertck = 0
EOF

echo "=== Creating project VersatusHPC:OHPC:4 ==="
osc api -X PUT "/source/VersatusHPC:OHPC:4/_meta" -d '
<project name="VersatusHPC:OHPC:4">
  <title>OpenHPC 4.x for Ubuntu</title>
  <description>
    VersatusHPC port of OpenHPC to Ubuntu 24.04 LTS (noble).
    Native Debian packaging with full compiler x MPI matrix.
  </description>
  <repository name="Ubuntu_24.04">
    <path project="Ubuntu:24.04" repository="universe"/>
    <arch>x86_64</arch>
    <arch>aarch64</arch>
  </repository>
</project>'

echo "=== Setting project config ==="
osc api -X PUT "/source/VersatusHPC:OHPC:4/_config" -d '
# VersatusHPC OpenHPC 4.x Project Configuration
# This is the Debian build configuration for OBS

Macros:
%_vendor versatushpc

# Disable dpkg hardening flags (OHPC sets its own via OHPC_setup_compiler)
Optflags: x86_64 -O0
Optflags: aarch64 -O0

# Build order hints
Prefer: ohpc-filesystem ohpc-buildroot lmod-ohpc
Prefer: gnu15-compilers-ohpc
'

echo "=== Project created ==="
echo "Next steps:"
echo "  1. Import Ubuntu 24.04 as download-on-demand repository"
echo "  2. Upload packages using obs/import-packages.sh"
echo "  3. Trigger builds"
