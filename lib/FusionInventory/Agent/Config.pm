package FusionInventory::Agent::Config;

use strict;
use warnings;

use Getopt::Long;
use English qw(-no_match_vars);

my $basedir = '';

if ($OSNAME eq 'MSWin32') {
    $basedir = $ENV{APPDATA}.'/fusioninventory-agent';
}

my $default = {
    'ca-cert-dir'             => '',
    'ca-cert-file'            => '',
    'conf-file'               => '',
    'color'                   => 0,
    'daemon'                  => 0,
    'daemon-no-fork'          => 0,
    'debug'                   => 0,
    'devlib'                  => 0,
    'disable-perllib-envvar'  => 0,
    'force'                   => 0,
    'help'                    => 0,
    'html'                    => 0,
    'html-dir'                => '',
    'info'                    => 1,
    'lazy'                    => 0,
    'local'                   => '',
#   'logger'                  => 'Syslog,File,Stderr',
    'logger'                  => 'Stderr',
    'logfile'                 => '',
    'logfacility'             => 'LOG_USER',
    'password'                => '',
    'proxy'                   => '',
    'realm'                   => '',
    'remotedir'               => '/ocsinventory', # deprecated
    'server'                  => '',
    'stdout'                  => 0,
    'tag'                     => '',
    'user'                    => '',
    'version'                 => 0,
    'wait'                    => '',
#   'xml'                     => 0,
    'no-ocsdeploy'            => 0,
    'no-inventory'            => 0,
    'nosoft'                  => 0, # deprecated
    'no-printer'              => 0,
    'no-socket'               => 0,
    'no-software'             => 0,
    'no-wakeonlan'            => 0,
    'no-snmpquery'            => 0,
    'no-netdiscovery'         => 0,
    'delaytime'               => 3600, # max delay time (seconds)
    'backend-collect-timeout' => 180,   # timeOut of process : see Backend.pm
    'no-ssl-check'            => 0,
    'scan-homedirs'           => 0,
    # Other values that can't be changed with the
    # CLI parameters
    'basevardir'              =>  $basedir.'/var/lib/fusioninventory-agent',
    'logdir'                  =>  $basedir.'/var/log/fusioninventory-agent',
#   'pidfile'                 =>  $basedir.'/var/run/ocsinventory-agent.pid',
};

sub load {
    my (undef, $params) = @_;

    my $config = $default;
    $config->{VERSION} = $FusionInventory::Agent::VERSION;

    if ($OSNAME eq 'MSWin32') {
        loadFromWinRegistry($config);
    } else {
        loadFromCfgFile($config);
    }

    loadUserParams($config);
    return $config;
}

sub loadFromWinRegistry {
    my $config = shift;

    eval {
        require Encode;
        Encode->import('encode');
        require Win32::TieRegistry;
        Win32::TieRegistry->import(
            Delimiter   => "/",
            ArrayValues => 0
        );
    };
    if ($EVAL_ERROR) {
        print "[error] $EVAL_ERROR";
        return;
    }

    my $machKey = $Win32::TieRegistry::Registry->Open( "LMachine", {Access=>Win32::TieRegistry::KEY_READ(),Delimiter=>"/"} );
    my $settings = $machKey->{"SOFTWARE/FusionInventory-Agent"};

    foreach my $rawKey (keys %$settings) {
        next unless $rawKey =~ /^\/(\S+)/;
        my $key = $1;
        my $val = $settings->{$rawKey};
        # Remove the quotes
        $val =~ s/\s+$//;
        $val =~ s/^'(.*)'$/$1/;
        $val =~ s/^"(.*)"$/$1/;
        $config->{lc($key)} = $val;
    }
}

sub loadFromCfgFile {
    my $config = shift;

    $config->{etcdir} = [];

    my $file;

    my $in;
    foreach (@ARGV) {
        if (!$in && /^--conf-file=(.*)/) {
            $file = $1;
            $file =~ s/'(.*)'/$1/;
            $file =~ s/"(.*)"/$1/;
        } elsif (/^--conf-file$/) {
            $in = 1;
        } elsif ($in) {
            $file = $_;
            $in = 0;
        } else {
            $in = 0;
        }
    }

    push (@{$config->{etcdir}}, '/etc/fusioninventory');
    push (@{$config->{etcdir}}, '/usr/local/etc/fusioninventory');
#  push (@{$config->{etcdir}}, $ENV{HOME}.'/.ocsinventory'); # Should I?

    if (!$file || !-f $file) {
        foreach (@{$config->{etcdir}}) {
            $file = $_.'/agent.cfg';
            last if -f $file;
        }
        return $config unless -f $file;
    }

    my $handle;
    if (!open $handle, '<', $file) {
        warn "Config: Failed to open $file: $ERRNO";
        return $config;
    }

    $config->{'conf-file'} = $file;

    while (<$handle>) {
        s/#.+//;
        if (/([\w-]+)\s*=\s*(.+)/) {
            my $key = $1;
            my $val = $2;
            # Remove the quotes
            $val =~ s/\s+$//;
            $val =~ s/^'(.*)'$/$1/;
            $val =~ s/^"(.*)"$/$1/;
            $config->{$key} = $val;
        }
    }
    close $handle;
}

sub loadUserParams {
    my $config = shift;

    Getopt::Long::Configure( "no_ignorecase" );

    GetOptions(
        $config,
        'backend-collect-timeout=s',
        'basevardir=s',
        'ca-cert-dir=s',
        'ca-cert-file=s',
        'conf-file=s',
        'color',
        'daemon|d',
        'daemon-no-fork|D',
        'debug',
        'delaytime=s',
        'devlib',
        'disable-perllib-envvar',
        'force|f',
        'help|h',
        'html',
        'html-dir=s',
        'info|i',
        'lazy',
        'local|l=s',
        'logfile=s',
        'no-ocsdeploy',
        'no-inventory',
        'no-printer',
        'no-socket',
        'no-soft',
        'no-software',
        'no-ssl-check',
        'no-wakeonlan',
        'no-snmpquery',
        'no-netdiscovery',
        'password|p=s',
        'perl-bin-dir-in-path',
        'proxy|P=s',
        'realm|r=s',
        'rpc-ip=s',
        'rpc-trust-localhost',
        'remotedir|R=s',
        'scan-homedirs',
        'server|s=s',
        'stdout',
        'tag|t=s',
        'user|u=s',
        'version',
        'wait|w=s',
    ) or help($config);

    help($config) if $config->{help};
    version() if $config->{version};
}

sub help {
    my ($config, $error) = @_;
    if ($error) {
        chomp $error;
        print "ERROR: $error\n\n";
    }

    if ($config->{'conf-file'}) {
        print STDERR "Setting initialised with values retrieved from ".
        "the config found at ".$config->{'conf-file'}."\n";
    }

    print STDERR <<EOF;

Common options:
    --debug             debug mode ($config->{debug})
    --html              save in HTML the inventory requested by --local ($config->{html})
    -l --local=DIR      do not contact server but write inventory in DIR directory in XML ($config->{local})
    --logfile=FILE      log message in FILE ($config->{logfile})
    --version           print the version


Network options:
    -p --password=PWD   password for server auth
    -P --proxy=PROXY    proxy address. e.g: http://user:pass\@proxy:port ($config->{proxy})
    -r --realm=REALM    realm for server HTTP auth. e.g: 'Restricted Area' ($config->{realm})
    -s --server=uri     server uri, e.g: http://server/ocsinventory ($config->{server})
    -u --user           user name to use for server auth

SSL options:
    --ca-cert-dir=D     SSL certificat directory ($config->{'ca-cert-dir'})
    --ca-cert-file=F    SSL certificat file ($config->{'ca-cert-file'})

Disable options:
    --no-ocsdeploy      Do not deploy packages or run command ($config->{'no-ocsdeploy'})
    --no-inventory      Do not generate inventory ($config->{'no-inventory'})
    --no-printer        do not return printer list in inventory $config->{'no-printer'})
    --no-socket         don't allow remote connexion ($config->{'no-socket'})
    --no-software       do not return installed software list ($config->{'no-software'})
    --no-ssl-check      do not check the SSL connexion with the server ($config->{'no-ssl-check'})
    --no-wakeonlan      do not use wakeonlan function ($config->{'no-wakeonlan'})
    --no-snmpquery      do not use snmpquery function ($config->{'no-snmpquery'})
    --no-netdiscovery   do not use snmpquery function ($config->{'no-netdiscovery'})

Extra options:
    --backend-collect-timeout set a max delay time of one inventory data collect job ($config->{'backend-collect-timeout'})
    --basevardir=/path  indicate the directory where should the agent store its files ($config->{basevardir})
    --color             use color in the console ($config->{color})
    -d --daemon         detach the agent in background ($config->{daemon})
    -D --daemon-no-fork daemon but don't fork in background ($config->{'daemon-no-fork'})
    --delaytime         set a max delay time (in second) if no PROLOG_FREQ is set ($config->{delaytime})
    --devlib            search for Backend mod in ./lib only ($config->{devlib})
    --disable-perllib-envvar    do not load Perl lib from PERL5LIB and PERLIB environment variable ($config->{'disable-perllib-envvar'})
    -f --force          always send data to server (Don't ask before) ($config->{force})
    --html-dir          alternative directory where the static HTML are stored
    -i --info           verbose mode ($config->{info})
    --lazy              do not contact the server more than one time during the PROLOG_FREQ ($config->{lazy})
    --rpc-ip=IP         ip of the interface to use for peer to peer exchange
    --rpc-trust-localhost      allow local users to http://127.0.0.1:62354/now to force an inventory
    --scan-homedirs     permit to scan home user directories ($config->{'scan-homedirs'})
    --stdout            do not write or post the inventory but print it on STDOUT
    -t --tag=TAG        use TAG as tag ($config->{tag}) Will be ignored by server if a value already exists.
    -w --wait=DURATION  wait during a random periode between 0 and DURATION seconds before contacting server ($config->{wait})

Manpage:
    See man fusioninventory-agent

FusionInventory-Agent is released under GNU GPL 2 license
EOF

    exit 1;
}

sub version {
    print "FusionInventory Agent (".$FusionInventory::Agent::VERSION.")\n";
    exit 0;
}

1;
