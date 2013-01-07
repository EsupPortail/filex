package FILEX::System::LDAP;
use strict;
use FILEX::System::Config;
use vars qw($VERSION);
use Net::LDAP;

$VERSION = 1.0;

# simple wrapper for handling ldap query

# 
# 
# 
sub new {
	my $this = shift;
	my $class = ref($this) || $this;

	my %ARGZ = @_;

	my $self = {
		_config_ => undef,
		_ldap_ => undef,
		_bind_ => undef,
	};

	$self->{'_config_'} = FILEX::System::Config->instance();

	bless($self,$class);
	return $self;
}

sub DESTROY {
	my $self = shift;
	if ( ref($self) && ref($self->{'_ldap_'}) ) {
		$self->{'_ldap_'}->unbind() && $self->{'_ldap_'}->disconnect();
	}
}

sub _connect {
	my $self = shift;
	# attempt to connect
	if ( !defined($self->{'_ldap_'}) ) {
		$self->{'_bind_'} = undef;
		$self->{'_ldap_'} = Net::LDAP->new( [ split(',',$self->{'_config_'}->getLdapServerUrl()) ] )
			or die(__PACKAGE__," => unable to connect to ldap server : ",$@);
	}
	# already binded ?
	return 1 if (defined($self->{'_bind_'}) && $self->{'_bind_'} == 1);
	# attempt to bind
	my $mesg;
	my $binddn = $self->{'_config_'}->getLdapBindDn();
	my $password = $self->{'_config_'}->getLdapBindPassword();

	if ( $binddn && length($binddn) > 0 ) {
		$mesg = $self->{'_ldap_'}->bind($binddn,password=>$password);
	} else {
		# anonymous
		$mesg = $self->{'_ldap_'}->bind();
	}

	# error binding
	die(__PACKAGE__," => unable to bind to ldap server : ",$mesg->error()) if ($mesg->is_error());
	$self->{'_bind_'} = 1;
	return 1;
}

# get the underlying LDAP object
sub srv {
	my $self = shift;
	$self->_connect();
	return $self->{'_ldap_'};
}

sub _searchRaw {
  my ($self, $uid, $attrs) = @_;

  my $ldap = $self->srv();
  my $baseSearch = $self->{'_config_'}->getLdapSearchBase();
  my $uidAttr = $self->{'_config_'}->getLdapUidAttr();
  my %searchArgz;
  $searchArgz{'base'} = $baseSearch if ( $baseSearch && length($baseSearch) );
  $searchArgz{'scope'} = "sub";
  $searchArgz{'attrs'} = $attrs;
  $searchArgz{'filter'} = "($uidAttr=$uid)";
  $searchArgz{'sizelimit'} = 1;
  my $mesg = $ldap->search(%searchArgz);
  if ( $mesg->is_error() || $mesg->code() ) {
    warn(__PACKAGE__,"-> LDAP error : ",$mesg->error());
    return undef;
  }
  return $mesg;
}

# get user DN
sub getUserDn {
	my $self = shift;
  my $uid = shift;

  my $uidAttr = $self->{'_config_'}->getLdapUidAttr();
  my $mesg = $self->_searchRaw($uid, [$uidAttr]);

 # only one value can be returned
  my $r = $mesg->as_struct();
  my @k = keys(%$r);
  return $k[0];
}

# check if user exists into ldap database
sub userExists {
  my $self = shift;
  my $uid = shift;

  my $uidAttr = $self->{'_config_'}->getLdapUidAttr();
  my $mesg = $self->_searchRaw($uid, [$uidAttr]);

  # count
  return $mesg->count();
}

# require uname
# uid => uid
# attrs => ['attr1','attr2','attr3 ...]
# return hash to ref containing attributes
sub getUserAttrs {
  my $self = shift;
  my %ARGZ = @_;
  my $uid = $ARGZ{'uid'} if exists($ARGZ{'uid'});
  return undef if (! defined($uid) || length($uid) <= 0);
  my $attrs = $ARGZ{'attrs'} if (exists($ARGZ{'attrs'}) && ref($ARGZ{'attrs'}) eq "ARRAY");
  return undef if !defined($attrs);

  my $mesg = $self->_searchRaw($uid, $attrs);

  # fetch datas if found then only one entry is returned !
  my $h = $mesg->as_struct();
  my ($dn,$res) = each(%$h);
  return $res;
}

# get mail helper method
# require uname
sub getMail {
  my $self = shift;
  my $uid = shift;
	my $mailAttr = $self->{'_config_'}->getLdapMailAttr();
	my $res = $self->getUserAttrs(uid=>$uid,attrs=>[$mailAttr]);
	return undef if !$res;
	return $res->{$mailAttr}->[0];
}

# require
# uid => user id
# gid => group name
sub inGroup {
	my $self = shift;
	my %ARGZ = @_;
	warn(__PACKAGE__,"-> require a user id !") && return undef if ( !exists($ARGZ{'uid'}) || length($ARGZ{'uid'}) <= 0 );
	my $uid = $ARGZ{'uid'};
	warn(__PACKAGE__,"-> require a group name !") && return undef if ( !exists($ARGZ{'gid'})||length($ARGZ{'gid'}) <= 0 );
	my $gid = $ARGZ{'gid'};

	my $ldap = $self->srv();
  my $baseSearch = $self->{'_config_'}->getLdapSearchBase();
  my $uidAttr = $self->{'_config_'}->getLdapUidAttr();
	my $ldapQuery = $self->{'_config_'}->getLdapGroupQuery();
	# replace %U (username), %G (group name), %D (user dn)
	# check if it require a DN
	if ( $ldapQuery =~ /\%D/ ) {
		my $dn = $self->getUserDn($uid);
		$ldapQuery =~ s/\%D/$dn/;
	}
	# replace the first %U
	$ldapQuery =~ s/\%U/$uid/;
	# replace the first %G
	$ldapQuery =~ s/\%G/$gid/;

	# do the rest
	my %searchArgz;
  $searchArgz{'base'} = $baseSearch if ( $baseSearch && length($baseSearch) );
  $searchArgz{'scope'} = "sub";
	$searchArgz{'filter'} = $ldapQuery;
	my $mesg = $ldap->search(%searchArgz);
  if ( $mesg->is_error() || $mesg->code() ) {
    warn(__PACKAGE__,"-> LDAP error : ",$mesg->error());
    return undef;
  }
	# return
	return $mesg->count();
}

# 
# generic ldap query
# uid
# query
sub inQuery {
	my $self = shift;
	my %ARGZ = @_;
	warn(__PACKAGE__,"-> require a user id !") && return undef if ( !exists($ARGZ{'uid'}) || length($ARGZ{'uid'}) <= 0 );
	my $uid = $ARGZ{'uid'};
	warn(__PACKAGE__,"-> require a query !") && return undef if ( !exists($ARGZ{'query'})||length($ARGZ{'query'}) <= 0 );
	my $query = $ARGZ{'query'};

 	my $ldap = $self->srv();
  my $baseSearch = $self->{'_config_'}->getLdapSearchBase();
  my $uidAttr = $self->{'_config_'}->getLdapUidAttr();
	# build the filter
	my $filter = "(&($uidAttr=$uid)$query)";
  my %searchArgz;
  $searchArgz{'base'} = $baseSearch if ( $baseSearch && length($baseSearch) );
  $searchArgz{'scope'} = "sub";
  $searchArgz{'filter'} = $filter;
  $searchArgz{'attrs'} = [$uidAttr];
  my $mesg = $ldap->search(%searchArgz);
  if ( $mesg->is_error() || $mesg->code() ) {
    warn(__PACKAGE__,"-> LDAP error : ",$mesg->error()," => $filter");
    return undef;
  }
	# return count
	return $mesg->count();
}

# 
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
