package FILEX::System;
use strict;
use vars qw($VERSION);
$VERSION = 1.0;

# Apache
use constant MP2 => (exists $ENV{MOD_PERL_API_VERSION} and $ENV{MOD_PERL_API_VERSION} >= 2);

# FILEX
use FILEX::System::Config;
use FILEX::System::Template;
use FILEX::System::I18N;
use FILEX::System::LDAP;
use FILEX::System::Mail;
use FILEX::System::Exclude; 
use FILEX::System::Session;
use FILEX::System::Cookie;
use FILEX::DB::System;
use FILEX::System::User;
use FILEX::Tools::Utils;

use constant FILEX_CONFIG_NAME=>"FILEXConfig";
use constant LOGIN_FORM_LOGIN_FIELD_NAME=>"login";
use constant LOGIN_FORM_PASSWORD_FIELD_NAME=>"password";
use constant LOGIN_FORM_CAS_TICKET_FIELD_NAME=>"ticket";

BEGIN {
	if (MP2) {
		require Apache2::Const;
		Apache2::Const->import(-compile => qw(OK REDIRECT));
		require Apache2::ServerRec;
		require Apache2::URI;
		require Apache2::Connection;
		require Apache2::Util;
		require Apache2::Request;
		require Apache2::Upload;
		require APR::Status;
	} else {
		require Apache::Constants;
		Apache::Constants->import(qw(OK REDIRECT));
		require Apache::Request;
		require Apache::Util;
	}
}
# first args = Apache object [mandatory]
# [opt]
# with_config => path to config file
# with_upload => 1 | 0 (default 0)
# with_hook => {hook_data=>"hook data", upload_hook=>CODE}
sub new {
	my $this = shift;
	my $class = ref($this) || $this;

	my $self = {
		_apreq_ => undef,
		_apreq_status_=>undef,
		_config_ => undef,
		_template_ => undef,
		_i18n_ => undef,
		_language_ => undef,
		_cookie_ => undef,
		_dropcookie_ => 0,
		_havecookie_ => 0,
		_user_ => undef,
		_session_ => undef,
		_ldap_ => undef,
		_mail_ => undef,
		_systemdb_ => undef,
		_exclude_=> undef, 
		_auth_=>undef,
	};
	_INITIALIZE_($self,@_);
	return bless($self,$class);
}

sub _INITIALIZE_ {
	my $self = shift;
	my $r = shift;
	my %ARGZ = @_; # remaining argz
	die(__PACKAGE__,"-> Require an Apache object") if ( ref($r) ne "Apache" && ref($r) ne "Apache2::RequestRec");

	# first initialize config file
	my $FILEXConfig = exists($ARGZ{'with_config'}) ? $ARGZ{'with_config'} : $r->dir_config(FILEX_CONFIG_NAME);
	$self->{'_config_'} = FILEX::System::Config->instance(file=>$FILEXConfig);
	
	# initialize the Apache::Request object
	if ( exists($ARGZ{'with_upload'}) && $ARGZ{'with_upload'} == 1 ) {
		my %ReqParams = (
			DISABLE_UPLOADS => 0,
			TEMP_DIR => $self->{'_config_'}->getTmpFileDir()
		);
		# has hook
		if ( exists($ARGZ{'with_hook'}) && ref($ARGZ{'with_hook'}) eq "HASH" ) {
			my $with_hook = $ARGZ{'with_hook'};
			if ( exists($with_hook->{'upload_hook'}) && ref($with_hook->{'upload_hook'}) eq "CODE" ) {
				# HOOK_DATA is not implemented une libapreq2 so we need to emulate it
				my $hook_data = $with_hook->{'hook_data'} || undef;
				my $hook_code = $with_hook->{'upload_hook'};
				if (MP2) {
					if ( defined($hook_data) ) {
						$hook_code = sub {
							$with_hook->{'upload_hook'}->(@_,$_[0]->upload_size(),$hook_data);
						};
					} 
					$ReqParams{'UPLOAD_HOOK'} = $hook_code;
				} else {
					$ReqParams{'UPLOAD_HOOK'} = $hook_code;
					$ReqParams{'HOOK_DATA'} = $hook_data if $hook_data;
				}
			}
		}
		# on MP2 : set APREQ2_ReadLimit into apache config
		$self->{'_apreq_'} = MP2 ? Apache2::Request->new($r,%ReqParams) : Apache::Request->new($r,%ReqParams);
	} else {
		$self->{'_apreq_'} = MP2 ? Apache2::Request->new($r) : Apache::Request->new($r);
	}
	# here the POST occurs
	$self->{'_apreq_status_'} = $self->{'_apreq_'}->parse();

	# initialize language switch incoming header
	my @lang = _initLanguage($r);
	push(@{$self->{'_language_'}},@lang) if ($#lang >= 0 );

	# load template module
	$self->{'_template_'} = FILEX::System::Template->new(inifile=>$self->{'_config_'}->getTemplateIniFile());

	# load the i18n module
	$self->{'_i18n_'} = FILEX::System::I18N->new(inifile=>$self->{'_config_'}->getI18nIniFile());

	# load session module
	$self->{'_session_'} = FILEX::System::Session->new();

	# set default language for both i18n & template
	if ( $self->{'_language_'} ) {
		if ( ref($self->{'_language_'}) eq "ARRAY" ) {
			my ($si18n,$stmpl);
			for ( my $l = 0; $l < $#{$self->{'_language_'}}; $l++ ) {
				if ( $self->{'_i18n_'}->langExists($self->{'_language_'}->[$l]) && !$si18n) {
					$self->{'_i18n_'}->setLang($self->{'_language_'}->[$l]);
					$si18n = 1;
				}
				if ( $self->{'_template_'}->langExists($self->{'_language_'}->[$l]) && !$stmpl) {
					$self->{'_template_'}->setLang($self->{'_language_'}->[$l]);
					$stmpl = 1;
				}
			}
		} elsif ( ref($self->{'_language_'}) eq "" ) {
			$self->{'_i18n_'}->setLang($self->{'_language_'});
			$self->{'_template_'}->setLang($self->{'_language_'});
		}
	}
	# initialize authentification module
	my $auth_mod = "FILEX::System::Auth::".$self->{'_config_'}->getAuthModule();
	# import module
	_require($auth_mod);
	# create instance
	$self->{'_auth_'} = $auth_mod->new(config=>$self->{'_config_'});

	return 1;
}

# return the current Apache::Request Object
sub apreq {
	my $self = shift;
	return $self->{'_apreq_'};
}

# get last Apache::Request->parse status
sub getApreqStatus {
	my $self = shift;
	return $self->{'_apreq_status_'};
}

# return config object
sub config {
	my $self = shift;
	return $self->{'_config_'};
}

# return i18n object
sub i18n {
	my $self = shift;
	return $self->{'_i18n_'};
}

# return ldap server object
sub ldap {
	my $self = shift;
	# load on demand
	if ( ! $self->{'_ldap_'} ) {
		$self->{'_ldap_'} = eval { FILEX::System::LDAP->new(config=>$self->config()); };
		warn(__PACKAGE__,"-> Unable to load LDAP object : $@") if ($@);
	}
	return ( $self->{'_ldap_'} ) ? $self->{'_ldap_'} : undef;
}

# return system object
sub _systemdb {
	my $self = shift;
	# load on demand
	if ( !$self->{'_systemdb_'} ) {
		$self->{'_systemdb_'} = eval { FILEX::DB::System->new(); };
		warn(__PACKAGE__,"-> Unable to Load FILEX::DB::System object : $@") if ($@);
	}
	return $self->{'_systemdb_'};
}

# return exclude object
sub _exclude {
	my $self = shift;
	# load on demand
	if ( !$self->{'_exclude_'} ) {
		$self->{'_exclude_'} = FILEX::System::Exclude->new(ldap=>$self->ldap());
	}
	return $self->{'_exclude_'};
}

# return FILEX::System::Mail object
sub mail {
	my $self = shift;
	# load on demand
	if ( ! $self->{'_mail_'} ) {
		$self->{'_mail_'} = FILEX::System::Mail->new(
			server=>$self->config()->getSmtpServer(),
			hello=>$self->config()->getSmtpHello(),
			timeout=>$self->config()->getSmtpTimeout());
	}
	return $self->{'_mail_'};
}

# return template object
# name =>
# [opt] lang =>
sub getTemplate {
	my $self = shift;
	return $self->{'_template_'}->getTemplate(@_);
}

# return current authenticated user
sub getUser {
	my $self = shift;
	return $self->{'_user_'};
}

#
# begin session
# 
# with no_auth => 1 then only cookie is read but authentification is not processed
# with no_login => 1 then the user will not be redirected to authentification form
#
# return the logged in user
sub beginSession {
	my $self = shift;
	my %ARGZ = @_;
	my $r = $self->apreq();
	my $isValid = undef;
	my $err_mesg = undef;
	# check if in no_auth mode (ie : simply read cookie)
	my $noAuth = ( exists($ARGZ{'no_auth'}) && defined($ARGZ{'no_auth'}) && ($ARGZ{'no_auth'} == 1) ) ? 1 : 0;
	my $noLogin = ( exists($ARGZ{'no_login'}) && defined($ARGZ{'no_login'}) && ($ARGZ{'no_login'}) == 1) ? 1 : 0;
	# cookie
	my $ckname = $self->config()->getCookieName();
	my $cookie = FILEX::System::Cookie::parse($r->headers_in->{'Cookie'});
	#
	# check if we are authenticated
	#

	# reset user before begin
	$self->{'_user_'} = undef;
  # have cookie 
	if ( $cookie && exists($cookie->{$ckname}) ) {
		$self->{'_havecookie_'} = 1;
		my $session_id = $cookie->{$ckname}->value();
		# initialize session
		if ( $self->{'_session_'}->load($session_id) ) {
			# if session has expired then re-auth
			if ( ! $self->{'_session_'}->isExpired() ) {
				# user's login
				$self->{'_user_'} = FILEX::System::User->new(uid=>$self->{'_session_'}->getParam('username'),
					ldap=>$self->ldap(),
					session=>$self->{'_session_'});
				$isValid = 1 if ( defined($self->{'_user_'}) );
			} else {
				$self->{'_session_'}->drop();
			}
		}
	}
	# 
	# if no authentification mode then return here
	# you can check if a user is auth with the method getAuthUser()
	# 
	#return 1 if ($noAuth == 1);
	return $self->{'_user_'} if ($noAuth == 1);
	#
	# here there is no auth 
	#
	if ( ! $isValid ) {
		my %process_auth_param;
		# doProcessAuthParam return 0 if no mandatory auth param are found
		my $go_auth = $self->_doProcessAuthParam(param=>[$self->{'_auth_'}->requireParam()],result=>\%process_auth_param);
		if ( $go_auth ) {
			my $user = $self->{'_auth_'}->processAuth(%process_auth_param);
			if ( ! defined($user) ) {
				warn(__PACKAGE__," => Unable to retrieve user : ",$self->{'_auth_'}->get_error());
				$err_mesg = "invalid credential";
			}
			if ( defined($user) && length($user) > 0 ) {
				$self->{'_user_'} = FILEX::System::User->new(uid=>$user,ldap=>$self->ldap());
				if ( defined($self->{'_user_'}) ) {
					# start a new session
					if ( $self->{'_session_'}->start() ) {
						# set username
						$self->{'_session_'}->setParam(username=>$user);
						$self->{'_user_'}->setSession($self->{'_session_'});
						# set cookie
						$self->{'_cookie_'} = FILEX::System::Cookie::generate($self->config(),-value=>$self->{'_session_'}->getSid());
						$isValid = 1;
					}
				} else {
					return undef if ($noLogin == 1);
					$self->denyAccess();
				}
			}
		}
	}
	#
	# if valid then check for exclude
	#
	if ( $isValid ) {
		# if have a session 
		my ($bIsExclude,$excludeReason);
		# from session
		if ( ref($self->{'_session_'}) ) {
			$bIsExclude =	$self->{'_session_'}->getParam("is_exclude");
			$excludeReason = $self->{'_session_'}->getParam("exclude_reason");
		} 
		if ( !defined($bIsExclude) ) {
			($bIsExclude,$excludeReason) = $self->isExclude($self->{'_user_'}) if !defined($bIsExclude);
			if ( ref($self->{'_session_'}) ) { 
				$self->{'_session_'}->setParam(is_exclude=>$bIsExclude,1);
				$self->{'_session_'}->setParam(exclude_reason=>(defined($excludeReason))?$excludeReason:"",1);
			}
		}
		if ( $bIsExclude ) {
			$isValid = undef;
			warn(__PACKAGE__,"-> user [".$self->{'_user_'}->getId()."] is Excluded !");
			# do access deny
			return undef if ($noLogin == 1);
			$self->denyAccess($excludeReason);
		} else {
			return $self->{'_user_'};
		}
	}
	# No ticket, no user, no cookie, cookie expires => require auth
	return undef if ($noLogin == 1);
	if ( $self->{'_auth_'}->needRedirect() ) {
		# maybe append the query string if any
		$self->_redirectAuth($self->{'_auth_'}->getRedirect($self->getCurrentUrl(1)));
	} else {
		$self->_doLogin($err_mesg);
	}
}

# require : param=> ARRAY_REF, results=>HASH_REF
sub _doProcessAuthParam {
	my $self = shift;
	my %ARGZ = @_;
	my $param = $ARGZ{'param'} if ( exists($ARGZ{'param'}) && ref($ARGZ{'param'}) eq "ARRAY" ) or warn(__PACKAGE__,"-> _doProcessAuthParam(param=>ARRAY_REF,result=>HASH_REF}") && return undef;
	my $result = $ARGZ{'result'} if ( exists($ARGZ{'result'}) && ref($ARGZ{'result'}) eq "HASH" ) or warn(__PACKAGE__,"-> _doProcessAuthParam(param=>ARRAY_REF,result=>HASH_REF}") && return undef;
	# counter for mandatory auth parameters.
	my $mandatory = 0;

	# loop on param
	while ( my $key = shift(@$param) ) {
		if ( $key eq "currenturl" ) {
			$result->{'currenturl'} = $self->getCurrentUrl(1);
		}
		if ( $key eq "ldap" ) {
			$result->{'ldap'} = $self->ldap();
		}
		if ( $key eq LOGIN_FORM_CAS_TICKET_FIELD_NAME ) {
			$result->{'ticket'} = $self->apreq->param(LOGIN_FORM_CAS_TICKET_FIELD_NAME);
			$mandatory++ if defined($result->{'ticket'});
		}
		if ( $key eq LOGIN_FORM_LOGIN_FIELD_NAME ) {
			$result->{'login'} = $self->apreq->param(LOGIN_FORM_LOGIN_FIELD_NAME);
			$mandatory++ if defined($result->{'login'});
		}
		if ( $key eq LOGIN_FORM_PASSWORD_FIELD_NAME ) {
			$result->{'password'} = $self->apreq->param(LOGIN_FORM_PASSWORD_FIELD_NAME);
			$mandatory++ if defined($result->{'password'});
		}
	}
	return $mandatory;
}

# Automatic Module loading
sub _require {
  my($filename) = @_;
  my($realfilename,$result,$prefix);
  ### format with :: = /
  $filename =~ s/::/\//g;
  $filename.='.pm';
  return 1 if $INC{$filename};
  ITER: {
    foreach $prefix (@INC) {
      $realfilename = "$prefix/$filename";
      if (-f $realfilename) {
        $result = do $realfilename;
        last ITER;
      }
    }
    die "Can't find $filename in \@INC";
  }
  die $@ if $@;
  die "$filename did not return true value" unless $result;
  $INC{$filename} = $realfilename;
  return $result;
}

# return a table of prefered user-agent language
# require a apache Object
sub _initLanguage {
	my $r = shift;
# TODO : voir $r->content_languages || "Content-Language"
	my $aclang = MP2 ? $r->headers_in->{"Accept-Language"} : $r->header_in("Accept-Language");
	# check for accept-language
	$aclang = (MP2 ? $r->headers_in->{"Accept-Language"} : $r->header_in("accept-language")) if (! $aclang);
	my @lang = split(',',$aclang) if $aclang;
	# remove q
	for (my $i = 0; $i <= $#lang; $i++) {
		$lang[$i] =~ s/;q.*$//;
	}
	# return 
	return ( wantarray ) ? @lang : $lang[0];
}

# return the prefered language
sub getPreferedLanguage {
	my $self = shift;
	return ( defined($self->{'_language_'} ) ) ? $self->{'_language_'}->[0] : undef;
}

# check if a given user is exclude 
sub isExclude {
	my $self = shift;
	my $user = shift;
	warn(__PACKAGE__,"=> require a FILEX::System::User") && return 1 if (!defined($user) || (ref($user) ne "FILEX::System::User"));
	# get exclude object
	my $exclude = $self->_exclude();
	if ( $exclude ) {
		return $exclude->isExclude($user->getId());
	} 
	# deny everybody if failed
	return 1;
}

# here we quit the application
sub _redirectAuth {
	my $self = shift;
	my $redirect_url = shift;
	my $r = $self->apreq();
	# if we have cookie then destroy it
	if ( $self->{'_havecookie_'} == 1 ) {
		my $dcookie = FILEX::System::Cookie::generate($self->config(),-value=>"",-expires=>"-1Y");
		$r->err_headers_out->add("Set-Cookie",$dcookie);
	}
	if ( MP2 ) {
		$r->headers_out->add("Location",$redirect_url);
		$r->status(Apache2::Const::REDIRECT);
		#$r->content-type();
	} else {
		$r->header_out(Location=>$redirect_url);
		$r->status(Apache::Constants::REDIRECT);
		$r->send_http_header();
	}
	exit( MP2 ? Apache2::Const::OK : Apache::Constants::OK );
}

sub _doLogin {
	my $self = shift;
	my $mesg = shift;
	# load template
	my $t = $self->getTemplate(name=>"login");
	# fill template
	$t->param(FILEX_STATIC_FILE_BASE=>$self->getStaticUrl());
	$t->param(FILEX_SYSTEM_EMAIL=>$self->config()->getSystemEmail());
	$t->param(FILEX_LOGIN_FORM_ACTION=>$self->getCurrentUrl());
	$t->param(FILEX_LOGIN_FORM_LOGIN_FIELD_NAME=>LOGIN_FORM_LOGIN_FIELD_NAME);
	$t->param(FILEX_LOGIN_FORM_PASSWORD_FIELD_NAME=>LOGIN_FORM_PASSWORD_FIELD_NAME);
	if ( $mesg ) {
		$t->param(FILEX_HAS_ERROR=>1);
		$t->param(FILEX_ERROR=>$self->i18n->localizeToHtml($mesg));
	}
	$self->sendHeader('Content-Type'=>"text/html");
	$self->apreq->print($t->output()) if ( $t && !$self->apreq->header_only() );
	exit( MP2 ? Apache2::Const::OK : Apache::Constants::OK );
}

sub denyAccess {
	my $self = shift;
	my $reason = shift;
	my $r = $self->apreq();
	# load access deny template
	my $t = $self->getTemplate(name=>"access_deny");
	# fill template
	$t->param(STATIC_FILE_BASE=>$self->getStaticUrl());
	$t->param(ERROR=>$self->i18n->localizeToHtml("access deny"));
	$t->param(SYSTEMEMAIL=>$self->config()->getSystemEmail());
	# reason
	if ( defined($reason) && length($reason) > 0 ) {
		$t->param(REASON=>FILEX::Tools::Utils::toHtml($reason));
	}
	$self->sendHeader('Content-Type'=>"text/html");
	$r->print($t->output()) if ( $t && ! $r->header_only() );
	exit( MP2 ? Apache2::Const::OK : Apache::Constants::OK );
}

# mandatory : content-type
sub sendHeader {
	my $self = shift;
	my $r = $self->apreq();
	$self->prepareHeader(@_);
	# save session if needed
	$self->{_session_}->save() if ( $self->{_session_} );
	# only on mod_perl 1.0
	$r->send_http_header() if (!MP2);
}

# common header params +
# no_cookie => 1 if you don't want to send cookie !
#
sub prepareHeader {
	my $self = shift;
	my $r = $self->apreq();
	my %ARGZ = @_;
	my $no_cookie = delete($ARGZ{'no_cookie'});
	$no_cookie = 0 if !defined($no_cookie);
	# put cookie if needed
	if ( $no_cookie != 1 ) {
		if ( defined($self->{'_cookie_'}) && $self->{'_dropcookie_'} != 1 ) {
			if ( MP2 ) {
				$r->headers_out->add("Set-Cookie",$self->{'_cookie_'});
			} else {
				$r->header_out("Set-Cookie",$self->{'_cookie_'});
			}
		} elsif ( $self->{'_dropcookie_'} == 1 && $self->{'_havecookie_'} == 1 ) {
			# destroy cookie
			if ( MP2 ) {
				$r->headers_out->add("Set-Cookie",FILEX::System::Cookie::generate($self->config(),
				-value=>"",
				-expires=>"-1Y"));
			} else {
				$r->header_out("Set-Cookie",FILEX::System::Cookie::generate($self->config(),
				-value=>"",
				-expires=>"-1Y")); 
			}
		}
	}
	# st content-type
	my $ct = delete($ARGZ{'Content-Type'});
	$ct = 'text/html' if ( !$ct );
	$r->content_type($ct);
	# check for ie because this browser is stupid !
	if ( $self->isIE() ) {
		# No Cache (cannot use the function $r->no_cache() because of a bug in IE 
		# cf http://support.microsoft.com/?kbid=327286)
		# http://forum.java.sun.com/thread.jsp?forum=45&thread=233446
		# http://jira.atlassian.com/browse/JRA-1738
		# http://bugs.php.net/bug.php?id=16173
		if ( MP2 ) {
			$r->headers_out->add("Expires","Thu 7 Nov 1974 8:00:00 GMT");
			$r->headers_out->add("Pragma","no-cache") if !_isHttps($r);
			$r->headers_out->add("Cache-control","public") if !_isHttps($r);
		} else {
			$r->header_out("Expires","Thu 7 Nov 1974 8:00:00 GMT");
			$r->header_out("Pragma","no-cache") if !_isHttps($r);
			$r->header_out("Cache-control","public") if !_isHttps($r);
		}
	} else {
		if ( MP2 ) {
			$r->headers_out->add("Pragma","no-cache");
		} else {
			$r->no_cache(1);
		}
	}
	# the rest
	while ( my ($k,$v) = each(%ARGZ) ) {
		if ( MP2 ) {
			$r->headers_out->add($k,$v);
		} else {
			$r->header_out($k,$v);
		}
	}
}

sub isIE {
	my $self = shift;
	my $user_agent = MP2 ? $self->apreq->headers_in->{"User-Agent"} : $self->apreq->header_in("User-Agent");
	return ( $user_agent =~ /msie/i ) ? 1 : 0;
}

# get mail helper method
# require uname
sub getMail {
	my $self = shift;
	return $self->ldap->getMail(@_);
}

sub getUserRealName {
	my $self = shift;
	my $uid = shift;
	my $attr = $self->config()->getLdapUsernameAttr();
	my $res = $self->ldap()->getUserAttrs(uid=>$uid, attrs=>[$attr]);
 	$attr = lc($attr);
  my $rn = ($res) ? $res->{$attr}->[0] : "unknown";
	return $rn;
}

sub getUsedDiskSpace {
	my $self = shift;
	my $sdb = $self->_systemdb();
	return ($sdb) ? $sdb->getUsedDiskSpace() : undef;
}

# check if we can upload on system switch user's params
sub isSpaceRemaining {
	my $self = shift;
	my $user = shift || $self->getUser();
	# 
	my $max_file_size = $user->getMaxFileSize();
	#
	my $max_disk_space = $self->config->getMaxDiskSpace();
	my $max_disk_space_limit = $self->config->getMaxDiskSpaceLimit();
	if ( $max_disk_space ) {
		my $current_used_space = $self->getUsedDiskSpace();
		# check if there is a max_file_size
		if ( $max_file_size > 0 ) {
			return 0 if ( $max_disk_space < ($current_used_space + $max_file_size) );
		} else {
			# we can't upload if the remaining space < max_disk_space_limit
      return 0 if ( $max_disk_space_limit && (($current_used_space/$max_disk_space)*100) >= $max_disk_space );
		}
		return 1;
	}
	return 1;
}
# send email
# from
# to 
# content
# subject
# type
# encoding
# charset
sub sendMail {
	my $self = shift;
	my $mail = $self->mail();
	return $mail->send(@_);
}

# fucking helper function for ie bug over https !!!! M$ is horrible !
sub _isHttps {
	my $r = shift;
	return ( $r->subprocess_env('https') ) ? 1 : undef;
}

# generate service url
# get current url without query string
# if getCurrentUrl(1) then append query string
sub getCurrentUrl {
	my $self = shift;
	my $with_qs = shift;
	$with_qs = 0 if ( !defined($with_qs) || $with_qs != 1 );
	# scheme
	my $url = $self->getServerUrl();
	# if you want the query string, use :
	# $r->parsed_uri
	# $qs = $uri->query()
	# uri
	$url .= $self->apreq->uri();
	if ( $with_qs ) {
		# rebuild the query string because we don't need the tichet in !
		my %args = ();
		if ( MP2 ) {
			my $tmpArgs = FILEX::Tools::Utils::qsParams($self->apreq->args());
			foreach my $k (keys %{$tmpArgs}) {
				$args{$k} = $tmpArgs->{$k};
			}
		} else {
			%args = $self->apreq->args();
		}
		my $key = LOGIN_FORM_CAS_TICKET_FIELD_NAME;
		delete($args{$key}) if exists($args{$key});
		my $qs = $self->genQueryString(params=>\%args);
		$url .= "?$qs" if length($qs);
	}
	return $url;
}

# generate server url
sub getServerUrl {
	my $self = shift;
	my $s = $self->apreq->server();
	my $url = ( $self->apreq->subprocess_env('https') ) ? "https://" : "http://";
	# host_name 
	$url .= $self->config()->getHostName() || $s->server_hostname();
	# port if not standard (0==80);
	$url .= ":".$s->port() if ( $s->port() != 80 && $s->port() != 443 && $s->port() != 0 );
	return $url;
}

# generate query string
# require a hash ref
sub genQueryString {
	my $self = shift;
	my %ARGZ = @_;
	return if ( !exists($ARGZ{'params'}) || ref($ARGZ{'params'}) ne "HASH" );
	my $separator = ( exists($ARGZ{'separator'}) && defined($ARGZ{'separator'}) ) ? $ARGZ{'separator'} : '&';
	my @res;
	my ($k,$v,$tmp);
	while ( ($k,$v) = each(%{$ARGZ{'params'}}) ) {
		# escape parmeter name and parameter value
		if ( MP2 ) {
			$tmp = Apache2::Util::escape_path($k,$self->apreq()->pool())."=".Apache2::Util::escape_path($v,$self->apreq()->pool());
		} else {
			$tmp = Apache::Util::escape_uri($k)."=".Apache::Util::escape_uri($v);
		}
		push(@res,$tmp);
	}
	return join($separator,@res);
}

sub getManageUrl {
	my $self = shift;
	my $url = $self->getServerUrl();
	$url .= (MP2) ? Apache2::Util::escape_path($self->config()->getUriManage(),$self->apreq->pool()) : Apache::Util::escape_uri($self->config()->getUriManage());
	return $url;
}

sub getUploadUrl {
	my $self = shift;
	my $url = $self->getServerUrl();
	$url .= (MP2) ? Apache2::Util::escape_path($self->config()->getUriUpload(),$self->apreq->pool()) : Apache::Util::escape_uri($self->config()->getUriUpload());
	return $url;
}

sub getMeterUrl {
	my $self = shift;
	my $url = $self->getServerUrl();
	$url .= (MP2) ? Apache2::Util::escape_path($self->config()->getUriMeter(), $self->apreq->pool()) : Apache::Util::escape_uri($self->config()->getUriMeter());
	return $url;
}

sub getAdminUrl {
	my $self = shift;
	my $url = $self->getServerUrl();
	$url .= (MP2) ? Apache2::Util::escape_path($self->config()->getUriAdmin(),$self->apreq->pool()) : Apache::Util::escape_uri($self->config()->getUriAdmin());
	return $url;
}

sub getGetUrl {
	my $self = shift;
	my $url = $self->getServerUrl();
	$url .= (MP2) ? Apache2::Util::escape_path($self->config()->getUriGet(), $self->apreq->pool()) : Apache::Util::escape_uri($self->config()->getUriGet());
	return $url;
}

sub getStaticUrl {
	my $self = shift;
	my $url = $self->getServerUrl();
	my $static_uri = $self->config()->getUriStatic();
	$static_uri .= "/" if ( $static_uri !~ /.*\/^/ );
	$url .= (MP2) ? Apache2::Util::escape_path($static_uri, $self->apreq->pool()) : Apache::Util::escape_uri($static_uri);
	return $url;
}

# check if a a proxy request
sub isBehindProxy {
	my $self = shift;
	my @headers = ('X-Forwarded-For','Via','Client-ip','Forwarded');
	my ($count,$line);
	$count = 0;
	foreach my $hkey (@headers) {
		$line = (MP2) ? $self->apreq->headers_in->{$hkey} : $self->apreq->header_in($hkey);
		$count += 1 if ( defined($line) && length($line) );
	}
	return ( $count ) ? 1 : 0;
	# possibilities :
	# Forwarded = "Forwarded" ":" #( "by" URI [ "(" product ")" ] [ "for" FQDN ] )
	#           = by http://info.cern.ch:8000/ for ptsun00.cern.ch
	# Via = 
	# Client-ip = client ip address
	# X-Forwarded-For = client ip address
}

# get remote host ip address
sub getRemoteIP {
	my $self = shift;
	return $self->apreq->connection->remote_ip();
	# if behind proxy 
	#return ( $self->isBehindProxy() ) ? $self->apreq->header_in('X-Forwarded-For') : $self->apreq->connection->remote_ip();
}

sub getProxyInfos {
	my $self = shift;
	return undef if ( ! $self->isBehindProxy() );
	my (@proxy_infos,$infos);
	my @headers = ('X-Forwarded-For','Via','Client-ip','Forwarded');
	my $line;
	foreach my $hkey (@headers) {
		$line = (MP2) ? $self->apreq->headers_in->{$hkey} : $self->apreq->header_in($hkey);
		push(@proxy_infos,"$hkey = $line") if ( defined($line) && length($line) );
	}
	$infos = join("\n",@proxy_infos);
	return ( length($infos) > 255 ) ? substr($infos,0,254) : $infos;
}
# get the user_agent string
sub getUserAgent {
	my $self = shift;
	return (MP2) ? $self->apreq->headers_in->{'User-Agent'} : $self->apreq->header_in('User-Agent');
}

# check if the user it it's "cancel" button
sub isAborted {
	my $self = shift;
	# IsClientConnected? Might already be disconnected for busy
	# site, if a user hits stop/reload
	# see : http://perl.apache.org/docs/1.0/guide/snippets.html#Detecting_a_Client_Abort
	my $conn = $self->apreq->connection();
	my $is_aborted = $conn->aborted() ? 1 : 0;
	if ( ! $is_aborted ) {
		if ( MP2 ) {
			$is_aborted = APR::Status::is_EOF($self->apreq()->body_status());
			#APR::Status::is_ECONNABORTED($self->apreq()->body_status());
			#my $cs = $conn->client_socket();
			#if ( $cs ) {
			#	$is_aborted = ($cs->poll($conn->pool(), 1, APR::Const::POLLIN) == APR::Const::TIMEUP) ? 1 : 0;
			#} else {
			#	$is_aborted = 1;
			#}
		} else {
			my $fileno = $conn->fileno;
			if (defined $fileno) {
				my $s = IO::Select->new($fileno);
				$is_aborted = $s->can_read(0) ? 1 : 0;
			}
		}
	}
	return $is_aborted;
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
