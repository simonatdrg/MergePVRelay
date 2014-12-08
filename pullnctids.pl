#/usr/bin/env perl
# mdd project - similar to brc
# read in list of people,, search on people ent and return matching doc ids
#
use 5.012;
#use Env qw(RELAY_HOME);
#use lib "$RELAY_HOME/dev/src/bdlive/model/perl/common/perl/site/lib";
use Relay::BufferedAttivioQuery;
use Storable qw (dclone);
use Text::CSV;

# open rvi today csv file
my $rvicsv ='rvi_today_post_2011.csv';
	open my $fh, "< :encoding(utf8)", $rvicsv;
	my $csv = Text::CSV->new({binary => 1});
	$csv->column_names($csv->getline($fh));
	
	while (my $hr = $csv->getline_hr($fh)){
	my $a = Relay::BufferedAttivioQuery->new();
	$a->baseurl("http://192.168.100.150:17001");
	$a->filterquery("table:ct");
	$a->filterquery("all_facet_date:[2011-01-01 TO *]");
	my $fwanted = [ "ct_url", "ct_nct_id"];
	$a->fields($fwanted);
	my $q = sprintf('drugs_ent:"%s" AND diseases_ent:"%s"', $hr->{drug}, $hr->{ind});
	$a->query($q);
	while (my $adoc = $a->nextdoc()) {
		say join("\t", $hr->{ravikey},
					$hr->{drug}, $hr->{ind},
					$adoc->field('ct_nct_id')->[0], $adoc->field('ct_url')->[0]);
	}
#	sleep 1;
}
exit;
