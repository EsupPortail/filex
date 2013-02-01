package FILEX::DB::Manage;
use strict;
use vars qw($VERSION @ISA);

use FILEX::DB::base 1.0;

@ISA = qw(FILEX::DB::base);
$VERSION = 1.0;

# owner => user name
# results => ARRAY REF
# [opt] orderby => "field name"
# [opt] order =>  1 (desc) | 0 (asc)
sub getFiles {
	my $self = shift;
	my %ARGZ = @_;
	warn(__PACKAGE__,"require an Array Ref") && return undef if ( !exists($ARGZ{'results'}) || ref($ARGZ{'results'}) ne "ARRAY");
	warn(__PACKAGE__,"require a owner") && return undef if ( !exists($ARGZ{'results'}) || length($ARGZ{'owner'}) == 0);
	my $dbh = $self->_dbh();
	my $res = $ARGZ{'results'};
	my $owner = $dbh->quote($ARGZ{'owner'});

	my $strQuery = "SELECT u.*, ".
	               "UNIX_TIMESTAMP(upload_date) AS ts_upload_date, ".
	               "UNIX_TIMESTAMP(expire_date) AS ts_expire_date, ".
	               "COUNT(g.upload_id) - SUM(g.admin_download) AS download_count, ".
	               "NOW() > expire_date AS expired ".
	               "FROM upload AS u ".
	               "LEFT JOIN get AS g ON u.id = g.upload_id ".
	               "WHERE owner=$owner ".
	               "GROUP BY u.id ";
	my $order_by = ( exists($ARGZ{'orderby'}) && length($ARGZ{'orderby'}) ) ? $ARGZ{'orderby'} : 'upload_date';
	my $order = ( exists($ARGZ{'order'}) ) ? $ARGZ{'order'} : 1;
	$order = ( defined($order) && $order == 1 ) ? "DESC" : "ASC";
	# order by default to 'upload_date'
	# in case of sorting on 'download_count'
	$strQuery .= ($order_by eq "download_count") ? "ORDER BY $order_by $order" : "ORDER BY u.$order_by $order";
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
