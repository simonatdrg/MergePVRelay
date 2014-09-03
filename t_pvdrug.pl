use 5.012;
use PVDrug;
use DBI;
use Relay::Connect2DB;


my $popt = {};
$popt->{database} = 'pharmaview';
$popt->{host}     = 'localhost';
$popt->{port}     = 3306;
$popt->{user}     = 'root';
$popt->{password} = 'mysql';
   my $dbh = mysqldbconnect(
        $popt->{database}, $popt->{host}, $popt->{port},
        $popt->{user},     $popt->{password}
    );
my $p = PVDrug->new($dbh, 'pvsuperset');
sleep 1;

exit;
