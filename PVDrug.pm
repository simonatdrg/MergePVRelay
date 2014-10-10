#!/usr/bin/env perl -w
use 5.012;
package PVDrug;
# pull lists of drugs,companies etc from Pv data
# V2: use table pvsuperset which has  changed names
# - actually using a table with unique product ids (pvprods)
#
use DBI;
use Carp;
use Iterator::Util;
#use List::MoreUtils qw (distinct);
use Iterator::DBI;

# constructor
# dbh and table
sub new {
	my ($proto, $handle, $tablename) = @_;
	my $self = {};
	my $class = ref($proto) || $proto or return;
 
    
    # if the handle is a dbi, then sth must be present 
    if (ref($handle) ne 'DBI::db') {
       croak ("handle was not a dbh handle");
    }
    # check that table exists ?
	$self->{dbh} = $handle;
	$self->{pvtable} = $tablename;
	$self->{companylist} = undef;
    bless $self, $class;
    return $self;
}

sub _dolist {
	my ($self,$tag ) = @_;
	my $list = $tag."_list";
	return $self->{$list} if ($self->{$list});
	my $sql= "select distinct $tag from ". $self->{pvtable}.
	" order by $tag asc";
	my $iter = idb_rows($self->{dbh}, $sql);
	my @a;
	while ($iter->isnt_exhausted) {
	push @a, $iter->value()->{$tag};	
	}
	# cache
	$self->{$list} = \@a;
	return \@a;
}

sub allrescodes {
	my ($self) = @_;
	return $self->_dolist('research_code');
}

# all unique companies in PV table returned as an array ref
sub allcompanies {
	my ($self) = @_;
	my $tag='company_name'; my $list = $tag."_list";
	return $self->{$list} if ($self->{$list});
	my $sql= "select distinct $tag from ". $self->{pvtable}.
	" order by $tag asc";
	my $iter = idb_rows($self->{dbh}, $sql);
	my @a;
	while ($iter->isnt_exhausted) {
	push @a, $iter->value()->{$tag};	
	}
	# cache
	$self->{$list} = \@a;
	return \@a;
}
# these next two relay on the 'company_is_forecast' column, present in the
# superset table
sub trackedcompanies {
	my ($self) = @_;
	my $tag='trackedcompany'; my $list = $tag."_list";
	return $self->{$list} if ($self->{$list});
	my $sql= "select distinct company from ". $self->{pvtable};
#	" where company_is_forecast = 'true' AND product_is_active = 'true' order by #company_name asc";
	my $iter = idb_rows($self->{dbh}, $sql);
	my @a;
	while ($iter->isnt_exhausted) {
	push @a, $iter->value()->{company};	
	}
	# cache
	$self->{$list} = \@a;
	return \@a;
}

sub othercompanies {
	my ($self) = @_;
	my $tag='othercompany'; my $list = $tag."_list";
	return $self->{$list} if ($self->{$list});
#	my $sql= "select distinct company from ". $self->{pvtable}.
#	" where company_is_forecast = 'false' order by $tag asc";
	my $sql= "SELECT DISTINCT company FROM ". $self->{pvtable};
#	" WHERE company NOT IN (SELECT distinct company_name from ". $self->{pvtable}.
#	" where company_is_forecast = 'true' AND product_is_active = 'true') ";

	my $iter = idb_rows($self->{dbh}, $sql);
	my @a;
	while ($iter->isnt_exhausted) {
	push @a, $iter->value()->{company};	
	}
	# cache
	$self->{$list} = \@a;
	return \@a;
}
# drug names:
# select distinct drug_id, brand-name molecule
# cache results and slice as needed

# all unique drug brand names returned as arrayref
sub branddrugnames {
	my ($self) = @_;
	return $self->_dolist('brand');
}
#	return $self->{brand_list} if ($self->{brand_list});
#	my $sql= "select distinct brand from ". $self->{pvtable}. ' order by brand asc';
#	my $iter = idb_rows($self->{dbh}, $sql);
#	my @a;
#	while ($iter->isnt_exhausted) {
#	push @a, $iter->value()->{brand};	
#	}
#	# cache
#	$self->{brand_list} = \@a;
#	return \@a;
#}

sub genericdrugnames {
	my ($self) = @_;
	return $self->{generic_list} if ($self->{generic_list});
	my $sql= "select distinct generic from ". $self->{pvtable}. ' order by generic asc';
	my $iter = idb_rows($self->{dbh}, $sql);
	my @a;
	while ($iter->isnt_exhausted) {
	push @a, $iter->value()->{generic};	
	}
	# cache
	$self->{generic_list} = \@a;
	return \@a;
	
}

# return an iterator which can be used to retrieve all rows in the pvdrugs
# table
# Iterator of class 'Iterator::DBI'
#TODO: handle the near duplicate rows if possible
#
sub iterator {
	my ($self) = @_;
	return idb_rows($self->{dbh}, "select * from ". $self->{pvtable} ." order by product_id asc ");
}

1;


