package FILEX::Apache::Handler::Admin::Common;
use strict;
use vars qw(@ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);
use Exporter;
@ISA = qw(Exporter);
@EXPORT = qw();
@EXPORT_OK = qw(
	doFileInfos
);
%EXPORT_TAGS = (all=>[@EXPORT_OK]);

use FILEX::DB::Admin::Stats;
use FILEX::Tools::Utils qw(tsToGmt hrSize tsToLocal);

use constant QS_ACTIVATE => "activate";
use constant QS_PURGE => "purge";
use constant QS_RESUME => "resume";
use constant QS_DELIVERY => "delivery";
use constant ADMIN_MODE => 1;

# require : FILEX::System + upload id
# system => FILEX::System object
# id => Upload id
# url => access url
# mode => 1 | 0
sub doFileInfos {
	my %ARGZ = @_;
	warn(__PACKAGE__,"-> require a FILEX::System object") && return undef if ( !exists($ARGZ{'system'}) || ref($ARGZ{'system'}) ne "FILEX::System");
	warn(__PACKAGE__,"-> require a file id") && return undef if ( !exists($ARGZ{'id'}) || $ARGZ{'id'} !~ /^[0-9]+$/ );
	warn(__PACKAGE__,"-> require url") && return undef if ( !exists($ARGZ{'url'}) );
	my $S = $ARGZ{'system'};
	my $file_id = $ARGZ{'id'};
	my $url = $ARGZ{'url'};
	my $mode = ( exists($ARGZ{'mode'}) && $ARGZ{'mode'} =~ /^[0-1]$/) ? $ARGZ{'mode'} : 0;
	my $T = $S->getTemplate(name=>"admin_fileinfo");
	my $DB = FILEX::DB::Admin::Stats->new(
		name=>$S->config->getDBName(),
		user=>$S->config->getDBUsername(),
		password=>$S->config->getDBPassword(),
		host=>$S->config->getDBHost(),
		port=>$S->config->getDBPort()
	);
	# Set template admin mode
	$T->param(ADMIN_MODE=>1) if ( $mode == ADMIN_MODE );
	# check if the user is the owner of the file
	my $bIsOwner = $DB->isOwner(id=>$file_id,owner=>$S->getAuthUser());
	# if in admin_mode => ok if the logged user is an administrator
	# if not in admin_mode then the file must belong to the user
	if ( ($mode != ADMIN_MODE && !$bIsOwner) ) {
		$T->param(HAS_ERROR=>1);
		$T->param(ERROR=>$S->i18n->localizeToHtml("you're not the owner of the file"));
		return $T;
	}
	# check for params
	my $activate = $S->apreq->param(QS_ACTIVATE);
	if ( defined($activate) && $mode == ADMIN_MODE) {
		$DB->setEnable(id=>$file_id, enable=> $activate);
	}
	my $purge = $S->apreq->param(QS_PURGE);
	if ( defined($purge) ) {
		$DB->setExpired($file_id);
	}
	my $delivery = $S->apreq->param(QS_DELIVERY);
	if ( defined($delivery) && ($delivery =~ /^[0-1]$/) ) {
		$DB->setDelivery(id=>$file_id,state=>$delivery);
	}
	my $resume = $S->apreq->param(QS_RESUME);
	if ( defined($resume) && ($resume =~ /^[0-1]$/) ) {
		$DB->setResume(id=>$file_id,state=>$resume);
	}
	# do the rest
	my (%results,$r);
	$r = $DB->fileInfos(id=>$file_id,results=>\%results); 
	if ( ! $r ) {
		$T->param(HAS_ERROR=>1);
		$T->param(ERROR=>$S->i18n->localizeToHtml("database error %s",$DB->getLastErrorString()));
		return $T;
	}
	if ( !exists($results{'file_name'}) ) {
		$T->param(HAS_ERROR=>1);
		$T->param(ERROR=>$S->i18n->localizeToHtml("requested file does not exists"));
		return $T;
	}
	# fill
	$T->param(FILENAME=>$S->toHtml($results{'real_name'}));
	my ($fsz,$funit) = hrSize($results{'file_size'});
	$T->param(FILESIZE=>$fsz." ".$S->i18n->localizeToHtml("$funit"));
	$T->param(FILEDATE=>$S->toHtml(tsToLocal($results{'ts_upload_date'})));
	$T->param(FILEEXPIRE=>$S->toHtml(tsToLocal($results{'ts_expire_date'})));
	$T->param(FILEOWNER=>$S->getMail($results{'owner'}));
	$T->param(FILEOWNER_ID=>$results{'owner'});
	$T->param(FILECOUNT=>$results{'download_count'});
	$T->param(DISKNAME=>$results{'file_name'});
	# ip,proxy ...
	$T->param(UL_ADDRESS=>$S->toHtml($results{'ip_address'}));
	if ( $results{'use_proxy'} == 1 ) {
		$T->param(USE_PROXY=>$S->i18n->localizeToHtml("yes"));
		$T->param(IF_USE_PROXY=>1);
		$T->param(PROXY_INFOS=>$results{'proxy_infos'});
	} else {
		$T->param(USE_PROXY=>$S->i18n->localizeToHtml("no"));
	}
	# enable / disable
	$T->param(STATE=> ($results{'enable'} == 1) ? $S->i18n->localizeToHtml("enable") : $S->i18n->localizeToHtml("disable") );
	$T->param(STATE_URL=>genActivateUrl($S,$url, ($results{'enable'} == 1) ? 0 : 1));
	# expire
	$T->param(EXPIRED=> ($results{'expired'} == 1 ) ? $S->i18n->localizeToHtml("yes") : $S->i18n->localizeToHtml("no") );
	if ( $results{'expired'} != 1 ) {
		$T->param(CAN_EXPIRE=>1);
		$T->param(EXPIRE_URL=>genPurgeUrl($S,$url));
	}
	# get delivery mail
	$T->param(DELIVERY=>($results{'get_delivery'} == 1) ? $S->i18n->localizeToHtml("yes") : $S->i18n->localizeToHtml("no") );
	$T->param(DELIVERY_URL=>genDeliveryUrl($S,$url,($results{'get_delivery'}==1) ? 0 : 1));
	# get resume mail
	$T->param(RESUME=>($results{'get_resume'} == 1) ? $S->i18n->localizeToHtml("yes") : $S->i18n->localizeToHtml("no") );
	$T->param(RESUME_URL=>genResumeUrl($S,$url,($results{'get_resume'}==1) ? 0 : 1));
	# get download address
	$T->param(GETADDRESS=>genGetUrl($S,$results{'file_name'}));
	return $T if ( $results{'download_count'} == 0 );
	# do access report
	my (@log,@download_loop);
	$T->param(HAS_DOWNLOAD=>1);
	$r = $DB->listDownload(id=>$results{'id'},results=>\@log);
	if ( !$r ) {
		$T->param(HAS_DOWNLOAD_ERROR=>1);
		$T->param(ERROR=>$S->i18n->localiseToHtml("database error %s",$DB->getLastErrorString()));
		return $T;
	}
	for ( my $l = 0; $l <= $#log; $l++ ) {
		my $dl_record = {};
		if ( $log[$l]->{'use_proxy'} == 1 && ($mode == ADMIN_MODE) ) {
			$dl_record->{'DL_USE_PROXY'} = 1;
			$dl_record->{'DL_PROXY_INFOS'} = $log[$l]->{'proxy_infos'};
		}
		$dl_record->{'DL_ADDRESS'} = $S->toHtml($log[$l]->{'ip_address'});
		$dl_record->{'DL_DATE'} = $S->toHtml(tsToLocal($log[$l]->{'ts_date'}));
		$dl_record->{'DL_STATE'} = ( $log[$l]->{'canceled'} ) ? $S->i18n->localizeToHtml("yes") : $S->i18n->localizeToHtml("no");
		push(@download_loop,$dl_record);
		$T->param(DOWNLOAD_LOOP=>\@download_loop);
	}
	return $T;
}

sub genActivateUrl {
	my $S = shift;
	my $current_url = shift;
	my $state = shift;
	my $activate = QS_ACTIVATE;
	$current_url .= "&".$S->genQueryString({$activate=>$state});
	return $current_url;
}

sub genDeliveryUrl {
	my $S = shift;
	my $current_url = shift;
	my $state = shift;
	my $activate = QS_DELIVERY;
	$current_url .= "&".$S->genQueryString({$activate=>$state});
	return $current_url;
}

sub genResumeUrl {
	my $S = shift;
	my $current_url = shift;
	my $state = shift;
	my $activate = QS_RESUME;
	$current_url .= "&".$S->genQueryString({$activate=>$state});
	return $current_url;
}

sub genPurgeUrl {
	my $S = shift;
	my $current_url = shift;
	my $expired = QS_PURGE;
	$current_url .= "&".$S->genQueryString({$expired=>1});
	return $current_url;
}

sub genGetUrl {
	my $S = shift; # FILEX::System
	my $i = shift; # file_name
	my $url = $S->getGetUrl();
	$url .= "?".$S->genQueryString({k=>$i});
	return $url;
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
