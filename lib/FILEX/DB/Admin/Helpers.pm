package FILEX::DB::Admin::Helpers;
use strict;
use vars qw($VERSION @ISA);
use FILEX::DB::base 1.0;
# inherit FILEX::DB::base
@ISA = qw(FILEX::DB::base);
$VERSION = 1.0;

# disable all user's non-expired files switch
# a given uniqId
sub disableUserFiles {
	my $self = shift;
	my $uniqId = shift;
	$self->setLastError(query=>"",
		string=>"require a user uniq id",
		code=>-1) && return undef if ( !defined($uniqId) );
	my $dbh = $self->_dbh();
	my $strQuery = "UPDATE upload ".
		"SET enable = 0 ".
		"WHERE expire_date > NOW() ".
		"AND enable = 1 ".
		"AND owner_uniq_id = ".$dbh->quote($uniqId);
	return $self->doQuery($strQuery);
}
# require a user uniqId
sub enableUserFiles {
	my $self = shift;
	my $uniqId = shift;
	$self->setLastError(query=>"",
		string=>"require a user uniq id",
		code=>-1) && return undef if ( !defined($uniqId) );
	my $dbh = $self->_dbh();
	my $strQuery = "UPDATE upload ".
		"SET enable = 1 ".
		"WHERE expire_date > NOW() ".
		"AND enable = 0 ".
		"AND owner_uniq_id = ".$dbh->quote($uniqId);
	return $self->doQuery($strQuery);
}
