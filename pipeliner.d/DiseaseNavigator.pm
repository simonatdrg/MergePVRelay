#!/usr/bin/env perl

# Moose class for navigating up/down disease hierarchy
# Constructor is
#
# 	$nav = DiseaseNavigator->new($);
# if either/neither of these are supplied then the defaults below are used
#
package DiseaseNavigator;
use strict;
use 5.012;
use Moose;

use JSON;
use List::MoreUtils qw (uniq any first_index first_value);
use File::Slurp;
use Tie::Hash::MultiValue;
use Carp;


our $def_kfile = "config/diskeys.json";
our $def_treefile = "config/distree.json";
our ($kfile,$treefile);

# global hashes
 # map disease names to mesh code, and vice versa
my (%d2mesh, %mesh2dis); 

# %tree: treecode -->[kids, ancestors];
# %mesh2tree: k = h,meshcode: v = array of treecodes, managed by tie::hash::multivalue
my (%tree, %code2id);
my (%mesh2tree);
my $c = tie %mesh2tree, "Tie::Hash::MultiValue";

# cache lookups for child_has_parent: key = childtreecode##parentcodes - val = 0/1
our %c2pcache = (); 
our $usecache = 1;
our $DEBUG=0;
our $init_done;

####################
# attributes
	has 'meshcode' => (is => 'ro', isa =>'Str');
	has 'name'  => (is =>'ro', isa =>'Str');
	has 'treecodes' => (is => 'ro', isa =>'ArrayrRef(Str)');
	has  debug => (is => 'rw', isa =>'Int', default => 0);
# set alternative 
#

# class method to specify alternate lookup/tree files:
# DiseaseNavigator->setfiles([path-to_lookupfile],[path_to_treefile])
sub setfiles {
	my($class, $lookup, $tree) = @_;
	$kfile = $lookup if defined ($lookup);
	$treefile = $tree if defined($tree);
}
sub BUILD {
	my ($self) = shift;
	if (! $init_done) {
		&make_lookup($kfile || $def_kfile);
		&make_treenav($treefile || $def_treefile);
		$init_done = 1;
	}
	
	# one of meshcode or name  must be sepcified
	if ((! exists $self->{meshcode}) && (! exists $self->{name})) {
		croak ("must specify one of meshcode or name in constructor!");
	}
	# get the name form the  meshcode, or vv, which ever was specified
	if (exists $self->{meshcode}) {
		$self->{name} = $mesh2dis{$self->{meshcode}};
		croak ("Nonexistent meshcode ". $self->{meshcode})
			unless (defined $self->{name});
	} else {
		$self->{meshcode} = $d2mesh{$self->{name}};
		croak ("Nonexistent name ". $self->{name})
			unless (defined $self->{meshcode});
	}
	$self->{treecodes} = $mesh2tree{$self->{meshcode}};
	return $self;
}

	
# make_dislookup
sub make_lookup {
	my ($fn) = @_;
	say STDERR "loading lookup tables";
	my $kin = decode_json(read_file($fn));
	# note that there are dups, but they are eliminated here
	foreach my $el (@$kin) {
		$d2mesh{$el->[0]} = $el->[1];
		$mesh2dis{$el->[1]} = $el->[0];
	}
}

# make_treenav

sub make_treenav {
	my ($fn) = @_;
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
#			# map treecode back to meshid
			$code2id{$mcode} = $key;
		}
	}
# sleep 1;
}

sub has_child_by_id {
	my ($self, $searchfor) = @_;
	return $self->has_relative_by_id($searchfor, "down");
}

sub has_parent_by_id {
	my ($self, $searchfor) = @_;
	return $self->has_relative_by_id($searchfor, "up");
}

sub has_relative_by_id {
	my ($self, $searchfor, $updown) = @_;
	my ($searchcodes);
	my $id = $self->meshcode();
	my $codes = $self->treecodes(); # all treecodes for this meshid
	
	# searchfor can optionally be a DiseaseNavigator object
	if (ref($searchfor) eq __PACKAGE__){
	#	say STDERR "Searching was passed DN object";
		$searchcodes = $searchfor->treecodes();
		printf STDERR ("\n#### checking %s (%s) for relative %s (%s) ->%s\n",
			$id, $self->name(),
			$searchfor->meshcode(),$searchfor->name(),
				$updown) if ($self->{debug});
		
#		say STDERR "\n##### checking $id for relative ".
#		$searchfor->meshcode()." ->: $updown" if ($self->{debug});
	} else {
# was passed a string
	return undef if (! exists $mesh2tree{$searchfor});
	$searchcodes = $mesh2tree{$searchfor};
	say STDERR "\n##### checking $id for relative $searchfor: $updown" if ($self->{debug});
	}
	# then call _by_treecode for each
	foreach my $co (@$codes) {
		my $res = $self->has_relative_by_treecode($co, $searchcodes, $updown);
		return 1 if ($res > 0);
	}
	return 0;
}

sub show_cache {
	my ($self) = @_;
	my $l = '';
	foreach my $k (sort keys %c2pcache) {
		$l .= sprintf("%s = %d\n", $k, $c2pcache{$k});
	}
	return $l;
}
#
# return 1/0 boolean: input is (treecode, arrayofcodestosearch, direction=up|down)
# treecode would usually be one of the ones in the treecodes array, but this
# method can be called on its own
#
sub has_relative_by_treecode {
	my ($self, $treeid, $searchcodes, $updown) = @_;
	#$updown ||= "up"; # default if not passed
	
	say STDERR "	>>checking $treeid for relatives ($updown) ".
			join("!",@{$searchcodes}) if ($self->{debug});
			
	# check cache: key is treecode: relatives treecodes: up/down
	my $cachekey = "$updown#".$treeid.'##'.join('#',@$searchcodes);
	if ($usecache && exists $c2pcache{$cachekey}) {
		say STDERR "cache hit:$cachekey=>".$c2pcache{$cachekey}
			if($self->{debug});
		return $c2pcache{$cachekey};
	}
	
	my @anccodeset = ();
	# launch search
	
		my $kidz = $tree{$treeid}->[0];
		my $ancz = $tree{$treeid}->[1];
		my $traversal = ($updown eq "up") ? $ancz : $kidz;
	
		
	
	# do we have any relatives ?
	#	return 0 if  (! (defined $traversal) || (scalar @$traversal) == 0);
		if  (! (defined $traversal) || (scalar @$traversal) == 0) {
			$c2pcache{$cachekey}= 0;
			return 0;
		}
		
	# check if any ancestors eq this searchfor treecode
		my $i = -1;
		#
		foreach my $searchtcode (@$searchcodes) {
			$i = first_index { $_ eq $searchtcode} @$traversal;
			if ($i >= 0) {# we have a match
			$c2pcache{$cachekey}=1;
			return 1;
			} 
		}
	
	
	# none of the relatives matched
	# So continue up/down, with possible multiple parents/kids
	
	#dedupe
	my @uniques = uniq (@$traversal);  # maybe not necessary ??
	say STDERR "dis $treeid has unique relative set ",
		join("!", @uniques) if($self->{debug});
		
	foreach my $anc (@uniques) {
	#	sleep 1;
		say STDERR "calling with search for $anc:" if ($self->{debug});
		my $res = $self->has_relative_by_treecode($anc, $searchcodes, $updown);
		# unwind if match, else keep trying
		 if ($res == 1) {
			$c2pcache{$cachekey} = 1;
			return $res;
		}
	}
	$c2pcache{$cachekey} = 0;
	return 0;
}


 
1;
