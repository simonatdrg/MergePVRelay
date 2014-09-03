#!/usr/bin/perl
use strict;
use 5.012;

#
#  summarize top level inds for mapping to DRG groups

use DBI;
use File::Slurp;
use Iterator::DBI;
use List::MoreUtils qw (uniq);
use Tie::Hash::MultiValue;

my $db = shift || 'relaybdlive';
my $extractquery = "select distinct ind from rvi_today order by ind asc";

my $connstr = ["dbi:mysql:database=$db;host=192.168.100.150", 'root','mysql'];
my $disconnstr = ["dbi:mysql:database=diseases;host=192.168.100.150", 'root','mysql'];
my $compnamestofilter = 'excludes.txt';
my ($lev1keys,$lev2keys);
my @disstoplist =  ('hemorrhage', 'blood loss, surgical');
our %cache ;
tie %cache, 'Tie::Hash::MultiValue';

main();

sub load_mapping {
	my ($fn,$lev)=@_;
	my %h =();
	my @l = read_file($fn, {chomp => 1});
		foreach my $ll (@l) {
			my @s = split/\t/, lc $ll;
			$h{$s[0]} = $s[1];
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
# rollup 2:
# goes directly to diseases.meshparent to traverse the hierarchy
# Will return an arrayref of level 2 (or 1) nodes for this disease entity
# may be slow, but we can keep a local cache
#

sub rollup2 {
	my ($disdbh, $term) = @_;
	my $done = 0;
	my @res = ();
	if (exists $cache{$term}) {
		return $cache{$term};
	}
	
	
	my $sth = $disdbh->prepare("select * from meshparents where mh = ?");
	$sth->execute($term);
	my @todo = ();
	my $ary = $sth->fetchall_arrayref({});
	foreach my $r (@$ary) {
		if ($r->{level} <= 2) {
			# success
			$cache{$term} =$term;
			return $cache{$term};
		} else {
			# list of parent mesh codes to look for
			push @todo, $r->{parent};
		}
	}
		# now iteratively search for the parent of each of these
	foreach my $par (@todo) {
		my $res = _uptolevel($disdbh, $par, 2);
		$cache{$term} = lc $res->{mh};
	}
	return 	$cache{$term};
}

sub _uptolevel {
	my ($dbh, $meshcode, $lev) = @_;
	my $done = undef;
	my $h ={};
	while (! $done) {
		my $stm = $dbh->prepare("select * from meshparents where treeloc = ? limit 1");
		$stm->execute($meshcode);
		# can only have one result as treeloc is PK
		$h = $stm->fetchrow_hashref();
		if ($h->{level} == $lev) {
		$done=1;
		} else {
			$stm->finish();
			$meshcode = $h->{parent};
		#	say STDERR "from $"
		}
		
	}
	return ($h);
}

sub main {
	my $disdbh = DBI->connect(@{$disconnstr});
	my $mapfiletransform=load_mapping('disease-mapping.txt');
	
	my %totals;
	my $it = do_rvitoday_query($connstr, $extractquery);
	
	while ($it->isnt_exhausted()) {
		# hash keyed by column
		my $hp = $it->value();
		my $lcind = lc $hp->{ind};
		my @uniq = ();
		next if ($lcind =~ /unconfirmed/);
		my $dismap =$mapfiletransform->{$lcind}; 
		my @mapped = split(/\|/, $dismap);
		if (scalar @mapped) {
			my @collect = ();
			foreach my $l (@mapped) {
				my $aref = rollup2($disdbh, lc $l);
				push @collect, @$aref;	
			}
			@uniq = uniq @collect;
			say  "$lcind\t",join("|",@uniq);
			foreach my $lev2 (@uniq) {
				$totals{$lev2}++;
			}
		}  else {
			say STDERR "no mapfile mapping for $dismap";
			exit;
		}
		
	#	sleep 1;
	}
	
	# print summary
	write_file("1234.txt",
			   map { $_.":".$totals{$_}."\n" } keys %totals);
	

	
}

