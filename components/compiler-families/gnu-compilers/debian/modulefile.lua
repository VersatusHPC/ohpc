help([[
This module loads the GNU compiler collection

See the man pages for gcc, g++, and gfortran for detailed information
on available compiler options and command-line syntax.

Version 15.2.0
]])

whatis("Name: GNU Compiler Collection")
whatis("Version: 15.2.0")
whatis("Category: compiler, runtime support")
whatis("Description: GNU Compiler Family (C/C++/Fortran for x86_64)")
whatis("URL: https://gcc.gnu.org/")

local version = "15.2.0"

prepend_path("PATH",            "/opt/ohpc/pub/compiler/gcc/15.2.0/bin")
prepend_path("MANPATH",         "/opt/ohpc/pub/compiler/gcc/15.2.0/share/man")
prepend_path("INCLUDE",         "/opt/ohpc/pub/compiler/gcc/15.2.0/include")
prepend_path("LD_LIBRARY_PATH", "/opt/ohpc/pub/compiler/gcc/15.2.0/lib64")
prepend_path("MODULEPATH",      "/opt/ohpc/pub/moduledeps/gnu15")

family("compiler")
