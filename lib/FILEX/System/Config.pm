package FILEX::System::Config;
use strict;
use vars qw($VERSION);
use Config::IniFiles;
use File::stat;

# some constants
use constant DBSECTION => "Database";
use constant SYSSECTION => "System";
use constant CASECTION => "Cache";
use constant LDAPSECTION => "Ldap";
use constant URISECTION => "Uri";
use constant SMTPSECTION => "Smtp";

$VERSION = 1.1;

# the unique configuration path
our $ConfigPath = undef;
our $Reload = undef;
our $DieOnReload = undef;
# 
my $_ref_counter = 0;
my $_self = undef;

# maybe reload on SIGUP (Config::IniFiles->Reload)
# Die on error
# parameters :
# 	file=>config filename
# 	reload=>0|1 reload if file change
# 	dieonreload=>0|1 die on reload or continue with in memory config file
sub new {
	my $this = shift;
	my $class = ref($this) || $this;
	# check if our Unique instance is defined
	if ( !defined($FILEX::System::Config::_self) ) {
		$FILEX::System::Config::_self = {
			_config_path_ => \$ConfigPath,
			_ref_counter_ => \$_ref_counter,
			_config_ => undef,
			_cmtime_ => undef,
			_reload_ => \$Reload,
			_dieonreload_ => \$DieOnReload,
		};
		# initialize 
		return undef if ( !_INITIALIZE_($FILEX::System::Config::_self,@_) );
		bless($FILEX::System::Config::_self,$class);
	}
	${$FILEX::System::Config::_self->{'_ref_counter_'}} ++;
	return $FILEX::System::Config::_self;
}

# initialize structure
sub _INITIALIZE_ {
	my $self = shift;
	my %ARGZ = @_;
	if ( !defined($FILEX::System::Config::ConfigPath) && !exists($ARGZ{'file'}) ) {
		warn (__PACKAGE__,"-> Require a Configuration file");
		return undef;
	}
	# override globals
	${$self->{'_config_path_'}} = $ARGZ{'file'} if exists($ARGZ{'file'});
	${$self->{'_reload_'}} = 1 if (exists($ARGZ{'reload'}) && $ARGZ{'reload'} == 1);
	${$self->{'_dieonreload_'}} = 1 if ( exists($ARGZ{'dieonreload'}) && $ARGZ{'dieonreload'} == 1 );
	# create new Config::IniFile
	$self->{'_config_'} = new Config::IniFiles(-file=>${$self->{'_config_path_'}},-reloadwarn=>1);
	# die on error
	if ( !defined($self->{'_config_'}) ) {
		warn (__PACKAGE__,"-> Unable to Read Config File : ",${$self->{'_config_path'}});
		return undef;
	}
	# check values
	if ( ! _VALIDATE_($self->{'_config_'}) ) {
		warn (__PACKAGE__,"-> Config File : ",${$self->{'_config_path_'}}," contains error !");
		return undef;
	}
	# stat the file
	my $st = stat(${$self->{'_config_path_'}});
 	if ( ! $st ) {
		warn(__PACKAGE__,"-> Unable to stat ",${$self->{'_config_path_'}});
		return undef;
	}
	# mtime is gmt
	$self->{'_cmtime_'} = $st->mtime();
	return 1;
}

# Validate INI Files
sub _VALIDATE_ {
	my $config = shift;
	my $tst_value;
	# Validate Database Section
	if ( $config->SectionExists(DBSECTION) != 1 ) {
		warn(__PACKAGE__,"-> [".DBSECTION."] is mandatory !");
		return undef;
	}
	# [Database].Name
	$tst_value = $config->val(DBSECTION, "Name");
	if ( !$tst_value || length($tst_value) <= 0 ) {
		warn(__PACKAGE__,"-> [".DBSECTION."].Name is mandatory !");
		return undef;
	}
	# [Database].Username
	$tst_value = $config->val(DBSECTION, "Username");
	if ( !$tst_value || length($tst_value) <= 0 ) {
		warn(__PACKAGE__,"-> [".DBSECTION."].Username is mandatory !");
		return undef;
	}
	# [Database].Password not mandatory
	# Validate System Section
	if ( $config->SectionExists(SYSSECTION) != 1 ) {
		warn(__PACKAGE__,"-> [".SYSSECTION."] is mandatory !");
		return undef;
	}
	# [System].TmpFileDir
	$tst_value = $config->val(SYSSECTION, "TmpFileDir");
	if ( !$tst_value || length($tst_value) <= 0 ) {
		warn(__PACKAGE__,"-> [".SYSSECTION."].TmpFileDir is mandatory !");
		return undef;
	}
	if ( ! -d $tst_value ) {
		warn(__PACKAGE__,"-> [".SYSSECTION."].TmpFileDir is not a directory : $tst_value !");
		return undef;
	}
	# [System].FileRepository
	$tst_value = $config->val(SYSSECTION, "FileRepository");
	if ( !$tst_value || length($tst_value) <= 0 ) {
		warn(__PACKAGE__,"-> [".SYSSECTION."].FileRepository is mandatory !");
		return undef;
	}
	if ( ! -d $tst_value ) {
		warn(__PACKAGE__,"-> [".SYSSECTION."].FileRepository is not a directory : $tst_value !");
		return undef;
	}
  # [System].StaticFileDir
	$tst_value = $config->val(SYSSECTION,"StaticFileDir");
	if ( !$tst_value || length($tst_value) <= 0 ) {
		warn(__PACKAGE__,"-> [".SYSSECTION."].StaticFileDir is mandatory !");
		return undef;
	}
	if ( ! -d $tst_value ) {
		warn(__PACKAGE__,"-> [".SYSSECTION."].StaticFileDir is not a directory : $tst_value !");
		return undef;
	}
	# [System].TemplateIniFile
	$tst_value = $config->val(SYSSECTION, "TemplateIniFile");
	if ( !$tst_value || length($tst_value) <= 0 ) {
		warn(__PACKAGE__,"-> [".SYSSECTION."].TemplateIniFile is mandatory !");
		return undef;
	}
	# [System].DefaultFileExpire
	# [System].MaxFileExpire
	# [System].MinFileExpire
	my ($dfe,$maxfe,$minfe);
	$minfe = abs(int($config->val(SYSSECTION,"MinFileExpire",1)));
	$dfe = abs(int($config->val(SYSSECTION,"DefaultFileExpire",7)));
	$maxfe = abs(int($config->val(SYSSECTION,"MaxFileExpire",7)));
	if ( $minfe > $maxfe ) {
		warn(__PACKAGE__,"-> [".SYSSECTION."].MinFileExpire > [".SYSSECTION."]MaxFileExpire");
		return undef;
	}
	if ( $dfe > $maxfe ) {
		warn(__PACKAGE__,"-> [".SYSSECTION."].DefaultFileExpire > [".SYSSECTION."]MaxFileExpire");
		return undef;
	}
	#
	if ( ! -f $tst_value ) {
		warn(__PACKAGE__,"-> [".SYSSECTION."].TemplateIniFile does not exists : $tst_value !");
		return undef;
	}
	# [System].MaxFileSize
	# [System].MaxUsedSpace
	# [System].EmailNotify
	if ( $config->val(SYSSECTION, "EmailNotify") == 1 ) {
		# [System].SmtpServer
		if ( $config->SectionExists(SMTPSECTION) != 1 ) {
			warn(__PACKAGE__,"-> [".SMTPSECTION."] is mandatory if [".SYSSECTION."].EmailNotify=1");
			return undef;
		}
		$tst_value = $config->val(SMTPSECTION, "Server");
		if ( !$tst_value || length($tst_value) <= 0 ) {
			warn(__PACKAGE__,"-> [".SMTPSECTION."].Server is mandatory if [".SYSSECTION."].EmailNotify=1");
			return undef;
		}
	}
	# [System].CasServer
	$tst_value = $config->val(SYSSECTION,"CasServer");
	if ( !$tst_value || length($tst_value) <= 0 ) {
			warn(__PACKAGE__,"-> [".SYSSECTION."].CasServer is mandatory !");
			return undef;
	}

	# [Ldap]
	if ( $config->SectionExists(LDAPSECTION) != 1 ) {
		warn(__PACKAGE__,"-> [".LDAPSECTION."] is mandatory !");
		return undef;
	}
	# [Ldap].ServerUrl
	$tst_value = $config->val(LDAPSECTION,"ServerUrl");
	if ( !$tst_value || length($tst_value) <= 0 ) {
		warn(__PACKAGE__,"-> [".LDAPSECTION."].ServerUrl is mandatory !");
		return undef;
	}
	# [Ldap].UidAttr
	$tst_value = $config->val(LDAPSECTION,"UidAttr");
	if ( !$tst_value || length($tst_value) <= 0 ) {
		warn(__PACKAGE__,"-> [".LDAPSECTION."].UidAttr is mandatory !");
		return undef;
	}
	
	# [Ldap].MailAttr
	$tst_value = $config->val(LDAPSECTION,"MailAttr");
	if ( !$tst_value || length($tst_value) <= 0 ) {
		warn(__PACKAGE__,"-> [".LDAPSECTION."].MailAttr is mandatory !");
		return undef;
	}

	# [ldap].UsernameAttr
	$tst_value = $config->val(LDAPSECTION,"UsernameAttr");	
	if ( !$tst_value || length($tst_value) <= 0 ) {
		warn(__PACKAGE__,"-> [".LDAPSECTION."].UsernameAttr is mandatory !");
		return undef;
	}

	# [Ldap].GroupQuery
	# not mandatory !

	# [Uri]
	if ( $config->SectionExists(URISECTION) != 1 ) {
		warn(__PACKAGE__,"-> [".URISECTION."] is mantatory !");
		return undef;
	}
	# [Uri].get
	$tst_value = $config->val(URISECTION,"get");
	if ( !$tst_value || length($tst_value) <= 0 ) {
		warn(__PACKAGE__,"-> [".URISECTION."].get is mandatory !");
		return undef;
	}
	warn(__PACKAGE__,"-> [".URISECTION."].get : invalid uri : $tst_value !") && return undef if ( $tst_value !~ /^\//);
	# [Uri].upload
	$tst_value = $config->val(URISECTION,"upload");
	if ( !$tst_value || length($tst_value) <= 0 ) {
		warn(__PACKAGE__,"-> [".URISECTION."].upload is mandatory !");
		return undef;
	}
	warn(__PACKAGE__,"-> [".URISECTION."].upload : invalid uri : $tst_value !") && return undef if ( $tst_value !~ /^\//);
	# [Uri].meter
	$tst_value = $config->val(URISECTION,"meter");
	if ( !$tst_value || length($tst_value) <= 0 ) {
		warn(__PACKAGE__,"-> [".URISECTION."].meter is mandatory !");
		return undef;
	}
	warn(__PACKAGE__,"-> [".URISECTION."].meter : invalid uri : $tst_value !") && return undef if ( $tst_value !~ /^\//);
	# [Uri].manage
	$tst_value = $config->val(URISECTION,"manage");
	if ( !$tst_value || length($tst_value) <= 0 ) {
		warn(__PACKAGE__,"-> [".URISECTION."].manage is mandatory !");
		return undef;
	}
	warn(__PACKAGE__,"-> [".URISECTION."].manage : invalid uri : $tst_value !") && return undef if ( $tst_value !~ /^\//);
	
	return 1;
}

# Reload Configuration File if needed
sub _reload {
	my $self = shift;
	# return if we don't need reload
	return if ( ! ${$self->{'_reload_'}} );
	# inline error function
	my $errfunc;
	if ( ${$self->{'_dieonreload_'}} ) {
		$errfunc = sub { die(__PACKAGE__,"-> ",@_); }; 
	} else { 
		$errfunc = sub { warn(__PACKAGE__,"-> ",@_); };
	}
	# stat file
	my $st = stat(${$self->{'_config_path_'}});
	# if no file
	if ( !$st ) {
		$errfunc->("Unable to stat ",${$self->{'_config_path_'}});
		return undef;
	}
	my $st_mtime = $st->mtime();
	# return if no reload needed
	if ( $self->{'_cmtime_'} < $st_mtime ) {
		$self->{'_cmtime_'} = $st_mtime;
	} else {
		return;
	}
	warn(__PACKAGE__,"-> Need to Reload ",${$self->{'_config_path_'}},":",$self->{'_cmtime_'});
	if ( ! $self->{'_config_'}->ReadConfig() ) {
		$errfunc->("Unable to Re-Read Configuration File ",${$self->{'_config_path_'}});
		return undef;
	}
	# Finaly check for values
	if ( ! _VALIDATE_($self->{'_config_'}) ) {
		$errfunc->("Configuration File ",${$self->{'_config_path_'}}, " contains error !");
		return undef;
	}
	return 1;
}

# Which authentification module to use
sub getAuthModule {
	my $self = shift;
	$self->_reload();
	return $self->{'_config_'}->val(SYSSECTION,"AuthModule","AuthCAS");
}

# Get Meter Refrech Delay (default to 5 seconds)
sub getMeterRefreshDelay {
	my $self = shift;
	$self->_reload();
	return $self->{'_config_'}->val(SYSSECTION,"MeterRefreshDelay",5);
}

# Get Database Name
sub getDBName {
	my $self = shift;
	$self->_reload();
	return $self->{'_config_'}->val(DBSECTION,"Name");
}

# Get Database Username
sub getDBUsername {
	my $self = shift;
	$self->_reload();
	return $self->{'_config_'}->val(DBSECTION,"Username");
}

# Get Database Password
sub getDBPassword {
	my $self = shift;
	$self->_reload();
	return $self->{'_config_'}->val(DBSECTION,"Password","");
}

sub getDBHost {
	my $self = shift;
	$self->_reload();
	return $self->{'_config_'}->val(DBSECTION,"Host","localhost");
}

sub getDBPort {
	my $self = shift;
	$self->_reload();
	return $self->{'_config_'}->val(DBSECTION,"Port");
}

# Get Temporary Directory
sub getTmpFileDir {
	my $self = shift;
	$self->_reload();
	return $self->{'_config_'}->val(SYSSECTION,"TmpFileDir");
}

# Get File Repository Directory
sub getFileRepository {
	my $self = shift;
	$self->_reload();
	return $self->{'_config_'}->val(SYSSECTION,"FileRepository");
}

sub getStaticFileDir {
	my $self = shift;
	$self->_reload();
	return $self->{'_config_'}->val(SYSSECTION,"StaticFileDir");
}

# Get Max Upload File Size
sub getMaxFileSize {
	my $self = shift;
	$self->_reload();
	my $value = $self->{'_config_'}->val(SYSSECTION,"MaxFileSize",-1);
	# check if an integer
	$value = ( $value !~ /^-?[0-9]+$/ || $value < 0 ) ? -1 : $value;
	return $value;
}

# get Max Concurrent Used space for a user
sub getMaxUsedSpace {
	my $self = shift;
	$self->_reload();
	my $value = $self->{'_config_'}->val(SYSSECTION,"MaxUsedSpace",-1);
	# check if an integer
	$value = ( $value !~ /^-?[0-9]+$/ || $value < 0 ) ? -1 : $value;
	return $value;
}

sub getMaxDiskSpace {
	my $self = shift;
	$self->_reload();
	my $value = $self->{'_config_'}->val(SYSSECTION,"MaxDiskSpace");
	# check if an integer
	return ( $value && $value =~ /^[0-9]+$/ ) ? $value : undef;
}

sub getMaxDiskSpaceLimit {
	my $self = shift;
	$self->_reload();
	my $value = $self->{'_config_'}->val(SYSSECTION,"MaxDiskSpaceLimit");
	return ( $value && $value =~ /^[0-9]+$/ ) ? $value : 95;
}

# Get SMTP Server
sub getSmtpServer {
	my $self = shift;
	$self->_reload();
	return $self->{'_config_'}->val(SMTPSECTION,"Server");
}

# get SMTP Timeout
sub getSmtpTimeout {
	my $self = shift;
	$self->_reload();
	return $self->{'_config_'}->val(SMTPSECTION,"Timeout");
}

# get SMTP Hello
sub getSmtpHello {
	my $self = shift;
	$self->_reload();
	return $self->{'_config_'}->val(SMTPSECTION,"Hello");
}

# check if we need to notify user via email
sub needEmailNotification {
	my $self = shift;
	$self->_reload();
	# if set to 1
	return ( $self->{'_config_'}->val(SYSSECTION,"EmailNotify") == 1 ) ? 1 : undef;
}

# get CAS Server
sub getCasServer {
	my $self = shift;
	$self->_reload();
	return $self->{'_config_'}->val(SYSSECTION,"CasServer");
}

# getCookieName
sub getCookieName {
	my $self = shift;
	$self->_reload();
	return $self->{'_config_'}->val(SYSSECTION,"CookieName");
}

# retrieve cookie expiration time
sub getCookieExpires {
	my $self = shift;
	$self->_reload();
	# default to 30 minutes if not specified
	my $cktime = $self->{'_config_'}->val(SYSSECTION,"CookieExpires",1800);
	return ($cktime =~ /^[0-9]+$/) ? $cktime : 1800;
}

# get Cookie magic
sub getCookieMagik {
	my $self = shift;
	$self->_reload();
	return $self->{'_config_'}->val(SYSSECTION,"CookieMagik","MaGiK");
}

# the template directory
sub getTemplateIniFile {
	my $self = shift;
	$self->_reload();
	return $self->{'_config_'}->val(SYSSECTION,"TemplateIniFile");
}

# get the i18n ini file
sub getI18nIniFile {
	my $self = shift;
	$self->_reload();
	return $self->{'_config_'}->val(SYSSECTION,"I18nIniFile");
}

# check if tmpdir & repository are on the same device
# return 1 if same device or undef.
sub isSameDevice {
	my $self = shift;
	$self->_reload();
	my ($tmp,$rep);
	# no error checking here
	$tmp = stat($self->getTmpFileDir()) || warn(__PACKAGE__,"-> unable to stat ",$self->getTmpFileDir()," : $@");
	$rep = stat($self->getFileRepository()) || warn(__PACKAGE__,"-> unable to stat ",$self->getFileRepository(), " : $@");
	return ($tmp->dev == $rep->dev) ? 1 : undef;
}

# get cache root for IPC
sub getCacheRoot {
	my $self = shift;
	$self->_reload();
	return $self->{'_config_'}->val(CASECTION,"CacheRoot");
}

# get cache namespace for IPC
# default to "FILEX"
sub getCacheNamespace {
	my $self = shift;
	$self->_reload();
	return $self->{'_config_'}->val(CASECTION,"Namespace","FILEX");
}

# get default expire time 
# default to 3600 seconds
sub getCacheDefaultExpire {
	my $self = shift;
	$self->_reload();
	return abs(int($self->{'_config_'}->val(CASECTION,"DefaultExpire",3600)));
}

# get autopure interval
# default to 60 seconds
sub getCacheAutoPurge {
	my $self = shift;
	$self->_reload();
	return abs(int($self->{'_config_'}->val(CASECTION,"AutoPurge",60)));
}

# get Ldap server url
sub getLdapServerUrl {
	my $self = shift;
	$self->_reload();
	return $self->{'_config_'}->val(LDAPSECTION,"ServerUrl");
}

# get Ldap BindDN
sub getLdapBindDn {
	my $self = shift;
	$self->_reload();
	return $self->{'_config_'}->val(LDAPSECTION,"BindDn");
}

# get Ldap bind password
sub getLdapBindPassword {
	my $self = shift;
	$self->_reload();
	return $self->{'_config_'}->val(LDAPSECTION,"BindPassword");
}

# get ldap search base
sub getLdapSearchBase {
	my $self = shift;
	$self->_reload();
	return $self->{'_config_'}->val(LDAPSECTION,"SearchBase");
}

# get ldap uid attr
sub getLdapUidAttr {
	my $self = shift;
	$self->_reload();
	return $self->{'_config_'}->val(LDAPSECTION,"UidAttr");
}

# get ldap username attr
sub getLdapUsernameAttr {
	my $self = shift;
	$self->_reload();
	return $self->{'_config_'}->val(LDAPSECTION,"UsernameAttr");
}

# get ldap mail attr
sub getLdapMailAttr {
	my $self = shift;
	$self->_reload();
	return $self->{'_config_'}->val(LDAPSECTION,"MailAttr");
}

# get ldap group query
sub getLdapGroupQuery {
	my $self = shift;
	$self->_reload();
	return $self->{'_config_'}->val(LDAPSECTION,"GroupQuery");
}

# get System Email
sub getSystemEmail {
	my $self = shift;
	$self->_reload();
	return $self->{'_config_'}->val(SYSSECTION,"SystemEmail");
}

# get File expiration default
sub getDefaultFileExpire {
	my $self = shift;
	$self->_reload();
	return abs(int($self->{'_config_'}->val(SYSSECTION,"DefaultFileExpire",$self->getMaxFileExpire())));
}

sub getMaxFileExpire {
	my $self = shift;
	$self->_reload();
	return abs(int($self->{'_config_'}->val(SYSSECTION,"MaxFileExpire",7)));
}

sub getMinFileExpire {
	my $self = shift;
	$self->_reload();
	return abs(int($self->{'_config_'}->val(SYSSECTION,"MinFileExpire",1)));
}

sub getRenewFileExpire {
	my $self = shift;
	$self->_reload();
	return abs(int($self->{'_config_'}->val(SYSSECTION,"RenewFileExpire",0)));
}

sub getUriGet {
	my $self = shift;
	$self->_reload();
	return $self->{'_config_'}->val(URISECTION,"get");
}

sub getUriUpload {
	my $self = shift;
	$self->_reload();
	return $self->{'_config_'}->val(URISECTION,"upload");
}

sub getUriMeter {
	my $self = shift;
	$self->_reload();
	return $self->{'_config_'}->val(URISECTION,"meter");
}

sub getUriAdmin {
	my $self = shift;
	$self->_reload();
	return $self->{'_config_'}->val(URISECTION,"admin");
}

sub getUriManage {
	my $self = shift;
	$self->_reload();
	return $self->{'_config_'}->val(URISECTION,"manage");
}

sub getUriStatic {
	my $self = shift;
	$self->_reload();
	return $self->{'_config_'}->val(URISECTION,"static");
}

sub isSetup {
	return( defined($FILEX::System::Config::ConfigPath) ) ? 1 : 0;
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
