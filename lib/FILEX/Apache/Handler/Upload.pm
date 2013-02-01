package FILEX::Apache::Handler::Upload;
use strict;
use vars qw($VERSION);
# Apache Related
use Apache::Constants qw(:common);

# FILEX related
use FILEX::System qw(genUniqId toHtml);
use FILEX::System::Config;
use FILEX::DB::Upload;
use FILEX::Tools::Utils qw(tsToLocal hrSize);
# Others
use File::Spec;
use IO::Select;
use Cache::FileCache;

use constant FILEX_CONFIG_NAME => "FILEXConfig";
# upload field
use constant UPLOAD_FIELD_NAME => "upload";
# keep file n days field
use constant DAY_KEEP_FIELD_NAME => "daykeep";
# get mail on delivery field
use constant DELIVERY_FIELD_NAME => "getdelivery";
# get mail on purge field
use constant RESUME_FIELD_NAME => "getresume";
# old download id field
use constant OLD_DLID_FIELD_NAME => "odlid";
# download id field
use constant DLID_FIELD_NAME => "dlid";

$VERSION = 1.0;

# OK => ok
# DECLINED => CONTINUE, NOT_AUTHORITATIVE -> pass thru
# AUTH_REQUIRED
# SERVER_ERROR
# The Main entry point
sub handler {
	# the request object
	my $r = shift;
	my $S; # FILEX::System object
	my ($Config); # FILEX::System::Config
	my $IPCache; #Cache::FileCache object
	my $Upload; # the Upload object
	my $download_id; # the uniq download id
	my %upload_infos; # upload informations
	my ($t_begin,$t_end); # the templates
	my $dlid_field_name = DLID_FIELD_NAME;

	# get current query params
	# and get uniq upload id
	my %args = $r->args();
	$download_id = $args{$dlid_field_name};

	# the new config object
	$FILEX::System::Config::ConfigPath = $r->dir_config(FILEX_CONFIG_NAME);
	$FILEX::System::Config::Reload = 1;
	$FILEX::System::Config::DieOnReload = 1;
	# init config object (because we need info to initialize the IPCache
	#$Config = FILEX::System::Config->new(file=>$r->dir_config(FILEX_CONFIG_NAME), reload=>1, dieonreload=>1);
	$Config = FILEX::System::Config->new();
	# get maximum file upload size and check it
	my $posted_content_length = $r->header_in('Content-Length');
	# initialize IPC Cache if we have a download id and if the upload size is not too large
	if ( $download_id ) {
		$IPCache = initIPCCache($Config);
		if ( !$IPCache ) {
			warn(__PACKAGE__,"-> Unable to create Shared Cache !");
		} else {
			# set the IPC Size 
			my $cntlength = $posted_content_length;
			$IPCache->set($download_id."size",$cntlength) if ( $cntlength );
		}
	}

	# initialize the upload hook
	# note : hook_data = uploadid
	# note : inspired from Apache::UploadMeter
	my $transparent_hook = sub {
		my ($upl, $buf, $len, $hook_data) = @_;
		return if ( ! $IPCache );
		# check if upload begin
		my $oldlength = $IPCache->get($hook_data."length") || 0;
		my $newlength = $len + $oldlength;
		if ( $oldlength == 0 ) {
			$IPCache->set($hook_data."filename",normalize($upl->filename()));
			$IPCache->set($hook_data."starttime",time());
			$IPCache->set($hook_data."canceled",0);
			$IPCache->set($hook_data."end",0);
		}
		# store current length
		# increment current length
		$IPCache->set($hook_data."length",$newlength);
	};

	# initialize FILEX system
	if ( $download_id && $IPCache ) {
		$S = FILEX::System->new($r,with_upload=>1,with_hook=>{"hook_data"=>$download_id,"upload_hook"=>$transparent_hook});
	} else {
		$S = FILEX::System->new($r,with_upload=>1);
	}
	# beginSession will redirect the user if required
	$S->beginSession(); 
	my $username = $S->getAuthUser();
	# load template
	$t_begin = $S->getTemplate(name=>"upload");
	$t_end = $S->getTemplate(name=>"upload_end");
	# fill in some parameters
	$t_begin->param(FILEX_FORM_UPLOAD_DAY_KEEP_NAME=>DAY_KEEP_FIELD_NAME);
	$t_begin->param(FILEX_FORM_UPLOAD_DELIVERY_NAME=>DELIVERY_FIELD_NAME);
	$t_begin->param(FILEX_FORM_UPLOAD_RESUME_NAME=>RESUME_FIELD_NAME);
	$t_begin->param(FILEX_FORM_UPLOAD_UPLOAD_NAME=>UPLOAD_FIELD_NAME);
	$t_begin->param(FILEX_FORM_UPLOAD_OLD_DLID_NAME=>OLD_DLID_FIELD_NAME);
	$t_begin->param(FILEX_MAX_DAY_KEEP=>$S->config->getMaxFileExpire());
	$t_begin->param(FILEX_SYSTEM_EMAIL=>$S->config->getSystemEmail());
	$t_begin->param(FILEX_USER_NAME=>$S->toHtml($S->getUserRealName($username)));
	$t_end->param(FILEX_SYSTEM_EMAIL=>$S->config->getSystemEmail());
	$t_end->param(FILEX_USER_NAME=>$S->toHtml($S->getUserRealName($username)));

	# generate the uniq download id
	my $old_download_id = $S->apreq->param(OLD_DLID_FIELD_NAME);
	$download_id = genUniqId() if ( ! $download_id );
	# check for the old_download_id only if upload not canceled
	if ( $S->isConnected() ) {
		$download_id = genUniqId() if ( ! $old_download_id || ($old_download_id ne $download_id) );
	} else {
		# set IPC Cancel state
		if ( $IPCache && $download_id ) {
			$IPCache->set($download_id."canceled",1);
		}
	}

	# fill in the first template
	$t_begin->param(FILEX_MANAGE_UPLOADED_FILES_COUNT=>$S->getUserUploadCount($username));
	$t_begin->param(FILEX_MANAGE_ACTIVE_FILES_COUNT=>$S->getUserActiveCount($username));
	$t_begin->param(FILEX_MANAGE_URL=>$S->getManageUrl());
	$t_begin->param(FILEX_CAN_UPLOAD=>1);
	$t_begin->param(FILEX_FORM_UPLOAD_ACTION=>genFormAction($S,$download_id));
	$t_begin->param(FILEX_OLD_DLID=>$download_id);
	$t_begin->param(FILEX_METER_URL=>genMeterUrl($S,$download_id));
	if ( $S->isAdmin($username) ) {
		$t_begin->param(FILEX_MANAGE_IS_ADMIN=>1);
		$t_begin->param(FILEX_MANAGE_ADMIN_URL=>$S->getAdminUrl());
	}
	# the expire loop
	my (@expire_loop, $expire_default, $expire_posted, $expire_value, $expire_min, $expire_max);
	$expire_default = $S->config->getDefaultFileExpire();
	$expire_min = $S->config->getMinFileExpire();
	$expire_max = $S->config->getMaxFileExpire();
	$upload_infos{'daykeep'} = $S->apreq->param(DAY_KEEP_FIELD_NAME) || $expire_default;
	$upload_infos{'daykeep'} = $expire_default if ( $upload_infos{'daykeep'} > $expire_max );
	# fill daykeep
	for ( $expire_value = $expire_min; $expire_value <= $expire_max; $expire_value++ ) {
		my $expire_loop_row = {'FILEX_EXPIRE_VALUE'=>$expire_value};
		if ( $expire_value == $upload_infos{'daykeep'} ) {
			$expire_loop_row->{'FILEX_EXPIRE_SELECTED'} = 1;
		} 
		push(@expire_loop,$expire_loop_row);
	}	
	$t_begin->param(FILEX_EXPIRE_LOOP=>\@expire_loop);

	# check for quotas
	my ($quota_max_file_size,$quota_max_used_space) = $S->getQuota($username);
	my ($hrsize,$hrunit);
	if ( $quota_max_used_space > 0 ) {
		($hrsize,$hrunit) = hrSize($quota_max_used_space);
		$t_begin->param(FILEX_MANAGE_HAVE_QUOTA=>1);
		$t_begin->param(FILEX_MANAGE_MAX_USED_SPACE=>"$hrsize ".$S->i18n->localizeToHtml($hrunit));
	}
	my $current_user_space = $S->getUserDiskSpace($username);
 	($hrsize,$hrunit) = hrSize($current_user_space);
	$t_begin->param(FILEX_MANAGE_USED_SPACE=>"$hrsize ".$S->i18n->localizeToHtml($hrunit));

	my $max_file_size = $S->getUserMaxFileSizeQuick($quota_max_file_size,$quota_max_used_space,$current_user_space);
	# if max_file_size < 0 then unlimited upload size
	# if max_file_size == 0 then we cannot upload (quota reached)
	#$bCanUpload = 0 if ( $max_file_size == 0 );
	# max_file_size == 0 then no upload
  if ( $max_file_size == 0 ) {
		$t_begin->param(FILEX_CAN_UPLOAD=>0);
		$t_begin->param(FILEX_HAS_ERROR=>1);
		$t_begin->param(FILEX_ERROR=>$S->i18n->localizeToHtml("quota exceed"));
		display($S,$t_begin);
	} 

	if ( $max_file_size > 0 ) {
		$t_begin->param(FILEX_HAS_MAX_FILE_SIZE=>1);
		($hrsize,$hrunit) = hrSize($max_file_size);
		$t_begin->param(FILEX_MAX_FILE_SIZE=>"$hrsize ".$S->i18n->localizeToHtml($hrunit));
	}

	# check for max disk space
	my $max_disk_space = $S->config->getMaxDiskSpace();
	my $max_disk_space_limit = $S->config->getMaxDiskSpaceLimit();
	if ( $max_disk_space ) {
		my $bCantUpload = 0;
		my $current_used_space = $S->getUsedDiskSpace();
		# check if there is a max_file_size
		if ( $max_file_size > 0 ) {
			$bCantUpload = 1 if ( $max_disk_space < ($current_used_space + $max_file_size) );
		} else {
			# we can't upload if the remaining space < max_disk_space_limit
			$bCantUpload = 1 if ( $max_disk_space_limit && (($current_used_space/$max_disk_space)*100) >= $max_disk_space );
		}
		if ( $bCantUpload ) {
			$t_begin->param(FILEX_CAN_UPLOAD=>0);
			$t_begin->param(FILEX_HAS_ERROR=>1);
			$t_begin->param(FILEX_ERROR=>$S->i18n->localizeToHtml("no more space on drive"));
			display($S,$t_begin);
		}
	}

	# the real begining is here
	# check if the request is aborted
	if ( ! $S->isConnected() )  {
		$t_begin->param(FILEX_HAS_ERROR=>1);
		$t_begin->param(FILEX_ERROR=>$S->i18n->localizeToHtml("upload canceled"));
		display($S,$t_begin);
	}
	# otherwise get the upload field
	$Upload  = $S->apreq->upload(UPLOAD_FIELD_NAME);
	# inform the IPC that download end
	if ( $IPCache && $download_id ) {
		$IPCache->set($download_id."end",1);
	}

	# check if we uploaded some things
	if ( !$Upload ) { 
		# if not then exit
		display($S,$t_begin);
	} elsif ( $Upload->size() <= 0 ) {
		$t_begin->param(FILEX_HAS_ERROR=>1);
		$t_begin->param(FILEX_ERROR=>$S->i18n->localizeToHtml("file size is null"));
		display($S,$t_begin);
	} elsif ( ($Upload->size() > $max_file_size) && ($max_file_size > 0) ) {
		$t_begin->param(FILEX_HAS_ERROR=>1);
		$t_begin->param(FILEX_ERROR=>$S->i18n->localizeToHtml("file size too large"));
		display($S,$t_begin);
	}

	# new - receive delivery & receive resume
	$upload_infos{'getdelivery'} = $S->apreq->param(DELIVERY_FIELD_NAME) || 0;
	$upload_infos{'getdelivery'} = 0 if ($upload_infos{'getdelivery'} !~ /^[0-1]$/);
	$upload_infos{'getresume'} = $S->apreq->param(RESUME_FIELD_NAME) || 0;
	$upload_infos{'getresume'} = 0 if ($upload_infos{'getresume'} !~ /^[0-1]$/);

	# process upload
	$upload_infos{'real_filename'} = normalize($Upload->filename());
	$upload_infos{'file_name'} = genUniqId(); # "filesystem" filename
	$upload_infos{'file_size'} = $Upload->size();
	$upload_infos{'file_type'} = $Upload->type();
	$upload_infos{'upload_date'} = time(); # get the time from 01/01/1970 0:0:0 GMT

	# store file on disk
	my $destination = File::Spec->catfile($S->config->getFileRepository(),$upload_infos{'file_name'});
	if ( !storeFile($destination, $Upload, $S->config()) ) {
		$t_begin->param(FILEX_HAS_ERROR=>1);
		$t_begin->param(FILEX_ERROR=>$S->i18n->localizeToHtml("unable to store file"));
		display($S,$t_begin);
	}
	# register the new file
	my $record = eval { FILEX::DB::Upload->new(); };
	if ( $@ ) {
		warn(__PACKAGE__,"-> problem while creating new record : $@");
		$t_begin->param(FILEX_HAS_ERROR=>1);
		$t_begin->param(FILEX_ERROR=>$@);
		display($S,$t_begin);
	}
	$record->setFileName($upload_infos{'file_name'});
	$record->setRealName($upload_infos{'real_filename'});
	$record->setOwner($S->getAuthUser());
	$record->setIpAddress($S->getRemoteIP());
	if ( $S->isBehindProxy() ) {
		$record->setUseProxy(1);
		$record->setProxyInfos($S->getProxyInfos());
	}
	$record->setContentType($upload_infos{'file_type'});
	$record->setFileSize($upload_infos{'file_size'});
	$record->setUploadDate($upload_infos{'upload_date'});
	$record->setExpireDays($upload_infos{'daykeep'});
	$record->setGetDelivery($upload_infos{'getdelivery'});
	$record->setGetResume($upload_infos{'getresume'});
	# create the new record
	if ( ! $record->save() ) {
		warn(__PACKAGE__,"-> Unable to save record ...");
		$t_begin->param(FILEX_HAS_ERROR=>1);
		$t_begin->param(FILEX_ERROR=>$record->getLastErrorString());
		display($S,$t_begin);
	}
	# send email if needed
	if ( $S->config->needEmailNotification() ) {
		if ( ! sendMail($S,$record) ) {
			$t_end->param(FILEX_HAS_ERROR=>1);
			$t_end->param(FILEX_ERROR=>$S->i18n->localizeToHtml("unable to send email"));
		}
	}
	# fill last template
	$t_end->param(FILEX_FILE_NAME=>toHtml($record->getRealName()));
	my ($fsz,$funit) = hrSize($record->getFileSize());
	$t_end->param(FILEX_FILE_SIZE=>$fsz." ".$S->i18n->localizeToHtml($funit));
	$t_end->param(FILEX_FILE_EXPIRE=>toHtml(tsToLocal($record->getExpireDate())));
	$t_end->param(FILEX_GET_URL=>genGetUrl($S,$record->getFileName()));
	$t_end->param(FILEX_DAY_KEEP=>$upload_infos{'daykeep'});
	$t_end->param(FILEX_UPLOAD_URL=>$S->getUploadUrl());
	display($S,$t_end);
	return OK;
}

# display 
sub display {
	my $S = shift;
	my $T = shift;
	# base for static include
	$T->param(FILEX_STATIC_FILE_BASE=>$S->getStaticUrl()) if ( $T->query(name=>'FILEX_STATIC_FILE_BASE') );
	$S->sendHeader("Content-type"=>"text/html");
	# print body only if it is not a HEAD request
	$S->apreq->print($T->output()) if ( ! $S->apreq->header_only() );
	exit(OK);
}

# generate the Form Action
sub genFormAction {
	my $s = shift;
	my $dlid = shift;
	my $dlid_field = DLID_FIELD_NAME;
	my $url = $s->getCurrentUrl();
	$url .= "?".$s->genQueryString({$dlid_field=>$dlid});
	return $url;
}

# generate the Get url
sub genGetUrl {
	my $s = shift; # FILEX::System
	my $fn = shift; 
	my $url = $s->getGetUrl();
	$url .= "?".$s->genQueryString({k=>$fn});
	return $url;
}

# generate the Meter Url
sub genMeterUrl {
	my $s = shift; # FILEX::System
	my $dlid = shift; # download id
	my $dlid_field = DLID_FIELD_NAME;
	my $url = $s->getMeterUrl();
	$url .= "?".$s->genQueryString({$dlid_field=>$dlid,ini=>1});
	return $url;
}

# store file on disk
sub storeFile {
	my $path = shift; # file path
	my $upload = shift; # Apache::Request::Upload object
	my $conf = shift; # FILEX::System::Config object
	
	if ( $conf->isSameDevice() ) {
		# use hardlink to copy the file
		$upload->link($path) or return undef;
	} else {
		# loop on input file handle
		my $out_fh = Apache::File->new($path) or return undef;
		my ($br,$buffer);
		while ( $br = read($upload->fh(), $buffer, 1024) ) {
			print $out_fh $buffer;
		}
		$out_fh->close();
	}
	return 1;
}

sub sendMail {
	my $s = shift;
	my $record = shift;
	# load template
	my $t = $s->getTemplate(name=>"mail_upload") or return undef;
	# fill template
	$t->param(FILEX_FILE_NAME=>$record->getRealName());
	$t->param(FILEX_GET_URL=>genGetUrl($s,$record->getFileName()));
	my ($fsz,$funit) = hrSize($record->getFileSize());
	$t->param(FILEX_FILE_SIZE=>$fsz." ".$s->i18n->localize($funit));
	$t->param(FILEX_FILE_DATE=>tsToLocal($record->getUploadDate()));
	$t->param(FILEX_FILE_EXPIRE=>tsToLocal($record->getExpireDate()));
	$t->param(FILEX_SYSTEM_EMAIL=>$s->config->getSystemEmail());
	$t->param(FILEX_GET_DELIVERY=>$s->i18n->localize($record->getGetDelivery() ? "yes" : "no"));
	$t->param(FILEX_GET_RESUME=>$s->i18n->localize($record->getGetResume() ? "yes" : "no"));
	# now it time to send email
	my $to = $s->getMail($s->getAuthUser());
	return undef if !length($to);
	return $s->sendMail(
		from=>$s->config->getSystemEmail(),
		to=>$to,
		charset=>"ISO-8859-1",
		subject=>$s->i18n->localize("mail subject %s",$record->getRealName()),
		content=>$t->output()
	);
}

# initialize IPC Cache
sub initIPCCache {
	my $conf = shift; # FILEX::System::Config object
	my $cache_opt = {};
	$cache_opt->{'namespace'} = $conf->getCacheNamespace();
	$cache_opt->{'default_expires_in'} = $conf->getCacheDefaultExpire();
	$cache_opt->{'auto_purge_interval'} = $conf->getCacheAutoPurge();
	$cache_opt->{'cache_root'} = $conf->getCacheRoot() if $conf->getCacheRoot();
	# instantiate the IPC cache
	return Cache::FileCache->new($cache_opt);
}

# IE & lynx send the full file path, so we need to strip some things
sub normalize {
	my $file = shift;
	$file =~ s/.*[\\|\/](.+)$/$1/;
	return $file;
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
