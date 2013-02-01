package FILEX::SOAP::Transport;
use strict;
use SOAP::Transport::HTTP;
use FILEX::System::Config;
use FILEX::System::Cookie;

use vars qw(@ISA);
@ISA = qw(SOAP::Transport::HTTP::Apache);

1;

sub request {
	my $self = shift;

	my $request = ($#_ >= 0) ? $_[0] : undef;
	if ( defined($request) ) {
		my $config = FILEX::System::Config->new() or die("Unable to load config file");
		my %cookie = FILEX::System::Cookie::parse($request->headers->header('Cookie'));
		if ( exists($cookie{$config->getCookieName()}) ) {
			my $value = $cookie{$config->getCookieName()}->value;
			$ENV{'FILEX_SID'} = $value if defined($value);
		}
	}

	$self->SUPER::request(@_);
}

sub response {
	my $self = shift;
	my $response = ($#_ >= 0) ? $_[0] : undef;
	if ( defined($response) ) {
		my $config = FILEX::System::Config->new() or die("Unable to load config file");
		if ( exists($ENV{'FILEX_Drop_Cookie'}) && $ENV{'FILEX_Drop_Cookie'} == 1 ) {
			# drop cookie
			my $cookie = FILEX::System::Cookie::generate($config,-value=>"",-expire=>"-1Y");
			$response->headers->push_header('Set-Cookie'=>$cookie);
			delete($ENV{'FILEX_Drop_Cookie'});
		} else {
			if ( exists($ENV{'FILEX_Cookie'}) && defined($ENV{'FILEX_Cookie'}) ) {
				my $cookie = FILEX::System::Cookie::generate($config,-value=>$ENV{'FILEX_Cookie'});
				$response->headers->push_header('Set-Cookie'=>$cookie);
				delete($ENV{'FILEX_Cookie'});
			}
		}
	}
	$self->SUPER::response(@_);
}
