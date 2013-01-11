package FILEX::DB::Manage;
use strict;
use vars qw($VERSION @ISA);

use FILEX::DB::base 1.0;

@ISA = qw(FILEX::DB::base);
$VERSION = 1.0;

# owner_uniq_id => user name
# results => ARRAY REF
# [opt] orderby => "field name"
# [opt] order =>  1 (desc) | 0 (asc)
# [opt] active => 1 | 0 get only active files - non expired -
sub getFiles {
	my $self = shift;
	my %ARGZ = @_;
	warn(__PACKAGE__,"=> require an Array Ref") && return undef if ( !exists($ARGZ{'results'}) || ref($ARGZ{'results'}) ne "ARRAY");
	warn(__PACKAGE__,"=> require a owner_uniq_id") && return undef if ( !exists($ARGZ{'owner_uniq_id'}) || length($ARGZ{'owner_uniq_id'}) == 0);
	my $dbh = $self->_dbh();
	my $res = $ARGZ{'results'};
	my $owner = $dbh->quote($ARGZ{'owner_uniq_id'});
	# show only active files
	my $active = ( exists($ARGZ{'active'}) ) ? $ARGZ{'active'} : 0;
	$active = 0 if ( !defined($active) || ($active != 1) );

	# the query	
	my $strQuery = "SELECT u.*, ".
	               "UNIX_TIMESTAMP(upload_date) AS ts_upload_date, ".
	               "UNIX_TIMESTAMP(expire_date) AS ts_expire_date, ".
	               "COUNT(g.upload_id) - SUM(g.admin_download) AS download_count, ".
	               "NOW() > expire_date AS expired ".
	               "FROM upload AS u ".
	               "LEFT JOIN get AS g ON u.id = g.upload_id ".
	               "WHERE owner_uniq_id=$owner ";
	if ( $active ) {
		$strQuery .= "AND expire_date >= NOW() ";
	}
	$strQuery .=   "GROUP BY u.id ";
	# order
	my $order_by = ( exists($ARGZ{'orderby'}) && length($ARGZ{'orderby'}) ) ? $ARGZ{'orderby'} : 'upload_date';
	my $order = ( exists($ARGZ{'order'}) ) ? $ARGZ{'order'} : 1;
	$order = ( defined($order) && $order == 1 ) ? "DESC" : "ASC";
	# order by default to 'upload_date'
	# in case of sorting on 'download_count'
	$strQuery .= ($order_by eq "download_count") ? "ORDER BY $order_by $order" : "ORDER BY u.$order_by $order";

	my $rows = $self->queryAllRows($strQuery) or return undef;
	push(@$res, @$rows);
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
