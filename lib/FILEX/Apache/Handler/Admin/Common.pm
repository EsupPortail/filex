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

use FILEX::DB::Upload;
use FILEX::Tools::Utils qw(tsToGmt hrSize tsToLocal);

use constant FIELD_STATE_NAME => "state";
use constant FIELD_EXPIRE_NAME => "expire";
use constant FIELD_RESUME_NAME => "resume";
use constant FIELD_DELIVERY_NAME => "delivery";
use constant FIELD_RENEW_NAME => "renew";
use constant ADMIN_MODE => 1;

# require : FILEX::System + upload id
# system => FILEX::System object
# id => Upload id
# url => access url
# mode => 1 | 0
sub doFileInfos {
	my %ARGZ = @_;
	warn(__PACKAGE__,"-> require a FILEX::System object") && return undef if ( !exists($ARGZ{'system'}) || ref($ARGZ{'system'}) ne "FILEX::System");
	warn(__PACKAGE__,"-> require a file_id") && return undef if ( !exists($ARGZ{'file_id'}) || $ARGZ{'file_id'} !~ /^[0-9]+$/ );
	warn(__PACKAGE__,"-> require url") && return undef if ( !exists($ARGZ{'url'}) );
	warn(__PACKAGE__,"-> require sub_action_field_name") && return undef if ( !exists($ARGZ{'sub_action_field_name'}) );
	warn(__PACKAGE__,"-> require sub_action_value") && return undef if ( !exists($ARGZ{'sub_action_value'}) );
	warn(__PACKAGE__,"-> require file_id_field_name") && return undef if ( !exists($ARGZ{'file_id_field_name'}) );
	my $S = $ARGZ{'system'};
	my $file_id = $ARGZ{'file_id'};
	my $mode = ( exists($ARGZ{'mode'}) && $ARGZ{'mode'} =~ /^[0-1]$/) ? $ARGZ{'mode'} : 0;
	my $T = $S->getTemplate(name=>"admin_fileinfo");
	$T->param(SUB_ACTION_FIELD_NAME=>$ARGZ{'sub_action_field_name'});
	$T->param(SUB_ACTION_VALUE=>$ARGZ{'sub_action_value'});
	$T->param(FILE_ID_FIELD_NAME=>$ARGZ{'file_id_field_name'});
	$T->param(FILE_ID_VALUE=>$file_id);
	$T->param(FILEX_FORM_ACTION_URL=>$ARGZ{'url'});
	my $upload = eval { FILEX::DB::Upload->new(id=>$file_id); };
	if ($@) {
		$T->param(FILEX_HAS_ERROR=>1);
		$T->param(FILEX_ERROR=>$S->i18n->localizeToHtml("database error %s",$upload->getLastErrorString()));
		return $T;
	}
  if ( !$upload->exists() ) {
		$T->param(FILEX_HAS_ERROR=>1);
		$T->param(FILEX_ERROR=>$S->i18n->localizeToHtml("requested file does not exists"));
		return $T;
	}
	# Set template admin mode
	$T->param(FILEX_ADMIN_MODE=>1) if ( $mode == ADMIN_MODE );
	# check if the user is the owner of the file
	my $bIsOwner = $upload->checkOwner($S->getAuthUser());
	# if in admin_mode => ok if the logged user is an administrator
	# if not in admin_mode then the file must belong to the user
	if ( ($mode != ADMIN_MODE && !$bIsOwner) ) {
		$T->param(FILEX_HAS_ERROR=>1);
		$T->param(FILEX_ERROR=>$S->i18n->localizeToHtml("you're not the owner of the file"));
		return $T;
	}

	# check for params
	my $changes = 0;
	my $activate = $S->apreq->param(FIELD_STATE_NAME);
	if ( defined($activate) && $mode == ADMIN_MODE ) {
		if (($upload->getEnable() != $activate) && ($activate == 1 || $activate == 0)) {
			$upload->setEnable($activate);
			$changes++;
		}
	}
	my $purge = $S->apreq->param(FIELD_EXPIRE_NAME);
	if ( defined($purge) && $purge == 1) {
		$upload->makeExpire();
		$changes++;
	}
	my $resume = $S->apreq->param(FIELD_RESUME_NAME);
	if ( defined($resume) ) {
		if (($upload->getGetResume() != $resume) && ($resume == 1 || $resume == 0)) {
			$upload->setGetResume($resume);
			$changes++;
		}
	}
	my $delivery = $S->apreq->param(FIELD_DELIVERY_NAME);
	if ( defined($delivery) ) {
		if (($upload->getGetDelivery() != $delivery) && ($delivery == 1 || $delivery == 0)) {
			$upload->setGetDelivery($delivery);
			$changes++;
		}
	}
	my $renew = $S->apreq->param(FIELD_RENEW_NAME);
	if ( defined($renew) && ($renew != 0) ) {
		if ( $upload->getRenewCount() < $S->config->getRenewFileExpire() ) {
			if ( $renew >= $S->config->getMinFileExpire() && $renew <= $S->config->getMaxFileExpire() ) {
				$upload->extendExpireDate($renew);
				$changes++
			}
		}
	}
	if ( $changes && !$upload->save() ) {
		$T->param(FILEX_HAS_ERROR=>1);
		$T->param(FILEX_ERROR=>$upload->getLastErrorString());
		return $T;
	}
	# fill
	$T->param(FILEX_RENEW_COUNT=>$upload->getRenewCount());
	$T->param(FILEX_MAX_RENEW_COUNT=>$S->config->getRenewFileExpire());
	$T->param(FILEX_FILE_NAME=>$S->toHtml($upload->getRealName()));
	my ($fsz,$funit) = hrSize($upload->getFileSize());
	$T->param(FILEX_FILE_SIZE=>$fsz." ".$S->i18n->localizeToHtml("$funit"));
	$T->param(FILEX_FILE_DATE=>$S->toHtml(tsToLocal($upload->getUploadDate())));
	$T->param(FILEX_FILE_EXPIRE=>$S->toHtml(tsToLocal($upload->getExpireDate())));
	$T->param(FILEX_FILE_OWNER=>$S->getMail($upload->getOwner()));
	$T->param(FILEX_FILE_OWNER_ID=>$upload->getOwner());
	$T->param(FILEX_FILE_COUNT=>$upload->getDownloadCount());
	$T->param(FILEX_DISK_NAME=>$upload->getFileName());
	# ip,proxy ...
	$T->param(FILEX_UPLOAD_ADDRESS=>$S->toHtml($upload->getIpAddress()));
	if ( $upload->getUseProxy() == 1 ) {
		$T->param(FILEX_USE_PROXY=>$S->i18n->localizeToHtml("yes"));
		$T->param(FILEX_IF_USE_PROXY=>1);
		$T->param(FILEX_PROXY_INFOS=>$upload->getProxyInfos());
	} else {
		$T->param(FILEX_USE_PROXY=>$S->i18n->localizeToHtml("no"));
	}
	# enable / disable
	# form parameter name
	$T->param(FILEX_FORM_STATE_NAME=>FIELD_STATE_NAME);
	$T->param(FILEX_FORM_STATE_VALUE_ACTIVATE=>1);
	$T->param(FILEX_FORM_STATE_VALUE_DESACTIVATE=>0);
	if ( $upload->getEnable() == 1 ) {
		$T->param(FILEX_FORM_STATE_VALUE_ACTIVATE_CHECKED=>1);
	} else {
		$T->param(FILEX_FORM_STATE_VALUE_DESACTIVATE_CHECKED=>1);
	}
	# set expired
	if ( $upload->isExpired() != 1 ) {
		$T->param(FILEX_CAN_EXPIRE=>1);
		$T->param(FILEX_FORM_EXPIRE_NAME=>FIELD_EXPIRE_NAME);
		$T->param(FILEX_FORM_EXPIRE_VALUE_YES=>1);
		$T->param(FILEX_FORM_EXPIRE_VALUE_NO=>0);
	} else {
		$T->param(FILEX_EXPIRED=>$S->i18n->localizeToHtml("yes"));
	}
	# get delivery mail
	$T->param(FILEX_FORM_DELIVERY_NAME=>FIELD_DELIVERY_NAME);
	$T->param(FILEX_FORM_DELIVERY_VALUE_YES=>1);
	$T->param(FILEX_FORM_DELIVERY_VALUE_NO=>0);
	if ( $upload->getGetDelivery() == 1 ) {
		$T->param(FILEX_FORM_DELIVERY_VALUE_YES_CHECKED=>1);
		$T->param(FILEX_DELIVERY=>$S->i18n->localizeToHtml("yes"));
	} else {
		$T->param(FILEX_FORM_DELIVERY_VALUE_NO_CHECKED=>1);
		$T->param(FILEX_DELIVERY=>$S->i18n->localizeToHtml("no"));
	}
	# get resume mail
	$T->param(FILEX_FORM_RESUME_NAME=>FIELD_RESUME_NAME);
	$T->param(FILEX_FORM_RESUME_VALUE_YES=>1);
	$T->param(FILEX_FORM_RESUME_VALUE_NO=>0);
	if ( $upload->getGetResume() == 1 ) {
		$T->param(FILEX_FORM_RESUME_VALUE_YES_CHECKED=>1);
		$T->param(FILEX_RESUME=>$S->i18n->localizeToHtml("yes"));
	} else {
		$T->param(FILEX_FORM_RESUME_VALUE_NO_CHECKED=>1);
		$T->param(FILEX_RESUME=>$S->i18n->localizeToHtml("no"));
	}
	# allow renewal of expiration time
	my $renew_count = $S->config->getRenewFileExpire();
	my $file_renew_count = $upload->getRenewCount();
	if ( $renew_count > 0 && $file_renew_count < $renew_count ) {
		# generate the loop
		my (@expire_loop, $expire_value, $expire_min, $expire_max);
		$expire_min = $S->config->getMinFileExpire();
		$expire_max = $S->config->getMaxFileExpire();
		# add ZERO
		push(@expire_loop,{FILEX_FORM_RENEW_VALUE=>0});
		for ( $expire_value = $expire_min; $expire_value <= $expire_max; $expire_value++ ) {
			push(@expire_loop,{FILEX_FORM_RENEW_VALUE=>$expire_value});
		}
		$T->param(FILEX_CAN_RENEW_FILE_LIFE=>1);
		$T->param(FILEX_FORM_RENEW_NAME=>FIELD_RENEW_NAME);
		$T->param(FILEX_RENEW_LOOP=>\@expire_loop);
	}
	# get download address
	$T->param(FILEX_GET_ADDRESS=>genGetUrl($S,$upload->getFileName()));
	return $T if ( $upload->getDownloadCount() == 0 );
	# do access report
	my (@log,@download_loop);
	$T->param(FILEX_HAS_DOWNLOAD=>1);
	if ( !$upload->getDownloads(\@log) ) {
		$T->param(FILEX_HAS_DOWNLOAD_ERROR=>1);
		$T->param(FILEX_DOWNLOAD_ERROR=>$S->i18n->localiseToHtml("database error %s",$upload->getLastErrorString()));
		return $T;
	}
	for ( my $l = 0; $l <= $#log; $l++ ) {
		my $dl_record = {};
		if ( $log[$l]->{'use_proxy'} == 1 && ($mode == ADMIN_MODE) ) {
			$dl_record->{'FILEX_DOWNLOAD_USE_PROXY'} = 1;
			$dl_record->{'FILEX_DOWNLOAD_PROXY_INFOS'} = $log[$l]->{'proxy_infos'};
		}
		$dl_record->{'FILEX_DOWNLOAD_ADDRESS'} = $S->toHtml($log[$l]->{'ip_address'});
		$dl_record->{'FILEX_DOWNLOAD_DATE'} = $S->toHtml(tsToLocal($log[$l]->{'ts_date'}));
		$dl_record->{'FILEX_DOWNLOAD_STATE'} = ( $log[$l]->{'canceled'} ) ? $S->i18n->localizeToHtml("yes") : $S->i18n->localizeToHtml("no");
		push(@download_loop,$dl_record);
		$T->param(FILEX_DOWNLOAD_LOOP=>\@download_loop);
	}
	return $T;
}

sub genActivateUrl {
	my $S = shift;
	my $current_url = shift;
	my $state = shift;
	my $activate = FIELD_STATE_NAME;
	$current_url .= "&".$S->genQueryString({$activate=>$state});
	return $current_url;
}

sub genDeliveryUrl {
	my $S = shift;
	my $current_url = shift;
	my $state = shift;
	my $activate = FIELD_DELIVERY_NAME;
	$current_url .= "&".$S->genQueryString({$activate=>$state});
	return $current_url;
}

sub genResumeUrl {
	my $S = shift;
	my $current_url = shift;
	my $state = shift;
	my $activate = FIELD_RESUME_NAME;
	$current_url .= "&".$S->genQueryString({$activate=>$state});
	return $current_url;
}

sub genPurgeUrl {
	my $S = shift;
	my $current_url = shift;
	my $expired = FIELD_EXPIRE_NAME;
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
