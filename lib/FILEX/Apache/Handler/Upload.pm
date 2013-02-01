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
use constant UPLOAD_FIELD => "upload";

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
	my $Config; # FILEX::System::Config
	my $IPCache; #Cache::FileCache object
	my $Upload; # the Upload object
	my $download_id; # the uniq download id
	my %upload_infos; # upload informations
	my ($t_begin,$t_end); # the templates
	my $db; # database

	# get current query params
	# and get uniq upload id
	my %args = $r->args();
	$download_id = $args{'dlid'};

	# init config object (because we need info to initialize the IPCache
	$Config = FILEX::System::Config->new(file=>$r->dir_config(FILEX_CONFIG_NAME), reload=>1, dieonreload=>1);

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
	$t_begin->param(DAYKEEP=>$S->config->getDefaultFileExpire());
	$t_begin->param(SYSTEMEMAIL=>$S->config->getSystemEmail());
	$t_begin->param(USERNAME=>$S->toHtml($S->getUserRealName($username)));
	$t_end->param(SYSTEMEMAIL=>$S->config->getSystemEmail());
	$t_end->param(USERNAME=>$S->toHtml($S->getUserRealName($username)));
	# check for available disk space
	$db = eval { FILEX::DB::Upload->new(name=>$S->config->getDBName(),
	                           user=>$S->config->getDBUsername(),
	                           password=>$S->config->getDBPassword(),
	                           host=>$S->config->getDBHost(),
	                           port=>$S->config->getDBPort()); };
	if ($@) {
		# cannot continue
		$t_begin->param(HAS_ERROR=>1);
		$t_begin->param(ERROR=>$S->i18n->localizeToHtml("database error %s",$@));
		display($S,$t_begin);
	}

	# generate the uniq download id
	my $old_download_id = $S->apreq->param('odlid');
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
	$t_begin->param(MANAGE_UPLOADED_FILES_COUNT=>$db->getUserUploadCount($username));
	$t_begin->param(MANAGE_ACTIVE_FILES_COUNT=>$db->getUserActiveCount($username));
	$t_begin->param(MANAGE_URL=>$S->getManageUrl());
	$t_begin->param(CAN_UPLOAD=>1);
	$t_begin->param(FORM_UPLOAD_ACTION=>genFormAction($S,$download_id));
	$t_begin->param(ODLID=>$download_id);
	$t_begin->param(METERURL=>genMeterUrl($S,$download_id));
	if ( $S->isAdmin($username) ) {
		$t_begin->param(MANAGE_IS_ADMIN=>1);
		$t_begin->param(MANAGE_ADMIN_URL=>$S->getAdminUrl());
	}
	# the expire loop
	my (@expire_loop, $expire_default, $expire_posted, $expire_value);
	$expire_default = $S->config->getDefaultFileExpire();
	$upload_infos{'daykeep'} = $S->apreq->param('daykeep') || $expire_default;
	$upload_infos{'daykeep'} = $expire_default if ( $upload_infos{'daykeep'} > $expire_default );
	# fill daykeep
	for ( $expire_value = 1; $expire_value <= $expire_default; $expire_value++ ) {
		my $expire_loop_row = {'EXPIRE_VALUE'=>$expire_value};
		if ( $upload_infos{'daykeep'} == $expire_value ) {
			$expire_loop_row->{'EXPIRE_SELECTED'} = 1;
		}
		push(@expire_loop,$expire_loop_row);
	}	
	$t_begin->param(EXPIRE_LOOP=>\@expire_loop);

	# check for quotas
	my ($quota_max_file_size,$quota_max_used_space) = $S->getQuota($username);
	my ($hrsize,$hrunit);
	if ( $quota_max_used_space > 0 ) {
		($hrsize,$hrunit) = hrSize($quota_max_used_space);
		$t_begin->param(MANAGE_HAVE_QUOTA=>1);
		$t_begin->param(MANAGE_MAX_USED_SPACE=>"$hrsize ".$S->i18n->localizeToHtml($hrunit));
	}
	my $current_user_space = $S->getUserDiskSpace($username);
 	($hrsize,$hrunit) = hrSize($current_user_space);
	$t_begin->param(MANAGE_USED_SPACE=>"$hrsize ".$S->i18n->localizeToHtml($hrunit));

	my $max_file_size = $S->getUserMaxFileSizeQuick($quota_max_file_size,$quota_max_used_space,$current_user_space);
	# if max_file_size < 0 then unlimited upload size
	# if max_file_size == 0 then we cannot upload (quota reached)
	#$bCanUpload = 0 if ( $max_file_size == 0 );
	# max_file_size == 0 then no upload
  if ( $max_file_size == 0 ) {
		$t_begin->param(CAN_UPLOAD=>0);
		$t_begin->param(HAS_ERROR=>1);
		$t_begin->param(ERROR=>$S->i18n->localizeToHtml("quota exceed"));
		display($S,$t_begin);
	} 

	if ( $max_file_size > 0 ) {
		$t_begin->param(HAS_MAXFILESIZE=>1);
		($hrsize,$hrunit) = hrSize($max_file_size);
		$t_begin->param(MAXFILESIZE=>"$hrsize ".$S->i18n->localizeToHtml($hrunit));
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
			$t_begin->param(CAN_UPLOAD=>0);
			$t_begin->param(HAS_ERROR=>1);
			$t_begin->param(ERROR=>$S->i18n->localizeToHtml("no more space on drive"));
			display($S,$t_begin);
		}
	}

	# the real begining is here
	# check if the request is aborted
	if ( ! $S->isConnected() )  {
		$t_begin->param(HAS_ERROR=>1);
		$t_begin->param(ERROR=>$S->i18n->localizeToHtml("upload canceled"));
		display($S,$t_begin);
	}

	# otherwise get the upload field
	$Upload  = $S->apreq->upload(UPLOAD_FIELD);
	# inform the IPC that download end
	if ( $IPCache && $download_id ) {
		$IPCache->set($download_id."end",1);
	}

	# check if we uploaded some things
	if ( !$Upload ) { 
		# if not then exit
		display($S,$t_begin);
	} elsif ( $Upload->size() <= 0 ) {
		$t_begin->param(HAS_ERROR=>1);
		$t_begin->param(ERROR=>$S->i18n->localizeToHtml("file size is null"));
		display($S,$t_begin);
	} elsif ( ($Upload->size() > $max_file_size) && ($max_file_size > 0) ) {
		$t_begin->param(HAS_ERROR=>1);
		$t_begin->param(ERROR=>$S->i18n->localizeToHtml("file size too large"));
		display($S,$t_begin);
	}

	# new - receive delivery & receive resume
	$upload_infos{'getdelivery'} = $S->apreq->param('getdelivery') || 0;
	$upload_infos{'getdelivery'} = 1 if ($upload_infos{'getdelivery'} !~ /^[0-1]$/);
	$upload_infos{'getresume'} = $S->apreq->param('getresume') || 0;
	$upload_infos{'getresume'} = 0 if ($upload_infos{'getresume'} !~ /^[0-1]$/);

	# process upload
	$upload_infos{'real_filename'} = normalize($Upload->filename());
	$upload_infos{'file_name'} = genUniqId(); # "filesystem" filename
	$upload_infos{'file_size'} = $Upload->size();
	$upload_infos{'file_type'} = $Upload->type();
	$upload_infos{'upload_date'} = time(); # get the time from 01/01/1970 0:0:0 GMT
	$upload_infos{'expire_date'} = $upload_infos{'upload_date'} + ($upload_infos{'daykeep'}*(24*3600));

	# store file on disk
	my $destination = File::Spec->catfile($S->config->getFileRepository(),$upload_infos{'file_name'});
	if ( !storeFile($destination, $Upload, $S->config()) ) {
		$t_begin->param(HAS_ERROR=>1);
		$t_begin->param(ERROR=>$S->i18n->localizeToHtml("unable to store file"));
		display($S,$t_begin);
	}

	# register the new file
	# TODO : CHECK FOR ERRORS !
	$db->registerNewFile(days=>$S->config->getDefaultFileExpire(),
	                     fields=>[file_name=>$upload_infos{'file_name'},
	                              real_name=>$upload_infos{'real_filename'},
	                              owner=>$S->getAuthUser(),
																ip_address=>$S->getRemoteIP(),
																use_proxy=>$S->isBehindProxy(),
                                proxy_infos=>$S->getProxyInfos(),
	                              content_type=>$upload_infos{'file_type'},
	                              file_size=>$upload_infos{'file_size'},
	                              upload_date=>$upload_infos{'upload_date'},
	                              expire_date=>$upload_infos{'expire_date'},
	                              get_delivery=>$upload_infos{'getdelivery'},
	                              get_resume=>$upload_infos{'getresume'}]);

	# send email if needed
	if ( $S->config->needEmailNotification() ) {
		if ( ! sendMail($S,\%upload_infos) ) {
			$t_end->param(HAS_ERROR=>1);
			$t_end->param(ERROR=>$S->i18n->localizeToHtml("unable to send email"));
		}
	}
	# fill last template
	$t_end->param(FILENAME=>toHtml($upload_infos{'real_filename'}));
	my ($fsz,$funit) = hrSize($upload_infos{'file_size'});
	$t_end->param(FILESIZE=>$fsz." ".$S->i18n->localizeToHtml($funit));
	$t_end->param(FILEEXPIRE=>toHtml(tsToLocal($upload_infos{'expire_date'})));
	$t_end->param(GETURL=>genGetUrl($S,\%upload_infos));
	$t_end->param(DAYS=>$upload_infos{'daykeep'});
	$t_end->param(UPLOADURL=>$S->getUploadUrl());
	display($S,$t_end);
	return OK;
}

# display 
sub display {
	my $S = shift;
	my $T = shift;
	# base for static include
	$T->param(STATIC_FILE_BASE=>$S->getStaticUrl()) if ( $T->query(name=>'STATIC_FILE_BASE') );
	$S->sendHeader("Content-type"=>"text/html");
	# print body only if it is not a HEAD request
	$S->apreq->print($T->output()) if ( ! $S->apreq->header_only() );
	exit(OK);
}

# generate the Form Action
sub genFormAction {
	my $s = shift;
	my $dlid = shift;
	my $url = $s->getCurrentUrl();
	$url .= "?".$s->genQueryString({dlid=>$dlid});
	return $url;
}

# generate the Get url
sub genGetUrl {
	my $s = shift; # FILEX::System
	my $i = shift; # \%file_infos
	my $url = $s->getGetUrl();
	$url .= "?".$s->genQueryString({k=>$i->{'file_name'}});
	return $url;
}

# generate the Meter Url
sub genMeterUrl {
	my $s = shift; # FILEX::System
	my $dlid = shift; # download id
	my $url = $s->getMeterUrl();
	$url .= "?".$s->genQueryString({dlid=>$dlid,ini=>1});
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
	my $file_infos = shift;
	# load template
	my $t = $s->getTemplate(name=>"mail_upload") or return undef;
	# fill template
	$t->param(FILENAME=>$file_infos->{'real_filename'});
	$t->param(GETURL=>genGetUrl($s,$file_infos));
	my ($fsz,$funit) = hrSize($file_infos->{'file_size'});
	$t->param(FILESIZE=>$fsz." ".$s->i18n->localize($funit));
	$t->param(FILEDATE=>tsToLocal($file_infos->{'upload_date'}));
	$t->param(FILEEXPIRE=>tsToLocal($file_infos->{'expire_date'}));
	$t->param(SYSTEMEMAIL=>$s->config->getSystemEmail());
	$t->param(GETDELIVERY=>$s->i18n->localize($file_infos->{'getdelivery'} ? "yes" : "no"));
	$t->param(GETRESUME=>$s->i18n->localize($file_infos->{'getresume'} ? "yes" : "no"));
	# now it time to send email
	my $to = $s->getMail($s->getAuthUser());
	return undef if !length($to);
	return $s->sendMail(
		from=>$s->config->getSystemEmail(),
		to=>$to,
		charset=>"ISO-8859-1",
		subject=>$s->i18n->localize("mail subject %s",$file_infos->{'real_filename'}),
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
