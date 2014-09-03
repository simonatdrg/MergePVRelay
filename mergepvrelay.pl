#!/usr/bin/env perl
#
# mergepvrelay.pl
#	create file /table with merged pv/relay pipeline data
# Merge rules:
#  Do not add  Relay drugs already in PV
#  Do not add any Relay data from companies already in PV
#  Only pre-approval phase data for Relay drugs being added
#
# original, actually does the filtering
# makerelay4merge.pl builds on this and outputs a complete file showing matches with
# PV pipeline data
#
use 5.012;
use DBI;
use Iterator::DBI;

#use Text::CSV;
use Relay::Connect2DB;
use PVDrug;
use List::MoreUtils qw (uniq any);
use findparents;
use Regexp::Assemble;
use File::Slurp;

# constants
# mysql data
my $popt = {};
$popt->{database} = 'pharmaview';
$popt->{host}     = '192.168.100.150';
$popt->{port}     = 3306;
$popt->{user}     = 'root';
$popt->{password} = 'mysql';
my $rvisql = "select * from rvi_today where all_facet_date >='2011-01-01'";

# data file locations
my $compnamestofilter = 'trackedcomps.txt'; # top 47
my $othercompnnames = 'othercomps.txt';
#my $pvextractcsv  = 

my @disstoplist = ( 'hemorrhage', 'blood loss, surgical' );

####

sub make_company_regexp {
    my ($companyp) = @_;
    my ($rex);
##
    # create regular expression
    #
    $rex = Regexp::Assemble->new();
    $rex->flags('i');

    foreach my $i (@{$companyp}) {

        #	$rex->add('\b'.$i);
        $rex->add($i);
    }
    my $bigreg = $rex->re();
    return $bigreg;
}

# compare company to the PV big ones: true if match
sub filter_on_company {
    my ( $field, $bigregexp ) = @_;
    if ( $field =~ /$bigregexp/ ) {
        return 1;
    }
    return 0;
}


sub load_lev12 {
    my ( $fn, $lev ) = @_;
    my %h = ();
    my @l = read_file( $fn, { chomp => 1 } );
    foreach my $ll (@l) {
        my @s = split /\t/, $ll;
        $h{ $s[0] }++ if ( $s[1] == $lev );
    }
    return \%h;
}

# rollup an indication to the level 2 ancestor(s).
# this does assume that each term has a level 2...
sub rollup {
    my ( $ancs, $term, $subref, $presults ) = @_;

    #	say STDERR "checking $term";
    if ( scalar( grep { $_ eq $term } @disstoplist ) ) {
        $presults->{$term} = 1;
        return;
    }

    my $pars = $ancs->parents($term);
    if ( scalar @$pars == 0 ) {
        $presults->{$term} = 1;
        return;
    }

    # debug ....
    if ( scalar @$pars > 1 ) {

        #	say STDERR "multiple parents ",join("|",@$pars);
        #		sleep 1;
    }

    foreach my $parent (@$pars) {
        next if ( $parent && exists $presults->{$parent} );
        if ( !$parent ) {

            # has no parents so that's it
            $presults->{$term} = 1;
        }
        elsif ( &$subref($parent) ) {    # is it a lev 2
            $presults->{$parent} = 1;
        }
        else {
            # continue on up
            my $presults = rollup( $ancs, $parent, $subref, $presults );

            #		sleep 1;
        }

    }

}

sub create_pv_row {
	my ($rvrow) = @_;
	# stub
	my $l = join( ":",
            $rvrow->{drug}, $rvrow->{company}, $rvrow->{ind},
			$rvrow->{devdrindphase} );
	return $l;
}


sub main {

    # iterator for RVI data
    my $dbh = mysqldbconnect(
        $popt->{database}, $popt->{host}, $popt->{port},
        $popt->{user},     $popt->{password}
    );

    my $rvi_iter = idb_rows( $dbh, $rvisql );
####

    # instance of wrapper class  for pv data peeking and loading
    my $pvd = PVDrug->new( $dbh, "drugprof" );
	# and lists of interesting data
    my $brlistp = $pvd->branddrugnames();
    my $molistp = $pvd->moldrugnames();
    my $compp   = $pvd->allcompanies();

    my $lastid = undef;
    my $piter  = $pvd->iterator();
	
	my $compre = make_company_regexp($compp);
#
# ind mapping to higher levels
#
	my $lev2keys = load_lev12('mesh12.txt',2);
	my $lev1keys = load_lev12('mesh12.txt',1);
	
######


    while ( my $hp = $rvi_iter->value() ) {
		# omit any drugs already in PV
        next if ( any { lc $hp->{drug} eq lc $_ } @{ $pvd->moldrugnames } );
        next if ( any { lc $hp->{drug} eq lc $_ } @{ $pvd->branddrugnames } );
		# TODO: how to handle multiple companies
        next if ( $hp->{company} =~ /multiple|unconfirmed/i );
		
		# omit any with companies already in PV, using regexp
        my $r = filter_on_company(lc $hp->{company}, $compre);
		next if ($r > 0);
		
		# only pre-approval state
        next unless ( $hp->{devdrindphase} =~ /Phase/i );
		
		# create a row using PV columns
		
		my $row = create_pv_row($hp);
        say $row;
    }

}

main();
exit;
