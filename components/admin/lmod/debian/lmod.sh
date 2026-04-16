# -*- shell-script -*-
########################################################################
#  This is the system wide source file for setting up modules
########################################################################

# NOOP if running under known resource manager
if [ ! -z "$SLURM_NODELIST" ] || [ ! -z "$PBS_NODEFILE" ]; then
     return
fi

export LMOD_SETTARG_CMD=":"
export LMOD_FULL_SETTARG_SUPPORT=no
export LMOD_COLORIZE=no
export LMOD_PREPEND_BLOCK=normal

if [ $EUID -eq 0 ]; then
    export MODULEPATH=/opt/ohpc/admin/modulefiles:/opt/ohpc/pub/modulefiles
else
    export MODULEPATH=/opt/ohpc/pub/modulefiles
fi

# Add : to MANPATH to not drop default search paths
export MANPATH="${MANPATH}:"
export MANPATH=$(/opt/ohpc/admin/lmod/lmod/libexec/addto MANPATH /opt/ohpc/admin/lmod/lmod/share/man)

# Set BASH_ENV for environment
export BASH_ENV=/opt/ohpc/admin/lmod/lmod/init/bash

# Initialize modules system
. /opt/ohpc/admin/lmod/lmod/init/bash >/dev/null

# Load baseline OpenHPC environment
module try-add ohpc
