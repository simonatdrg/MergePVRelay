#!/usr/bin/env perl
use strict;
use 5.012;

# create JSON structs from disease data
use JSON;
use DBI;
use Iterator::DBI;
use Relay::Connect2DB;
use List::MoreUtils qw (uniq);
use File::Slurp;
use Tie::Hash::MultiValue;

# everything except the heads we decided to delete
#my $sql1 = "SELECT  meshid, mh, treeloc,
#group_concat( child  SEPARATOR ';' ) AS kids,
#group_concat( parent SEPARATOR ';' ) AS ancestors
#FROM `meshtree` where meshid not in (SELECT srcid as meshid
#FROM `relayextra`
#WHERE (act = 'delete-head'))
#GROUP BY meshid,treeloc ORDER BY meshid";

my $sql1 = "SELECT  meshid, mh, treeloc,
group_concat( child  SEPARATOR ';' ) AS kids,
group_concat( parent SEPARATOR ';' ) AS ancestors
FROM `meshtree` where meshid not in (SELECT srcid as meshid
FROM `relayextra`
WHERE (act = 'delete-head'))
GROUP BY meshid,treeloc ORDER BY meshid";

my $kfile = "diskeys.json";
my $treefile = "distree.json";
my $synfile = "dissyns.json";

my $popt = {};
$popt->{database} = 'diseases';  # for rvi_today
$popt->{host}     = '192.168.100.150';
$popt->{port}     = 3306;
$popt->{user}     = 'root';
$popt->{password} = 'mysql';

my $dbdis = mysqldbconnect(
	$popt->{database}, $popt->{host}, $popt->{port},
	$popt->{user},     $popt->{password}
);

my $dis_iter = idb_rows( $dbdis, $sql1);
my @htlookup ;
my @synlookup ;

my %tree ;
my $c = tie %tree, "Tie::Hash::MultiValue";

while ($dis_iter->isnt_exhausted()) {
	my $h = $dis_iter->value();
	say join ("!",$h->{meshid}, $h->{treeloc}, $h->{ancestors});
	push @htlookup, [$h->{mh}, $h->{meshid}];
	# now process and clean up the ancestors and children
	my @ancs = (); my @kids=();
	my $a = $h->{ancestors};
	# check if zero length string or just whitespace and semicolons
	if ((length($a) == 0) || ($a =~ m/^[\s;]+$/)){
		;
	} else {
		@ancs = uniq (split(/;/, $a));
	}
	# same for children
		$a = $h->{kids};
	# check if zero length string or just whitespace and semicolons
	if ((length($a) == 0) || ($a =~ m/^[\s;]+$/)){
		;
	} else {
		@kids = uniq (split(/;/, $a));
	}
	if ($h->{meshid} eq 'C07.320.610') {
		say STDERR "debug";
	#	sleep 1;
	}
	my $tarr = [$h->{treeloc}, \@kids, \@ancs];
	$tree{$h->{meshid}} = $tarr;
#	push @tree, [$h->{meshid}, $h->{treeloc}, \@kids, \@ancs];
}

my $sql2 = "SELECT meshid, mh, group_concat( syn SEPARATOR ';' ) as syns
FROM `meshsyns`
GROUP BY meshid";
my @syntree;
my $syn_iter =idb_rows($dbdis, $sql2);
while ($syn_iter->isnt_exhausted()) {
	my $h = $syn_iter->value();
	my $tarr = [$h->{meshid}, $h->{mh}, $h->{syns}];
	push @syntree, $tarr;
}
# now json-ize
write_file($kfile, encode_json(\@htlookup));
write_file($treefile, encode_json(\%tree));
write_file($synfile, encode_json(\@syntree));

exit;


