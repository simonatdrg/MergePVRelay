package ConfigParser;
use 5.012;

use Config::Properties;
use Getopt::Long;
use Carp;
use Try::Tiny;
#use Relay::Common qw(logme $RELAY_DATA $RELAY_LOGD);


sub new {
    my ($proto, $configfile, $clargs)= @_;
    my ($self) ={};
    my $class = ref($proto) || $proto or return;
	open my $cfh, '<', $configfile
		or croak ("unable to open configuration file $configfile");

	my $props = Config::Properties->new();
	$props->load($cfh);
	$self->{cf} = $props;
	bless $self, $class;
	$self->doconfig($clargs);
	return $self;
}
#
# get individual config items, checking for command line overrides
#
sub doconfig {
  # popt is preparsed command line hash from getOpt::Long;
  my ($self, $popt) = @_;
  $self->{taggerurl} = $self->{cf}->requireProperty('tagger.url');
  
  $self->{debug} = $popt->{debug};
  #  get items we want, including any command line overrides
	 # can specify done dir explicity if it isn't the default
  $self->{outputdir} =  $self->{cf}->getProperty('outputdir');
  
 #
 # my $dbtype = $popt->{backend}|| $self->{cf}->getProperty("dbtype") || "mysql";
	$self->parseMySQLConnectorInfo();
  
  return;
}

# getter for configs
sub getCFItem {
	my($self, $item) = @_;
	return $self->{$item};
}

sub parseMySQLConnectorInfo {
    my ($self, $popt) = @_;
    # DBI stuff
	# look for full dsn with host/port (deal with ovwerrides from cmd line - TBD)
	#          0    1     2 
	# $dsn = "DBI:mysql:database=$database;host=$hostname;port=$port";
	 $self->{dsn} = $self->{cf}->requireProperty('db.dsn');
	 my @s = split(":", $self->{dsn});
	 # get the semicolon separated stuff
	 my (@ss) = split(/;/, $s[2]);
	my ( $h, $p);
	$self->{host}="localhost";
	$self->{port}=3306;
	(undef, $self->{'db'}) = split(/=/, $ss[0]);
	(undef, $self->{host})  = split(/=/, $ss[1]) if defined($ss[1]);
	(undef, $self->{port})  = split(/=/, $ss[2]) if defined($ss[2]);
    $self->{user} = $self->{cf}->requireProperty('db.user');
    $self->{pass} = $self->{cf}->requireProperty('db.pass');
    $self->{table} = $self->{cf}->requireProperty('db.table');
	$self->{statustable} = $self->{cf}->requireProperty('db.statustable');
	$self->{startdate} = $self->{cf}->requireProperty('startdate');
	# possibly use today as default ?
	$self->{enddate} = $self->{cf}->requireProperty('enddate');
    return 1;
}
1;
