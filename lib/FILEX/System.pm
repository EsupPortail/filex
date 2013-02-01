package FILEX::System;
use strict;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);
use Exporter;
@ISA = qw(Exporter);
@EXPORT = qw();
@EXPORT_OK = qw(
	genUniqId
	genQueryString
	toHtml
);
%EXPORT_TAGS = (all=>[@EXPORT_OK]);
$VERSION = 1.0;

# Apache
use Apache::Constants qw(:common REDIRECT);
use Apache::Request;
use Apache::Cookie;
use Apache::Util;

# FILEX
use FILEX::System::Config;
use FILEX::System::Template;
use FILEX::System::I18N;
use FILEX::System::Auth::CAS;
use FILEX::System::LDAP;
use FILEX::System::Mail;
use FILEX::System::Exclude;
use FILEX::System::Quota;
use FILEX::DB::System;

# others
use Data::Uniqid;
use Crypt::CBC;
use Crypt::Blowfish;
use HTML::Entities ();

use constant FILEX_CONFIG_NAME=>"FILEXConfig";
use constant LOGIN_FORM_LOGIN_FIELD_NAME=>"login";
use constant LOGIN_FORM_PASSWORD_FIELD_NAME=>"password";
use constant LOGIN_FORM_CAS_TICKET_FIELD_NAME=>"ticket";

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
		_username_ => undef,
		_cas_ => undef,
		_ldap_ => undef,
		_mail_ => undef,
		_systemdb_ => undef,
		_exclude_=> undef,
		_quota_=>undef,
		_auth_=>undef,
	};
	_INITIALIZE_($self,@_);
	return bless($self,$class);
}

sub _INITIALIZE_ {
	my $self = shift;
	my $r = shift;
	my %ARGZ = @_; # remaining argz
	die(__PACKAGE__,"-> Require an Apache object") if ( ref($r) ne "Apache" );

	# first initialize config file
	my $FILEXConfig;
	if ( ! FILEX::System::Config::isSetup() ) {
		$FILEXConfig = exists($ARGZ{'with_config'}) ? $ARGZ{'with_config'} : $r->dir_config(FILEX_CONFIG_NAME);
		$self->{'_config_'} = FILEX::System::Config->new(file=>$FILEXConfig, reload=>1, dieonreload=>1);
	} else {
		$self->{'_config_'} = FILEX::System::Config->new();
	}
	die(__PACKAGE__,"-> Unable to load Config File : $FILEXConfig") if ! defined($self->{'_config_'});
	# initialize the Apache::Request object
	if ( exists($ARGZ{'with_upload'}) && $ARGZ{'with_upload'} == 1 ) {
		my %ReqParams = (
			DISABLE_UPLOADS => 0,
			TEMP_DIR => $self->{'_config_'}->getTmpFileDir()
		);
		#$ReqParams{'POST_MAX'} = $self->{'_config_'}->getMaxFileSize() if ( $self->{'_config_'}->getMaxFileSize() );
		# has hook
		if ( exists($ARGZ{'with_hook'}) && ref($ARGZ{'with_hook'}) eq "HASH" ) {
			my $with_hook = $ARGZ{'with_hook'};
			if ( exists($with_hook->{'upload_hook'}) && ref($with_hook->{'upload_hook'}) eq "CODE" ) {
				$ReqParams{'UPLOAD_HOOK'} = $ARGZ{'with_hook'}->{'upload_hook'};
				$ReqParams{'HOOK_DATA'} = $ARGZ{'with_hook'}->{'hook_data'};
			}
		}
		$self->{'_apreq_'} = Apache::Request->new($r,%ReqParams);
	} else {
		$self->{'_apreq_'} = Apache::Request->new($r);
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
	# initialize CAS server
	$self->{'_cas_'} = FILEX::System::Auth::CAS->new(casUrl=>$self->{'_config_'}->getCasServer());
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

# return exlude object
sub _exclude {
	my $self = shift;
	# load on demand
	if ( !$self->{'_exclude_'} ) {
		$self->{'_exclude_'} = FILEX::System::Exclude->new(ldap=>$self->ldap());
	}
	return $self->{'_exclude_'};
}

# return quota object
sub _quota {
	my $self = shift;
	# load on demand
	if ( !$self->{'_quota_'} ) {
		$self->{'_quota_'} = FILEX::System::Quota->new(config=>$self->config(),ldap=>$self->ldap());
	}
	return $self->{'_quota_'}
}

# return FILEX::System::Mail object
sub mail {
	my $self = shift;
	# load on demand
	if ( ! $self->{'_mail_'} ) {
		$self->{'_mail_'} = FILEX::System::Mail->new(
			server=>$self->config->getSmtpServer(),
			hello=>$self->config->getSmtpHello(),
			timeout=>$self->config->getSmtpTimeout());
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

# get the authentified user
sub getAuthUser {
	my $self = shift;
	return $self->{'_username_'}
}

# get quota for a user
# return both MFS & MUS
sub getQuota {
	my $self = shift;
	my $uid = shift;
	my $q = $self->_quota();
	return ( $q ) ? $q->getQuota($uid) : (0,0);
}

#
# begin session
# 
# with no_auth => 1 then only cookie is read but authentification is not processed
#
sub beginSession {
	my $self = shift;
	my %ARGZ = @_;
	my $r = $self->apreq();
	my $isValid = undef;
	my $err_mesg = undef;
	# check if in no_auth mode (ie : simply read cookie)
	my $noAuth = ( exists($ARGZ{'no_auth'}) && defined($ARGZ{'no_auth'}) && ($ARGZ{'no_auth'} == 1) ) ? 1 : 0;
	# cookie
	my $ckname = $self->config->getCookieName();
	my $cktime = $self->config->getCookieExpires();
	my $ckmagik = $self->config->getCookieMagik();
	my $acookie = Apache::Cookie->new($r);
	my $cookie = $acookie->parse();
	#
	# check if we are authenticated
	#

	# reset username before begin
	$self->{'_username_'} = undef;
	if ( $cookie && exists($cookie->{$ckname}) ) {
		$self->{'_havecookie_'} = 1;
		my $ckvalue = _decryptData($ckmagik,$cookie->{$ckname}->value());
		# retrieve cookie expire time & username
		my ($cketime,$ckuname) = split("\t",$ckvalue);
		my $ctime = time;
		# if cookie expires then re-auth
		if ( $ctime < $cketime ) {
			$self->{'_username_'} = $ckuname;
			$isValid = 1 if ( defined($self->{'_username_'}) && length($self->{'_username_'}) > 0 );
		}
	}
	# 
	# if no authentification mode then return here
	# you can check if a user is auth with the method getAuthUser()
	# 
	return 1 if ($noAuth == 1);
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
				warn(__PACKAGE__,"-> Unable to retrieve user : ",$self->{'_auth_'}->get_error());
				$err_mesg = "invalid credential";
			}
			if ( defined($user) && length($user) > 0 ) {
				$self->{'_username_'} = $user;
				# get current time for expiration
				my $cketime = time + $cktime;
				$self->{'_cookie_'} = _genCookie($r,-name=>$ckname,-value=>_encryptData($ckmagik,"$cketime\t$user"));
				$isValid = 1;
			}
		}
	}
	#
	# if valid then check for exclude
	#
	if ( $isValid ) {
		if ( $self->_isExclude($self->{'_username_'}) ) {
			$isValid = undef;
			warn(__PACKAGE__,"-> user [$self->{'_username_'}] is Excluded !");
			# do access deny
			$self->denyAccess();
		} else {
			return 1;
		}
	}
	# No ticket, no user, no cookie, cookie expires => require auth
	if ( $self->{'_auth_'}->needRedirect() ) {
		$self->_redirectAuth($self->{'_auth_'}->getRedirect($self->getCurrentUrl()));
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
			$result->{'currenturl'} = $self->getCurrentUrl();
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
	my $aclang = $r->header_in("Accept-Language");
	# check for accept-language
	$aclang = $r->header_in("accept-language") if (! $aclang);
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
sub _isExclude {
	my $self = shift;
	my $uid = shift;
	# get exclude object
	my $exclude = $self->_exclude();
	return ( $exclude ) ? $exclude->isExclude($uid) : 1;
}

# process authentification
# return a username if successfull
sub _processAuth {
	my $self = shift;
	my $ticket = shift;
	my $user = $self->{'_cas_'}->validateST($self->getCurrentUrl(), $ticket);
	return $user;
}

# here we quit the application
sub _redirectAuth {
	my $self = shift;
	my $redirect_url = shift;
	my $r = $self->apreq();
	# if we have cookie then destroy it
	if ( $self->{'_havecookie_'} == 1 ) {
		my $dcookie = _genCookie($r,-name=>$self->config->getCookieName(),
			-value=>"",
			-expires=>"-1Y");
		$r->err_headers_out->add("Set-Cookie",$dcookie);
	}
	$r->header_out(Location=>$redirect_url);
	$r->status(REDIRECT);
	$r->send_http_header();
	exit(OK);
}

sub _doLogin {
	my $self = shift;
	my $mesg = shift;
	$self->{'_dropcookie_'} = 1;
	# load template
	my $t = $self->getTemplate(name=>"login");
	# fill template
	$t->param(FILEX_STATIC_FILE_BASE=>$self->getStaticUrl());
	$t->param(FILEX_SYSTEM_EMAIL=>$self->config->getSystemEmail());
	$t->param(FILEX_LOGIN_FORM_ACTION=>$self->getCurrentUrl());
	$t->param(FILEX_LOGIN_FORM_LOGIN_FIELD_NAME=>LOGIN_FORM_LOGIN_FIELD_NAME);
	$t->param(FILEX_LOGIN_FORM_PASSWORD_FIELD_NAME=>LOGIN_FORM_PASSWORD_FIELD_NAME);
	if ( $mesg ) {
		$t->param(FILEX_HAS_ERROR=>1);
		$t->param(FILEX_ERROR=>$self->i18n->localizeToHtml($mesg));
	}
	$self->sendHeader('Content-Type'=>"text/html");
	$self->apreq->print($t->output()) if ( $t && !$self->apreq->header_only() );
	exit(OK);
}

sub denyAccess {
	my $self = shift;
	my $r = $self->apreq();
	# if we have a cookie then destroy it
	$self->{'_dropcookie_'} = 1;
	# load access deny template
	my $t = $self->getTemplate(name=>"access_deny");
	# fill template
	$t->param(STATIC_FILE_BASE=>$self->getStaticUrl());
	$t->param(ERROR=>$self->i18n->localizeToHtml("access deny"));
	$t->param(SYSTEMEMAIL=>$self->config->getSystemEmail());
	$self->sendHeader('Content-Type'=>"text/html");
	$r->print($t->output()) if ( $t && ! $r->header_only() );
	exit(OK);
}

# create a new cookie en return has string
sub _genCookie {
	my $r = shift;
	my $c = Apache::Cookie->new($r,@_);
	return $c->as_string;
}

# encrypt datas (CF : Apache::Cookie::Encrypted)
sub _encryptData {
	my $key = shift;
	my $data = shift;
	my $cipher = new Crypt::CBC($key,'Blowfish');
                                                                                                                      
	if (ref($data) eq "ARRAY") {
		for (my $i = 0; $i <= $#$data; $i++) {
			$data->[$i] = $cipher->encrypt_hex($data->[$i]);
		}
	} else {
		$data = $cipher->encrypt_hex( $data );
	}
	return $data;
}

# decrypt datas
sub _decryptData {
	my $key = shift;
	my $data = shift;
	my $cipher = new Crypt::CBC($key,'Blowfish');
	
	if (ref($data) eq "ARRAY") {
		for (my $i = 0; $i <= $#$data; $i++) {
			$data->[$i] = $cipher->decrypt_hex($data->[$i]);
		}
	} else {
		$data = $cipher->decrypt_hex( $data );
	}
	return $data;
}

# mandatory : content-type
sub sendHeader {
	my $self = shift;
	my $r = $self->apreq();
	$self->prepareHeader(@_);
	$r->send_http_header();
}

sub prepareHeader {
	my $self = shift;
	my $r = $self->apreq();
	my %ARGZ = @_;
	# put cookie if needed
	if ( defined($self->{'_cookie_'}) && $self->{'_dropcookie_'} != 1 ) {
		$r->header_out("Set-Cookie",$self->{'_cookie_'});
	} elsif ( $self->{'_dropcookie_'} == 1 && $self->{'_havecookie_'} == 1 ) {
		# destroy cookie
		$r->header_out("Set-Cookie",_genCookie(
			$r,-name=>$self->config->getCookieName(),
			-value=>"",
			-expires=>"-1Y")); 
	}
	# set content-type
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
		$r->header_out("Expires","Thu 7 Nov 1974 8:00:00 GMT");
		$r->header_out("Pragma","no-cache") if !_isHttps($r);
		$r->header_out("Cache-control","public") if !_isHttps($r);
	} else {
		$r->no_cache(1);
	}
	# the rest
	while ( my ($k,$v) = each(%ARGZ) ) {
		$r->header_out($k,$v);
	}
}

sub isIE {
	my $self = shift;
	my $user_agent = $self->apreq->header_in("User-Agent");
	return ( $user_agent =~ /msie/i ) ? 1 : 0;
}

# get mail helper method
# require uname
sub getMail {
	my $self = shift;
	return $self->ldap->getMail(@_);
}

# get user real name (cn)
sub getUserRealName {
	my $self = shift;
	my $uid = shift;
	my $attr = $self->config->getLdapUsernameAttr();
	my $res = $self->ldap->getUserAttrs(uid=>$uid,attrs=>[$attr]);
	$attr = lc($attr);
	return ($res) ? $res->{$attr}->[0] : "unknown";
}

# check if admin
sub isAdmin {
	my $self = shift;
	my $uid = shift;
	my $sdb = $self->_systemdb();
	return ($sdb) ? $sdb->isAdmin($uid) : 0;
}

sub getUserDiskSpace {
	my $self = shift;
	my $sdb = $self->_systemdb();
	return ($sdb) ? $sdb->getUserDiskSpace(@_) : undef;
}

sub getUsedDiskSpace {
	my $self = shift;
	my $sdb = $self->_systemdb();
	return ($sdb) ? $sdb->getUsedDiskSpace() : undef;
}

sub getUserActiveCount {
	my $self = shift;
	my $uid = shift;
	my $sdb = $self->_systemdb();
	return ($sdb) ? $sdb->getUserActiveCount($uid) : undef;
}

sub getUserUploadCount {
	my $self = shift;
	my $uid = shift;
	my $sdb = $self->_systemdb();
	return ($sdb) ? $sdb->getUserUploadCount($uid) : undef;
}

sub getUserMaxFileSize {
	my $self = shift;
	my $uid = shift;
	my ($quota_max_file_size,$quota_max_used_space) = $self->getQuota($uid);
	my $current_user_space = $self->getUserDiskSpace($uid);
	return $self->getUserMaxFileSizeQuick($quota_max_file_size,$quota_max_used_space,$current_user_space);
}

sub getUserMaxFileSizeQuick {
	my $self = shift;
	my $quota_max_file_size = shift || 0;
	my $quota_max_used_space = shift || 0; 
	my $current_user_space = shift || 0;
	# if ( quota_max_file_size == 0 || quota_max_used_space == 0 ) then disable
	return 0 if ( $quota_max_file_size == 0 || $quota_max_used_space == 0 );
	# if $quota_max_used_space <= $current_user_space then no more upload
	# since quota_max_used_space == -1 if unlimited it's always < current_user_space 
	# because the minimal value of current_user_space is ZERO
	return 0 if (  $quota_max_used_space <= $current_user_space && $quota_max_used_space != -1 );
	# if quota_max_used_space == unlimited ( < 0 )
	return $quota_max_file_size if ( $quota_max_used_space < 0 );
	# now we have a max_used_space
	my $remaining_space = $quota_max_used_space - $current_user_space;
	# if quota_max_file_size == unlimited ( < 0 )
	return $remaining_space if ( $quota_max_file_size < 0 || $quota_max_file_size >= $remaining_space );
	# otherwise return the quota_max_file_size
	return $quota_max_file_size;
}

# send email
# from
# to 
# content
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
sub getCurrentUrl {
	my $self = shift;
	# scheme
	my $url = $self->getServerUrl();
	# if you want the query string, use :
	# $uri = Apache::Uri->parse($r);
	# $r->parsed_uri
	# $qs = $uri->query()
	# uri
	$url .= Apache::Util::escape_uri($self->apreq->uri());
	return $url;
}

# generate server url
sub getServerUrl {
	my $self = shift;
	my $s = $self->apreq->server();
	my $url = ( $self->apreq->subprocess_env('https') ) ? "https://" : "http://";
	# host_name
	$url .= $s->server_hostname();
	# port if not standard (0==80);
	$url .= ":".$s->port() if ( $s->port() != 80 && $s->port() != 443 && $s->port() != 0 );
	return $url;
}

# generate UniqId's via Data::Uniqid
sub genUniqId {
	return Data::Uniqid::luniqid();
}

# generate query string
# require a hash ref
sub genQueryString {
	my $qs = shift;
	$qs = shift if (ref($qs) eq "FILEX::System");
	return if ! (ref($qs) eq "HASH");
	my @res;
	my ($k,$v,$tmp);
	while ( ($k,$v) = each(%$qs) ) {
		$tmp = Apache::Util::escape_uri($k)."=".Apache::Util::escape_uri($v);
		push(@res,$tmp);
	}
	return join("&amp;",@res);
}

sub getManageUrl {
	my $self = shift;
	my $url = $self->getServerUrl();
	$url .= Apache::Util::escape_uri($self->config->getUriManage());
	return $url;
}

sub getUploadUrl {
	my $self = shift;
	my $url = $self->getServerUrl();
	$url .= Apache::Util::escape_uri($self->config->getUriUpload());
	return $url;
}

sub getMeterUrl {
	my $self = shift;
	my $url = $self->getServerUrl();
	$url .= Apache::Util::escape_uri($self->config->getUriMeter());
	return $url;
}

sub getAdminUrl {
	my $self = shift;
	my $url = $self->getServerUrl();
	$url .= Apache::Util::escape_uri($self->config->getUriAdmin());
	return $url;
}

sub getGetUrl {
	my $self = shift;
	my $url = $self->getServerUrl();
	$url .= Apache::Util::escape_uri($self->config->getUriGet());
	return $url;
}

sub getStaticUrl {
	my $self = shift;
	my $url = $self->getServerUrl();
	my $static_uri = $self->config->getUriStatic();
	$static_uri .= "/" if ( $static_uri !~ /.*\/^/ );
	$url .= Apache::Util::escape_uri($static_uri);
	return $url;
}

# encode string to html entities
sub toHtml {
	my $str = shift;
	$str = shift if (ref($str) eq "FILEX::System");
	return HTML::Entities::encode_entities($str);
}

# check if a a proxy request
sub isBehindProxy {
	my $self = shift;
	my @headers = ('X-Forwarded-For','Via','Client-ip','Forwarded');
	my ($count,$line);
	$count = 0;
	foreach my $hkey (@headers) {
		$line = $self->apreq->header_in($hkey);
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
		$line = $self->apreq->header_in($hkey);
		push(@proxy_infos,"$hkey = $line") if ( defined($line) && length($line) );
	}
	$infos = join("\n",@proxy_infos);
	return ( length($infos) > 255 ) ? substr($infos,0,254) : $infos;
}
# get the user_agent string
sub getUserAgent {
	my $self = shift;
	return $self->apreq->header_in('User-Agent');
}

# check if the user it it's "cancel" button
sub isConnected {
	my $self = shift;
	# IsClientConnected? Might already be disconnected for busy
	# site, if a user hits stop/reload
	# see : http://perl.apache.org/docs/1.0/guide/snippets.html#Detecting_a_Client_Abort
	my $conn = $self->apreq->connection;
	my $is_connected = $conn->aborted ? undef : 1;
	if ($is_connected) {
		my $fileno = $conn->fileno;
		if (defined $fileno) {
			my $s = IO::Select->new($fileno);
			$is_connected = $s->can_read(0) ? undef : 1;
		}
	}
	return $is_connected;
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
