# OpenHPC shared variables for Debian packaging
#
#-----------------------------------------------------------------------
# Licensed under the Apache License, Version 2.0 (the "License"); you
# may not use this file except in compliance with the License. You may
# obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
# implied. See the License for the specific language governing
# permissions and limitations under the License.
#-----------------------------------------------------------------------
#
# This file is the Debian equivalent of OHPC_macros. Include it in
# every debian/rules file:
#
#   include /path/to/components/OHPC_vars.mk
#
# Or if building inside a container with the repo mounted at /build:
#
#   include /build/components/OHPC_vars.mk

# Top-level OpenHPC installation paths
PROJ_NAME       := ohpc
OHPC_HOME       := /opt/$(PROJ_NAME)
OHPC_ADMIN      := $(OHPC_HOME)/admin
OHPC_PUB        := $(OHPC_HOME)/pub
OHPC_APPS       := $(OHPC_PUB)/apps
OHPC_BIN        := $(OHPC_PUB)/bin
OHPC_COMPILERS  := $(OHPC_PUB)/compiler
OHPC_LIBS       := $(OHPC_PUB)/libs
OHPC_MODULES    := $(OHPC_PUB)/modulefiles
OHPC_MODULEDEPS := $(OHPC_PUB)/moduledeps
OHPC_MPI_STACKS := $(OHPC_PUB)/mpi
OHPC_UTILS      := $(OHPC_PUB)/utils
OHPC_DOCS       := $(OHPC_PUB)/doc/contrib

# Package naming
PROJ_DELIM      := -ohpc

# Default compiler/MPI/Python families (overridable via environment)
COMPILER_FAMILY ?= gnu15
MPI_FAMILY      ?= openmpi5
PYTHON_FAMILY   ?= python3

# Lua version for Ubuntu 24.04
LUAVER          := 5.4

# Python settings for Ubuntu 24.04
PYTHON_PREFIX   := python3
PYTHON_BIN      := /usr/bin/python3
PYTHON_VERSION  := $(shell $(PYTHON_BIN) -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>/dev/null || echo 3.12)
PYTHON_SITE_DIR  = $(shell $(PYTHON_BIN) -c "import sysconfig; print(sysconfig.get_path('platlib'))" 2>/dev/null)

# Uppercase PNAME helper (call with: $(call uc,pname))
uc = $(shell echo '$(1)' | tr '[:lower:]' '[:upper:]' | tr '-' '_')

# Helper to derive PNAME from pname
PNAME = $(call uc,$(pname))

# Architecture from dpkg (available in debian/rules context)
DEB_HOST_ARCH ?= $(shell dpkg-architecture -qDEB_HOST_ARCH 2>/dev/null || echo amd64)
DEB_HOST_MULTIARCH ?= $(shell dpkg-architecture -qDEB_HOST_MULTIARCH 2>/dev/null || echo x86_64-linux-gnu)

# Compiler dependency package name
ifeq ($(COMPILER_FAMILY),gnu15)
  COMPILER_DEP := gnu15-compilers$(PROJ_DELIM) (>= 14.1.0)
  GNU_FAMILY   := gnu15
endif
ifeq ($(COMPILER_FAMILY),gnu14)
  COMPILER_DEP := gnu14-compilers$(PROJ_DELIM) (>= 14.1.0)
  GNU_FAMILY   := gnu14
endif
ifeq ($(COMPILER_FAMILY),gnu13)
  COMPILER_DEP := gnu13-compilers$(PROJ_DELIM) (>= 13.1.0)
  GNU_FAMILY   := gnu13
endif
ifeq ($(COMPILER_FAMILY),gnu12)
  COMPILER_DEP := gnu12-compilers$(PROJ_DELIM) (>= 12.1.0)
  GNU_FAMILY   := gnu12
endif
ifeq ($(COMPILER_FAMILY),gnu9)
  COMPILER_DEP := gnu9-compilers$(PROJ_DELIM) (>= 9.2.0)
  GNU_FAMILY   := gnu9
endif
ifeq ($(COMPILER_FAMILY),intel)
  COMPILER_DEP := g++, intel-compilers-devel$(PROJ_DELIM)
endif
ifeq ($(COMPILER_FAMILY),arm1)
  COMPILER_DEP := arm1-compilers-devel$(PROJ_DELIM)
endif
ifeq ($(COMPILER_FAMILY),llvm)
  COMPILER_DEP := llvm-compilers$(PROJ_DELIM) (>= 9.0.0)
endif

# MPI dependency package name
ifeq ($(MPI_FAMILY),impi)
  MPI_DEP := intel-mpi-devel$(PROJ_DELIM)
endif
ifeq ($(MPI_FAMILY),mpich)
  MPI_DEP := mpich-$(COMPILER_FAMILY)$(PROJ_DELIM)
endif
ifeq ($(MPI_FAMILY),mvapich2)
  MPI_DEP := mvapich2-$(COMPILER_FAMILY)$(PROJ_DELIM)
endif
ifeq ($(MPI_FAMILY),openmpi3)
  MPI_DEP := openmpi3-$(COMPILER_FAMILY)$(PROJ_DELIM)
endif
ifeq ($(MPI_FAMILY),openmpi4)
  MPI_DEP := openmpi4-$(COMPILER_FAMILY)$(PROJ_DELIM)
endif
ifeq ($(MPI_FAMILY),openmpi5)
  MPI_DEP := openmpi5-$(COMPILER_FAMILY)$(PROJ_DELIM)
endif

# Install path helpers
# Independent package: $(call install_path_indep,pname)
install_path_indep = $(OHPC_LIBS)/$(1)

# Compiler-dependent package: $(call install_path_comp,compiler,pname,version)
install_path_comp = $(OHPC_LIBS)/$(1)/$(2)/$(3)

# MPI-dependent package: $(call install_path_mpi,compiler,mpi,pname,version)
install_path_mpi = $(OHPC_LIBS)/$(1)/$(2)/$(3)/$(4)

# Module path helpers
# Independent: $(call module_path_indep,pname)
module_path_indep = $(OHPC_MODULES)/$(1)

# Compiler-dependent: $(call module_path_comp,compiler,pname)
module_path_comp = $(OHPC_MODULEDEPS)/$(1)/$(2)

# MPI-dependent: $(call module_path_mpi,compiler,mpi,pname)
module_path_mpi = $(OHPC_MODULEDEPS)/$(1)-$(2)/$(3)

# Setup compiler/MPI environment (for use in shell commands within rules)
# Usage in debian/rules:
#   override_dh_auto_build:
#       $(OHPC_SETUP_COMPILER) && $(MAKE)
OHPC_SETUP_COMPILER = . $(OHPC_ADMIN)/ohpc/OHPC_setup_compiler $(COMPILER_FAMILY)
OHPC_SETUP_MPI      = . $(OHPC_ADMIN)/ohpc/OHPC_setup_mpi $(MPI_FAMILY)

# Combined setup for MPI-dependent packages
OHPC_SETUP_COMPILER_MPI = $(OHPC_SETUP_COMPILER) && $(OHPC_SETUP_MPI)

# Custom delimiter support (for micro-architecture optimized builds)
ifdef OHPC_CUSTOM_DELIM
  OHPC_CUSTOM_PKG_DELIM := -$(OHPC_CUSTOM_DELIM)
  PROJ_DELIM := -$(OHPC_CUSTOM_DELIM)-ohpc
else
  OHPC_CUSTOM_PKG_DELIM :=
endif

# Common dh overrides that all OHPC packages need.
# Include these in your debian/rules by adding the targets below.
# They are provided as reference — copy them into each debian/rules
# since Make doesn't support inheriting pattern rules from includes.
#
# override_dh_usrlocal:
# 	# OpenHPC installs to /opt/ohpc, not /usr/local
#
# override_dh_shlibdeps:
# 	dh_shlibdeps -l$(INSTALL_PATH)/lib -- --ignore-missing-info || true
#
# override_dh_strip:
# 	dh_strip --no-automatic-dbgsym || true
