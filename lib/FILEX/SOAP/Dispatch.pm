package FILEX::SOAP::Dispatch;
use strict;

use constant FILEX_CONFIG_NAME => "FILEXConfig";

use FILEX::SOAP::Transport;
use FILEX::System::Config;
use FILEX::System::Cookie;
use FILEX::SOAP::Test;
use SOAP::Transport::HTTP;
#use SOAP::Transport::HTTP;
#my $server = FILEX::SOAP::Transport->dispatch_with({'urn:FILEX'=>'FILEX::SOAP::Test'});
my $server = SOAP::Transport::HTTP::Apache->dispatch_with({'urn:FILEX'=>'FILEX::SOAP::Test'});

sub handler {
	# first arg = Apache request
	my $req = $_[0];
	my $config;
	# we can check for cookie and set cookie here
	if ( ! defined($FILEX::System::Config::ConfigPath) ) {
		$FILEX::System::Config::ConfigPath = $req->dir_config(FILEX_CONFIG_NAME);
	}
	$config = FILEX::System::Config->new() 
			or die(sprintf("Unable to load config file : %s !",$FILEX::System::Config::ConfigPath));
	warn "Start Apache Handler :",$req->header_in('Cookie');
	# init parameters
warn("INIT PARAMS");
	%FILEX::SOAP::Test::PARAMS = ();
	my $in_cookie = $req->header_in('Cookie');
	my %cookie;
	my $sid = undef; # session id
	if ( $in_cookie ) {
		%cookie = FILEX::System::Cookie::parse($in_cookie);
		if ( exists($cookie{$config->getCookieName()}) ) {
			$sid = $cookie{$config->getCookieName()}->value;
			$FILEX::SOAP::Test::PARAMS{'in_cookie'} = $sid if defined($sid);
		}
	}
	$server->handler(@_); 
warn("PARAMS : ",keys(%FILEX::SOAP::Test::PARAMS));
	# set cookie if needed
	if ( exists($FILEX::SOAP::Test::PARAMS{'out_cookie'}) && defined($FILEX::SOAP::Test::PARAMS{'out_cookie'}) ) {
		my $out_value = $FILEX::SOAP::Test::PARAMS{'out_cookie'};
warn("setting new cookie : ",$out_value);
		my $out_cookie = FILEX::System::Cookie::generate($config,-value=>$out_value);
warn("new cookie ? $out_cookie");
		$req->header_out('Set-Cookie'=>$out_cookie);
	} else {
warn("no cookie to set : $sid !");
		# drop cookie if no out_cookie && in_cookie
		if ( defined($sid) ) {
warn("dropping cookie");
			# drop cookie if previous defined
			my $out_cookie = FILEX::System::Cookie::generate($config,-value=>"",-expire=>"-1Y");
			$req->header_out('Set-Cookie'=>$out_cookie);
		}
	}
	$req->send_http_header();
	warn "End Apache Handler : ",$req->headers_out->{'Set-Cookie'};
	warn keys(%FILEX::SOAP::Test::PARAMS);
}

1;
