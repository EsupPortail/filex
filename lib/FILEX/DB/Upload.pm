package FILEX::DB::Upload;
use strict;
use vars qw($VERSION @ISA);
use FILEX::DB::base 1.0;

# inherit FILEX::DB::base
@ISA = qw(FILEX::DB::base);
$VERSION = 1.0;

# days
# DB specific
# fields => [ real_name => 
# file_name
# file_size
# owner
# (opt) content_type
# (opt) get_delivery
# (opt) get_resume
# ]
sub registerNewFile {
	my $self = shift;
	my %ARGZ = @_;
	# must contain : days => n, fields => hash_ref
	warn(__PACKAGE__,"-> Number of days ?") && return undef if ( ! exists($ARGZ{'days'}) );
	warn(__PACKAGE__,"-> Need fields !") && return undef if ( ! exists($ARGZ{'fields'}) || ref($ARGZ{'fields'}) ne "ARRAY");
	# real_name
	# file_name
	# file_size
	# owner
	# ip_address
	# use_proxy (opt)
	# proxy_infos (opt)
	# content_type (opt)
	# get_delivery (opt)
	# get_resume (opt)
	# upload_date (FUNC)
	# expire_date (FUNC)
	my (%f,@cols,@values);
	%f = @{$ARGZ{'fields'}};
	$f{'real_name'} = $self->_dbh->quote($f{'real_name'});
	$f{'file_name'} = $self->_dbh->quote($f{'file_name'});
	$f{'ip_address'} = $self->_dbh->quote($f{'ip_address'}) if ( exists($f{'ip_address'}) );
	# use_proxy && proxy_address
	$f{'use_proxy'} = ( exists($f{'use_proxy'}) && $f{'use_proxy'} == 1 ) ? 1 : 0;
	$f{'proxy_infos'} = ( exists($f{'proxy_infos'}) && defined($f{'proxy_infos'}) ) ? $self->_dbh->quote($f{'proxy_infos'}) : "NULL";
	$f{'file_size'} = $f{'file_size'};
	$f{'owner'} = $self->_dbh->quote($f{'owner'});
	if ( exists($f{'content_type'}) ) {
		$f{'content_type'} = $self->_dbh->quote($f{'content_type'});
	}
	# if upload_date exists assume it is a unix timestamp
	if ( exists($f{'upload_date'}) ) {
		$f{'upload_date'} = "FROM_UNIXTIME($f{'upload_date'})";
		if ( ! exists($f{'expire_date'}) ) {
			$f{'expire_date'} = "DATE_ADD(FROM_UNIXTIME($f{'upload_date'}), INTERVAL $ARGZ{'days'} DAY)"
		} else {
			$f{'expire_date'} = "FROM_UNIXTIME($f{'expire_date'})";
		}
	} else {
		$f{'upload_date'} = "NOW()";
		$f{'expire_date'} = "DATE_ADD(NOW(), INTERVAL $ARGZ{'days'} DAY)";
	}

	while (my ($k,$v) = each(%f)) {
		push(@cols,$k);
		push(@values,$v);
	}
	my $strQuery = "INSERT INTO upload(".join(",",@cols).") VALUES(".join(",",@values).")";
	my $dbh = $self->_dbh();
	my $sth;
 	eval {
		$sth = $dbh->prepare($strQuery);
		$sth->execute();
		$dbh->commit();
	};
	if ($@) {
		$self->setLastError(query=>$strQuery,string=>$dbh->errstr(),code=>$dbh->err());
		warn(__PACKAGE__,"-> Database Error : $@");
		return undef;
	} 
	return 1;
}

# get total user upload file count
sub getUserUploadCount {
	my $self = shift;
	my $user = shift;
	return undef if !$user;
	my $dbh = $self->_dbh();
	my $strQuery = "SELECT COUNT(id) FROM upload WHERE owner = ".$dbh->quote($user);
	my $res;
	eval {
		my $sth = $dbh->prepare($strQuery);
		$sth->execute();
		$res = $sth->fetchrow();
		$sth->finish();
	};
	if ($@) {
		$self->setLastError(query=>$strQuery,string=>$dbh->errstr(),code=>$dbh->err());
		warn(__PACKAGE__,"-> Database Error : $@");
		return undef;
	}
	return $res;
}

# get total user active files
sub getUserActiveCount {
	my $self = shift;
	my $user = shift;
	return undef if !$user;
	my $dbh = $self->_dbh();
	my $strQuery = "SELECT COUNT(id) FROM upload WHERE owner = ".$dbh->quote($user).
	               " AND expire_date > NOW()";
	my $res;
	eval {
		my $sth = $dbh->prepare($strQuery);
		$sth->execute();
		$res = $sth->fetchrow();
		$sth->finish();
	};
	if ($@) {
		$self->setLastError(query=>$strQuery,string=>$dbh->errstr(),code=>$dbh->err());
		warn(__PACKAGE__,"-> Database Error : $@");
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
