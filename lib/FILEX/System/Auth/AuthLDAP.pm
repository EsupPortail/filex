package FILEX::System::Auth::AuthLDAP;
use strict;
use vars qw(@ISA $VERSION);
use FILEX::System::Auth::base 1.0;
use Net::LDAP;

# inherit FILEX::System::Auth::base
@ISA = qw(FILEX::System::Auth::base);
$VERSION = 1.0;

sub needRedirect {
	return 0;
}

sub getRedirect {
	return undef;
}

sub processAuth {
	my $self = shift;
	my %ARGZ = @_;
	warn(__PACKAGE__,"-> requre a ldap object") && return undef if ( !exists($ARGZ{'ldap'}) || !defined($ARGZ{'ldap'}) );
	warn(__PACKAGE__,"-> require a login") && return undef if ( !exists($ARGZ{'login'}) || !defined($ARGZ{'login'}) );
	warn(__PACKAGE__,"-> require a password") && return undef if ( !exists($ARGZ{'password'}) || !defined($ARGZ{'password'}) );
	my $ldap = $ARGZ{'ldap'};
	# step 1 - find user dn switch login
	my $uid = $ARGZ{'login'};
	my $dn = $ldap->getUserDn($uid);
	if ( ! $dn ) {
		$self->_set_error("user does not exists");
		return undef;
	}
	# step 2 - attempt to bind using user dn + password
	my $ldap_bind = Net::LDAP->new($self->_config->getLdapServerUrl());
	if ( ! $ldap_bind ) {
		$self->_set_error("$@");
		return undef;
	}
	my $mesg = $ldap_bind->bind($dn,password=>$ARGZ{'password'});
	if ( $mesg->is_error() ) {
		$self->_set_error($mesg->error());
		return undef;
	}	
	$ldap_bind->unbind();

	return $uid;
}

sub requireParam {
	return qw(ldap login password);
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
