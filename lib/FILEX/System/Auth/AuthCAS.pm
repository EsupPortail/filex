package FILEX::System::Auth::AuthCAS;
use strict;
use vars qw(@ISA $VERSION);
use FILEX::System::Auth::base 1.0;
use FILEX::System::Auth::CAS;

# inherit FILEX::System::Auth::base
@ISA = qw(FILEX::System::Auth::base);
$VERSION = 1.0;

# override constructor
sub new {
	my $class = shift;
	# call the parent constuctor
	my $self = $class->SUPER::new(@_);
	# init the cas client
	$self->{'_cas_'} = FILEX::System::Auth::CAS->new(casUrl=>$self->_config->getCasServer());
	# reconsecrate
	bless($self,$class);
	return $self;
}

# simple private var accessor
sub _cas {
	my $self = shift;
	return $self->{'_cas_'};
}

sub needRedirect {
	return 1;
}

sub getRedirect {
	my $self = shift;
	my $url = shift;
	return $self->_cas->getServerLoginURL($url);
}

sub processAuth {
	my $self = shift;
	my %ARGZ = @_;
	warn(__PACKAGE__,"-> require an url") && return undef if ( !exists($ARGZ{'currenturl'}) || !defined($ARGZ{'currenturl'}) );
	warn(__PACKAGE__,"-> require a ticket") && return undef if ( !exists($ARGZ{'ticket'}) || !defined($ARGZ{'ticket'}) );
	my $user = $self->_cas->validateST($ARGZ{'currenturl'},$ARGZ{'ticket'});
	$self->_set_error($self->_cas->get_errors()) if ( !defined($user) );
	return $user;
}

sub requireParam {
	return qw(ticket currenturl);
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
