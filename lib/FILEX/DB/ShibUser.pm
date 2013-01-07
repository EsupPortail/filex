package FILEX::DB::ShibUser;
use strict;
use vars qw($VERSION @ISA);
use FILEX::DB::base 1.0;

# inherit FILEX::DB::base
@ISA = qw(FILEX::DB::base);
$VERSION = 1.0;

sub addUser {
	my ($self, $user) = @_;
	$self->doQuery("INSERT INTO shib_user (id, mail, real_name) VALUES (?, ?, ?)",
			$user->{id}, $user->{mail}, $user->{real_name});
}

sub updateUser {
	my ($self, $user) = @_;
	$self->doQuery("UPDATE shib_user SET mail = ?, real_name = ? WHERE id = ?",
			$user->{mail}, $user->{real_name}, $user->{id});
}

sub setUser {
    my ($self, $user) = @_;
    hasUser($self, $user) ? updateUser($self, $user) : addUser($self, $user);
}

sub hasUser {
    my ($self, $user) = @_;
    getAttr($self, $user->{id}, 'id');
}

sub getAttr {
    my ($self, $id, $attr) = @_;
    $self->simpleWhere('shib_user', $attr, id => $id);
}

sub getMail {    
    my ($self, $id) = @_;
    getAttr($self, $id, 'mail');
}
sub getUserRealName {    
    my ($self, $id) = @_;
    getAttr($self, $id, 'real_name');
}
sub getUniqId {    
    my ($self, $id) = @_;
    die "UniqAttrMode is not supported by shibboleth authentication";
}

1;
=pod

=head1 AUTHOR AND COPYRIGHT

FileX - a web file exchange system.

Copyright (c) 2013 Pascal Rigaux

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
