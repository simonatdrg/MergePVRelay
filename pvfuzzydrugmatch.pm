#!/usr/bin/env perl
# wrapper to return the matching PV drugs using the Solr tagger

package pvfuzzydrugmatch;
use 5.012;
use strict;
use Relay::Tagger;
require Exporter;
use vars qw(@ISA @EXPORT);
@ISA = qw(Exporter);

@EXPORT = qw (fuzzydrugmatch);

my $tagendpt = undef;
# do a regular search here
#
sub fuzzydrugmatch {
	my ($drug) = @_;
	if (! defined $tagendpt) {
		$tagendpt = Relay::Tagger->new();
		$tagendpt->baseurl('http://localhost:8983/solr/tagger');
		$tagendpt->synfield(['head']);
	}
#	my $res = $tagendpt->tagger($drug);
	my $res = $tagendpt->plainsearch("head:\"$drug\"");
	# check for empty hash - n o results
	return(undef,undef,undef) if (! keys %$res);
	my @r = ();
	#brand, generic, scientific
	$r[0] = join(";", @{$res->{pvbrand}}) if exists($res->{pvbrand});
	$r[1] = join(";", @{$res->{pvmol}}) if exists($res->{pvmol});
	$r[2] = join(";", @{$res->{pvsci}}) if exists($res->{pvsci});
	
	return @r;
}
1;
__END__
main();

sub main {
my @r  =fuzzydrugmatch('vildagliptin');
sleep 1;
@r = fuzzydrugmatch('noxafil');
sleep 1;
@r = fuzzydrugmatch('xa1237dhf');
sleep 1;
exit;
}

1;

