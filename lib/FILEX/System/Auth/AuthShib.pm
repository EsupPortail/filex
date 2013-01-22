package FILEX::System::Auth::AuthShib;
use strict;
use vars qw(@ISA $VERSION);
use FILEX::System::Auth::base 1.0;
use HTTP::Headers;
use FILEX::DB::ShibUser;
use FILEX::System::RuleMatcherShib;

# inherit FILEX::System::Auth::base
@ISA = qw(FILEX::System::Auth::base);
$VERSION = 1.0;

sub needRedirect {
	return 0;
}

sub getRedirect {
	return undef;
}

sub get_getUserInfo {
    my ($self) = @_;
    eval { $self->{_db_} ||= FILEX::DB::ShibUser->new() };
    warn(__PACKAGE__,"-> Unable to Load FILEX::DB::ShibUser object : $@") if ($@);
    return $self->{_db_};
}


# the Auth object is stateful:
# after initial authentication, it saves its params in the session
sub saveInSession {
    my ($self, $session) = @_;
    $session->setParam(shib_attrs => $self->{_ruleMatcher_}->attrs);    
}
# then it can restore its params from session
sub readFromSession {
    my ($self, $session) = @_;
    $self->_create_ruleMatcher($session->getParam('shib_attrs'));
}


sub get_ruleMatcher {
    my ($self) = @_;
    return $self->{_ruleMatcher_};
}

sub _create_ruleMatcher {
    my ($self, $shib_attrs) = @_;
    $self->{_ruleMatcher_} = FILEX::System::RuleMatcherShib->new(attrs => $shib_attrs);
}

sub _computeAttrs {
    my ($headers) = @_;
    join('', sort map {
	"$_=$headers->{$_}\n";
    } grep {
	!/^(Accept|Accept-Charset|Accept-Encoding|Accept-Language|Accept-Datetime|Authorization|Cache-Control|Connection|Cookie|Content-Length|Content-MD5|Content-Type|Date|Expect|From|Host|If-Match|If-Modified-Since|If-None-Match|If-Range|If-Unmodified-Since|Max-Forwards|Pragma|Proxy-Authorization|Range|Referer|TE|Upgrade|User-Agent|Via|Warning)$/ 
	  && !/^(X-.*|Shib-Application-ID|Shib-Authentication-Instant|Shib-AuthnContext-Decl|Shib-Session-ID|Shib-Assertion-Count|Shib-Authentication-Method|Shib-AuthnContext-Class)$/;
    } keys %$headers);
}

sub _computeUser {
    my ($self, $headers) = @_;

    return { 
	id => $headers->{'eppn'},
	mail => $headers->{$self->{'_config_'}->getMailAttr},
	real_name => $headers->{$self->{'_config_'}->getUsernameAttr},
    };
}

sub processAuth {
	my $self = shift;
	my %ARGZ = @_;
	warn(__PACKAGE__,"-> requre a headers object") && return undef if ( !exists($ARGZ{'headers'}) || !defined($ARGZ{'headers'}) );

	my $headers = $ARGZ{'headers'};

	my $shib_user = $self->_computeUser($headers);
	$self->get_getUserInfo->setUser($shib_user);

	my $shib_attrs = _computeAttrs($headers);
	#print $shib_attrs;
	$self->_create_ruleMatcher($shib_attrs);

	return $shib_user->{id};
}

sub requireParam {
	return qw(headers);
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
