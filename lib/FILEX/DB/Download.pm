package FILEX::DB::Download;
use strict;
use vars qw($VERSION @ISA);
use FILEX::DB::base 1.0;

# inherit FILEX::DB::base
@ISA = qw(FILEX::DB::base);
$VERSION = 1.0;

# log current download
sub logCurrentDownload {
	my $self = shift;
	my %ARGZ = @_;
	warn(__PACKAGE__,"-> Need fields !") && return undef if ( !exists($ARGZ{'fields'}) || ref($ARGZ{'fields'}) ne "ARRAY" );
	my %f = @{$ARGZ{'fields'}};
	my $strQuery = "INSERT INTO current_download (download_id, upload_id, start_date, ip_address) ".
	               "VALUES (".$self->_dbh->quote($f{'download_id'}).",".$f{'upload_id'}.",".
	               "NOW(),".$self->_dbh->quote($f{'ip_address'}).")";
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

# delete current download
sub delCurrentDownload {
	my $self = shift;
	my $download_id = shift;
	my $strQuery = "DELETE FROM current_download WHERE download_id = ".$self->_dbh->quote($download_id);
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

# require an Array ref
sub currentDownloads {
	my $self = shift;
	my $res = shift;
	my $dbh = $self->_dbh();
	my $strQuery = "SELECT u.id,u.real_name,u.owner,u.file_size,UNIX_TIMESTAMP(cd.start_date) as start_date,cd.ip_address ".
	               "FROM upload AS u, current_download AS cd ".
	               "WHERE u.id = cd.upload_id ".
	               "ORDER BY u.id"; 
	eval {
		my $sth = $dbh->prepare($strQuery);
		$sth->execute();
		while ( my $row = $sth->fetchrow_hashref() ) {
			push(@$res,$row);
		}
	};
	if ($@) {
		$self->setLastError(query=>$strQuery,string=>$dbh->errstr(),code=>$dbh->err);
		warn(__PACKAGE__,"-> Database Error : $@ : $strQuery");
		return undef;
	}
	return 1;
}

# current non expired files
sub currentFiles {
	my $self = shift;
	my %ARGZ = @_;
	warn(__PACKAGE__,"require an Array Ref") && return undef if ( !exists($ARGZ{'results'}) || ref($ARGZ{'results'}) ne "ARRAY");
	my $dbh = $self->_dbh();
	my $res = $ARGZ{'results'};

	my $strQuery = "SELECT u.*, ".
	               "UNIX_TIMESTAMP(upload_date) AS ts_upload_date, ".
	               "UNIX_TIMESTAMP(expire_date) AS ts_expire_date, ".
                 "COUNT(g.upload_id) - SUM(g.admin_download) AS download_count ".
	               "FROM upload AS u ".
	               "LEFT JOIN get AS g ON u.id = g.upload_id ".
	               "WHERE u.expire_date > NOW() ".
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
