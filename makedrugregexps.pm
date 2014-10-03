#
# make custom regexps from production PV drug data 0916
# returns a hashpointer where key = entity type (brand|molecule|scientific|company)
# and value
# is large regexp
# raow formats:
# drugs/brands
#
# 
package makedrugregexps;
require Exporter;
@ISA = qw(Exporter);

@EXPORT = qw (makeregexps);

use 5.012;
use Regexp::Assemble;
use IO::File;

use Storable;
my @comprecs =();
my @drugrecs=();
my @molrecs=();
my @brandrecs=();
#my $compfile = 'data/company_production_0916.txt';
my $drugfile ='data/drug_production_0916.txt'; # brands and scientific
my $molfile = 'data/molecule_production_0916.txt';
#
my $rehash = {};
sub makeregexps {
	my $fhdr =  IO::File->new("< $drugfile");
	my $fhmol = IO::File->new("< $molfile");
	my $rebrand = Regexp::Assemble->new();
	my $remol =  Regexp::Assemble->new();
	$rebrand->flags('i');
	$rebrand->track(1);
	$remol->flags('i');
	$remol->track(1);
	my $rescientific = Regexp::Assemble->new();
	$rescientific->flags('i');
	$rescientific->track(1);
	# drug file
	my $nr = 0;
	while (my $l = <$fhdr>) {
		next if ($nr++ ==0);
		
		my ($id, $brand, $sci, undef)  = split(/\t/, $l);
	#	say "$id:$brand";
		$brand =~ s/[()]//g; # regexp doesn't like parens'
		$rebrand->add($brand);
		if (($sci !~ /^\s+$/) && (length $sci > 0) && ($sci !~ /NULL/i)) {
			$sci =~ s/[()]//g; # regexp doesn't like parens'
			$rescientific->add($sci);
		}
	}
	$fhdr->close();
	# molecules
	say "molecules";
	$nr =0;
	while (my $l = <$fhmol>) {
		next if ($nr++ ==0);
		my ($id, $molname, undef)  = split(/\t/, $l);
		next if (length $molname == 0);
	#	say "m $id:$molname";
		$molname =~ s/[()]//g; # regexp doesn't like parens'
		$remol->add($molname);
	}
	$fhmol->close();
	$rehash->{scientific} = $rescientific;
	$rehash->{molecule} = $remol;
	$rehash->{brand} = $rebrand;
	return $rehash;
}
	
1;


