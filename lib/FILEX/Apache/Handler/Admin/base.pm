package FILEX::Apache::Handler::Admin::base;
use strict;
use vars qw($VERSION);


$VERSION = 1.0;
# global Action File

sub new {
	my $this = shift;
	my $class = ref($this) || $this;
	my %ARGZ = @_;
	my $self = {
		_SYS_ => undef,
		_ID_=> undef,
		_LABEL_ => undef,
		_DNAME_ => undef
	};
	$self->{'_SYS_'} = $ARGZ{'sys'} if exists($ARGZ{'sys'});
	$self->{'_ID_'} = $ARGZ{'id'} if exists($ARGZ{'id'});
	$self->{'_LABEL_'} = $ARGZ{'label'} if exists($ARGZ{'label'});
	$self->{'_DNAME_'} = $ARGZ{'dname'} if exists($ARGZ{'dname'});
	die(__PACKAGE__,"-> Require a FILEX::System object") if (ref($self->{'_SYS_'}) ne "FILEX::System");
	die(__PACKAGE__,"-> Require an id") if !defined($self->{'_ID_'});
	die(__PACKAGE__,"-> Require a label") if !defined($self->{'_LABEL_'});
	die(__PACKAGE__,"-> Require a dname") if !defined($self->{'_DNAME_'});
	return bless($self,$class);
}

sub getActionId { my $self = shift; return $self->{'_ID_'}; }
sub getActionLabel { my $self = shift; return $self->{'_LABEL_'}; }
sub getDispatchName { my $self = shift; return $self->{'_DNAME_'}; }
sub sys { my $self = shift; return $self->{'_SYS_'}; }
sub process { warn(__PACKAGE__,"-> need to be override"); return undef; } 

# generate query string with given parameters
sub genQueryString { 
	my $self = shift;
	# get args
	my %QS = @_;
	my $dname = $self->getDispatchName();
	my $aid = $self->getActionId();
	# the hash 	
	my $q = { $dname => $aid };
	# enum parameters
	my ($k,$v);
	while ( ($k,$v) = each(%QS) ) {
		next if $k eq $dname;
		$q->{$k} = $v;
	}
	return $self->{'_SYS_'}->genQueryString($q);
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
