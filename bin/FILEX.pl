#!/usr/bin/perl
use strict;
use lib qw(/usr/local/FILEX/lib);
use constant FILEX_CONFIG_FILE => "/usr/local/FILEX/conf/FILEX.ini";

use FILEX::System::Config;
use FILEX::DB::Sys;
use FILEX::DB::Admin::Stats;
use FILEX::System::LDAP;
use FILEX::System::Mail;
use FILEX::System::Template;
use FILEX::System::I18N;
use FILEX::Tools::Utils qw(tsToLocal hrSize rDns);
use File::Spec;
use POSIX qw(strftime);

# BEGIN
my $FILEXConf = FILEX::System::Config->new(file=>FILEX_CONFIG_FILE) or die("Unable to load Configuration File : $@");
my $FILEXDb = eval { FILEX::DB::Sys->new(name=>$FILEXConf->getDBName(),
                              user=>$FILEXConf->getDBUsername(),
                              password=>$FILEXConf->getDBPassword(),
                              host=>$FILEXConf->getDBHost(),
                              port=>$FILEXConf->getDBPort()); };
die("Unable to connect to the database : $@") if $@;
# statistics
my $FILEXDbStats = eval { FILEX::DB::Admin::Stats->new(name=>$FILEXConf->getDBName(),
	                      user=>$FILEXConf->getDBUsername(),
	                      password=>$FILEXConf->getDBPassword(),
	                      host=>$FILEXConf->getDBHost(),
	                      port=>$FILEXConf->getDBPort()); };
die("Unable to connect to the database : $@") if $@;
# ldap
my $Ldap = eval { FILEX::System::LDAP->new(server=>$FILEXConf->getLdapServerUrl(),
                    binddn=>$FILEXConf->getLdapBindDn(),
                    password=>$FILEXConf->getLdapBindPassword()); };
die("Unable to bind to ldap : $@") if ($@);
# template
my $Template = eval { FILEX::System::Template->new(inifile=>$FILEXConf->getTemplateIniFile()); };
die("Unable to load template module : $@") if ($@);
# mail
my $Mail = FILEX::System::Mail->new(server=>$FILEXConf->getSmtpServer(),
                                  hello=>$FILEXConf->getSmtpHello(),
                                  timeout=>$FILEXConf->getSmtpTimeout());
die("Unable to load Mail module") if !$Mail;
# i18n
my $I18n = FILEX::System::I18N->new(inifile=>$FILEXConf->getI18nIniFile());
die("Unable to load I18N module") if !$I18n;

# get outdated files
my @records;
my $r = $FILEXDb->getExpiredFiles(\@records);
if ( ! $r ) {
	::log("An error occured while retrieving expired files");
	exit 1;
}

# loop on results
my ($path,$file_name,$id,$is_downloaded,$bFileNotFound,$baserep,@file_downloads,$usr_mail);
$baserep = $FILEXConf->getFileRepository();

foreach my $idx (0 .. $#records) {
	$bFileNotFound = undef;
	$file_name = $records[$idx]->{'file_name'};
	$id = $records[$idx]->{'id'};
	$is_downloaded = $records[$idx]->{'is_downloaded'};
	$path = File::Spec->catfile($baserep,$file_name);
	# if there is downloads for the file skip it
	if ( $is_downloaded != 0 ) {
		::log("file is currently downloaded [name=>$file_name,id=>$id,path=>$path]");
		next;
	}
	# file not found !
	if ( ! -f $path ) {
		$bFileNotFound = 1;
		::log("File not found [name=>$file_name,id=>$id,path=>$path] marking as deleted");
	}
	# first mark as deleted next delete the file
	::log("Cannot mark file as deleted [name=>$file_name,id=>$id,path=>$path]") if ! $FILEXDb->markDeleted($id);
	next if $bFileNotFound; # next if file was not found on disk
	# delete the file
	::log("deleting file [name=>$file_name,id=>$id,path=>$path]");
	unlink($path) or ::log("Cannot delete file [name=>$file_name,id=>$id,path=>$path]");
	# now send resume to the owner of the file
	next if ( $records[$idx]->{'get_resume'} != 1 );
	# get file downloads
	if ( ! $FILEXDbStats->listDownload(id=>$records[$idx]->{'id'},results=>\@file_downloads) ) {
		::log("Unable to retrieve file download statistics [name=>$file_name,id=>$id,path=>$path]");
		next;
	}
	# get users email
	$usr_mail = getMail($records[$idx]->{'owner'});
	::log("unable to retrieve user mail for : ".$records[$idx]->{'owner'}) && next if !$usr_mail;
	# now send email
	if ( ! sendMail($usr_mail,$records[$idx],\@file_downloads) ) {
		::log("unable to send mail to : $usr_mail");
	}
}

exit 0;

# functions
sub getMail {
	my $uname = shift;
	my $baseSearch = $FILEXConf->getLdapSearchBase();
	my $mailAttr = $FILEXConf->getLdapMailAttr();
	my $uidAttr = $FILEXConf->getLdapUidAttr();
	my %searchArgz;
	$searchArgz{'base'} = $baseSearch if ( $baseSearch && length($baseSearch) );
	$searchArgz{'scope'} = "sub";
	$searchArgz{'attrs'} = [$mailAttr];
	$searchArgz{'filter'} = "($uidAttr=$uname)";
	my $mesg = $Ldap->srv->search(%searchArgz);
	if ( $mesg->is_error() || $mesg->code() ) {
		::log(__PACKAGE__,"-> LDAP error : ",$mesg->error());
		return undef;
	}
	my $h = $mesg->as_struct();
	my ($dn,$res) = each(%$h);
	return $res->{$mailAttr}->[0];
}

# to
# file_info
# downloads
sub sendMail($\%\@) {
	my $to = shift;
	my $file_infos = shift;
	my $dl_infos = shift;
	# load template
	my $t = $Template->getTemplate(name=>"mail_resume");
	::log("unable to load template : mail_resume") && return undef if !$t;
	# fill template
	$t->param(SYSTEMEMAIL=>$FILEXConf->getSystemEmail());
	$t->param(FILENAME=>$file_infos->{'real_name'});
	$t->param(FILEDATE=>tsToLocal($file_infos->{'ts_upload_date'}));
	$t->param(FILEEXPIRE=>tsToLocal($file_infos->{'ts_expire_date'}));
	my ($sz,$su) = hrSize($file_infos->{'file_size'});
	$t->param(FILESIZE=>"$sz ".$I18n->localize($su));
	$t->param(DOWNLOADCOUNT=>($#$dl_infos+1));
	# loop
	my @dl_loop;
	for ( my $i = 0; $i <= $#$dl_infos; $i++ ) {
		push(@dl_loop,{DLADDRESS=>rDns($dl_infos->[$i]->{'ip_address'}) || $dl_infos->[$i]->{'ip_address'},DLDATE=>tsToLocal($dl_infos->[$i]->{'ts_date'})});
	}
	$t->param(DL_LOOP=>\@dl_loop) if ($#dl_loop >= 0);

	# send email
	return $Mail->send(
		from=>$FILEXConf->getSystemEmail(),
		to=>$to,
		charset=>"ISO-8859-1",
		subject=>$I18n->localize("mail subject %s",$file_infos->{'real_name'}),
		content=>$t->output()
	);
}

sub log {
	my $str = shift;
	warn("[",strftime("%a %b %e %H:%M:%S %Y",localtime()),"] $str");
	return 1;
}
