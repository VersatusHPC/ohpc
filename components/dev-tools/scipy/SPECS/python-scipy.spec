#----------------------------------------------------------------------------bh-
# This RPM .spec file is part of the OpenHPC project.
#
# It may have been modified from the default version supplied by the underlying
# release package (if available) in order to apply patches, perform customized
# build/install configurations, and supply additional files to support
# desired integration conventions.
#
#----------------------------------------------------------------------------eh-

# OpenHPC:check-updates:skip missing dependencies
# scipy build that is dependent on compiler toolchain
%define ohpc_compiler_dependent 1
%define ohpc_mpi_dependent 1
%define ohpc_python_dependent 1
%define _lto_cflags %{nil}
%include %{_sourcedir}/OHPC_macros

%global gnu_family gnu15

%if "%{compiler_family}" != "intel" && "%{compiler_family}" != "arm"
BuildRequires: openblas-%{compiler_family}%{PROJ_DELIM}
Requires: openblas-%{compiler_family}%{PROJ_DELIM}
%endif

# Base package name
%define pname scipy

Name:           %{python_prefix}-%{pname}-%{compiler_family}-%{mpi_family}%{PROJ_DELIM}
Version:        1.14.1
Release:        1%{?dist}
Summary:        Scientific Tools for Python
License:        BSD-3-Clause
Group:          %{PROJ_NAME}/dev-tools
Url:            http://www.scipy.org
Source0:        https://github.com/scipy/scipy/releases/download/v%{version}/%{pname}-%{version}.tar.gz
Source1:        beniget-0.4.2.post1-py3-none-any.whl
Source2:        gast-0.6.0-py3-none-any.whl
Source3:        meson-1.10.2-py3-none-any.whl
Source4:        meson_python-0.19.0-py3-none-any.whl
Source5:        packaging-26.0-py3-none-any.whl
Source6:        ply-3.11-py2.py3-none-any.whl
Source7:        pybind11-3.0.3-py3-none-any.whl
Source8:        pyproject_metadata-0.11.0-py3-none-any.whl
Source9:        pythran-0.18.1-py3-none-any.whl
Source10:       setuptools-82.0.1-py3-none-any.whl
%if 0%{?sle_version}
BuildRequires:  fdupes
%endif
%if "%{compiler_family}" != "arm"
BuildRequires:  fftw-%{compiler_family}-%{mpi_family}%{PROJ_DELIM}
Requires:       fftw-%{compiler_family}-%{mpi_family}%{PROJ_DELIM}
%endif
BuildRequires:  %{python_prefix}-Cython%{PROJ_DELIM}
BuildRequires:  %{python_prefix}-numpy-%{compiler_family}%{PROJ_DELIM}
BuildRequires:  %{python_prefix}-pip
BuildRequires:  ninja-build
Requires:       lmod%{PROJ_DELIM} >= 7.6.1
Requires:       %{python_prefix}-numpy-%{compiler_family}%{PROJ_DELIM}

# Default library install path
%define install_path %{OHPC_LIBS}/%{compiler_family}/%{mpi_family}/%{pname}/%version

#!BuildIgnore: post-build-checks

%description
Scipy is open-source software for mathematics, science, and
engineering. The core library is NumPy which provides convenient and
fast N-dimensional array manipulation. The SciPy library is built to
work with NumPy arrays, and provides many user-friendly and efficient
numerical routines such as routines for numerical integration and
optimization. Together, they run on all popular operating systems, are
quick to install, and are free of charge. NumPy and SciPy are easy to
use, but powerful enough to be depended upon by some of the world's
leading scientists and engineers.

%prep
%setup -q -n %{pname}-%{version}
find . -type f -name "*.py" \
    ! -path "./scipy/_build_utils/_generate_blas_wrapper.py" \
    ! -path "./scipy/_build_utils/echo.py" \
    ! -path "./scipy/_build_utils/tempita.py" \
    ! -path "./scipy/linalg/_generate_pyx.py" \
    ! -path "./scipy/sparse/_generate_sparsetools.py" \
    ! -path "./scipy/special/_generate_pyx.py" \
    ! -path "./tools/generate_f2pymod.py" \
    ! -path "./tools/version_utils.py" \
    -exec sed -i "s|#!/usr/bin/env python3||" {} \;
for helper in \
    scipy/_build_utils/_generate_blas_wrapper.py \
    scipy/_build_utils/echo.py \
    scipy/_build_utils/tempita.py \
    scipy/linalg/_generate_pyx.py \
    scipy/sparse/_generate_sparsetools.py \
    scipy/special/_generate_pyx.py \
    tools/generate_f2pymod.py \
    tools/version_utils.py
do
    test ! -f "${helper}" || chmod +x "${helper}"
done
sed -i "/^f2py = find_program('f2py')/d" scipy/meson.build
sed -i "/^f2py_version = run_command/s|.*|f2py_version = run_command(py3, ['-c', 'import numpy; print(numpy.__version__)'], check: true).stdout().strip()|" scipy/meson.build

%build
# OpenHPC compiler/mpi designation
%ohpc_setup_compiler

SCIPY_BUILD_DEPS=%{_builddir}/scipy-build-deps
rm -rf "${SCIPY_BUILD_DEPS}"
%__python -m pip install --no-index --no-deps --find-links=%{_sourcedir}/pip-wheels \
    --find-links=%{_sourcedir} \
    --prefix="${SCIPY_BUILD_DEPS}" \
    meson-python meson pybind11 pythran packaging pyproject-metadata beniget gast ply setuptools
SCIPY_BUILD_SITE=$(%__python - <<PY
import sysconfig
print(sysconfig.get_path("purelib", vars={"base": "${SCIPY_BUILD_DEPS}", "platbase": "${SCIPY_BUILD_DEPS}"}))
PY
)
export PATH="${SCIPY_BUILD_DEPS}/bin:${PATH}"
export PYTHONPATH="${SCIPY_BUILD_SITE}:${PYTHONPATH}"

%if "%{compiler_family}" != "intel" && "%{compiler_family}" != "arm"
module load openblas
module load fftw
export PKG_CONFIG_PATH="${OPENBLAS_LIB}/pkgconfig:${PKG_CONFIG_PATH}"
%endif

module load %{python_module_prefix}numpy

%if "%{compiler_family}" == "intel"
cat > site.cfg << EOF
[mkl]
library_dirs = $MKLROOT/lib/intel64
include_dirs = $MKLROOT/include
mkl_libs = mkl_rt
lapack_libs =
EOF
%endif

%if "%{compiler_family}" == "arm"
cat > site.cfg << EOF
[openblas]
libraries = armpl
library_dirs = $ARMPL_LIBRARIES
include_dirs = $ARMPL_INCLUDES
EOF
%endif

%if "%{compiler_family}" != "intel" && "%{compiler_family}" != "arm"
cat > site.cfg << EOF
[openblas]
libraries = openblas
library_dirs = $OPENBLAS_LIB
include_dirs = $OPENBLAS_INC
EOF
%endif

%__python -m pip wheel --no-build-isolation --no-deps --wheel-dir=dist .

%install
# OpenHPC compiler/mpi designation
%ohpc_setup_compiler

%if "%{compiler_family}" == "%{gnu_family}"
module load openblas
export CFLAGS="${CFLAGS} -Wno-implicit-int"
export CFLAGS="${CFLAGS} -Wno-incompatible-pointer-types"
%endif

module load %{python_module_prefix}numpy
%__python -m pip install --prefix=%{install_path} --root=%{buildroot} \
    --no-index --find-links=dist --no-deps scipy
find %{buildroot}%{install_path}/lib64/%{python_lib_dir}/site-packages/scipy -type d -name tests | xargs rm -rf # Don't ship tests
# Don't ship weave examples, they're marked as documentation:
find %{buildroot}%{install_path}/lib64/%{python_lib_dir}/site-packages/scipy -path '*/weave/examples' -type d | xargs --no-run-if-empty rm -rf

%if 0%{?sles_version} || 0%{?suse_version}
%fdupes %{buildroot}%{install_path}/lib64/%{python_lib_dir}/site-packages
%endif

# The default python3 binary is too old. This package uses a newer
# version than the default. Let's point the default python3 binary
# to that newer version.
%{__mkdir_p} %{buildroot}/%{install_path}/bin
ln -sn %{__python} %{buildroot}/%{install_path}/bin/%{python_family}

# fix executability issue
test ! -f %{buildroot}%{install_path}/lib64/%{python_lib_dir}/site-packages/%{pname}/io/arff/arffread.py || \
    chmod +x %{buildroot}%{install_path}/lib64/%{python_lib_dir}/site-packages/%{pname}/io/arff/arffread.py
test ! -f %{buildroot}%{install_path}/lib64/%{python_lib_dir}/site-packages/%{pname}/special/spfun_stats.py || \
    chmod +x %{buildroot}%{install_path}/lib64/%{python_lib_dir}/site-packages/%{pname}/special/spfun_stats.py

# OpenHPC module file
%{__mkdir_p} %{buildroot}%{OHPC_MODULEDEPS}/%{compiler_family}-%{mpi_family}/%{python_module_prefix}%{pname}
%{__cat} << EOF > %{buildroot}/%{OHPC_MODULEDEPS}/%{compiler_family}-%{mpi_family}/%{python_module_prefix}%{pname}/%{version}
#%Module1.0#####################################################################

proc ModulesHelp { } {

puts stderr " "
puts stderr "This module loads the %{python3_prefix}-%{pname} library built with the %{compiler_family} compiler"
puts stderr "toolchain and the %{mpi_family} MPI library."
puts stderr "\nVersion %{version}\n"

}
module-whatis "Name: %{python3_prefix}-%{pname} built with %{compiler_family} compiler and %{mpi_family}"
module-whatis "Version: %{version}"
module-whatis "Category: python module"
module-whatis "Description: %{summary}"
module-whatis "URL %{url}"

family                      scipy
set     version             %{version}

prepend-path    PATH                %{install_path}/bin
prepend-path    PYTHONPATH          %{install_path}/lib64/%{python_lib_dir}/site-packages

setenv          %{PNAME}_DIR        %{install_path}

%if "%{compiler_family}" != "arm"
depends-on fftw
%endif
depends-on %{python_module_prefix}numpy

EOF

%{__cat} << EOF > %{buildroot}/%{OHPC_MODULEDEPS}/%{compiler_family}-%{mpi_family}/%{python_module_prefix}%{pname}/.version.%{version}
#%Module1.0#####################################################################
##
## version file for %{pname}-%{version}
##
set     ModulesVersion      "%{version}"
EOF

%{__mkdir_p} ${RPM_BUILD_ROOT}/%{_docdir}

%files
%{OHPC_PUB}
%doc LICENSE.txt
