#!/usr/bin/perl 
use strict;
use warnings;
use 5.010000;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Games::Lacuna::Client;
use List::Util qw(min max sum);
use Data::Dumper;
use Getopt::Long qw(GetOptions);
use AnyEvent;
use POSIX qw(floor);

use constant MINUTE => 60;

our $TimePerIteration = 10;

my $high_water = 200;
my $low_water  = 100;

my $balanced = 0;
GetOptions(
        'i|interval=f'  => \$TimePerIteration,
        'b|balanced=i'  => \$balanced,
        'h|highwater=i' => \$high_water,
        'l|lowwater=i'  => \$low_water,
        );
$TimePerIteration = int($TimePerIteration * MINUTE);

my $config_file = shift @ARGV;
usage() if not defined $config_file or not -e $config_file;

my $client = Games::Lacuna::Client->new(
        cfg_file => $config_file,
        #debug => 1,
        );

my $program_exit = AnyEvent->condvar;
my $int_watcher = AnyEvent->signal(
        signal => "INT",
        cb => sub {
        output("Interrupted!");
        undef $client;
        exit(1);
        }
        );

#my $res = $client->alliance->find("The Understanding");
#my $id = $res->{alliances}->[0]->{id};

my $empire = $client->empire;
my $estatus = $empire->get_status->{empire};
my %planets_by_name = map { ($estatus->{planets}->{$_} => $client->body(id => $_)) }
keys %{$estatus->{planets}};
# Beware. I think these might contain asteroids, too.
# TODO: The body status has a 'type' field that should be listed as 'habitable planet'


my @wrs;
foreach my $planet (values %planets_by_name) {
    my %buildings = %{ $planet->get_buildings->{buildings} };

    my @waste_ids = grep {$buildings{$_}{name} eq 'Waste Recycling Center'}
    keys %buildings;
    push @wrs, map  { $client->building(type => 'WasteRecycling', id => $_) } @waste_ids;
}

my @wr_handlers;
my @wr_timers;
foreach my $iwr (0..$#wrs) {
    my $wr = $wrs[$iwr];
    push @wr_handlers, sub {
        my $wait_sec = update_wr($wr, $iwr);
        return if not $wait_sec;
        $wr_timers[$iwr] = AnyEvent->timer(
                after => $wait_sec,
                cb    => sub {
                output("Waited for $wait_sec on WR $iwr");
                $wr_handlers[$iwr]->()
                },
                );
    };
}

foreach my $wrh (@wr_handlers) {
    $wrh->();
}

output("Done setting up initial jobs. Waiting for events.");
$program_exit->recv;
undef $client; # for session persistence
exit(0);

sub output {
    my $str = join ' ', @_;
    $str .= "\n" if $str !~ /\n$/;
    print "[" . localtime() . "] " . $str;
}

sub usage {
    die <<"END_USAGE";
Usage: $0 myempire.yml
           --interval MINUTES  (defaults to 20)

           Need to generate an API key at https://us1.lacunaexpanse.com/apikey
           and create a configuration YAML file that should look like this

           ---
           api_key: the_public_key
           empire_name: Name of empire
           empire_password: password of empire
           server_uri: https://us1.lacunaexpanse.com/

END_USAGE

}

sub update_wr {
    my $wr = shift;
    my $iwr = shift;

    output("checking WR stats for WR $iwr");
    my $wr_stat = $wr->view;

    my $busy_seconds = $wr_stat->{building}{work}{seconds_remaining};
    if ($busy_seconds) {
        output("Still busy for $busy_seconds, waiting");
        return $busy_seconds+3;
    }

    output("Checking resource stats");
    my $pstatus = $wr_stat->{status}{body} or die "Could not get planet status via \$struct->{status}{body}: " . Dumper($wr_stat);
    my $waste_per_hour = $wr_stat->{status}{body}{waste_hour};
    my $waste = $pstatus->{waste_stored};

    if ($low_water >= $high_water) {
        $high_water = $low_water + 1;
    }

    if (not $waste or $waste < $high_water) {
        output("waste accumulated ($waste) below high water ($high_water), waiting");
        return 5*MINUTE;
    }

    my $sec_per_waste = $wr_stat->{recycle}{seconds_per_resource};
    die "seconds_per_resource not found" if not $sec_per_waste;

    my $rec_waste = min($waste - $low_water, $TimePerIteration / $sec_per_waste, $wr_stat->{recycle}{max_recycle});

    # yeah, I know this is a bit verbose.
    my $ore_c    = $pstatus->{ore_capacity};
    my $water_c  = $pstatus->{water_capacity};
    my $energy_c = $pstatus->{energy_capacity};

    my $ore_s    = $pstatus->{ore_stored};
    my $water_s  = $pstatus->{water_stored};
    my $energy_s = $pstatus->{energy_stored};

    # produce boolean = capacity > stored + 1
    my $produce_ore    = $ore_c > $ore_s+1;
    my $produce_water  = $water_c > $water_s+1;
    my $produce_energy = $energy_c > $energy_s+1;
    my $total_s        = $ore_s + $water_s + $energy_s;

    my $produce_count = $produce_ore + $produce_water + $produce_energy;
    if ($produce_count == 0) {
        output("All storage full! Producing equal amounts of resources to keep waste low.");
        $produce_count = 3;
    }

    # balanced
    my $ore = 0;
    my $water = 0;
    my $energy = 0;

    # Normalize to % stored
    my $ore_p    = 1.0 * $ore_s    / $ore_c;
    my $water_p  = 1.0 * $water_s  / $water_c;
    my $energy_p = 1.0 * $energy_s / $energy_c;

    if (not $balanced) {
        my $max_p     = max($water_p, $ore_p, $energy_p);

	# Get the % stored required to become balanced
        my $water_pd  = $max_p - $water_p; 
        my $ore_pd    = $max_p - $ore_p;
        my $energy_pd = $max_p - $energy_p;
        my $total_pd  = $water_pd + $ore_pd + $energy_pd;

        if ($total_pd) {
            # Convert to % of total waste to balance % stored
            my $water_r   = $water_pd  / $total_pd;
            my $ore_r     = $ore_pd    / $total_pd;
            my $energy_r  = $energy_pd / $total_pd;

            # Convert to actual waste numbers
            $ore    = $rec_waste * $ore_r;
            $water  = $rec_waste * $water_r;
            $energy = $rec_waste * $energy_r;
        }

        $rec_waste -= ($ore + $water + $energy);
        if ($rec_waste) {
            $ore    += $rec_waste / 3;
            $water  += $rec_waste / 3;
            $energy += $rec_waste / 3;
        }
            
        $ore    = floor($ore    + 0.5);
        $water  = floor($water  + 0.5);
        $energy = floor($energy + 0.5);

        $rec_waste = min($ore + $water + $energy, $waste);
    }

    if ($ore == 0 && $water == 0 && $energy == 0 ) {
        # if balanced is set, just divide evenly
        output('spending as evenly as possible');
        $ore    = $rec_waste * (1 / $produce_count) if $produce_ore;
        $water  = $rec_waste * (1 / $produce_count) if $produce_water;
        $energy = $rec_waste * (1 / $produce_count) if $produce_energy;
    }

    # TODO warn if we aren't keeping pace
    output("WARNING!!! WASTE RECYCLER NOT KEEPING PACE WITH WASTE PER HOUR!!!") if ((60 * 60) / $sec_per_waste < $waste_per_hour);

    # don't do anything if waste production is negative and will put below threshold
    if ($waste - $rec_waste >= $low_water - 3) {
        output(sprintf("RECYCLING %0d of %0d waste to ore=%0d, water=%0d, energy=%0d", $rec_waste, $waste, $ore, $water, $energy));
        eval {
            $wr->recycle(int($water), int($ore), int($energy), 0);
        };
        output("Recycling failed: $@"), return(1*MINUTE) if $@;
        output("Waiting for recycling job to finish");
        return int($rec_waste*$sec_per_waste)+3;
    }
    else {
        output("Choosing not to recycle right this moment. -- It ($rec_waste) would put us below $low_water waste threshold.");
        return 5*MINUTE;
    }

}
