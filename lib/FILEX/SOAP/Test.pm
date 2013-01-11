package FILEX::SOAP::Test;
use strict;
use FILEX::System::Session;
use FILEX::System::LDAP;
use FILEX::System::Auth::AuthLDAP;
use FILEX::System::Auth::CAS;
use FILEX::System::Quota;
use FILEX::System::User;
use FILEX::DB::Manage;

# use to communicate with the up level
use vars qw(%PARAMS);

sub new {
	warn __PACKAGE__,"New called !";
}

# login thru ldap
# return : nothing
sub loginLDAP {
	my $self = shift;
	my $username = shift;
	my $password = shift;
	my $filex_ldap = eval { FILEX::System::LDAP->new(); };
	die SOAP::Fault->faultcode('Server.RuntimeError')
		->faultstring("Unable to access ldap sub-system")
		->faultdetail($@) if $@;
	my $auth_ldap = FILEX::System::Auth::AuthLDAP->new() or die SOAP::Fault->faultcode('Server.RuntimeError')->faultstring("Unable to load LDAP Authentication module");
	my $result = $auth_ldap->processAuth(ldap=>$filex_ldap,login=>$username,password=>$password);
	die SOAP::Fault->faultcode('Server.AuthError')
		->faultstring("Unable to authenticate user $username")
		->faultdetail($auth_ldap->get_error()) if !$result;
	# start session
	my $session = _checkAccess(0); #FILEX::System::Session->new();
	if ( $session->getSid() ) {
		warn "Already have session : ",$session->getSid(),"\n";
		$session->drop();
	}
	if ( $session->start() ) {
		$session->data()->{'username'} = $result;
		#$ENV{'FILEX_Cookie'} = $session->getSid();
		$PARAMS{'out_cookie'} = $session->getSid();
warn("LOGIN => ",keys(%PARAMS));
	} else {
		die SOAP::Fault->faultcode('Server.RuntimeError')->faultstring("Unable to start session");
	}
	return SOAP::Data->name("sid")->value($session->getSid())->type("xsd:string");
}
sub loginCAS {
	my $self = shift;
	my $ticket = shift;
	my $auth_cas = FILEX::System::Auth::AuthCAS->new() or 
		die SOAP::Fault->faultcode('Server.RuntimeError')->faultstring("Unable to load CAS authentication module");
	# get the current url
	# thru conf : getUriSoap + get server url !
	my $url;
	my $result = $auth_cas->processAuth(currenturl=>$url,ticket=>$ticket);
	die SOAP::Fault->faultcode('Server.AuthError')
		->faultstring("Unable to authenticate with ticket $ticket")
		->faultdetail($auth_cas->get_error()) if !$result;
	# start session
	my $session = _checkAccess(0);
	if ( $session->getSid() ) {
		warn "Already have session : ",$session->getSid(),"\n";
		$session->drop();
	}
	if ( $session->start() ) {
		$session->data()->{'username'} = $result;
		#$ENV{'FILEX_Cookie'} = $session->getSid();
		$PARAMS{'out_cookie'} = $session->getSid();
	} else {
		die SOAP::Fault->faultcode('Server.RuntimeError')->faultstring("Unable to start session");
	}
	return SOAP::Data->name("sid")->value($session->getSid())->type("xsd:string");
}
# logout method
# return : nothing
sub logout {
	my $self = shift;
	my $session = _checkAccess(0);
	my $result = 0;
	if ( $session && $session->getSid() ) {
			$result = 1 if $session->drop();
			delete($PARAMS{'out_cookie'}) if exists($PARAMS{'out_cookie'});
			#$ENV{'FILEX_Drop_Cookie'} = 1;
	}
	return SOAP::Data->name("return")->type("xsd:boolean")->value($result);
}
sub list {
	my $self = shift;
	my $active = shift;
	$active = ( !defined($active) || ($active !~ /^[0-1]$/) ) ? 1 : $active;
	my $session = _checkAccess();
	my $user = FILEX::System::User->new(uid=>$session->data()->{'username'});
	die SOAP::Fault->faultcode('Server.RuntimeError')
			->faultstring("Unable to retrieve user : ",$session->data()->{'username'}) if (!$user);
	my $db = eval { FILEX::DB::Manage->new(); };
	die SOAP::Fault->faultcode('Server.RuntimeError')
			->faultstring("Unable to access database")
			->faultdetail($@) if ($@);
	# get files
	my @results;
	if ( !$db->getFiles(owner_uniq_id=>$user->getUniqId(),results=>\@results,active=>$active) ) {
		die SOAP::Fault->faultcode('Server.RuntimeError')
			->faultstring('Database error')
			->faultdetail($db->getLastErrorString());
	}
	return [ @results ];
}
# 
# get resume
#
sub getResume {
	my $self = shift;
	my $session = _checkAccess();
	my $user = FILEX::System::User->new(uid=>$session->data()->{'username'});
	die SOAP::Fault->faultcode('Server.RuntimeError')
			->faultstring("Unable to retrieve user : ",$session->data()->{'username'}) if (!$user);
	my $result = {};
	$result->{'used_space'} = SOAP::Data->name("used_space")->type("xsd:int")->value(int($user->getDiskSpace()));
	$result->{'active_count'} = SOAP::Data->name("active_count")->type("xsd:int")->value(int($user->getActiveCount()));
	return SOAP::Data->name("resume")->value($result);
}
#
# get Quotas
#
sub getQuota {
	my $self = shift;
	my $session = _checkAccess();
	my $user = FILEX::System::User->new(uid=>$session->data()->{'username'});
	die SOAP::Fault->faultcode('Server.RuntimeError')
		->faultstring("Unable to retrieve user : ",$session->data()->{'username'}) if (!$user);
	my $quotas = FILEX::System::Quota->new(ruleMatcher => FILEX::System::LDAP->new());
	die SOAP::Fault->faultcode('Server.RuntimeError')
			->faultstring("Unable to access quota sub-system") if (!$quotas);
	my ($quota_max_file_size,$quota_max_used_space) = $quotas->getQuota($user->getId());
	my $result = {};
	$result->{'max_file_size'} = SOAP::Data->name("max_file_size")->type("xsd:int")->value(int($quota_max_file_size));
	$result->{'max_used_space'} = SOAP::Data->name("max_used_space")->type("xsd:int")->value(int($quota_max_used_space));
	return SOAP::Data->name("quota")->value($result);
}
# 
# check Access
#
sub _checkAccess {
	my $die = ($#_ >= 0) ? $_[0] : 1;
	$die = ( defined($die) && $die =~ /^[0-1]$/ ) ? $die : 1;
	my $session = eval { FILEX::System::Session->new(); };
	die SOAP::Fault->faultcode('Server.RuntimeError')->faultstring("Unable to start session")->faultdetail($@) if ($@);
	# auth
	#if ( exists($ENV{'FILEX_SID'}) ) {
	if ( exists($PARAMS{'in_cookie'}) ) {
		#$session->load($ENV{'FILEX_SID'});
		$session->load($PARAMS{'in_cookie'});
		#delete($ENV{'FILEX_SID'});
		delete($PARAMS{'in_cookie'});
	}
	if ( $session->getSid() ) {
		warn ("Authenticated user :",$session->data->{'username'});
		# maybe check for access ACL
		#$ENV{'FILEX_Cookie'} = $session->getSid();
		$PARAMS{'out_cookie'} = $session->getSid();
	} else {
		die SOAP::Fault->faultcode('Server.AuthError')
				->faultstring("Authorisation failed !")
				->faultdetail("You need to be authenticated to access this function.") if $die;
	}
	return $session;
}

1;
