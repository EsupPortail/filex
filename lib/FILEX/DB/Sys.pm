package FILEX::DB::Sys;
use vars qw($VERSION @ISA);
use FILEX::DB::base 1.0;

@ISA = qw(FILEX::DB::base);
$VERSION = 1.0;

# param = ref to ARRAY
sub getExpiredFiles {
	my $self = shift;
	my $results = shift;
	return undef && warn(__PACKAGE__,"-> Require an Array ref") if ( !$results || ref($results) ne "ARRAY");
	my $strQuery = "SELECT u.*,count(cd.upload_id) AS is_downloaded, ".
	               "UNIX_TIMESTAMP(u.upload_date) AS ts_upload_date, ".
	               "UNIX_TIMESTAMP(u.expire_date) AS ts_expire_date ".
	               "FROM upload AS u ".
	               "LEFT JOIN current_download AS cd ON u.id=cd.upload_id ".
	               "WHERE u.expire_date < NOW() ".
	               "AND u.deleted = 0 ".
	               "GROUP BY u.id";
	my $dbh = $self->_dbh();
	eval {
		my $sth = $dbh->prepare($strQuery);
		$sth->execute();
		while ( my $row = $sth->fetchrow_hashref() ) {
			push(@$results,$row);
		}
		$sth->finish();
	};
	if ($@) {
		$self->setLastError(query=>$strQuery,string=>$dbh->errstr(),code=>$dbh->err());
		warn(__PACKAGE__,"-> Database Error : $@ : $strQuery");
		return undef;
	}
	return 1;
}

# mark file as deleted
# require a file id
sub markDeleted {
	my $self = shift;
	my $id = shift;
	my $strQuery = "UPDATE upload SET deleted = 1 WHERE id = $id";
	my $dbh = $self->_dbh();
	eval {
		my $sth = $dbh->prepare($strQuery);
		$sth->execute();
		$dbh->commit();
	};
	if ($@) {
		$self->setLastError(query=>$strQuery,string=>$dbh->errstr(),code=>$dbh->err());
		warn(__PACKAGE__,"-> Database Error : $@ : $strQuery");
		return undef;
	}
	return 1;
}

1;
=pod

=head1 AUTHOR AND COPYRIGHT

FileX - a web file exchange system.

Copyright (c) 2004-2005 Olivier FRANCO

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; see the file COPYING . If not, write to the
Free Software Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

=cut
