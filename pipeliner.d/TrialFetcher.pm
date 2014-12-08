
package TrialFetcher;
use strict;
use 5.012;
use Iterator::DBI;
#
# do sql query and rteurn a DBI::Iterator
#  $cfg is configuration object which will have access to all
# parameters needed to bind in the sql query
#
our $sqlquery = "SELECT *
FROM ctdocs
WHERE (date_added > ?) and (date_added < ?) 
AND 
( ct_inter_type REGEXP '^(drug|biologic|genetic)')
AND
(ct_study_type REGEXP 'intervention')
AND
(ct_phase REGEXP 'phase' )   
ORDER BY ct_phase ASC , date_added ASC";

sub fetchTrialIterator {
	my ($dbh, $cfg) = @_;
	my @bind=();
	$bind[0] = $cfg->getCFItem('startdate');
	$bind[1] = $cfg->getCFItem('enddate');
	# try/catch these for exceptions
	my $iter = idb_rows($dbh, $sqlquery, @bind);
	return $iter;
}
1;

__END__

SELECT *
FROM ctdocs
WHERE date_added > '2014-06-01'  // this date will be modified as time passes
AND 
( ct_inter_type REGEXP '^(drug|biologic|genetic)'  // intervention type )AND (
ct_study_type REGEXP 'intervention'  // study must be interventional
) AND
(ct_phase REGEXP 'phase' )     // only phase
ORDER BY ct_phase ASC , date_added ASC