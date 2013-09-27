package FILEX::Apache::Handler::Upload;
use strict;
use vars qw($VERSION);
# Apache Related
use constant MP2 => (exists $ENV{MOD_PERL_API_VERSION} and $ENV{MOD_PERL_API_VERSION} >= 2);

# FILEX related
use FILEX::System;
use FILEX::System::Config;
use FILEX::DB::Upload;
use FILEX::Tools::Utils qw(tsToLocal hrSize toHtml genUniqId);
# Others
use File::Spec;
use IO::Select;
use Time::HiRes qw(gettimeofday tv_interval);
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
# use password id field
use constant NEED_PASSWORD_FIELD_NAME => "withpwd";
# password id field
use constant PASSWORD_FIELD_NAME => "pwd";

$VERSION = 1.0;

BEGIN {
	if (MP2) {
		require Apache2::Const;
		Apache2::Const->import(-compile=>qw(OK));
		require Apache2::RequestRec;
		require Apache2::Upload;
	} else {
		require Apache::Constants;
		Apache::Constants->import(qw(OK));
	}
}

# handler between MP1 && MP2 have changed
sub handler_mp1($$) { &run; }
sub handler_mp2 : method { &run; }
*handler = MP2 ? \&handler_mp2 : \&handler_mp1;

# OK => ok
# DECLINED => CONTINUE, NOT_AUTHORITATIVE -> pass thru
# AUTH_REQUIRED
# SERVER_ERROR
# The Main entry point
sub run {
	my $class = shift;
	# the request object
	my $r = shift;
	my $S; # FILEX::System object
	my $bUploadCanceled = 0; # upload canceled ?
	my $dlid_field_name = DLID_FIELD_NAME;

	# BEGIN INITIALIZATION 
	# get current query params
	# and get uniq upload id
	my %args;
	if ( MP2 ) {
		%args = FILEX::Tools::Utils::qsParams($r->args());
	} else {
		%args = $r->args();
	}
	# if we have de dlid in the QS then we must hook for upload meter
	my $download_id = exists($args{$dlid_field_name}) ? $args{$dlid_field_name} : undef;
	if ( $download_id ) {
		# the new config object
		# init config object (because we need info to initialize the IPCache
		my $Config = FILEX::System::Config->instance(file=>$r->dir_config(FILEX_CONFIG_NAME));
		# get maximum file upload size and check it
		my $posted_content_length = (MP2) ? $r->headers_in->{'Content-Length'} : $r->header_in('Content-Length');
		# initialize IPC Cache if we have a download id and if the upload size is not too large
		my $IPCache = initIPCCache($Config);
		if ( !$IPCache ) {
			warn(__PACKAGE__,"-> Unable to create Shared Cache !");
			$S = FILEX::System->new($r,with_upload=>1);
		} else {
			# set the IPC Size 
			my $cntlength = $posted_content_length;
			$IPCache->set($download_id."size",$cntlength) if ( $cntlength );
			my $transparent_hook = _new_upload_hook($IPCache);
			$S = FILEX::System->new($r,with_upload=>1,with_hook=>{"hook_data"=>$download_id,"upload_hook"=>$transparent_hook});
		}
		# continue there the request is parsed now
		my $old_download_id = $S->apreq->param(OLD_DLID_FIELD_NAME);
		# check if user is connected
		if ( $S->isAborted() ) {
			# set IPC Cancel state
			$IPCache->set($download_id."canceled",1) if $IPCache;
			$bUploadCanceled = 1;
		} else {
			$download_id = genUniqId() if ( ! $old_download_id || ($old_download_id ne $download_id) );
			# inform the IPC that download end
			$IPCache->set($download_id."end",1) if $IPCache;
		}
	} else {
		$S = FILEX::System->new($r);
		$download_id = genUniqId();
	}
	# END INITIALIZATION 
	# beginSession will redirect the user if required
	my $user = $S->beginSession(); 

	# load templates
	my $t_begin = _template_begin($S);
	my $t_end = $S->getTemplate(name=>"upload_end");

	$t_begin->param(FILEX_USER_NAME=>toHtml($user->getRealName()));
	$t_end->param(FILEX_SYSTEM_EMAIL=>$S->config->getSystemEmail());
	$t_end->param(FILEX_USER_NAME=>toHtml($user->getRealName()));

	# fill in the first template
	$t_begin->param(FILEX_MANAGE_UPLOADED_FILES_COUNT=>$user->getUploadCount());
	$t_begin->param(FILEX_MANAGE_ACTIVE_FILES_COUNT=>$user->getActiveCount());
	$t_begin->param(FILEX_MANAGE_URL=>toHtml($S->getManageUrl()));
	$t_begin->param(FILEX_CAN_UPLOAD=>1);
	$t_begin->param(FILEX_FORM_UPLOAD_ACTION=>toHtml(genFormAction($S,$download_id)));
	$t_begin->param(FILEX_OLD_DLID=>$download_id);
	$t_begin->param(FILEX_METER_URL=>toHtml(genMeterUrl($S,$download_id)));
	if ( $user->isAdmin() ) {
		$t_begin->param(FILEX_MANAGE_IS_ADMIN=>1);
		$t_begin->param(FILEX_MANAGE_ADMIN_URL=>$S->getAdminUrl());
	}

	my %upload_infos = _get_upload_infos_from_req_params($S);

	my @expire_loop = _compute_expire_loop($S, $upload_infos{daykeep});
	$t_begin->param(FILEX_EXPIRE_LOOP=>\@expire_loop);

	# check for quotas
	my ($quota_max_file_size,$quota_max_used_space) = $user->getQuota(); 
	if ( $quota_max_used_space > 0 ) {
		my ($hrsize,$hrunit) = hrSize($quota_max_used_space);
		$t_begin->param(FILEX_MANAGE_HAVE_QUOTA=>1);
		$t_begin->param(FILEX_MANAGE_MAX_USED_SPACE=>"$hrsize ".$S->i18n->localizeToHtml($hrunit));
	}
	my $current_user_space = $user->getDiskSpace();
 	my ($hrsize,$hrunit) = hrSize($current_user_space);
	$t_begin->param(FILEX_MANAGE_USED_SPACE=>"$hrsize ".$S->i18n->localizeToHtml($hrunit));

	# check if space remaining
	if ( ! $S->isSpaceRemaining() ) {
		$t_begin->param(FILEX_CAN_UPLOAD=>0);
		$t_begin->param(FILEX_HAS_ERROR=>1);
		$t_begin->param(FILEX_ERROR=>$S->i18n->localizeToHtml("no more space on drive"));
		display($S,$t_begin);
	}

	# the real begining is here
	# check if the request is aborted
	if ( $bUploadCanceled )  {
		$t_begin->param(FILEX_HAS_ERROR=>1);
		$t_begin->param(FILEX_ERROR=>$S->i18n->localizeToHtml("upload canceled"));
		display($S,$t_begin);
	}
	# otherwise get the upload field
	my $Upload  = $S->apreq->upload(UPLOAD_FIELD_NAME);

	_check_upload_size($S, $Upload, $t_begin, $user->getMaxFileSize());

	# check if we uploaded some things
	if ( !$Upload ) { 
		# if not then exit
		display($S,$t_begin);
	}

	$upload_infos{'owner'} = $user->getId();
	$upload_infos{'owner_uniq_id'} = $user->getUniqId();

	my $record = eval { _store_file_and_register_on_disk($S, $Upload, %upload_infos) };
	if ( $@ ) {
		warn(__PACKAGE__,"-> problem while creating new record : $@");
		$t_begin->param(FILEX_HAS_ERROR=>1);
		$t_begin->param(FILEX_ERROR=>$@);
		display($S,$t_begin);
	}
	# send email if needed
	if ( $S->config->needEmailNotification() ) {
		# password is stored as an md5 string so we need the clear text one
		if ( ! sendMail($S,$record,$upload_infos{'password'}) ) {
			$t_end->param(FILEX_HAS_ERROR=>1);
			$t_end->param(FILEX_ERROR=>$S->i18n->localizeToHtml("unable to send email"));
		}
	}
	# fill last template
	$t_end->param(FILEX_FILE_NAME=>toHtml($record->getRealName()));
	my ($fsz,$funit) = hrSize($record->getFileSize());
	$t_end->param(FILEX_FILE_SIZE=>$fsz." ".$S->i18n->localizeToHtml($funit));
	$t_end->param(FILEX_FILE_EXPIRE=>toHtml(tsToLocal($record->getExpireDate())));
	$t_end->param(FILEX_GET_URL=>toHtml(genGetUrl($S,$record->getFileName())));
	$t_end->param(FILEX_DAY_KEEP=>$upload_infos{'daykeep'});
	$t_end->param(FILEX_UPLOAD_URL=>toHtml($S->getUploadUrl()));
	if ( $record->needPassword() ) {
		$t_end->param(FILEX_HAS_PASSWORD=>1);
		$t_end->param(FILEX_PASSWORD=>toHtml($upload_infos{'password'}));
	}
	display($S,$t_end);
	return MP2 ? Apache2::Const::OK : Apache::Constants::OK;
}

sub _store_file_and_register_on_disk {
	my ($S, $Upload, %upload_infos) = @_;

	$upload_infos{'file_name'} = genUniqId(); # "filesystem" filename
	$upload_infos{'upload_date'} = time(); # get the time from 01/01/1970 0:0:0 GMT
	$upload_infos{'real_filename'} = normalize($Upload->filename());
	$upload_infos{'file_size'} = $Upload->size();
	$upload_infos{'file_type'} = $Upload->type();
    
	# store file on disk
	my $destination = File::Spec->catfile($S->config->getFileRepository(),$upload_infos{'file_name'});
	if (!storeFile($destination, $Upload, $S->config())) {
		die $S->i18n->localizeToHtml("unable to store file");
	}
	_register_new_upload($S, %upload_infos);
}

sub _register_new_upload {
	my ($S, %upload_infos) = @_;

	# register the new file
	my $record = FILEX::DB::Upload->new();

	$record->setFileName($upload_infos{'file_name'});
	$record->setRealName($upload_infos{'real_filename'});
	$record->setOwner($upload_infos{'owner'});
	$record->setOwnerUniqId($upload_infos{'owner_uniq_id'});
	$record->setContentType($upload_infos{'file_type'});
	$record->setFileSize($upload_infos{'file_size'});
	$record->setUploadDate($upload_infos{'upload_date'});
	$record->setExpireDays($upload_infos{'daykeep'});
	$record->setGetDelivery($upload_infos{'getdelivery'});
	$record->setGetResume($upload_infos{'getresume'});
	$record->setPassword($upload_infos{'password'}) if defined $upload_infos{'password'};

	$record->setUserAgent($S->getUserAgent());
	$record->setIpAddress($S->getRemoteIP());
	if ( $S->isBehindProxy() ) {
		$record->setUseProxy(1);
		$record->setProxyInfos($S->getProxyInfos());
	}

	# create the new record
	$record->save() or die "unable to save record " . $record->getLastErrorString();

	$record;
}

sub _get_upload_infos_from_req_params {
	my ($S) = @_;

	my %upload_infos; # upload informations
	$upload_infos{'getdelivery'} = $S->apreq->param(DELIVERY_FIELD_NAME) || 0;
	$upload_infos{'getdelivery'} = 0 if ($upload_infos{'getdelivery'} !~ /^[0-1]$/);
	$upload_infos{'getresume'} = $S->apreq->param(RESUME_FIELD_NAME) || 0;
	$upload_infos{'getresume'} = 0 if ($upload_infos{'getresume'} !~ /^[0-1]$/);
	$upload_infos{'wpwd'} = $S->apreq->param(NEED_PASSWORD_FIELD_NAME) || 0;
	$upload_infos{'wpwd'} = 0 if ( $upload_infos{'wpwd'} !~ /^[0-1]$/);
	
	# set password if checked and password is ok
	if ( $upload_infos{'wpwd'} == 1 ) {
	        my $password = $S->apreq->param(PASSWORD_FIELD_NAME);
		if ( defined $password ) {
			# strip whitespace 
			$password =~ s/\s//g;
			my $pwd_length = length($password);
			# set password only if in valid range
			$upload_infos{'password'} = $password if ( $pwd_length >= $S->config->getMinPasswordLength() && 
								   $pwd_length <= $S->config->getMaxPasswordLength() );
		}
	}

	my $expire_default = $S->config->getDefaultFileExpire();
	my $expire_max = $S->config->getMaxFileExpire();
	$upload_infos{'daykeep'} = $S->apreq->param(DAY_KEEP_FIELD_NAME) || $expire_default;
	$upload_infos{'daykeep'} = $expire_default if ( $upload_infos{'daykeep'} > $expire_max );

	%upload_infos;
}

sub _compute_expire_loop {
	my ($S, $daykeep) = @_;

	map { 
		my $expire_loop_row = {'FILEX_EXPIRE_VALUE'=>$_};
		if ( $_ == $daykeep) {
		    $expire_loop_row->{'FILEX_EXPIRE_SELECTED'} = 1;
		}
		$expire_loop_row;
	} ($S->config->getMinFileExpire() .. $S->config->getMaxFileExpire());
}

sub _new_upload_hook {
	my ($IPCache) = @_;

			# initialize the upload hook
			# note : hook_data = uploadid
			# note : inspired from Apache::UploadMeter
			my $prevtime;
			my $oldlength = 0;

			sub {
				my ($upl, $buf, $len, $hook_data) = @_;
				return if ( ! $IPCache );
				# check if upload begin
				if ( $oldlength == 0 ) {
					$IPCache->set($hook_data."filename",normalize((MP2) ? $upl->upload_filename() : $upl->filename()));
					$IPCache->set($hook_data."starttime",time());
					$IPCache->set($hook_data."canceled",0);
					$IPCache->set($hook_data."end",0);
				}

				# on MP2 the len was the current total upload size
				my $newlength = (MP2) ? $len : $len + $oldlength;

				# increment current length
				$oldlength = $newlength;

				my $time = [gettimeofday];
				if (!$prevtime || tv_interval($prevtime, $time) > 0.2) {
				    # store current length
				    $IPCache->set($hook_data."length",$newlength);
				    $prevtime = $time;
				}
			};
}


sub _template_begin {
	my ($S) = @_;

	my $t_begin = $S->getTemplate(name=>"upload");
	$t_begin->param(FILEX_FORM_UPLOAD_DAY_KEEP_NAME=>DAY_KEEP_FIELD_NAME);
	$t_begin->param(FILEX_FORM_UPLOAD_DELIVERY_NAME=>DELIVERY_FIELD_NAME);
	$t_begin->param(FILEX_FORM_UPLOAD_RESUME_NAME=>RESUME_FIELD_NAME);
	$t_begin->param(FILEX_FORM_UPLOAD_UPLOAD_NAME=>UPLOAD_FIELD_NAME);
	$t_begin->param(FILEX_FORM_UPLOAD_OLD_DLID_NAME=>OLD_DLID_FIELD_NAME);
	$t_begin->param(FILEX_FORM_UPLOAD_NEED_PASSWORD_NAME=>NEED_PASSWORD_FIELD_NAME);
	$t_begin->param(FILEX_FORM_UPLOAD_PASSWORD_NAME=>PASSWORD_FIELD_NAME);
	$t_begin->param(FILEX_MIN_PASSWORD_LENGTH=>$S->config->getMinPasswordLength());
	$t_begin->param(FILEX_MAX_PASSWORD_LENGTH=>$S->config->getMaxPasswordLength());
	$t_begin->param(FILEX_MAX_DAY_KEEP=>$S->config->getMaxFileExpire());
	$t_begin->param(FILEX_SYSTEM_EMAIL=>$S->config->getSystemEmail());

	$t_begin;
}

sub _check_upload_size {
	my ($S, $Upload, $t_begin, $max_file_size) = @_;

	# if max_file_size < 0 then unlimited upload size
	# if max_file_size == 0 then we cannot upload (quota reached)
	# max_file_size == 0 then no upload
	if ( $max_file_size == 0 ) {
		$t_begin->param(FILEX_CAN_UPLOAD=>0);
		$t_begin->param(FILEX_HAS_ERROR=>1);
		$t_begin->param(FILEX_ERROR=>$S->i18n->localizeToHtml("quota exceed"));
		display($S,$t_begin);
	} 

	if ( $max_file_size > 0 ) {
		$t_begin->param(FILEX_HAS_MAX_FILE_SIZE=>1);
		my ($hrsize,$hrunit) = hrSize($max_file_size);
		$t_begin->param(FILEX_MAX_FILE_SIZE=>"$hrsize ".$S->i18n->localizeToHtml($hrunit));
	}

	$Upload or return;

	if ( $Upload->size() <= 0 ) {
		$t_begin->param(FILEX_HAS_ERROR=>1);
		$t_begin->param(FILEX_ERROR=>$S->i18n->localizeToHtml("file size is null"));
		display($S,$t_begin);
	} elsif ( ($Upload->size() > $max_file_size) && ($max_file_size > 0) ) {
		$t_begin->param(FILEX_HAS_ERROR=>1);
		$t_begin->param(FILEX_ERROR=>$S->i18n->localizeToHtml("file size too large"));
		display($S,$t_begin);
	}
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
	exit( MP2 ? Apache2::Const::OK : Apache::Constants::OK );
}

# generate the Form Action
sub genFormAction {
	my $s = shift;
	my $dlid = shift;
	my $dlid_field = DLID_FIELD_NAME;
	my $url = $s->getCurrentUrl();
	$url .= "?".$s->genQueryString(params=>{$dlid_field=>$dlid});
	return $url;
}

# generate the Get url
sub genGetUrl {
	my $s = shift; # FILEX::System
	my $fn = shift; 
	my $url = $s->getGetUrl();
	$url .= "?".$s->genQueryString(params=>{k=>$fn});
	return $url;
}

# generate the Meter Url
sub genMeterUrl {
	my $s = shift; # FILEX::System
	my $dlid = shift; # download id
	my $dlid_field = DLID_FIELD_NAME;
	my $url = $s->getMeterUrl();
	$url .= "?".$s->genQueryString(params=>{$dlid_field=>$dlid,ini=>1});
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
		my $out_fh = Apache::File->new(">$path") or warn(__PACKAGE__,"=> unable to open $path for writing : $!") && return undef;
		my ($in_fh,$buffer);
		$in_fh = $upload->fh();
		while ( read($in_fh, $buffer, 1024) ) {
			print $out_fh $buffer;
		}
		$out_fh->close();
	}
	return 1;
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

sub sendMail {
	my $s = shift;
	my $record = shift;
	my $password = shift;
	my $return_value = undef;
	my ($fsz,$funit,$user,$to);
	# load template
	my $t = $s->getTemplate(name=>"mail_upload");
	if ( !$t ) {
		warn(__PACKAGE__,"=> unable to load template : mail_upload");
		$return_value = undef;
	} else {
		# fill template
		$t->param(FILEX_FILE_NAME=>$record->getRealName());
		$t->param(FILEX_GET_URL=>genGetUrl($s,$record->getFileName()));
		($fsz,$funit) = hrSize($record->getFileSize());
		$t->param(FILEX_FILE_SIZE=>$fsz." ".$s->i18n->localize($funit));
		$t->param(FILEX_FILE_DATE=>tsToLocal($record->getUploadDate()));
		$t->param(FILEX_FILE_EXPIRE=>tsToLocal($record->getExpireDate()));
		$t->param(FILEX_SYSTEM_EMAIL=>$s->config->getSystemEmail());
		$t->param(FILEX_GET_DELIVERY=>$s->i18n->localize($record->getGetDelivery() ? "yes" : "no"));
		$t->param(FILEX_GET_RESUME=>$s->i18n->localize($record->getGetResume() ? "yes" : "no"));
		if ( $record->needPassword() ) {
			$t->param(FILEX_HAS_PASSWORD=>1);
			$t->param(FILEX_PASSWORD=>$password);
		}
		# now it time to send email
		$user = $s->getUser();
		$to = $user->getMail() if ($user);
		if ( $to && length($to) ) {
			$return_value = $s->sendMail(
				from=>$s->config->getSystemEmail(),
				to=>$to,
				charset=>"ISO-8859-1",
				subject=>$s->i18n->localize("mail subject %s",$record->getRealName()),
				content=>$t->output()
			);
		} else {
			warn(__PACKAGE__," => unable to get user's mail");
			$return_value = undef;
		}
	}
	# go for bigbrother
	my $iswatched = $user->isWatched() if ($user);
	if ( $iswatched && length($iswatched) > 1 ) {
		my $tw = $s->getTemplate(name=>"mail_big_brother");
		if ( $tw ) {
			$tw->param(FILEX_USER_NAME=>$user->getRealName());
			$tw->param(FILEX_USER_ID=>$user->getId());
			$tw->param(FILEX_USER_MAIL=>$user->getMail());
			$tw->param(FILEX_FILE_NAME=>$record->getRealName());
			$tw->param(FILEX_FILE_SIZE=>$fsz." ".$s->i18n->localize($funit));
			$tw->param(FILEX_FILE_DATE=>tsToLocal($record->getUploadDate()));
			$tw->param(FILEX_FILE_EXPIRE=>tsToLocal($record->getExpireDate()));
			#http://pc401-189.insa-lyon.fr/admin?sa=1&id=108&maction=ac4
			my $admin_url = $s->getAdminUrl();
			$admin_url .= "?".$s->genQueryString(params=>{sa=>1,maction=>"ac4",id=>$record->getId()});
			$tw->param(FILEX_FILE_GET_URL=>$admin_url);
			$s->sendMail(from=>$s->config->getSystemEmail(),
				to=>$iswatched,
				charset=>"ISO-8859-1",
				subject=>$s->i18n->localize("%s upload a file",$user->getId()),
				content=>$tw->output()) or warn(__PACKAGE__,"=> unable to send watch mail : $iswatched!");
			} else {
				warn(__PACKAGE__,"=> unable to load template : mail_big_brother");
			}
	}
	return $return_value;
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
