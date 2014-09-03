#!/usr/bin/perl -w
use strict;
use 5.012;

#
# do extraction from rvi_today and curate for pharmaview
# Steps:
# Create a company regex (Regex::assmeble) which we can use to filter out
# the top 48 companies
# Create data structure to hold disease hierarchy
# DBI to connect , do query
# iterate through rows
#	- filter out companies
#   - map indication to level 2 or 3 ancestor
#   - map ancestor to DRG drug grouping
# write everything out
#
use DBI;
use Regexp::Assemble;
use File::Slurp;
use Iterator::DBI;
use findparents;

my $db = shift || 'relaybdlive';
my $extractquery = "select ravikey,drug,ind,company,devdrindphase,all_facet_date from rvi_today \
				   where all_facet_date >= '2011
-01-01' AND (devdrindphase like '%Phase%') ORDER BY company asc";

#my $extractquery = "select ravikey,drug,ind,company,devdrindphase,all_facet_date from rvi_today \
#				   where all_facet_date >= '2011-01-01' AND (devdrindphase like '%Phase%') AND (company LIKE 'Merck')";
# 
my $connstr = ["dbi:mysql:database=$db;host=192.168.100.150", 'root','mysql'];
my $compnamestofilter = 'excludes.txt';
my ($lev1keys,$lev2keys);
my @disstoplist =  ('hemorrhage', 'blood loss, surgical');

main();

sub make_company_regexp {
	my ($companyfn) = @_;
	my ($rex);
	my @comps = read_file($companyfn, {chomp => 1});
##
# create regular expression
#
	$rex = Regexp::Assemble->new();
	$rex->flags('i');

	foreach my $i (@comps ) {
#	$rex->add('\b'.$i);
	$rex->add($i);
	}
	my $bigreg = $rex->re();
	return $bigreg;
}

# compare company to the PV big ones: true if match
sub filter_on_company {
	my ($field, $bigregexp) = @_;
	if ($field =~ /$bigregexp/) {
		return 1;
	}
	return 0;
}

sub load_lev12 {
	my ($fn,$lev)=@_;
	my %h =();
	my @l = read_file($fn, {chomp => 1});
		foreach my $ll (@l) {
			my @s = split/\t/, $ll;
			$h{$s[0]}++ if ($s[1] == $lev);
		}
	return \%h;
	}

sub do_rvitoday_query {
	my ($connectstr,  $sql) = @_;
	# use Iterator::DBI to return an iterator based on fetchrow->hashref
	my $dbh = DBI->connect(@{$connectstr});
	my $iter = idb_rows ($dbh, $sql);
	return $iter;
}

# rolup an indication to the level 2 ancestor(s).
# this does assume that each term has a level 2...
sub rollup {
	my ($ancs,$term, $subref, $presults) = @_;
#	say STDERR "checking $term";
	if (scalar(grep {$_ eq $term } @disstoplist)){
		$presults->{$term} =1;
		return;
	}
	
	my $pars = $ancs->parents($term);
	if (scalar @$pars == 0) {
		$presults->{$term} = 1;
		return;
	}
	# debug ....
	if (scalar @$pars > 1) {
	#	say STDERR "multiple parents ",join("|",@$pars);
#		sleep 1; 
	}
	
	
	foreach my $parent (@$pars) {
		next if ($parent && exists $presults->{$parent});
		if (! $parent) {
			# has no parents so that's it
			$presults->{$term} = 1;
		} elsif (&$subref($parent)) {  # is it a lev 2
			$presults->{$parent}=1;
		} else {
			# continue on up
			my $presults = rollup($ancs, $parent, $subref, $presults);
#		sleep 1;
		}
		
	}
	
}
sub main {
	# load the disease hierarchy
	my $ancs = findparents->new('many-to-many-diseases.txt');
	# load the level1/2 filters
	$lev2keys = load_lev12('mesh12.txt',2);
	$lev1keys = load_lev12('mesh12.txt',1);
	
	my $subrefl2 = sub { my $t = shift;
					return 1 if(exists $lev2keys->{$t}) ;
					return undef;
				};
	# make a big regexp for company filtering
	my $compregexp = make_company_regexp($compnamestofilter);
	# return an iterator for the mysql result set
	my $it = do_rvitoday_query($connstr, $extractquery);
	my $n =0;
	
	while ($it->isnt_exhausted()) {
		my %allparents =();
		# hash keyed by column
		my $hp = $it->value();
		my $c = $hp->{company};
		next if ($c =~ /multiple|unconfirmed/i) ;
		my $r = filter_on_company($c, $compregexp);
		next if ($r > 0);
	#	say STDERR join("\t", $hp->{drug}, $hp->{company},$hp->{ind}, $hp->{devdrindphase});
		my $lcind = lc $hp->{ind};
		rollup($ancs, $lcind, $subrefl2, \%allparents);
		say  STDERR "$lcind rolled up to ",join("|",keys %allparents);
		say join("\t", $hp->{drug}, $hp->{company},$hp->{ind}, $hp->{devdrindphase},
	join("|",keys %allparents));
		$n++;
		#sleep 1;
	}
	say STDERR "$n included recs";

	
}

