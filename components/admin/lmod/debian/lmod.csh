# -*- shell-script -*-
########################################################################
#  This is the system wide source file for setting up modules
########################################################################

if ( $?SLURM_NODELIST ) then
    exit 0
endif

if ( $?PBS_NODEFILE ) then
    exit 0
endif

setenv LMOD_SETTARG_CMD ":"
setenv LMOD_FULL_SETTARG_SUPPORT "no"
setenv LMOD_COLORIZE "no"
setenv LMOD_PREPEND_BLOCK "normal"

if ( `id -u` == "0" ) then
   setenv MODULEPATH "/opt/ohpc/admin/modulefiles:/opt/ohpc/pub/modulefiles"
else
   setenv MODULEPATH "/opt/ohpc/pub/modulefiles"
endif

if ( $?MANPATH ) then
    setenv MANPATH "${MANPATH}:"
else
    setenv MANPATH ":"
endif
setenv MANPATH `/opt/ohpc/admin/lmod/lmod/libexec/addto MANPATH /opt/ohpc/admin/lmod/lmod/share/man`

# Initialize modules system
source /opt/ohpc/admin/lmod/lmod/init/csh >/dev/null

# Load baseline OpenHPC environment
module try-add ohpc
