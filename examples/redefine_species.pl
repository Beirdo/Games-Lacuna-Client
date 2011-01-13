#!/usr/bin/perl 
use 5.12.2;

use FindBin;
use lib "$FindBin::Bin/../lib";
use Games::Lacuna::Client;
use YAML::Any;

$| = 1;

my $cfg_file = shift(@ARGV) || 'lacuna.yml';
die "Did not provide a config file" unless -e $cfg_file;

my $client = Games::Lacuna::Client->new(
    cfg_file => $cfg_file,
    debug    => 1,
);

$client->empire->redefine_species(
    {
        name                   => 'Nuveau Average',
        description            => "More average than average.",
        min_orbit              => 4,
        max_orbit              => 4,
        manufacturing_affinity => 4,
        deception_affinity     => 4,
        research_affinity      => 4,
        management_affinity    => 4,
        farming_affinity       => 4,
        mining_affinity        => 4,
        science_affinity       => 4,
        environmental_affinity => 4,
        political_affinity     => 4,
        trade_affinity         => 4,
        growth_affinity        => 4,
    }
);

exit;
