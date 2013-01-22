package FILEX::System::Config;
use strict;
use vars qw($VERSION $FILE);
use Config::IniFiles;
use File::stat;
use base qw(Class::Singleton);

# some constants
use constant DBSECTION => "Database";
use constant SYSSECTION => "System";
use constant CASECTION => "Cache";
use constant LDAPSECTION => "Ldap";
use constant ATTRIBUTESECTION => "Attribute";
use constant URISECTION => "Uri";
use constant SMTPSECTION => "Smtp";
use constant ADMSECTION => "Admin";

$VERSION = 1.1;
$FILE = undef;

sub _new_instance {
	my $this = shift;
	my $class = ref($this) || $this;
	my $self = {
		_config_path_ => undef,
		_config_ => undef
	};
	# init
	_initialize_($self,@_);
	bless($self,$class);
	return $self;
}

# initialize structure
sub _initialize_ {
	my $self = shift;
	my %ARGZ = @_;
	die(__PACKAGE__,"-> Require a Configuration file") if (  !defined($FILE) && !exists($ARGZ{'file'}) );
	# override globals
	$self->{'_config_path_'} = exists($ARGZ{'file'}) ? $ARGZ{'file'} : $FILE;
	# create new Config::IniFile
	$self->{'_config_'} = new Config::IniFiles(-file=>$self->{'_config_path_'},-reloadwarn=>1) or 
		die(__PACKAGE__,"=> Unable to Read Config File : ",$self->{'_config_path_'});
	# check values
	eval { _validate_($self->{'_config_'}) };
	if ($@) {
	    warn "$@\n";
	    die(__PACKAGE__,"-> Config File : ",$self->{'_config_path_'}," contains error !\n") 
	}
	# stat the file
	#my $st = stat(${$self->{'_config_path_'}});
 	#if ( ! $st ) {
	#	warn(__PACKAGE__,"-> Unable to stat ",${$self->{'_config_path_'}});
	#	return undef;
	#}
	# mtime is gmt
	#$self->{'_cmtime_'} = $st->mtime();
	#return 1;
}

# Validate INI Files
sub _validate_ {
	my $config = shift;
	my $tst_value;

	# [Database]
	_validate_mandatory_value($config, DBSECTION, "Name");
	_validate_mandatory_value($config, DBSECTION, "Username");
	# [Database].Password not mandatory

	# [System]
	_validate_mandatory_directory($config, SYSSECTION, "TmpFileDir");
	_validate_mandatory_directory($config, SYSSECTION, "FileRepository");
	_validate_mandatory_directory($config, SYSSECTION,"StaticFileDir");
	_validate_mandatory_value($config, SYSSECTION, "TemplateIniFile");
	$tst_value = $config->val(SYSSECTION,"TemplateIniFile");
	if ( ! -f $tst_value ) {
		die(__PACKAGE__,"-> [".SYSSECTION."].TemplateIniFile does not exists : $tst_value !\n");
	}
	# [System].DefaultFileExpire
	# [System].MaxFileExpire
	# [System].MinFileExpire
	my ($dfe,$maxfe,$minfe);
	$minfe = abs(int($config->val(SYSSECTION,"MinFileExpire",1)));
	$dfe = abs(int($config->val(SYSSECTION,"DefaultFileExpire",7)));
	$maxfe = abs(int($config->val(SYSSECTION,"MaxFileExpire",7)));
	if ( $minfe > $maxfe ) {
		die(__PACKAGE__,"-> [".SYSSECTION."].MinFileExpire > [".SYSSECTION."]MaxFileExpire\n");
	}
	if ( $dfe > $maxfe ) {
		die(__PACKAGE__,"-> [".SYSSECTION."].DefaultFileExpire > [".SYSSECTION."]MaxFileExpire\n");
	}
	# [System].MaxFileSize
	# [System].MaxUsedSpace
	# [System].EmailNotify

	if ( $config->val(SYSSECTION, "EmailNotify") == 1 ) {
		# [Smtp]
		_validate_mandatory_value($config, SMTPSECTION, "Server");
	}
	_validate_mandatory_value($config, SYSSECTION,"CasServer");
	_validate_mandatory_directory($config, SYSSECTION,"SessionDirectory");
	_validate_mandatory_directory($config, SYSSECTION,"SessionLockDirectory");

	# [Ldap]
	_validate_mandatory_value($config, LDAPSECTION,"ServerUrl");

	# [Attribute]
	_validate_mandatory_value($config, ATTRIBUTESECTION,"UidAttr");
	_validate_mandatory_value($config, ATTRIBUTESECTION,"MailAttr");
	_validate_mandatory_value($config, ATTRIBUTESECTION,"UsernameAttr");	
	# [Ldap].GroupQuery not mandatory

	# [Uri]
	_validate_mandatory_url($config, URISECTION,"get");
	_validate_mandatory_url($config, URISECTION,"upload");
	_validate_mandatory_url($config, URISECTION,"meter");
	_validate_mandatory_url($config, URISECTION,"manage");

	# [Admin]
	_validate_mandatory_value($config, ADMSECTION,"Modules");
	_validate_mandatory_value($config, ADMSECTION,"Default");
	_validate_mandatory_value($config, ADMSECTION,"ModuleRouteParameter");
}

sub _validate_section_exists {
    my ($config, $section) = @_;

    if ( $config->SectionExists($section) != 1 ) {
	die(__PACKAGE__,"-> [" . $section . "] is mandatory !\n");
    }
}

sub _validate_mandatory_value {
    my ($config, $section, $name) = @_;

    _validate_section_exists($config, $section);

    my $tst_value = $config->val($section, $name);
    if ( !$tst_value || length($tst_value) <= 0 ) {
	die(__PACKAGE__,"-> [" . $section . "].$name is mandatory !\n");
    }
}

sub _validate_mandatory_directory {
    my ($config, $section, $name) = @_;

    _validate_mandatory_value($config, $section, $name);

    my $tst_value = $config->val($section, $name);
    if ( ! -d $tst_value ) {
	die(__PACKAGE__,"-> [" . $section . "].$name is not a directory : $tst_value !\n");
    }
}

sub _validate_mandatory_url {
    my ($config, $section, $name) = @_;

    _validate_mandatory_value($config, $section, $name);

    my $tst_value = $config->val($section, $name);
    if ( $tst_value !~ m!^/! ) {
	die(__PACKAGE__,"-> [" . $section . "].$name : invalid uri : $tst_value !\n");
    }
}

sub getConfigFile {
	my $self = shift;
	return $self->{'_config_path_'};
}

# Reload Configuration File if needed
sub _reload {
	my $self = shift;
	# return if we don't need reload
	return if ( !${$self->{'_reload_'}} );
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
	# get current modified time
	my $st_mtime = $st->mtime();
	# return if no reload needed
	if ( $self->{'_cmtime_'} < $st_mtime ) {
		warn(__PACKAGE__,"-> Need to Reload ",${$self->{'_config_path_'}},":",$self->{'_cmtime_'},":",$st_mtime);
		$self->{'_cmtime_'} = $st_mtime;
	} else {
		return;
	}
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

# MinPasswordLength 
sub getMinPasswordLength {
	my $self = shift;
	#$self->_reload();
	my $value = int($self->{'_config_'}->val(SYSSECTION,"MinPasswordLength",4));
	$value = 4 if ($value <= 0 || $value > 30);
	return $value;
}

#MaxPasswordLength
sub getMaxPasswordLength {
	my $self = shift;
	#$self->_reload();
	my $value = int($self->{'_config_'}->val(SYSSECTION,"MaxPasswordLength",4));
	$value = 30 if ( $value <= 0 || $value > 30);
	return $value;
}

# Which authentification module to use
sub getAuthModule {
	my $self = shift;
	#$self->_reload();
	return $self->{'_config_'}->val(SYSSECTION,"AuthModule","AuthCAS");
}

sub isShib {
	my $self = shift;
	return $self->getAuthModule eq 'AuthShib';
}

# Get Meter Refrech Delay (default to 5 seconds)
sub getMeterRefreshDelay {
	my $self = shift;
	#$self->_reload();
	return $self->{'_config_'}->val(SYSSECTION,"MeterRefreshDelay",5);
}

# Get Database Name
sub getDBName {
	my $self = shift;
	#$self->_reload();
	return $self->{'_config_'}->val(DBSECTION,"Name");
}

# Get Database Username
sub getDBUsername {
	my $self = shift;
	#$self->_reload();
	return $self->{'_config_'}->val(DBSECTION,"Username");
}

# Get Database Password
sub getDBPassword {
	my $self = shift;
	#$self->_reload();
	return $self->{'_config_'}->val(DBSECTION,"Password","");
}

sub getDBHost {
	my $self = shift;
	#$self->_reload();
	return $self->{'_config_'}->val(DBSECTION,"Host","localhost");
}

sub getDBPort {
	my $self = shift;
	#$self->_reload();
	return $self->{'_config_'}->val(DBSECTION,"Port",undef);
}
sub getDBSocket {
	my $self = shift;
	#$self->_reload();
	return $self->{'_config_'}->val(DBSECTION,"Socket",undef);
}
# HostName
sub getHostName {
	my $self = shift;
	#$self->_reload();
	return $self->{'_config_'}->val(SYSSECTION,"HostName",undef);
}
# Get Temporary Directory
sub getTmpFileDir {
	my $self = shift;
	#$self->_reload();
	return $self->{'_config_'}->val(SYSSECTION,"TmpFileDir");
}

# Get File Repository Directory
sub getFileRepository {
	my $self = shift;
	#$self->_reload();
	return $self->{'_config_'}->val(SYSSECTION,"FileRepository");
}

sub getStaticFileDir {
	my $self = shift;
	#$self->_reload();
	return $self->{'_config_'}->val(SYSSECTION,"StaticFileDir");
}

# Get Max Upload File Size
sub getMaxFileSize {
	my $self = shift;
	#$self->_reload();
	my $value = $self->{'_config_'}->val(SYSSECTION,"MaxFileSize",-1);
	# check if an integer
	$value = ( $value !~ /^-?[0-9]+$/ || $value < 0 ) ? -1 : $value;
	return $value;
}

# get Max Concurrent Used space for a user
sub getMaxUsedSpace {
	my $self = shift;
	#$self->_reload();
	my $value = $self->{'_config_'}->val(SYSSECTION,"MaxUsedSpace",-1);
	# check if an integer
	$value = ( $value !~ /^-?[0-9]+$/ || $value < 0 ) ? -1 : $value;
	return $value;
}

sub getMaxDiskSpace {
	my $self = shift;
	#$self->_reload();
	my $value = $self->{'_config_'}->val(SYSSECTION,"MaxDiskSpace");
	# check if an integer
	return ( $value && $value =~ /^[0-9]+$/ ) ? $value : undef;
}

sub getMaxDiskSpaceLimit {
	my $self = shift;
	#$self->_reload();
	my $value = $self->{'_config_'}->val(SYSSECTION,"MaxDiskSpaceLimit");
	return ( $value && $value =~ /^[0-9]+$/ ) ? $value : 95;
}

# Get SMTP Server
sub getSmtpServer {
	my $self = shift;
	#$self->_reload();
	return $self->{'_config_'}->val(SMTPSECTION,"Server");
}

# get SMTP Timeout
sub getSmtpTimeout {
	my $self = shift;
	#$self->_reload();
	return $self->{'_config_'}->val(SMTPSECTION,"Timeout");
}

# get SMTP Hello
sub getSmtpHello {
	my $self = shift;
	#$self->_reload();
	return $self->{'_config_'}->val(SMTPSECTION,"Hello");
}

# check if we need to notify user via email
sub needEmailNotification {
	my $self = shift;
	#$self->_reload();
	# if set to 1
	return ( $self->{'_config_'}->val(SYSSECTION,"EmailNotify") == 1 ) ? 1 : undef;
}
# check if we need to use the big brother feature
sub useBigBrother {
	my $self = shift;
	#$self->_reload();
	return ( $self->{'_config_'}->val(SYSSECTION,"UseBigBrother") == 1 ) ? 1 : 0;
}
# get CAS Server
sub getCasServer {
	my $self = shift;
	#$self->_reload();
	return $self->{'_config_'}->val(SYSSECTION,"CasServer");
}

# session directory
sub getSessionDirectory {
	my $self = shift;
	#$self->_reload();
	return $self->{'_config_'}->val(SYSSECTION,"SessionDirectory");
}
# session lock
sub getSessionLockDirectory {
	my $self = shift;
	#$self->_reload();
	return $self->{'_config_'}->val(SYSSECTION,"SessionLockDirectory");
}
# getCookieName
sub getCookieName {
	my $self = shift;
	#$self->_reload();
	return $self->{'_config_'}->val(SYSSECTION,"CookieName");
}
# retrieve cookie expiration time
sub getCookieExpires {
	my $self = shift;
	#$self->_reload();
	# default to 30 minutes if not specified
	my $cktime = $self->{'_config_'}->val(SYSSECTION,"CookieExpires",1800);
	return ($cktime =~ /^[0-9]+$/) ? $cktime : 1800;
}
sub getCookiePath {
	my $self = shift;
	# default to "/"
	my $ckpath = $self->{'_config_'}->val(SYSSECTION,"CookiePath","/");
	return $ckpath;
}
# the template directory
sub getTemplateIniFile {
	my $self = shift;
	#$self->_reload();
	return $self->{'_config_'}->val(SYSSECTION,"TemplateIniFile");
}

# get the i18n ini file
sub getI18nIniFile {
	my $self = shift;
	#$self->_reload();
	return $self->{'_config_'}->val(SYSSECTION,"I18nIniFile");
}

# check if tmpdir & repository are on the same device
# return 1 if same device or undef.
sub isSameDevice {
	my $self = shift;
	#$self->_reload();
	my ($tmp,$rep);
	# no error checking here
	$tmp = stat($self->getTmpFileDir()) || warn(__PACKAGE__,"-> unable to stat ",$self->getTmpFileDir()," : $@");
	$rep = stat($self->getFileRepository()) || warn(__PACKAGE__,"-> unable to stat ",$self->getFileRepository(), " : $@");
	return ($tmp->dev == $rep->dev) ? 1 : undef;
}

# get cache root for IPC
sub getCacheRoot {
	my $self = shift;
	#$self->_reload();
	return $self->{_config_}->val(CASECTION,"CacheRoot");
}

# get cache namespace for IPC
# default to "FILEX"
sub getCacheNamespace {
	my $self = shift;
	#$self->_reload();
	return $self->{_config_}->val(CASECTION,"Namespace","FILEX");
}

# get default expire time 
# default to 3600 seconds
sub getCacheDefaultExpire {
	my $self = shift;
	#$self->_reload();
	return abs(int($self->{_config_}->val(CASECTION,"DefaultExpire",3600)));
}

# get autopure interval
# default to 60 seconds
sub getCacheAutoPurge {
	my $self = shift;
	#$self->_reload();
	return abs(int($self->{_config_}->val(CASECTION,"AutoPurge",60)));
}

# get Ldap server url
sub getLdapServerUrl {
	my $self = shift;
	#$self->_reload();
	return $self->{_config_}->val(LDAPSECTION,"ServerUrl");
}

# get Ldap BindDN
sub getLdapBindDn {
	my $self = shift;
	#$self->_reload();
	return $self->{_config_}->val(LDAPSECTION,"BindDn");
}

# get Ldap bind password
sub getLdapBindPassword {
	my $self = shift;
	#$self->_reload();
	return $self->{_config_}->val(LDAPSECTION,"BindPassword");
}

# get ldap search base
sub getLdapSearchBase {
	my $self = shift;
	#$self->_reload();
	return $self->{_config_}->val(LDAPSECTION,"SearchBase");
}

# get ldap uid attr
sub getUidAttr {
	my $self = shift;
	#$self->_reload();
	return $self->{_config_}->val(ATTRIBUTESECTION,"UidAttr");
}

# get ldap username attr
sub getUsernameAttr {
	my $self = shift;
	#$self->_reload();
	return $self->{_config_}->val(ATTRIBUTESECTION,"UsernameAttr");
}
# get ldap uniq id attr
sub getUniqAttr {
	my $self = shift;
	#$self->_reload();
	return $self->{_config_}->val(ATTRIBUTESECTION,"UniqAttr",undef);
}
# get ldap unid id attr mode
sub getUniqAttrMode {
	my $self = shift;
	#$self->_reload();
	return $self->{_config_}->val(ATTRIBUTESECTION,"UniqAttrMode",0);
}
# get ldap mail attr
sub getMailAttr {
	my $self = shift;
	#$self->_reload();
	return $self->{_config_}->val(ATTRIBUTESECTION,"MailAttr");
}

# get ldap group query
sub getLdapGroupQuery {
	my $self = shift;
	#$self->_reload();
	return $self->{_config_}->val(LDAPSECTION,"GroupQuery");
}

# get System Email
sub getSystemEmail {
	my $self = shift;
	#$self->_reload();
	return $self->{_config_}->val(SYSSECTION,"SystemEmail");
}

# get File expiration default
sub getDefaultFileExpire {
	my $self = shift;
	#$self->_reload();
	return abs(int($self->{_config_}->val(SYSSECTION,"DefaultFileExpire",$self->getMaxFileExpire())));
}

sub getMaxFileExpire {
	my $self = shift;
	#$self->_reload();
	return abs(int($self->{_config_}->val(SYSSECTION,"MaxFileExpire",7)));
}

sub getMinFileExpire {
	my $self = shift;
	#$self->_reload();
	return abs(int($self->{_config_}->val(SYSSECTION,"MinFileExpire",1)));
}

sub getRenewFileExpire {
	my $self = shift;
	#$self->_reload();
	return abs(int($self->{_config_}->val(SYSSECTION,"RenewFileExpire",0)));
}

sub getSessionCacheTimeout() {
	my $self = shift;
	return abs(int($self->{_config_}->val(SYSSECTION,"SessionCacheTimeout",900)));
}

sub getOnExcludeNotify() {
	my $self = shift;
	return abs(int($self->{_config_}->val(SYSSECTION,"OnExcludeNotify",0)));
}

sub getExcludeExpireDays() {
	my $self = shift;
	return abs(int($self->{_config_}->val(SYSSECTION,"ExcludeExpireDays",0)));
}

sub getUriGet {
	my $self = shift;
	#$self->_reload();
	return $self->{_config_}->val(URISECTION,"get");
}

sub getUriUpload {
	my $self = shift;
	#$self->_reload();
	return $self->{_config_}->val(URISECTION,"upload");
}

sub getUriMeter {
	my $self = shift;
	#$self->_reload();
	return $self->{_config_}->val(URISECTION,"meter");
}

sub getUriAdmin {
	my $self = shift;
	#$self->_reload();
	return $self->{_config_}->val(URISECTION,"admin");
}

sub getUriManage {
	my $self = shift;
	#$self->_reload();
	return $self->{_config_}->val(URISECTION,"manage");
}

sub getUriStatic {
	my $self = shift;
	#$self->_reload();
	return $self->{_config_}->val(URISECTION,"static");
}

sub getUriManageXml {
	my $self = shift;
	#$self->_reload();
	return $self->{_config_}->val(URISECTION,"managexml",undef);
}

sub getUriSoap {
	my $self = shift;
	return $self->{_config_}->val(URISECTION,"soap",undef);
}
# admin
sub getAdminModules {
	my $self = shift;
	#$self->_reload();
	return $self->{_config_}->val(ADMSECTION,"Modules");
}

sub getAdminDefault {
	my $self = shift;
	#$self->_reload();
	return $self->{_config_}->val(ADMSECTION,"Default");
}

sub getAdminModuleRouteParameter {
	my $self = shift;
	#$self->_reload();
	return $self->{_config_}->val(ADMSECTION,"ModuleRouteParameter");
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
