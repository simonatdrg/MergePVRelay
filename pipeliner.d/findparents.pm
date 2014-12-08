#!/usr/bin/perl
package findparents;

use strict;
use 5.012;
use Tie::Hash::MultiValue;
use Storable;
our %h;
#
sub new {
    my($class, $fn, $blobname) = @_;
    my $c = tie %h, 'Tie::Hash::MultiValue';
    #open M2M, " < many-to-many-diseases.txt";
    open M2M, " < $fn";
    binmode M2M, ":crlf";
    make_hash();
    bless \%h,$class;
}
#
sub parents {
    my ($self, $syn) = @_;
	my $r = [];
# arrayref, may be multiple parents
	return $r if (! defined $self->{$syn}); # force return into an arrayref
	
	return  $self->{$syn} ;
}

# read the many-to-many, lowercase, and create a lookup hash
# Tie::Hash::MultiValue allows multiple values per key
#
sub  make_hash {
	while (my $l = <M2M>) {
	chomp $l;
	$l = lc $l;
	if ($l =~ /^inflammation$/i) {
		sleep 1;
	}
	
	my @s = split (/\t/, $l);
#	my @s = split (/>>/, $l);
	$h{$s[0]} = $s[1] unless ($s[0] eq $s[1]);
#	$h{$s[0]} = $s[1] ;
	}
}

1;
	


