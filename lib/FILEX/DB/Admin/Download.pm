package FILEX::DB::Admin::Download;
use strict;
use vars qw($VERSION @ISA);
use FILEX::DB::base 1.0;

# inherit FILEX::DB::base
@ISA = qw(FILEX::DB::base);
$VERSION = 1.0;

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
		$sth->finish();
	};
	if ($@) {
		$self->setLastError(query=>$strQuery,string=>$dbh->errstr(),code=>$dbh->err);
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
