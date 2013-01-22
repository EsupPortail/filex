package FILEX::System::Auth::base;
use strict;
use vars qw($VERSION);

use FILEX::System::Config;

$VERSION=1.0;

#
sub new {
	my $this = shift;
	my $class = ref($this) || $this;
	my $self = {
		_config_ => undef,
		_error_ => undef,
	};
	$self->{'_config_'} = FILEX::System::Config->instance();
	bless($self,$class);
	return $self;
}

# private method to get FILEX::System::Config object
sub _config {
	my $self = shift;
	return $self->{'_config_'};
}

sub get_getUserInfo {
    undef;
}

sub get_ruleMatcher {
    undef;
}


# the Auth object can be stateful:
# after initial authentication, it can save its params in the session
sub saveInSession {}
# then it can restore its params from session
sub readFromSession {}


sub needRedirect {
	warn(__PACKAGE__,"-> needRedirect method need to be overriden and must return 0 or 1");
}

sub getRedirect {
	warn(__PACKAGE__,"-> getRedirect method need to be overriden and must return an url. Get redirect always receive the current url at first parameter");
}

sub processAuth {
	warn(__PACKAGE__,"-> processAuth method need to be overriden and must return a username or undef.");
}

sub requireParam {
	warn(__PACKAGE__,"-> requireParam method need to be overriden and must return an array of parameters needed for processAuth Valid parameters are : currenturl, ldap, request, ticket, login, password");
}

sub _set_error {
	my $self = shift;
	$self->{'_error_'} = shift;
}

sub get_error {
	my $self = shift;
	return $self->{'_error_'};
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
