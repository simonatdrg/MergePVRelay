#!/usr/bin/env perl
#
# makelreay4merge.pl
#	create file /table with a superset of relay pipeline data and flags to
# indicate possible linkages/overalps with PV data
# Logic rules:
#  Do not add  Relay drugs already in PV
#  Do not add any Relay data from companies already in PV
#  Only pre-approval phase data for Relay drugs being added
#
#  First iteration:
# return all post 2011 trials. Do not filter but add fields to each row indicating what
# actions would have been taken
#
# Second Iteration - 2.0
# Use the tagger to map relay drugs to pharmaview {brand, generic, scientific}
# 
use 5.012;
use strict;
use DBI;
use Iterator::DBI;

#use Text::CSV;
use Relay::Connect2DB;
use PVDrug;
use List::MoreUtils qw (uniq any);
use findparents;
use Regexp::Assemble;
use File::Slurp;
use Try::Tiny;

# for looking up RTM drugs and their PV erquivalents
use pvfuzzydrugmatch;

# use makedrugregexps;

# constants
# mysql data
my $popt = {};
$popt->{database} = 'relaybdlive';  # for rvi_today
$popt->{host}     = '192.168.100.150';
#$popt->{host}     = '127.0.0.1';
$popt->{port}     = 3306;
$popt->{user}     = 'root';
$popt->{password} = 'mysql';
my $rvisql = "select * from rvi_today where all_facet_date >='2011-01-01'";

# data file locations
my $compnamestofilter = 'trackedcomps.txt'; # top 47
my $othercompfile = 'othercomps.txt';
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
	my ($pvrow) = @_;
	my @keys = qw (relay_id date relay_drug relay_company relay_ind  relay_toplevelind relay_phase pv_tracked_comp pv_other_comp pv_brand pv_generic pv_researchcode);
	# stub
	my @pvvals = map {$pvrow->{$_}} @keys;
	my $l = join( "\t", @pvvals);
  
	return $l;
}
#
# same as create-row, but write to mysql
#
sub write_pv_rec {
	my ($dbh, $rvrow,  $table) = @_;
	my ($k, $v);
	my $str ='';
	# concatenate into $rvrow
#	while (($k,$v) = each %$match) {
#		$rvrow->{$k} = $v;
#	}
	
	while (($k,$v) = each %$rvrow) {
	my $val=undef;
		if ( ref ($v) eq 'ARRAY') {
			if(scalar (@$v) > 0) {
			$val = join('|', @$v);
			} else {
			  next;
			}
		} else { # scalar
		  next unless (defined $v);
		 $val = $v;
		}
	next unless defined ($val); # catchall ...
	$str .= " $k=". $dbh->quote($val).",";
	}	
	$str =~ s/,$//;
	$str = "REPLACE INTO $table  SET $str ";

	eval {
	$dbh->do($str);
	} ; 
	if($@) {
		say STDERR "error",$@;
		return undef;
	}
	return 1;
}
#
#  main
#

sub main {
    # load the disease hierarchy stuff
	my $ancs = findparents->new('many-to-many-diseases.txt');
		# load the level1/2 filters
	my $lev2keys = load_lev12('config/mesh12.txt',2);
	my $lev1keys = load_lev12('config/mesh12.txt',1);
	my $subrefl2 = sub {
		my $t = shift;
		return 1 if(exists $lev2keys->{$t}) ;
		return undef;
	};
	say STDERR "loaded disease tree";
    # iterator for RVI data in 
    my $dbhr = mysqldbconnect(
        $popt->{database}, $popt->{host}, $popt->{port},
        $popt->{user},     $popt->{password}
    );

    my $rvi_iter = idb_rows( $dbhr, $rvisql );
####
	# and sa separate dbh for pv database
	my $dbhpv = mysqldbconnect(
        'pharmaview', $popt->{host}, $popt->{port},
        $popt->{user},     $popt->{password}
    );
    # instance of wrapper class  for pv data peeking and loading
    my $pvd = PVDrug->new( $dbhpv, "pvprods" );
	# and lists of interesting data
    my $brlistp = $pvd->branddrugnames();
    my $molistp = $pvd->genericdrugnames();
	my $rescodelistp = $pvd->allrescodes();
    my $comptracked   = $pvd->trackedcompanies();
	my $compother = $pvd->othercompanies();
	say STDERR "extracted drug and company names from PV";
    my $lastid = undef;
    my $piter  = $pvd->iterator();
	# active companies from PV data
	my $compre = make_company_regexp($comptracked);
#	my @othercomps = read_file($othercompfile, {chomp => 1});
	my $otherre = make_company_regexp($compother);
######


    while ( $rvi_iter->isnt_exhausted() ) {
		my $hp = $rvi_iter->value() ;
		# only pre-approval state(s)
        next unless ( $hp->{devdrindphase} =~ /Phase/i );
		# flag drugs and companies already in PV
		#
		# matching with a search against the pv drug index
		my %match;
		my ($brname, $genname,$sciname);
		try {
		($brname, $genname,$sciname)= fuzzydrugmatch($hp->{drug});
		} catch {
			say STDERR 'error in fuzzydrugmatch $_: drug was ', $hp->{drug};
		}; 
		$match{bdrugmatch} = $brname ? $brname : undef;
		$match{gdrugmatch} = $genname ? $genname : undef;
		$match{rescodematch} = $sciname ? $sciname : undef;
		
#		goto REMATCH;
#        my $f =  any { lc $hp->{drug} eq lc $_ } @{ $pvd->genericdrugnames()};
#		$match{gdrugmatch} =  $f ? 1 :0;
#        $f =  any { lc $hp->{drug} eq lc $_ } @{ $pvd->branddrugnames() };
#		$match{bdrugmatch} = $f ? 1 : 0;
#		$f =  any { lc $hp->{drug} eq lc $_ } @{ $pvd->allrescodes() };
#		$match{rescodematch} = $f ? 1 : 0;
	REMATCH:
		
		# TODO: how to handle multiple companies ???
        next if ( $hp->{company} =~ /multiple|unconfirmed/i );
	#	say STDERR join ('|', $hp->{drug},
	#			$match{brdugmatch},$match{gdrugmatch},$match{rescodematch});
		my @c = fuzzycompanymatch($hp->{company});
		# is it a PV tracked company ?
        $match{tracked} = $hp->{company} if
			(filter_on_company(lc $hp->{company}, $compre) ==1);
		# or an other followed company
		$match{other} =  $hp->{company} if 
			(filter_on_company(lc $hp->{company}, $otherre) == 1);
		
		# disease rollup
		my %allparents=();
		my $lcind = lc $hp->{ind};
		rollup($ancs, $lcind, $subrefl2, \%allparents);
#		say  STDERR "$lcind rolled up to ",join("|",keys %allparents);
		
		# create a row using PV columns
		my $pvrow = {};
		$pvrow->{relay_id} = $hp->{ravikey};
		$pvrow->{date} = $hp->{all_facet_date};
		$pvrow->{relay_drug} = $hp->{drug};
		$pvrow->{relay_ind} = $hp->{ind};
		$pvrow->{relay_company} = $hp->{company};
		$pvrow->{relay_toplevelind} = join("|",keys %allparents);
		$pvrow->{relay_phase} = $hp->{devdrindphase};
		$pvrow->{pv_company_match} = $c[0] if (defined $c[0]);
		$pvrow->{pv_tracked_comp} = $match{tracked};
		$pvrow->{pv_other_comp} = $match{other};
		$pvrow->{pv_brand} = $match{bdrugmatch};
		$pvrow->{pv_generic} = $match{gdrugmatch};
		$pvrow->{pv_researchcode} = $match{rescodematch};

		
		my $row = create_pv_row($pvrow);
        say $row;
		my $rc = write_pv_rec($dbhpv, $pvrow, 'relaypipeline');
    }
	say STDERR "finished relay pipeline table generation";
	$dbhpv->commit();
	say STDERR "waiting for db commit"; sleep 30;
	$dbhr->disconnect();
	$dbhpv->disconnect();
}

main();
exit;
