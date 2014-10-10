#!/usr/bin/env perl
# test navigate diseases with OO interface
use 5.012;
use DiseaseNavigator;

my $kid = "D063173"; #retrognathia
my $baddad = "D000008";
my $gooddad = 'D008336';

my $res;
say STDERR "$kid/$baddad no match either up or down";
my $do = DiseaseNavigator->new(meshcode => $kid);
$do->debug(1);
my $d1 = DiseaseNavigator->new(meshcode => $baddad);
say STDERR "checking search for passed by object";
$d1->debug(1);
$res = $do->has_parent_by_id($d1);
sleep 1;
$res = $do->has_parent_by_id($baddad);
say "res (parent) = $res";
$res = $do->has_child_by_id($baddad);
say "res (child) = $res";
sleep 1;

say STDERR "$kid/$gooddad will have parent match";
$res = $do->has_parent_by_id($gooddad);
 say "res (parent) = $res";
 say STDERR "repeat to check cache hits";
$res = $do->has_parent_by_id($gooddad);
 say "res (parent) = $res";
 
say STDERR "but child match should fail";
$res = $do->has_child_by_id($gooddad);
 say "res (child) = $res";
 say STDERR "repeat to check cache hits";
$res = $do->has_child_by_id($gooddad);
 say "res (child) = $res";

sleep 1;



#say STDERR "cache dump\n", $do->show_cache();

XXX:
say "Now Enter code1 code2, we will test both directions";
while (my $l=<STDIN>) {
	say STDERR "--";
	chomp $l;
	my @a = split(/\s+/, $l);
	my $d0 = DiseaseNavigator->new(meshcode => $a[0]);
	my $d1 = DiseaseNavigator->new(meshcode => $a[1]);
	$res = $d0->has_parent_by_id($a[1]);
	say "$a[0] is child of $a[1] =", $res;
	$res = $d0->has_child_by_id($a[1]);
	say "$a[0] is parent of $a[1] =", $res;
	
}

 
 exit;
