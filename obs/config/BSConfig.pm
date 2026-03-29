################################################################################
# OBS Backend Configuration for VersatusHPC
################################################################################

our $reporoot = '/srv/obs/repos';
our $srcrepdir = '/srv/obs/srcrep';
our $uploaddir = '/srv/obs/upload';
our $treesdir = '/srv/obs/trees';

our $bsdir = '/srv/obs';

# Scheduler architectures to build for
our @all_schedulers = ('x86_64', 'aarch64');

# Source server
our $srcserver = 'http://backend:5352';

# Repo server
our $reposerver = 'http://backend:5252';

# Disable signing for development (enable in production with GPG key)
our $sign = undef;

# Download on demand (for importing upstream Ubuntu packages)
our $forceprojectkeys = 0;

1;
