#!/usr/bin/perl
use strict;
use lib qw(/usr/local/FILEX/lib);
use constant FILEX_CONFIG_FILE => "/usr/local/FILEX/conf/FILEX.ini";

use FILEX::System::Config;
use FILEX::System::Purge;
use FILEX::System::Mail;
use FILEX::System::Template;
use FILEX::System::I18N;
use FILEX::Tools::Utils qw(tsToLocal hrSize rDns);
use File::Spec;
use POSIX qw(strftime);

# BEGIN
$FILEX::System::Config::ConfigPath=FILEX_CONFIG_FILE;
my $config = FILEX::System::Config->new() or die("Unable to load Configuration File : $@");
# Purge
my $purge = eval { FILEX::System::Purge->new(); };
die($@) if ($@);
# ldap
my $ldap = eval { FILEX::System::LDAP->new(); };
die("Unable to bind to ldap : $@") if ($@);
# template
my $template = eval { FILEX::System::Template->new(inifile=>$config->getTemplateIniFile()); };
die("Unable to load template module : $@") if ($@);
# mail
my $mail = FILEX::System::Mail->new(server=>$config->getSmtpServer(),
                                  hello=>$config->getSmtpHello(),
                                  timeout=>$config->getSmtpTimeout());
die("Unable to load Mail module") if !$mail;
# i18n
my $i18n = FILEX::System::I18N->new(inifile=>$config->getI18nIniFile());
die("Unable to load I18N module") if !$i18n;

# get outdated files
my @records;
my $r = $purge->getExpiredFiles(\@records);
if ( ! $r ) {
	::log("An error occured while retrieving expired files : ",$purge->getLastError());
	exit 1;
}

# loop on results
my $upload;
foreach my $idx (0 .. $#records) {
	$upload = $purge->purge($records[$idx]->{'id'});
	::log("An error occured :",$purge->getLastError()) if !$upload;
	if ( $upload && $upload->getGetResume() == 1 && $config->needEmailNotification() ) {
		sendMail($upload);
	}
}

exit 0;

# to
# file_info
# downloads
sub sendMail() {
	my $u = shift;
	# load template
	my $t = $template->getTemplate(name=>"mail_resume");
	::log("unable to load template : mail_resume") && return undef if !$t;
	my $to = $ldap->getMail($u->getOwner());
	::log("unable to get email address for : ",$u->getOwner()) && return undef if !$to;
	# fill template
	$t->param(FILEX_SYSTEM_EMAIL=>$config->getSystemEmail());
	$t->param(FILEX_FILE_NAME=>$u->getRealName());
	$t->param(FILEX_FILE_DATE=>tsToLocal($u->getUploadDate()));
	$t->param(FILEX_FILE_EXPIRE=>tsToLocal($u->getExpireDate()));
	my ($sz,$su) = hrSize($u->getFileSize());
	$t->param(FILEX_FILE_SIZE=>"$sz ".$i18n->localize($su));
	$t->param(FILEX_DOWNLOAD_COUNT=>$u->getDownloadCount());
	# loop
	my (@downloads,@download_loop);
	if ( $u->getDownloads(\@downloads) ) {
		for ( my $i = 0; $i <= $#downloads; $i++ ) {
			push(@download_loop,{FILEX_DOWNLOAD_ADDRESS=>rDns($downloads[$i]->{'ip_address'}) || $downloads[$i]->{'ip_address'},FILEX_DOWNLOAD_DATE=>tsToLocal($downloads[$i]->{'ts_date'})});
		}
		$t->param(FILEX_DOWNLOAD_LOOP=>\@download_loop) if ($#download_loop >= 0);
	}
	# send email
	return $mail->send(
		from=>$config->getSystemEmail(),
		to=>$to,
		charset=>"ISO-8859-1",
		subject=>$i18n->localize("mail subject %s",$u->getRealName()),
		content=>$t->output()
	);
}

sub log {
	my $str = shift;
	warn("[",strftime("%a %b %e %H:%M:%S %Y",localtime()),"] $str");
	return 1;
}

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
