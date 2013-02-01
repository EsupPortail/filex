package FILEX::System::Mail;
use vars qw($VERSION);
use MIME::Entity;
use MIME::Words;
use Net::SMTP;

$VERSION = 1.0;

# server => server name
# opt hello => identify string
# opt timeout => timeout
sub new {
	my $this = shift;
	my $class = ref($this) || $this;
	my $self = {
		'SmtpServer' => undef,
		'Hello' => undef,
		'Timeout' => undef,
	};
	my %ARGZ = @_;
	if ( ! exists($ARGZ{'server'}) || length($ARGZ{'server'}) <= 0 ) {
		warn(__PACKAGE__,"-> Require a server !");
		return undef;
	}
	$self->{'SmtpServer'} = $ARGZ{'server'};
	$self->{'Hello'} = $ARGZ{'hello'} if ( defined($ARGZ{'hello'}) && length($ARGZ{'hello'}) > 0);
	$self->{'Timeout'} = $ARGZ{'timeout'} if ( defined($ARGZ{'timeout'}) );
	return bless($self,$class);
}

# from
# to
# subject
# charset
# encoding
# type
# content
sub send {
	my $self = shift;
	my %ARGZ = @_;
	my %smtp_opts;
	$smtp_opts{'Hello'} = $self->{'Hello'} if defined($self->{'Hello'});
	$smtp_opts{'Timeout'} = $self->{'Timeout'} if defined($self->{'Timeout'});
	my $smtp = Net::SMTP->new($self->{'SmtpServer'},%smtp_opts);
	if ( !$smtp ) {
		warn(__PACKAGE__,"-> Unable to connect to Smtp server : $self->{'SmtpServer'}");
		return undef;
	}
	# create the message
	# encoding
	$ARGZ{'charset'} = "ISO-8859-1" if ( ! exists($ARGZ{'charset'}) );
	$ARGZ{'encoding'} = "quoted-printable" if ( ! exists($ARGZ{'encoding'}) );
	$ARGZ{'type'} = "text/plain" if ( ! exists($ARGZ{'type'}) );
	# create email
	my $mesg = MIME::Entity->build(
		Charset=>$ARGZ{'charset'},
		Encoding=>$ARGZ{'encoding'},
		Type=>$ARGZ{'type'},
		From=>$ARGZ{'from'},
		Subject=>MIME::Words::encode_mimewords($ARGZ{'subject'},Charset=>$ARGZ{'charset'}),
		To=>$ARGZ{'to'},
		Data=>$ARGZ{'content'}
	);
	$mesg->sync_headers(Length=>'COMPUTE');
	# send
	$smtp->mail($ARGZ{'from'});
	$smtp->to($ARGZ{'to'});
	my $r = $smtp->data($mesg->stringify());
	$smtp->quit();
	return ( $r == 1 ) ? 1 : undef;
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
