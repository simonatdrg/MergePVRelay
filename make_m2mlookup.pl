use strict;
use 5.012;
use Tie::Hash::Multivalue;
use Storable;

my %h;
tie %h, 'Tie::Hash::MultiValue';

while (<STDIN>) {
    chomp $_; $_ =~ s/\r//g;
    $_ = lc $_;
    my ($k,$v) = split(/\t/, $_);
    $h{$k} = $v;
}
store \%h, 'm2m.map';
exit;
