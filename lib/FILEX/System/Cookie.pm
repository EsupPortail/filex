package FILEX::System::Cookie;
use strict;
use CGI::Cookie;

sub parse {
	my $cookie_string = shift or return undef;
	return CGI::Cookie->parse($cookie_string);
}

sub raw_generate {
	my $c = CGI::Cookie->new(@_);
	return $c->as_string();
}

sub generate {
	my $config = shift or return undef && warn(__PACKAGE__,"=> require a FILEX::System::Config");
	return undef && warn(__PACKAGE__,"=> require a FILEX::System::Config") if (ref($config) ne "FILEX::System::Config");
	# override
	my %args = @_;
	$args{'-name'} = $config->getCookieName();
	$args{'-path'} = $config->getCookiePath();
	return raw_generate(%args);
}
1;
