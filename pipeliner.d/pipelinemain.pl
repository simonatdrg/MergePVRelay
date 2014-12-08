#!/usr/bin/env perl
#
# pipelinemain.pl
# pull CT trials from MySQL and filter out those of interest for PV and Analysts
# 
#	create file /table with CT pipeline data with some mapping done of
# drugs and companies

#  Selection of trials to consider will be managed by a pipeline status table
#
# Second Iteration - 2.0
# Use the tagger to map relay drugs to pharmaview {brand, generic, scientific}
#
# Third Iteration:
# a) Use a sql statement to do all the filtering rather than within the script
# b) return grouped records with a group-concat of indications
# c) use that to eliminate non-leaf locations
# d) burst back into individual records (one ind per row)
# e) create new IDs (these will rely on the ordering in the SQL statement)
#

# Classes/Modules:
#
# ConfigReader: read a config file (properties format) and merge with command line options.
# we can basically reuse the xml2db code

# TrialFetcher: Using the criteria found from the config by Configreader
# connect to DB and generate query. Will return a result Iterator
# or throw an exception

# TrialDataMapper:
# interfaces to the tagger and any other entity mapping we use
# will also do the disease upmapping

# OutputFileGenerator
# for selected records, write outout file (tab delimited)

# OutputDBRecordGenerator
# same, but writes to a database, which could be on SQL server

# commandline options, some of which can overwrite the config file
#

use 5.012;
use strict;
# database
use DBI;
use Iterator::DBI;
use Relay::Connect2DB;

# mapping and conversion of fields
use PVDrug;
use DiseaseNavigator;
use findparents;
# for looking up RTM drugs and their PV erquivalents
use pvfuzzydrugmatch;

# misc other  modules
use Regexp::Assemble;
use File::Slurp;
use Try::Tiny;
use List::MoreUtils qw (uniq any);
use Getopt::Long;

use ConfigParser;
use TrialFetcher;


# constants
our @outputkeys = qw (relay_id date relay_drug relay_company relay_ind has_child  relay_toplevelind relay_phase pv_company pv_tracked_comp pv_other_comp pv_brand pv_generic pv_researchcode);

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
# create rows with burst set of diseases
# return an array of printable rows
# plus an array of hashrefs (one per row), which are needed for a db write
# a bit ugly
sub create_multiple_rows {
	my ($pvrow, $diseaseh) =@_;
	my @a = (); my @hr = ();
#		my @outputkeys = qw (relay_id date relay_drug relay_company relay_ind has_child  relay_toplevelind relay_phase pv_company pv_tracked_comp pv_other_comp pv_brand pv_generic pv_researchcode);
	
	# convert the disease hierarchy into to a Y/N
    
	foreach my $r (keys %$diseaseh) {
		my $l = "";
		my %pvtemp = %$pvrow;  # deep copy
		$pvtemp{relay_ind} = $r;
		if ($diseaseh->{$r} == 1) {
			$pvtemp{has_child} = "Y";
		} else {
			$pvtemp{has_child} = "N";
		}
		my @pvvals = map {$pvtemp{$_}} @outputkeys;
		$l = join( "\t", @pvvals);
		push @a, $l;
	    push @hr, \%pvtemp;
	}
	return  (\@a, \@hr);
}
# obsolete
#
#sub create_pv_row {
#	my ($pvrow) = @_;
#	my @keys = qw (relay_id date relay_drug relay_company relay_ind  relay_toplevelind relay_phase pv_tracked_comp pv_other_comp pv_brand pv_generic pv_researchcode);
#	# stub
#	my @pvvals = map {$pvrow->{$_}} @keys;
#	my $l = join( "\t", @pvvals);
#  
#	return $l;
#}
#
# same as create-row, but write to mysql
#
sub write_pv_rec {
	my ($dbh, $rvrow,  $table) = @_;
	my ($k, $v);
	my $str ='';
	
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
	$str = "INSERT INTO $table  SET $str ";

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
# get the leaf indication nodes by consulting the disease hierarchy
#
sub get_leaves {
	my ($l) = @_;
	my @dis = split(/;/, $l);
	my %navh = (); # hold results of traversals: 1 indicates tagged as parent
	return {} if (scalar @dis == 0); #should never happen
	
	my @mcodes =();
#	say STDERR "---";
	for (my $i = 0 ; $i < scalar @dis; $i++) {
		my $d;
		try {
			$d = DiseaseNavigator->new(name => $dis[$i]);
			$mcodes[$i] = $d;
		} catch {
			say STDERR "failed code lookup for $dis[$i]";
			$mcodes[$i] = undef;
		};
	#	say STDERR $dis[$i],"\t", $mcodes[$i];
		
	}
		if (scalar @dis == 1) {
		return {$dis[0] => 0 };  # single ind, no comparisons to do
	}
	# remove the very few inds which didn't map
	
	my @umcodes = grep { $_ ;} @mcodes;
	#fixme: lasst array elemnt idn't tested for as a parent
	for (my $i1 = 0; $i1 < (scalar @umcodes) ; $i1++) {
		$navh{$umcodes[$i1]->name()} = 0; # default to not a parent
		for (my $i2 = 0 ; $i2 < scalar @umcodes; $i2++) {
			next if ($i1 == $i2);
			my $r = $umcodes[$i1]->has_child_by_id($umcodes[$i2]);
			if ($r) {
				$navh{$umcodes[$i1]->name()}++;
				last;  # no need to go through more of inner loop 
			}
		}
	}
#	sleep 1;
	return \%navh;
 }
#
#  main
#

sub main {
	my %o;
	
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
	# 
	my $res = GetOptions(\%o, "config=s");
	my $cf = ConfigParser->new($o{config}, {});
	#sleep 1;
	
    # ctdocs iter: db, host, port, user, passwd
    my $dbhr = mysqldbconnect(
        $cf->getCFItem('db'),
		$cf->getCFItem('host'),
		$cf->getCFItem('port'),
        $cf->getCFItem('user'),
		$cf->getCFItem('password')
    );
	say STDERR "querying RVI today table";
    my $ctd_iter = TrialFetcher::fetchTrialIterator($dbhr, $cf);
	goto L1;
####
	# and sa separate dbh for pv database:
	## TBD - do we need this and could it be on sql server ??
	# my $dbhpv = mysqldbconnect(
    #    'pharmaview', $popt->{host}, $popt->{port},
    #    $popt->{user},     $popt->{password}
    #);
    # instance of wrapper class  for pv data peeking and loading
   #  my $pvd = PVDrug->new( $dbhpv, "pvprods" );
	my $pvd=undef;
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
# col headers
	say join("\t", @outputkeys);
# main loop
L1:
	say STDERR "Staring iteration through ctdocs";
    while ( $ctd_iter->isnt_exhausted() ) {
		my $hp = $ctd_iter->value() ;
		next unless ($hp->{ct_sponsor_agency_class} =~ /industry/i);
		say join("\t", $hp->{ct_sponsor_agency}, $hp->{ct_nct_id}, $hp->{ct_condition}, $hp->{ct_brief_title},
				 $hp->{ct_phase});
		next;
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
		
		# TODO: how to handle multiple companies ???
    #   next if ( $hp->{company} =~ /multiple|unconfirmed/i );
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
		my $leafdiseaseh = get_leaves($hp->{allinds});
	#	next;
		# create a template row using PV columns
		my $pvrow = {};
	#	$pvrow->{relay_id} = make_id($hp);
		$pvrow->{date} = $hp->{all_facet_date};
		$pvrow->{relay_drug} = $hp->{drug};
		$pvrow->{relay_ind} = $hp->{ind};
		$pvrow->{relay_company} = $hp->{company};
		$pvrow->{relay_toplevelind} = join("|",keys %allparents);
		$pvrow->{relay_phase} = $hp->{devdrindphase};
		$pvrow->{pv_company} = $c[0] if (defined $c[0]);
		$pvrow->{pv_tracked_comp} = $match{tracked};
		$pvrow->{pv_other_comp} = $match{other};
		$pvrow->{pv_brand} = $match{bdrugmatch};
		$pvrow->{pv_generic} = $match{gdrugmatch};
		$pvrow->{pv_researchcode} = $match{rescodematch};

	# TODO: create multiple PV rows, where
		my ($rowarr, $pvhashes) = create_multiple_rows($pvrow, $leafdiseaseh);
	#	my $row = create_pv_row($pvrow);
	# write rows to STDOUT
        say $_ foreach @$rowarr;
	#	my $rc = write_pv_rec($dbhpv, $pvrow, 'relaypipeline');
	# and add to table
#		my $rc = write_pv_rec($dbhpv, $_, 'relaypipeline') foreach @$pvhashes;
    }
#	say STDERR "finished relay pipeline table generation";
#	$dbhpv->commit();
#	say STDERR "waiting for db commit"; sleep 30;
#	$dbhr->disconnect();
#	$dbhpv->disconnect();
}

main();
exit;
