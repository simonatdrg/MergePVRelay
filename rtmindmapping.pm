#!/usr/bin/env perl -w
package rtmindmapping;
# takes the mappings defined in Combined Pipeline Mapping File_18 08 2014.xlsx 
# converted to relay-ind-mappings.csv
# and generates a hash which maps relay inds and toplevel inds to PV TA
# relay inds can have multiple top level inds, which are pipe separated.
# 
use 5.012;
use Text::CSV;
require Exporter;
our @ISA = qw (Exporter);
our @EXPORT = qw(lookupind);

my %h = ();
#rel to mergepv 
my $file='data/relay-ind-mappings.csv';
my %moremap =  ('oph'=> 'Opthalmology',
				  'msp' => 'Musculoskeltal_Pain',
				  'gi' =>  'Gastrointestinal',
				  'ai' =>  'Anti-infectives',
				  'resp' => 'Respiratory',
				  'cv'	=> 'Cardiovasculars',
				  'met' => 'Metabolism',
				  'gu' => 'Genitourinary',
				  'cns' => 'Central Nervous System',
				  'derm' => 'Dermatology'
);

sub _read_file {
	my ($fh )= @_;
	my $csvin = Text::CSV->new({binary =>1});
	$csvin->column_names($csvin->getline($fh));
	
	while (my $row = $csvin->getline($fh)) {
# relayind relaytoplevelind TA
    my %t = ();
	my @ri = split(/\|/, $row->[0]); 
	push @ri, 	split(/\|/, $row->[1]);
	# deduped
	map { $t{lc $_} = 1} @ri;
	# add to lookup hash
	map {$h{lc $_} = $row->[2]} keys %t;
	}
	say STDERR scalar keys %h, " keys";
	
}

sub lookupind {
	my ($q) = @_;
	$q = lc $q;
	if (scalar keys %h ==0) {
		open(FH, "< $file")  or die "can't open $file: $!";
		_read_file(*FH);
	}
	return undef if (! exists $h{$q});
	return _mapmore($h{$q});
}
# map the variant abbreviations of therapy are to the full name
# why do they let this happen ?
sub _mapmore {
	if (exists $moremap{lc $_[0]}) {
		return $moremap{lc $_[0]};
	} else {
		return $_[0];
	}
	
}

1;
