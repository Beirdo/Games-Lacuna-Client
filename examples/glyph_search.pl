#!/usr/bin/perl

use 5.010;
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use List::Util            (qw(first));
use Games::Lacuna::Client ();
use Getopt::Long          (qw(GetOptions));
use YAML::Any             (qw(Dump));

if ( $^O !~ /MSWin32/) {
    $Games::Lacuna::Client::PrettyPrint::ansi_color = 1;
}

my $planet_name;
my $opt_update_yml = 0;
GetOptions(
    'planet=s' => \$planet_name,
    'c|color!' => \$Games::Lacuna::Client::PrettyPrint::ansi_color,
    'u|update' => \$opt_update_yml,
);

my (%recipes, @wishlist, %glyph, %plan, %ore);
my $cfg_file = shift(@ARGV) || 'lacuna.yml';
unless ( $cfg_file and -e $cfg_file ) {
	die "Did not provide a config file";
}
my $glyph_recipes_file = shift(@ARGV) || 'glyph_recipes.yml';
my $plans_wanted_file  = shift(@ARGV) || 'plans_wanted.yml';


if( $opt_update_yml ){
    warn "This web-scraping function requires HTML::TableExtract and a helluva lot of luck.\n";
    eval { require HTML::TableExtract };
    die "Sorry, unable to load HTML::TableExtract, please install. Error: $@" if $@;
    warn "Replace the DATA block in this script with the following STDOUT content.\n";
    generate_yaml();
    warn "Complete.\n";
    exit;
}

my $client = Games::Lacuna::Client->new(
	cfg_file => $cfg_file,
	# debug    => 1,
);

<<<<<<< HEAD
=======
my @ores_to_look_for = ("bauxite", "kerogen", "sulfur",
                        "magnetite", "halite", "goethite",
                        "trona", "zircon", "gold",
                        "fluorite");

>>>>>>> be6ab59244b87fb45a788df78ce9c482ab4a0cc7
# Load the planets
my $empire  = $client->empire->get_status->{empire};

# key => planet name, value => planet api object
my %planet = map { my $id=$_; $empire->{planets}{$id}, { id => $id, plans=>[], glyphs=>[], ore=>[] } }
                  keys %{$empire->{planets}};
for my $name (keys %planet) {
    my $body      = $client->body(id => $planet{$name}{id});
    my $buildings = $body->get_buildings()->{buildings};

    # Find the Archaeology Ministry and Planetary Command Center
    $planet{$name}{AM}  = first {$buildings->{$_}{name} eq 'Archaeology Ministry'}     keys %$buildings;
    $planet{$name}{PCC} = first {$buildings->{$_}{name} eq 'Planetary Command Center'} keys %$buildings;
}


recipes_get();
wishlist_get();

while (@wishlist) {
    glyphs_get();
    plans_get();
    ores_get();
    wishlist_completed();
    if (!@wishlist) {@wishlist = (['Halls of Vrbansk',-1])}

    search();
    print "\nsleeping for 6 hours...\n\n";
    sleep 60 * 60 * 6 + 300; # 6 hours 5 minutes...

    recipes_get();  # may be updated
    wishlist_get(); # may change...
}

#print Dump(\%planet), "\n";
#print Dump(\@wishlist), "\n";

sub search {
    my %search;
    my @planet_name = (grep {$planet{$_}{AM} and !$planet{$_}{searching} } keys %planet);

    if (!@planet_name) {
	print "all planets are busy searching\n";
	return;
    };

    # prioritize on wishes in order
    OUTER: for my $wish (@wishlist) {
	my $item = $wish->[0];
	print "Can we look for any ingredients for a $item?\n";
	my (@recipes) = @{$recipes{$item}};
	# try to complete any recipe for that wish
	INNER: for my $recipe (@recipes) {
	    my %need;
	    $need{$_}++ for @$recipe;
	    for my $glyph_name (keys %need) { # ignore glyphs we already have
		delete $need{$glyph_name}  if exists $glyph{$glyph_name};
	    }
	    for my $ore_name (keys %need) {
		for (my $i=$#planet_name; $i>=0; $i--) {
		    my $planet_name = $planet_name[$i];
		    my $ph = $planet{$planet_name};
		    if (exists $ore{$ore_name}{$planet_name}) {
			print "\t$planet_name searching for $ore_name\n";
			$client->building(id=>$ph->{AM}, type=>'Archaeology')->search_for_glyph($ore_name);
			$ph->{searching} = 1;
			splice @planet_name, $i, 1;
		    }
		}
	    }
	    last OUTER  if !@planet_name;
	    print "\tplanets w/o ingredients for this recipe: ", join(', ', @planet_name), "\n";
	}
	last OUTER  if !@planet_name;
    }
    if (@planet_name) {
	for my $planet_name (@planet_name) {
	    my $ph = $planet{$planet_name};
	    my $ore_name = $ph->{ore}[0];
	    print "\t$planet_name has no useful ores available... searching for $ore_name...\n";
#	    $client->building(id=>$ph->{AM}, type=>'Archaeology')->search_for_glyph($ore_name);
	    $ph->{searching} = 1;
	}
    }
}


sub wishlist_completed {
    WISH: for (my $i=0; $i<@wishlist; $i++) {
	my ($item,$count) = @{$wishlist[$i]};

	# remove from wishlist the number of plans for this item which exists
	if (exists $plan{$item}) {
	    my $plan_count = $plan{$item};
	    if (($count - $plan_count) <= 0) {
		splice @wishlist, $i, 1; # remove item from wishlist if done
	        print "have $plan_count of $item, only $count wanted... removing from wishlist.\n";
		$i--;
		next;
	    }
	    else {
		$wishlist[$i][1] -= $plan_count;
	        print "have $plan_count of $item, reduce wanted count to $wishlist[$i][1]...\n";
	    }
	}

	# remove from wishlist plans which can be create from glyphs on hand...
	my (@recipes) = @{$recipes{$item}};
#	print "$item\n";
#	print Dump(\@recipes), "\n"; <STDIN>;
	die "no recipes for $item!"  unless @recipes;
        OUTER: for (my $k=1; $k<=$count; $k++) {
	    INNER: for (my $j=0; $j<@recipes; $j++) {
		my (@glyphs) = @{$recipes[$j]};
	        my $found=0;
		for (@glyphs) { $found++  if exists $glyph{$_}; }
		if (scalar @glyphs == $found) {
#		    print "\@glyphs = ", join(', ', @glyphs), "\n";
#		    print "found = $found\n";
		    print "can do $item, desired count reduced to $wishlist[$i][1]...\n";
		    $glyph{$_}-- for @glyphs;  # reduce glyph count
		    for my $key (keys %glyph) {
			delete $glyph{$key}  if ! $glyph{$key}; # remove glyphs where none remain
		    };
		    $wishlist[$i][1]--;  # remove if it can be built from glyphs
		    if ($wishlist[$i][1] <= 0) {
			splice @wishlist, $i, 1;
			$i--;
			next WISH;
		    }
		    else {
			next OUTER;
		    }
		}
	    }
	    last OUTER;
	}
    }
}

<<<<<<< HEAD
sub ores_get {
    for my $name (keys %planet) {
	my $ph = $planet{$name};
	next unless $ph->{AM};
	my $ore = $client->building(id=>$ph->{AM}, type=>'Archaeology')->get_ores_available_for_processing()->{ore};
	next unless keys %$ore;
	$planet{$name}{ore} = [];
	for my $key (keys %$ore) {
	    push @{$planet{$name}{ore}}, $key;
	    $ore{$key} ||= {};
	    $ore{$key}{$name}++;
	}
=======
    my $ores = $arch->get_ores_available_for_processing;
    my @available_ores = keys %{$ores->{ore}};
    if (scalar @available_ores) {
        my $ore_to_try = $available_ores[0] // next;
        foreach my $desired_ore (@ores_to_look_for) {
            if ($ores->{ore}->{$desired_ore} && $ores->{ore}->{$desired_ore} > 10000) {
                $ore_to_try = $desired_ore;
                last;
            }
        }
        print "Looking for $ore_to_try on $name\n";
        $arch->search_for_glyph ($ore_to_try);
>>>>>>> be6ab59244b87fb45a788df78ce9c482ab4a0cc7
    }
}

sub plans_get {
    for my $name (keys %planet) {
	my $ph = $planet{$name};
	my $plans = $client->building(id => $ph->{PCC}, type => 'PlanetaryCommand')->view_plans()->{plans};
	next unless @$plans;
	my $plan_count = scalar @$plans;
	if ($plan_count > 18) {
	    warn "planet $name has $plan_count plans. After 20, the oldest plan will be deleted!!!\n";
	}
	$planet{$name}{plans} = [];
	for my $plan (@$plans) {
	    my $plan_name = $plan->{name};
	    push @{$planet{$name}{plans}}, $plan_name;
	    $plan{$plan_name}++;
	}
    }
}

sub glyphs_get {
    for my $name (keys %planet) {
	my $ph = $planet{$name};
	next unless $ph->{AM};
	my $am = $client->building(id => $ph->{AM}, type => 'Archaeology');
	my $glyphs = $am->get_glyphs()->{glyphs};
	next unless @$glyphs;
	$planet{$name}{glyphs} = [];
	for my $glyph (@$glyphs) {
	    push @{$planet{$name}{glyphs}}, $glyph->{type};
	    $glyph{$glyph->{type}}++;
	}
	$ph->{searching} = $am->view()->{building}{work} ? 1 : 0;
    }
}

sub recipes_get {
    if ( $glyph_recipes_file and -e $glyph_recipes_file ) {
	%recipes = %{YAML::Any::LoadFile($glyph_recipes_file)};
    }
    else {
	die "Did not provide a recipe file";
    }
}

sub wishlist_get {
    if ( $plans_wanted_file and -e $plans_wanted_file ) {
	@wishlist = @{YAML::Any::LoadFile($plans_wanted_file)};
    }
    else {
	@wishlist = (['Halls of Vrbansk',-1]);
    }
    for my $wish (@wishlist) {
	die "check file $plans_wanted_file, no recipe exists for $wish->[0]!"  unless $recipes{$wish->[0]};
    }
}

1;
__END__

