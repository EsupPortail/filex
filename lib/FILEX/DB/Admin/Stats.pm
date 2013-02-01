package FILEX::DB::Admin::Stats;
use strict;
use vars qw($VERSION @ISA);
use FILEX::DB::base 1.0;

# inherit FILEX::DB::base
@ISA = qw(FILEX::DB::base);
$VERSION = 1.0;

# download count -> upload id
sub downloadCount {
	my $self = shift;
	my $id = shift;
	my $dbh = $self->_dbh();
	my $strQuery = "SELECT COUNT(1) FROM get WHERE upload_id=$id";
	my $res;
	eval {
		my $sth = $dbh->prepare($strQuery);
		$sth->execute();
		$res = $sth->fetchrow_array();
		$sth->finish();
	};
	if ($@) {
		$self->setLastError(string=>$dbh->errstr(),code=>$dbh->err(),query=>$strQuery);
		warn(__PACKAGE__,"-> Database Error : $@ : $strQuery");
		return undef;
	}
	return $res;
}

# get file infos including download count
# id
# results
sub fileInfos {
	my $self = shift;
	my %ARGZ = @_;
	my $id = $ARGZ{'id'} if exists($ARGZ{'id'}) or return undef;
	my $results = $ARGZ{'results'} if (exists($ARGZ{'results'}) && ref($ARGZ{'results'}) eq "HASH") or return undef;
	my $dbh = $self->_dbh();
	my $strQuery = "SELECT u.*, (NOW() > expire_date) AS expired, ".
	               "UNIX_TIMESTAMP(upload_date) AS ts_upload_date, ".
	               "UNIX_TIMESTAMP(expire_date) AS ts_expire_date, ".
	               "COUNT(g.upload_id) AS download_count ".
	               "FROM upload AS u ".
	               "LEFT JOIN get AS g ON u.id = g.upload_id ".
	               "WHERE id=$id ".
	               "GROUP BY id";
	my $res;
	eval {
		my $sth = $dbh->prepare($strQuery);
		$sth->execute();
		$res = $sth->fetchrow_hashref();
		$sth->finish();
	};
	if ($@) {
		$self->setLastError(string=>$dbh->errstr(),code=>$dbh->err(),query=>$strQuery);
		warn(__PACKAGE__,"-> Database Error : $@ : $strQuery");
		return undef;
	}
	my $k;
	foreach $k ( keys(%$res) ) {
		$results->{$k} = $res->{$k};
	}
	return 1;
}

# get total downloaded file
sub totalDownloadedFileCount {
	my $self = shift;
	my $dbh = $self->_dbh();
	my $strQuery = "SELECT COUNT(g.upload_id), SUM(u.file_size) ".
	               "FROM get AS g ".
	               "LEFT JOIN upload AS u ON g.upload_id = u.id";
	my ($count,$size);
	eval {
		my $sth = $dbh->prepare($strQuery);
		$sth->execute();
		($count,$size) = $sth->fetchrow_array();
		$sth->finish();
	};
	if ($@) {
		$self->setLastError(string=>$dbh->errstr(),code=>$dbh->err(),query=>$strQuery);
		warn(__PACKAGE__,"-> Database Error : $@ : $strQuery");
		return undef;
	}
	return ($count,$size);
}

# get total expired file count
sub totalExpiredFileCount {
	my $self = shift;
	my $dbh = $self->_dbh();
	my $strQuery = "SELECT COUNT(1), SUM(file_size) FROM upload WHERE expire_date < NOW()";
	my ($count,$size);
	eval {
		my $sth = $dbh->prepare($strQuery);
		$sth->execute();
		($count,$size) = $sth->fetchrow_array();
		$sth->finish();
	};
	if ($@) {
		$self->setLastError(string=>$dbh->errstr(),code=>$dbh->err(),query=>$strQuery);
		warn(__PACKAGE__,"-> Database Error : $@ : $strQuery");
		return undef;
	}
	return ($count,$size);
}

# get total valid file count 
sub totalFileCount {
	my $self = shift;
	my $dbh = $self->_dbh();
	my $strQuery = "SELECT COUNT(1), SUM(file_size) FROM upload WHERE expire_date >= NOW()";
	my ($count,$size);
	eval {
		my $sth = $dbh->prepare($strQuery);
		$sth->execute();
		($count,$size) = $sth->fetchrow_array();
		$sth->finish();
	};
	if ($@) {
		$self->setLastError(string=>$dbh->errstr(),code=>$dbh->err(),query=>$strQuery);
		warn(__PACKAGE__,"-> Database Error : $@ : $strQuery");
		return undef;
	}
	return ($count,$size);
}

# get all non-expired files
# results => ARRAY REF
# [opt] orderby => "field name"
# [opt] order => 1 | 0
#                1 = desc
#                0 = asc
sub currentFiles {
	my $self = shift;
	my %ARGZ = @_;
	warn(__PACKAGE__,"require an Array Ref") && return undef if ( !exists($ARGZ{'results'}) || ref($ARGZ{'results'}) ne "ARRAY");
	my $dbh = $self->_dbh();
	my $res = $ARGZ{'results'};

	my $strQuery = "SELECT u.*, ".
	               "UNIX_TIMESTAMP(upload_date) AS ts_upload_date, ".
	               "UNIX_TIMESTAMP(expire_date) AS ts_expire_date, ".
	               "COUNT(g.upload_id) AS download_count ".
	               "FROM upload AS u ".
	               "LEFT JOIN get AS g ON u.id = g.upload_id ".
	               "WHERE expire_date > NOW() ".
	               "GROUP BY u.id ";
	my $order_by = ( exists($ARGZ{'orderby'}) && length($ARGZ{'orderby'}) ) ? $ARGZ{'orderby'} : 'upload_date';
	my $order = $ARGZ{'order'} if ( exists($ARGZ{'order'}) );
	if ( defined($order) && $order == 1 ) {
		$order = "DESC";
	} else { 
		$order = "ASC";
	}
	$strQuery .= ( $order_by eq "download_count" ) ? "ORDER BY $order_by $order" : "ORDER BY u.$order_by $order";
	# LIMIT offset, row_count
	eval {
		my $sth = $dbh->prepare($strQuery);
		$sth->execute();
		while ( my $r = $sth->fetchrow_hashref() ) {
			push(@$res,$r);
		}
		$sth->finish();
	};
	if ($@) {
		$self->setLastError(string=>$dbh->errstr(),code=>$dbh->err(),query=>$strQuery);
		warn(__PACKAGE__,"-> Database Error : $@ : $strQuery");
		return undef;
	}
	return 1;
}

# check if a given if is owned by a given owner
sub isOwner {
	my $self = shift;
	my %ARGZ = @_;
	warn(__PACKAGE__,"->require an id") && return undef if (!exists($ARGZ{'id'}) || $ARGZ{'id'} !~ /^[0-9]+$/);
	warn(__PACKAGE__,"->require a owner") && return undef if (!exists($ARGZ{'owner'}) || length($ARGZ{'owner'}) <= 0);
	my $dbh = $self->_dbh();
	my $strQuery = "SELECT COUNT(1) FROM upload WHERE id=".$ARGZ{'id'}." AND owner=".$dbh->quote($ARGZ{'owner'});
	my $res;
	eval {
		my $sth = $dbh->prepare($strQuery);
		$sth->execute();
		$res = $sth->fetchrow();
		$sth->finish();
	};
	if ($@) {
		$self->setLastError(string=>$dbh->errstr(),code=>$dbh->err(),query=>$strQuery);
		warn(__PACKAGE__,"-> Database Error : $@ : $strQuery");
		return undef;
	}
	return $res;
}

# set delivery flag
sub setDelivery {
	my $self = shift;
	my %ARGZ = @_;
	warn(__PACKAGE__,"-> require an id") && return undef if (!exists($ARGZ{'id'}) || $ARGZ{'id'} !~ /^[0-9]+$/);
	warn(__PACKAGE__,"-> require a state") && return undef if (!exists($ARGZ{'state'}) || $ARGZ{'state'} !~ /^[0-1]$/);
	my $dbh = $self->_dbh();
	my $strQuery = "UPDATE upload SET get_delivery=$ARGZ{'state'} WHERE id=$ARGZ{'id'}";
	eval {
		my $sth = $dbh->prepare($strQuery);
		$sth->execute();
		$dbh->commit();
	};
	if ($@) {
		$self->setLastError(string=>$dbh->errstr(),code=>$dbh->err(),query=>$strQuery);
		warn(__PACKAGE__,"-> Database Error : $@ : $strQuery");
		return undef;
	}
	return 1;
}

# set delivery flag
sub setResume {
	my $self = shift;
	my %ARGZ = @_;
	warn(__PACKAGE__,"-> require an id") && return undef if (!exists($ARGZ{'id'}) || $ARGZ{'id'} !~ /^[0-9]+$/);
	warn(__PACKAGE__,"-> require a state") && return undef if (!exists($ARGZ{'state'}) || $ARGZ{'state'} !~ /^[0-1]$/);
	my $dbh = $self->_dbh();
	my $strQuery = "UPDATE upload SET get_resume=$ARGZ{'state'} WHERE id=$ARGZ{'id'}";
	eval {
		my $sth = $dbh->prepare($strQuery);
		$sth->execute();
		$dbh->commit();
	};
	if ($@) {
		$self->setLastError(string=>$dbh->errstr(),code=>$dbh->err(),query=>$strQuery);
		warn(__PACKAGE__,"-> Database Error : $@ : $strQuery");
		return undef;
	}
	return 1;
}

# set a file expired
# id =>
sub setExpired {
	my $self = shift;
	my $id = shift;
	warn(__PACKAGE__,"-> Invalid id format") && return undef if ($id !~ /^[0-9]+$/);
	my $dbh = $self->_dbh();
	my $strQuery = "UPDATE upload SET expire_date = DATE_ADD(NOW(),INTERVAL -5 SECOND) WHERE id = $id";
	eval {
		my $sth = $dbh->prepare($strQuery);
		$sth->execute();
		$dbh->commit();
	};
	if ($@) {
		$self->setLastError(string=>$dbh->errstr(),code=>$dbh->err(),query=>$strQuery);
		warn(__PACKAGE__,"-> Database Error : $@ : $strQuery");
		return undef;
	}
	return 1;
}

# set a file disabled
# id => file id
# enable => 0 | 1
sub setEnable {
	my $self = shift;
	my %ARGZ = @_;
	warn(__PACKAGE__,"-> require an id") && return undef if ( ! exists($ARGZ{'id'}) || $ARGZ{'id'} !~ /^[0-9]+$/ );
	my $dbh = $self->_dbh();
	my $enable = exists($ARGZ{'enable'}) ? $ARGZ{'enable'} : 1;
	$enable = ( $enable =~ /^[0-1]{1}$/ ) ? $enable : 1;
	my $strQuery = "UPDATE upload SET enable = $enable WHERE id = $ARGZ{'id'}";
	eval {
		my $sth = $dbh->prepare($strQuery);
		$sth->execute();
		$dbh->commit();
	};
	if ($@) {
		$self->setLastError(string=>$dbh->errstr(),code=>$dbh->err(),query=>$strQuery);
		warn(__PACKAGE__,"-> Database Error : $@ : $strQuery");
		return undef;
	}
	return 1;
}

# list download for a file
# id => file id
# results => ARRAYREF
sub listDownload {
	my $self = shift;
	my %ARGZ = @_;
	warn(__PACKAGE__,"-> require an id") && return undef if ( !exists($ARGZ{'id'}) || $ARGZ{'id'} !~ /^[0-9]+$/ );
	warn(__PACKAGE__,"-> require a results") && return undef if ( !exists($ARGZ{'results'}) || ref($ARGZ{'results'}) ne "ARRAY" );
	my $dbh = $self->_dbh();
	my $results = $ARGZ{'results'};
	my $strQuery = "SELECT *, UNIX_TIMESTAMP(date) AS ts_date FROM get WHERE upload_id = $ARGZ{'id'} ORDER BY date DESC";
	eval {
		my $sth = $dbh->prepare($strQuery);
		$sth->execute();
		while ( my $r = $sth->fetchrow_hashref() ) {
			push(@$results,$r);
		}
		$sth->finish();
	};
	if ($@) {
		$self->setLastError(string=>$dbh->errstr(),code=>$dbh->err(),query=>$strQuery);
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
