#!/usr/bin/env perl

package navigate_diseases;
use strict;
use 5.012;


#  disease tree navigation functions
use JSON;
use List::MoreUtils qw (uniq any first_index first_value);
use File::Slurp;
use Tie::Hash::MultiValue;
require Exporter;
our @ISA = qw (Exporter);
our @EXPORT = qw( make_lookup make_treenav has_parent_by_id);

my $kfile = "diskeys.json";
my $treefile = "distree.json";
my (%d2mesh, %mesh2dis);
# %tree: treecode -->[kids, ancestors];
# %mesh2tree: k = h,meshcode: v = array of treecodes, managed by tie::hash::multivalue
my (%tree, %code2id);
my (%mesh2tree);
my $c = tie %mesh2tree, "Tie::Hash::MultiValue";

our %cache = (); # cache lookups: key is child#parent, val = 1,0 -TBD
our $usecache = 1;
our $DEBUG=0;

# make_dislookup
sub make_lookup {
	my ($fn) = @_;
	$fn ||= $kfile;
	my $kin = decode_json(read_file($fn));
	# note that there are dups, but they are elimiated here
	foreach my $el (@$kin) {
		$d2mesh{$el->[0]} = $el->[1];
		$mesh2dis{$el->[1]} = $el->[0];
	}
}

# make_treenav

sub make_treenav {
	my ($fn) = @_;
	$fn ||= $treefile;
	my $kin = decode_json(read_file($fn));
#	sleep 1;
	foreach my $key (sort keys %$kin) {
		my $el = $kin->{$key};  # AofA, one per treecode mapped to this mesh code
		foreach my $meshcodearr (@$el) {
		
			my $mcode = shift @{$meshcodearr}; #  leave [kids], [ancestors]
			# debug
			#if (($mcode eq 'C07.320.610')) {
			#say STDERR "$mcode matched";
			#}
			$tree{$mcode} = $meshcodearr;
			$mesh2tree{$key} = $mcode;
#			# map treecode back to meshid -- needed for traversal
			$code2id{$mcode} = $key;
		}
	}
sleep 1;
}

sub has_parent_by_id {
	my ($id, $searchfor) = @_;
	say STDERR "\n>>checking $id for parent $searchfor" if ($DEBUG);
	# navigate up tree until we get to the root. Remember we can have more than one
	# parent
	return undef if (! exists $mesh2tree{$id});
	return undef if (! exists $mesh2tree{$searchfor});
	my $searchcodes = $mesh2tree{$searchfor};
	my $codes = $mesh2tree{$id}; # all treecodes for this meshid
	# then call _by_treecode for each
	foreach my $co (@$codes) {
		my $res = has_parent_by_treecode($co, $searchcodes);
		return 1 if ($res > 0);
	}
	return 0;
}
# return 1/0 boolean: input is (treecode, arrayofparenttcodestosearch)
sub has_parent_by_treecode {
	my ($treeid, $searchcodes) = @_;
	say STDERR "\n>>checking $treeid for parents ". join("!",@{$searchcodes}) if ($DEBUG);
	# navigate up tree until we get to the root. Remember we can have more than one
			my $cachekey = $treeid.'##'.join('#',@$searchcodes);
		return $cache{$cachekey} if ($usecache && exists $cache{$cachekey});
	my @anccodeset = ();
	# launch search
	
	#	my $kidz = $tree{$treeid}->[0];
		my $ancz = $tree{$treeid}->[1];
	
		
	# say STDERR "check if $id ($code) has parent ($searchfor ( $searchcode) )";
		return 0 if  (! (defined $ancz) || (scalar @$ancz) == 0);  # no more ancestors
		
	# check if any ancestors eq this searchfor treecode
		my $i = -1;
	#	my $cachekey = $treeid.'##'.join('#',@$searchcodes);
	#	return $cache{$cachekey} if ($usecache && exists $cache{$cachekey});
		#
		foreach my $searchtcode (@$searchcodes) {
			$i = first_index { $_ eq $searchtcode} @$ancz;
			if ($i >= 0) {# we have a match
			$cache{$cachekey}=1;
			return 1;
			} 
		}
	
	
	# none of the ancestors matched
	# So go up tree, with possible multiple ancestors
	
	#reduce the @anccodeset by deduping
	my @uniqueancs = uniq (@$ancz);  # maybe not necessary ??
	say STDERR "dis $treeid has unique parent set ",
		join("!", @uniqueancs) if($DEBUG);
	foreach my $anc (@uniqueancs) {
	#	sleep 1;
		say STDERR "calling with search for $anc:" if ($DEBUG);
		my $res = has_parent_by_treecode($anc, $searchcodes);
		# unwind if match, else keep trying
		 if ($res == 1) {
			$cache{$cachekey} = 1;
			return $res;
		}
	}
	$cache{$cachekey} = 0;
	return 0;
}
# make_treenav($treefile);
 
1;
