package FILEX::System::Purge;
use strict;
use vars qw($VERSION);

use FILEX::System::Config;
use FILEX::System::LDAP; 
use FILEX::DB::Purge;
use FILEX::DB::Upload;
use File::Spec;
use POSIX qw(strftime);

sub new {
	my $this = shift;
	my $class = ref($this)||$this;
	my $self = {
		_config_ => undef,
		_db_ => undef,
		_last_error_ => undef,
	};
	# initialize
	$self->{'_config_'}	= FILEX::System::Config->new() or die("Unable to load config file !");
	$self->{'_db_'} = eval { FILEX::DB::Purge->new(); }; 
	die($@) if ($@);

	return bless($self,$class);
}

sub getLastError {
	my $self = shift;
	return $self->{'_last_error_'};
}

# wrapper arround FILEX::DB::Purge->getExpiredFiles(ARRAY REF)
sub getExpiredFiles {
	my $self = shift;
	my $res = $self->{'_db_'}->getExpiredFiles(shift);
	$self->{'_last_error_'} = $self->{'_db_'}->getLastErrorString() if (!$res);
	return $res;
}

# purge a given file
# require a file id
# return a FILEX::DB::Upload object
sub purge {
	my $self = shift;
	my $file_id = shift;
	my $bFileNotFound = 0;
	$self->{'_last_error_'} = "";
	# first of all, get the file infos
	my $upload = eval { FILEX::DB::Upload->new(id=>$file_id); };
	if ($@) {
		$self->{'_last_error_'} = $@;
		return undef;
	}
	if ( !$upload->exists() ) {
		$self->{'_last_error_'} = "File identified by $file_id does not exists !";
		return undef;
	}
	# file already deleted ?
	if ( $upload->getDeleted() ) {
		$self->{'_last_error_'} = "File identified by $file_id (".$upload->getRealName().") already deleted !";
		return undef;
	}
	# file currently downloaded ?
	if ( $upload->isDownloaded() ) {
		$self->{'_last_error_'} = "File identified by $file_id (".$upload->getRealName().") currently downloaded !";
		return undef;
	}
	my $path = File::Spec->catfile($self->{'_config_'}->getFileRepository(),$upload->getFileName());
	# file exists on disk ?
	if ( ! -f $path ) {
		$bFileNotFound = 1;
		$self->{'_last_error_'} = "File $path does not exists !";
	}
	# mark as deleted
	$upload->setDeleted(1);
	# save file state
	if ( ! $upload->save() ) {
		$self->{'_last_error_'} = "Cannot mark as deleted : ".$upload->getLastErrorString();
		return undef;
	}
	# realy delete file
	if ( !$bFileNotFound ) {
		unlink($path) or $self->{'_last_error_'} = "Cannot delete $path !";
	}
	return $upload;
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
