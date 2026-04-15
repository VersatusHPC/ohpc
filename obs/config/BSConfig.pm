################################################################################
# OBS Backend Configuration for VersatusHPC
################################################################################

package BSConfig;

use Net::Domain;
use Socket;

my $hostname = $ENV{'OBS_HOSTNAME'} || Net::Domain::hostfqdn() || 'localhost';
my $ip = quotemeta inet_ntoa(inet_aton($hostname) || inet_aton("localhost"));

our $bsdir = '/srv/obs';

our $reporoot  = "$bsdir/repos";
our $srcrepdir = "$bsdir/srcrep";
our $uploaddir = "$bsdir/upload";
our $treesdir  = "$bsdir/trees";

# Scheduler architectures
our @all_schedulers = ('x86_64');

# Source server (bs_srcserver)
our $srcserver = "http://$hostname:5352";

# Repo server (bs_repserver)
our $reposerver = "http://$hostname:5252";

# Service server
our $serviceserver = "http://$hostname:5152";

# Access control
our $ipaccess = {
    '^::1$'          => 'rw',
    '^127\..*'       => 'rw',
    "^$ip\$"         => 'rw',
    '^10\.89\..*'    => 'rw',
    '^10\.88\..*'    => 'rw',
    '.*'             => 'worker',
};

# Disable signing for development
our $sign = undef;

# Download on demand
our $enable_download_on_demand = 1;
our $forceprojectkeys = 0;

1;
