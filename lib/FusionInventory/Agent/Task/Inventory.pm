package FusionInventory::Agent::Task::Inventory;

use strict;
use warnings;

use parent 'FusionInventory::Agent::Task';

use Config;
use English qw(-no_match_vars);
use UNIVERSAL::require;

use FusionInventory::Agent::Tools;
use FusionInventory::Device::Computer;

use FusionInventory::Agent::Task::Inventory::Version;

# Preload Module base class
use FusionInventory::Agent::Task::Inventory::Module;

our $VERSION = FusionInventory::Agent::Task::Inventory::Version::VERSION;

sub run {
    my ($self, %params) = @_;

    if ( $REAL_USER_ID != 0 ) {
        $self->{logger}->warning(
            "You should execute this task as super-user"
        );
    }

    $self->{modules} = {};

    my $computer = FusionInventory::Device::Computer->new(
        deviceid => $self->{deviceid},
        logger   => $self->{logger},
        tag      => $self->{config}->{'tag'}
    );

    # Set inventory as remote if running remote inventory like from wmi task
    $computer->setRemote($self->getRemote()) if $self->getRemote();

    if (not $ENV{PATH}) {
        # set a minimal PATH if none is set (#1129, #1747)
        $ENV{PATH} =
            '/sbin:/usr/sbin:/usr/local/sbin:/bin:/usr/bin:/usr/local/bin';
        $self->{logger}->debug(
            "PATH is not set, using $ENV{PATH} as default"
        );
    }


    $self->_initModulesList($params{categories});
    $self->_feedInventory($computer, $params{categories});
    return unless $self->_validateInventory($computer);

    binmode STDOUT, ':encoding(UTF-8)';
    print $computer->as_xml();
}

# Method to override if inventory needs to be validate
sub _validateInventory { 1 }

sub _initModulesList {
    my ($self, $categories) = @_;

    my $logger = $self->{logger};
    my $config = $self->{config};

    my @modules = $self->getModules('Inventory');
    die "no inventory module found\n" if !@modules;

    # Select isEnabled function to test
    my $isEnabledFunction = "isEnabled" ;
    $isEnabledFunction .= "ForRemote" if $self->getRemote();

    # first pass: compute all relevant modules
    foreach my $module (sort @modules) {
        # compute parent module:
        my @components = split('::', $module);
        my $parent = @components > 5 ?
            join('::', @components[0 .. $#components -1]) : '';

        # Just skip Version package as not an inventory package module
        # Also skip Module as not a real module but the base class for any module
        if ($module =~ /FusionInventory::Agent::Task::Inventory::(Version|Module)$/) {
            $self->{modules}->{$module}->{enabled} = 0;
            next;
        }

        # skip if parent is not allowed
        if ($parent && !$self->{modules}->{$parent}->{enabled}) {
            $logger->debug2("  $module disabled: implicit dependency $parent not enabled");
            $self->{modules}->{$module}->{enabled} = 0;
            next;
        }

        $module->require();
        if ($EVAL_ERROR) {
            $logger->debug("module $module disabled: failure to load ($EVAL_ERROR)");
            $self->{modules}->{$module}->{enabled} = 0;
            next;
        }

        # Simulate tested function inheritance as we test a module, not a class
        unless (defined(*{$module."::".$isEnabledFunction})) {
            no strict 'refs'; ## no critic (ProhibitNoStrict)
            *{$module."::".$isEnabledFunction} =
                \&{"FusionInventory::Agent::Task::Inventory::Module::$isEnabledFunction"};
        }

        my $enabled = runFunction(
            module   => $module,
            function => $isEnabledFunction,
            logger   => $logger,
            timeout  => $config->{'backend-collect-timeout'},
            params   => {
                category      => $categories,
                datadir       => $self->{datadir},
                logger        => $self->{logger},
                registry      => $self->{registry},
                scan_homedirs => $self->{config}->{'scan-homedirs'},
                scan_profiles => $self->{config}->{'scan-profiles'},
            }
        );
        if (!$enabled) {
            $logger->debug2("module $module disabled");
            $self->{modules}->{$module}->{enabled} = 0;
            next;
        }

        $self->{modules}->{$module}->{enabled} = 1;
        $self->{modules}->{$module}->{done}    = 0;
        $self->{modules}->{$module}->{used}    = 0;

        no strict 'refs'; ## no critic (ProhibitNoStrict)
        $self->{modules}->{$module}->{runAfter} = [
            $parent ? $parent : (),
            ${$module . '::runAfter'} ? @${$module . '::runAfter'} : (),
            ${$module . '::runAfterIfEnabled'} ? @${$module . '::runAfterIfEnabled'} : ()
        ];
        $self->{modules}->{$module}->{runAfterIfEnabled} = {
            map { $_ => 1 }
                ${$module . '::runAfterIfEnabled'} ? @${$module . '::runAfterIfEnabled'} : ()
        };
    }

    # second pass: disable fallback modules
    foreach my $module (@modules) {
        ## no critic (ProhibitProlongedStrictureOverride)
        no strict 'refs'; ## no critic (ProhibitNoStrict)

        # skip modules already disabled
        next unless $self->{modules}->{$module}->{enabled};
        # skip non-fallback modules
        next unless ${$module . '::runMeIfTheseChecksFailed'};

        my $failed;

        foreach my $other_module (@${$module . '::runMeIfTheseChecksFailed'}) {
            if ($self->{modules}->{$other_module}->{enabled}) {
                $failed = $other_module;
                last;
            }
        }

        if ($failed) {
            $self->{modules}->{$module}->{enabled} = 0;
            $logger->debug("module $module disabled because of $failed");
        }
    }
}

sub _runModule {
    my ($self, $module, $inventory, $categories) = @_;

    my $logger = $self->{logger};

    return if $self->{modules}->{$module}->{done};

    $self->{modules}->{$module}->{used} = 1; # lock the module

    # ensure all needed modules have been executed first
    foreach my $other_module (@{$self->{modules}->{$module}->{runAfter}}) {
        die "module $other_module, needed before $module, not found"
            if !$self->{modules}->{$other_module};

        if (!$self->{modules}->{$other_module}->{enabled}) {
            if ($self->{modules}->{$module}->{runAfterIfEnabled}->{$other_module}) {
                # soft dependency: run current module without required one
                next;
            } else {
                # hard dependency: abort current module execution
                die "module $other_module, needed before $module, not enabled";
            }
        }

        die "circular dependency between $module and $other_module"
            if $self->{modules}->{$other_module}->{used};

        $self->_runModule($other_module, $inventory, $categories);
    }

    $logger->debug("Running $module");

    runFunction(
        module   => $module,
        function => "doInventory",
        logger   => $logger,
        timeout  => $self->{config}->{'backend-collect-timeout'},
        params   => {
            datadir       => $self->{datadir},
            inventory     => $inventory,
            category      => $categories,
            logger        => $self->{logger},
            registry      => $self->{registry},
            scan_homedirs => $self->{config}->{'scan-homedirs'},
            scan_profiles => $self->{config}->{'scan-profiles'},
        }
    );
    $self->{modules}->{$module}->{done} = 1;
    $self->{modules}->{$module}->{used} = 0; # unlock the module
}

sub _feedInventory {
    my ($self, $inventory, $disabled) = @_;

    my $begin = time();
    my @modules =
        grep { $self->{modules}->{$_}->{enabled} }
        keys %{$self->{modules}};

    foreach my $module (sort @modules) {
        $self->_runModule($module, $inventory, $disabled);
    }

    if ($self->{config}->{'additional-content'} && -f $self->{config}->{'additional-content'}) {
        $self->_injectContent($self->{config}->{'additional-content'}, $inventory)
    }

    # Execution time
    $inventory->setHardware({ETIME => time() - $begin});
}

sub _injectContent {
    my ($self, $file, $inventory) = @_;

    return unless -f $file;

    $self->{logger}->debug(
        "importing $file file content to the inventory"
    );

    my $content;
    SWITCH: {
        if ($file =~ /\.xml$/) {
            eval {
                my $tree = XML::TreePP->new()->parsefile($file);
                $content = $tree->{REQUEST}->{CONTENT};
            };
            last SWITCH;
        }
        die "unknown file type $file";
    }

    if (!$content) {
        $self->{logger}->error("no suitable content found");
        return;
    }

    $inventory->mergeContent($content);
}

1;
__END__

=head1 NAME

FusionInventory::Agent::Task::Inventory - Inventory task for FusionInventory

=head1 DESCRIPTION

This task extract various hardware and software information on the agent host.
