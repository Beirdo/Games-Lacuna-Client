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
    # debug    => 1,
);

say Dump($client->empire->redefine_species_limits);

exit;
