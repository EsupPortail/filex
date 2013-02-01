package FILEX::DB::Get;
use strict;
use vars qw($VERSION @ISA);
use FILEX::DB::base 1.0;

# inherit FILEX::DB::base
@ISA = qw(FILEX::DB::base);
$VERSION = 1.0;

# file_name => 
# results => ref to hash
sub getFileInfos {
	my $self = shift;
	my %ARGZ = @_;
	return undef && warn(__PACKAGE__,"-> Give me a file_name") if ( !exists($ARGZ{'file_name'}) );
	return undef && warn(__PACKAGE__,"-> results must be a hash ref") if ( !exists($ARGZ{'results'}) || ref($ARGZ{'results'}) ne "HASH" );
	
	my $strQuery = "SELECT * FROM upload WHERE expire_date >= NOW() AND file_name = ".$self->_dbh->quote($ARGZ{'file_name'});
	my $dbh = $self->_dbh();
	my ($sth,$res);
	eval {
		$sth = $dbh->prepare($strQuery);
		$sth->execute();
		$res = $sth->fetchrow_hashref();
		$sth->finish();
	};
	if ($@) {
		$self->setLastError(query=>$strQuery,string=>$dbh->errstr(),code=>$dbh->err());
		warn(__PACKAGE__,"-> Database Error : $@ : $strQuery");
		return undef;
	}
	# copy results
	while ( my ($k,$v) = each(%$res) ) {
		$ARGZ{'results'}->{$k} = $v;
	}
	return 1;
}

# retrieve file info with expires time computation
# file_name => || id =>
# results => \%hash
sub getFileInfosEx {
	my $self = shift;
	my %ARGZ = @_;
	my $file_name = $ARGZ{'file_name'} if exists($ARGZ{'file_name'});
	my $id = $ARGZ{'id'} if exists($ARGZ{'id'});
	return undef && warn(__PACKAGE__,"-> Give me a file_name or an id") if ( !$file_name && !$id );
	return undef && warn(__PACKAGE__,"-> results must be a hash ref") if ( !exists($ARGZ{'results'}) || ref($ARGZ{'results'}) ne "HASH" );
	
	my $dbh = $self->_dbh();
	my $strQuery = "SELECT *, (NOW() > expire_date) AS expired, ".
	               "UNIX_TIMESTAMP(upload_date) AS ts_upload_date, ".
	               "UNIX_TIMESTAMP(expire_date) AS ts_expire_date ".
	               "FROM upload ";
	if ( $file_name ) {
		$strQuery .= "WHERE file_name=".$dbh->quote($file_name);
	} else {
		$strQuery .= "WHERE id=$id";
	}
	my $res;
	eval {
		my $sth = $dbh->prepare($strQuery);
		$sth->execute();
		$res = $sth->fetchrow_hashref();
		$sth->finish();
	};
	if ($@) {
		$self->setLastError(query=>$strQuery,string=>$dbh->errstr(),code=>$dbh->err());
		warn(__PACKAGE__,"-> Database Error : $@");
		return undef;
	}
	# copy results
	my $k;
	foreach $k ( keys(%$res) ) {
		$ARGZ{'results'}->{$k} = $res->{$k};
	}
	return 1;
}

# record
sub log {
	my $self = shift;
	my %ARGZ = @_;
	warn(__PACKAGE__,"-> Need fields !") && return undef if ( !exists($ARGZ{'fields'}) || ref($ARGZ{'fields'}) ne "ARRAY" );
	my (%f,@c,@v);
	%f = @{$ARGZ{'fields'}};
	$f{'ip_address'} = $self->_dbh->quote($f{'ip_address'});
	$f{'proxy_infos'} = ( exists($f{'proxy_infos'}) && defined($f{'proxy_infos'}) ) ? $self->_dbh->quote($f{'proxy_infos'}) : "NULL";
	$f{'use_proxy'} = ( exists($f{'use_proxy'}) && $f{'use_proxy'} == 1 ) ? 1 : 0;
	$f{'date'} = "NOW()";
	$f{'canceled'} = 1 if exists($f{'canceled'});
	while ( my ($k,$v) = each(%f) ) {
		push(@c,$k);
		push(@v,$v);
	}
	my $strQuery = "INSERT INTO get(".join(",",@c).") VALUES (".join(",",@v).")";
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
