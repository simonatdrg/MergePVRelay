#!/usr/bin/env perl
#
# DGmergepvrelay.pl
#	create file /table with merged pv/relay pipeline data
# Merge rules:
#  Do not add  Relay drugs already in PV
#  Do not add any Relay data from companies already in PV
#  Only pre-approval phase data for Relay drugs being added
#
# PV pipeline data is added to the file. Their drugs are matched to Relay drugs using the tagger

#rev 2: All relay recs regardless: just map companies and drugs
#
use 5.012;
use DBI;
use Iterator::DBI;

#use Text::CSV;
use Relay::Connect2DB;
use PVDrug;
use List::MoreUtils qw (uniq any);
use findparents;
use rtmindmapping qw (lookupind);
use Regexp::Assemble;
use File::Slurp;
use Relay::Tagger;
#use pvfuzzydrugmatch;

# constants
# mysql data
my $popt = {};
$popt->{database} = 'pharmaview';
$popt->{host}     = '192.168.100.150';
$popt->{port}     = 3306;
$popt->{user}     = 'root';
$popt->{password} = 'mysql';

my $rvisql = "select * from rvi_today where all_facet_date >='2011-01-01'";
# all pv recd regardless
my $pvsql = "select distinct(product_id) AS id, brand, generic, research_code, phase, company, lead_indication, therapy_area from pvsuperset where  NOT(brand like 'Other%' OR generic like '%Other')";


# data file locations
my $compnamestofilter = 'trackedcomps.txt'; # top 47
my $othercompnnames = 'othercomps.txt';

my ($lev1keys,$lev2keys);
my @disstoplist =  ('hemorrhage', 'blood loss, surgical');

####

sub make_company_regexp {
    my ($companyp) = @_;
    my ($rex);
##
    # create regular expression
    #
    $rex = Regexp::Assemble->new();
    $rex->flags('i');
	$rex->track(1); # rev 2

    foreach my $i (@{$companyp}) {

        #	$rex->add('\b'.$i);
        $rex->add($i);
    }
   # my $bigreg = $rex->re();
    return $rex;
}

# compare company to the PV big ones: true if match
sub filter_on_company {
    my ( $field, $rex ) = @_;
	my $re = $rex->re();
    if ( $field =~ /$re/ ) {
		# rev 2
        my $pat = $rex->source($^R);
		return $pat;
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

# toplevel ind --> therapy area mapping
sub map_rtmind_to_pvta {
	my ($ph) = @_;
	foreach my $k (keys %$ph) {
		my $ta = lookupind($k);
		return $ta if ($ta);
	}
	if (join(" ",keys %$ph) =~ /neoplasm/i) {
		return "Oncology";
	}
	
	say STDERR "!! no TA match for ". join('|', keys %$ph);
	return undef;
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

# generate tab separated row for output csv
sub create_rvi_row {
	my ($rvrow) = @_;
	# stub
	my $l = join( "\t", $rvrow->{ravikey},
            $rvrow->{drug}, $rvrow->{company}, $rvrow->{ind},
			$rvrow->{devdrindphase} , $rvrow->{ta},
			$rvrow->{flag});
	return $l;
}
# same but using pv col names
sub create_pv_row {
	my ($rvrow) = @_;
	# stub
	my $l = join( "\t", $rvrow->{id}+1000000,
            $rvrow->{drug}, $rvrow->{company}, $rvrow->{lead_indication},
			$rvrow->{phase} , $rvrow->{therapy_area},
			$rvrow->{flag});
	return $l;
}


sub main {

	# load the disease hierarchy
	my $ancs = findparents->new('many-to-many-diseases.txt');
	# load the level1/2 filters
	$lev2keys = load_lev12('config/mesh12.txt',2);
	$lev1keys = load_lev12('config/mesh12.txt',1);
	
	my $subrefl2 = sub { my $t = shift;
					return 1 if(exists $lev2keys->{$t}) ;
					return undef;
				};
	
    # iterator for RVI data
    my $dbh = mysqldbconnect(
        $popt->{database}, $popt->{host}, $popt->{port},
        $popt->{user},     $popt->{password}
    );
# setup iteration over rvi-today
    my $rvi_iter = idb_rows( $dbh, $rvisql );
# and pvprods
	my $pv_iter = idb_rows($dbh, $pvsql);
####

    # instance of wrapper class  for pv data peeking and loading
    my $pvd = PVDrug->new( $dbh, "drugprof" );
	# and lists of interesting data for filtering the relay companies and drugs
    my $brlistp = $pvd->branddrugnames();
    my $molistp = $pvd->genericdrugnames();
    my $compp   = $pvd->allcompanies();
    my $lastid = undef;
    my $piter  = $pvd->iterator();	
	my $compre = make_company_regexp($compp);
	# Tagger object 
	my $tagendpt = Relay::Tagger->new();
    $tagendpt->baseurl('http://localhost:8983/solr/tagger');
	$tagendpt->synfield(['dsyn2']);
	$tagendpt->domain('drug');
######
# main loop
#
#goto PVD;
# col head
	say join("\t", "id", "drug","company","indication", "phase","therapy_area","flag" );
    while ( $rvi_iter->isnt_exhausted() ) {
		my $hp = $rvi_iter->value();
		my %allparents =();
		# omit any drugs already in PV - rev2, include everything
        # next if ( any { lc $hp->{drug} eq lc $_ } @{ $pvd->genericdrugnames } );
        # next if ( any { lc $hp->{drug} eq lc $_ } @{ $pvd->branddrugnames } );
		# TODO: how to handle multiple companies
        next if ( $hp->{company} =~ /multiple|unconfirmed/i );
		
		# omit any with companies already in PV, using regexp
        #my $r = filter_on_company(lc $hp->{company}, $compre);
		#next if ($r > 0);
		#rev 2: get mapped-to-pv name else use what we have
		my $mappedcomp = filter_on_company(lc $hp->{company}, $compre);
		$hp->{company} = $mappedcomp if ($mappedcomp);
		# diease rollup
		my $lcind = lc $hp->{ind};
		rollup($ancs, $lcind, $subrefl2, \%allparents);
		#say  STDERR "$lcind rolled up to ",join("|",keys %allparents);
		
		# map top level to therapy area
		$hp->{ta} = map_rtmind_to_pvta(\%allparents);
		next if (! defined $hp->{ta});
		# only pre-approval state - omit for rev2
        # next unless ( $hp->{devdrindphase} =~ /Phase/i );
		$hp->{flag} =1;
		
		# create a row using RTM columns
		
		my $row = create_rvi_row($hp);
        say $row;
    }
PVD:
		my $np=0; my $nm = 0;
	# now the PV drugs, using pv_prods and the tagger to map pv drugs to rtm head terms
		while ($pv_iter->isnt_exhausted()) {
			my $hp = $pv_iter->value();
			$np++;
			my $id = $hp->{id};
			my $mappeddrug;
			# drug can be any of 3 ..." . brand name preferable.
			my $bdrug = $tagendpt->tagger($hp->{brand});
			if (defined $bdrug->{drug}) {
				$mappeddrug = $bdrug->{drug}->[0]; $nm++;
	#			say STDERR "$id: mapped brand to $mappeddrug";
			}  else {
				my $bdrug = $tagendpt->tagger($hp->{generic});
				if (defined $bdrug->{drug}) {
					$mappeddrug = $bdrug->{drug}->[0]; $nm++;
	#				say STDERR "$id: mapped generic to $mappeddrug";
				} else {
					my $bdrug = $tagendpt->tagger($hp->{research_code});
					if (defined $bdrug->{drug}) {
						$mappeddrug = $bdrug->{drug}->[0]; $nm++;
	#					say STDERR "$id: mapped researchcode to $mappeddrug";	
					} else {
						printf STDERR ("%d: %s|%s|%s no match\n", $id,
							$hp->{brand},$hp->{generic},$hp->{research_code});
						$mappeddrug=undef;
					}	
				}		
			}
#sleep 1
		if (! $mappeddrug) {
			# use the best one
			$mappeddrug = $hp->{brand} ||$hp->{generic} || $hp->{research_code};
		}
		$hp->{drug} = $mappeddrug;
		$hp->{flag} =2;
		my $row = create_pv_row($hp);
		say $row;
	}
	say STDERR "$np recs rec $nm drugs mapped";
	$dbh->disconnect();
}

main();
exit;
