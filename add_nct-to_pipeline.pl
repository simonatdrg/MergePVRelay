#!/usr/bin/env perl
#
# add NCT information to the pipeline table (v4) we're sending to PV analysts
#
use 5.012;
use DBI;
use Relay::Connect2DB;
use Iterator::DBI;
use Time::HiRes qw(usleep nanosleep);

# constants
# mysql data
my $popt = {};
$popt->{database} = 'pharmaview';
$popt->{host}     = '192.168.100.150';
$popt->{port}     = 3306;
$popt->{user}     = 'root';
$popt->{password} = 'mysql';


my $mappingstable = 'rvi_to_nct_mappings';
my $pipelinetable = 'relaypipeline_1112';

my $dbh = mysqldbconnect(
        $popt->{database}, $popt->{host}, $popt->{port},
        $popt->{user},     $popt->{password}
    );
#
# sql to get
# setup iteration over rvi-today
my $pipelinesql = "select relay_id from $pipelinetable order by relay_id";
my $pipeline_iter = idb_rows( $dbh, $pipelinesql );
# and the pull from the mapping table
my $pullsql = "select * from $mappingstable where rid = ?";
my $sthpull = $dbh->prepare($pullsql);
# pipeline table update with nct
my $pipeupdatesql = "UPDATE $pipelinetable SET nct_id = ?, nct_url = ? WHERE relay_id = ?";
my $sthupdate = $dbh->prepare($pipeupdatesql);
# log errors
open my $logf, ">mergenct.log";
#
#start iter through pipeline table: rids are unique
#_
my $ctr = 0;
 while ( $pipeline_iter->isnt_exhausted() ) {
		my $hp = $pipeline_iter->value();
		my $rid = $hp->{relay_id};
		# get matching rows from mappings table
		my $rc = $sthpull->execute($rid);
		my $nrows = $sthpull->rows();  # mysql specific ??
		if ($nrows == 1) {
			my $ref = $sthpull->fetchall_arrayref({});
			say STDERR join("\t", $ctr, $rid, $ref->[0]->{nct_id}, $ref->[0]->{nct_url});
			update_pipeline($sthupdate, $ref->[0] );
			$dbh->commit() if ((++$ctr % 100) == 0); # occasional commits
#debug			last if ($ctr > 5000);
		} elsif ($nrows == 0) {
			say $logf join("\t", "0", $rid);
		} else {
			my $ref = $sthpull->fetchall_arrayref({});
			say $logf join ("\t", "m", $rid, $_->{nct_id}) foreach @{$ref};
			
		}
		
		usleep(10000);
 }
 $dbh->commit();
 sleep 5;
 $dbh->disconnect();
 exit(0);
 #####
  sub update_pipeline {
	my ($sth, $maprec) = @_;
	#maprec will have rid, bctid, nct_url (inter alia);
	my $rc = $sth->execute($maprec->{nct_id}, $maprec->{nct_url}, $maprec->{rid});
	return $rc;
  }