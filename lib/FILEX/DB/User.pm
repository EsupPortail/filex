package FILEX::DB::User;
use strict;
use vars qw($VERSION @ISA);
use FILEX::DB::base 1.0;

# inherit FILEX::DB::base
@ISA = qw(FILEX::DB::base);
$VERSION = 1.0;

# get used disk space for a given user
# where files does not expire.
sub getDiskSpace {
	my $self = shift;
	my $uid = shift;
	return undef if !$uid;
	my $dbh = $self->_dbh();
	my $strQuery = "SELECT SUM(file_size) FROM upload WHERE owner_uniq_id=".$dbh->quote($uid).
                 " AND expire_date > NOW() AND deleted != 1";
	my $res;
	eval {
		my $sth = $dbh->prepare($strQuery);
		$sth->execute();
		$res = $sth->fetchrow();
	};
	if ($@) {
		$self->setLastError(query=>$strQuery,string=>$dbh->errstr(),code=>$dbh->err());
		warn(__PACKAGE__,"-> Database Error : $@");
		return undef;
	}
	# if no match then NULL is returned
	$res = 0 if ( !defined($res) );
	return $res;
}

# get total user upload file count
sub getUploadCount {
	my $self = shift;
	my $user = shift;
	return undef if !$user;
	my $dbh = $self->_dbh();
	my $strQuery = "SELECT COUNT(id) FROM upload WHERE owner_uniq_id = ".$dbh->quote($user);
	my $res;
	eval {
		my $sth = $dbh->prepare($strQuery);
		$sth->execute();
		$res = $sth->fetchrow();
	};
	if ($@) {
		$self->setLastError(query=>$strQuery,string=>$dbh->errstr(),code=>$dbh->err());
		warn(__PACKAGE__,"-> Database Error : $@");
		return undef;
	}
	return $res;
}

# get total user active files
sub getActiveCount {
	my $self = shift;
	my $user = shift;
	return undef if !$user;
	my $dbh = $self->_dbh();
	my $strQuery = "SELECT COUNT(id) FROM upload WHERE owner_uniq_id = ".$dbh->quote($user).
	               " AND expire_date > NOW()";
	my $res;
	eval {
		my $sth = $dbh->prepare($strQuery);
		$sth->execute();
		$res = $sth->fetchrow();
	};
	if ($@) {
		$self->setLastError(query=>$strQuery,string=>$dbh->errstr(),code=>$dbh->err());
		warn(__PACKAGE__,"-> Database Error : $@");
		return undef;
	}
	return $res;
}

# check if user is admin
sub isAdmin {
	my $self = shift;
	my $uid = shift;
	return undef if !$uid;
	my $dbh = $self->_dbh();
	my $strQuery = "SELECT COUNT(1) FROM usr_admin WHERE uid = ".$self->_dbh->quote($uid)." AND enable = 1";
	my ($res);
	eval {
		my $sth = $dbh->prepare($strQuery);
		$sth->execute();
		$res = $sth->fetchrow();
	};
	if ($@) {
		$self->setLastError(query=>$strQuery,string=>$dbh->errstr(),code=>$dbh->err());
		warn(__PACKAGE__,"-> Database Error : $@ : $strQuery");
		return undef;
	}
	return $res;
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
