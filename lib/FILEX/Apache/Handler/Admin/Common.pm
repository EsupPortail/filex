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
use FILEX::DB::Admin::Helpers;
use FILEX::Tools::Utils qw(tsToGmt hrSize tsToLocal toHtml);
# for rules creation
use FILEX::DB::Admin::Rules;
use FILEX::DB::Admin::Exclude;

use constant FILE_FIELD_NAME => "k";
use constant ADMIN_DOWNLOAD_FIELD_NAME => "adm";

use constant FIELD_STATE_NAME => "state";
use constant FIELD_EXPIRE_NAME => "expire";
use constant FIELD_RESUME_NAME => "resume";
use constant FIELD_DELIVERY_NAME => "delivery";
use constant FIELD_RENEW_NAME => "renew";
use constant FIELD_USE_PASSWORD_NAME => "upwd";
use constant FIELD_PASSWORD_NAME => "pwd";
use constant FIELD_DISABLE_USER_FILES_NAME => "duf";
use constant FIELD_DISABLE_USER_NAME => "du";
use constant FIELD_SUBMIT_NAME => "sub";
use constant ADMIN_MODE => 1;

# require : FILEX::System + upload id
# system => FILEX::System object
# id => Upload id
# url => access url
# go_back => go back url
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
	#$T->param(SUB_ACTION_FIELD_NAME=>$ARGZ{'sub_action_field_name'});
	#$T->param(SUB_ACTION_VALUE=>$ARGZ{'sub_action_value'});
	#$T->param(FILE_ID_FIELD_NAME=>$ARGZ{'file_id_field_name'});
	#$T->param(FILE_ID_VALUE=>$file_id);
	# go back
	if ( exists($ARGZ{'go_back'}) && defined($ARGZ{'go_back'}) ) {
		$T->param(GO_BACK_URL=>toHtml($ARGZ{'go_back'}));
	}
	# user name
	$T->param(FILEX_USER_NAME=>toHtml($S->getUser()->getRealName()));
	$T->param(FILEX_SYSTEM_EMAIL=>$S->config->getSystemEmail());
	# form url
	#$T->param(FILEX_FORM_ACTION_URL=>$S->toHtml($ARGZ{'url'}));
	#$T->param(FILEX_FORM_SUBMIT_NAME=>FIELD_SUBMIT_NAME);

	my $upload = eval { FILEX::DB::Upload->new(id=>$file_id); };
	if ($@) {
		$T->param(FILEX_HAS_ERROR=>1);
		$T->param(FILEX_ERROR=>$S->i18n->localizeToHtml("database error %s",$@));
		return $T;
	}
  if ( !$upload->exists() ) {
		$T->param(FILEX_HAS_ERROR=>1);
		$T->param(FILEX_ERROR=>$S->i18n->localizeToHtml("requested file does not exists"));
		return $T;
	}
	# check if the user is the owner of the file
	my $bIsOwner = $upload->checkOwner($S->getUser()->getUniqId());
	# if in admin_mode => ok if the logged user is an administrator
	# if not in admin_mode then the file must belong to the user
	if ( ($mode != ADMIN_MODE && !$bIsOwner) ) {
		$T->param(FILEX_HAS_ERROR=>1);
		$T->param(FILEX_ERROR=>$S->i18n->localizeToHtml("you're not the owner of the file"));
		return $T;
	}

	# CHECK FOR PARAMS
	my $isSubmit = $S->apreq->param(FIELD_SUBMIT_NAME);
	if ( defined($isSubmit) && length($isSubmit) > 0 ) {
		my $changes = 0;
		# admin mode
		if ( $mode == ADMIN_MODE ) {
			# set file enable or not
			my $activate = $S->apreq->param(FIELD_STATE_NAME);
			if ( defined($activate) ) {
				if (($upload->getEnable() != $activate) && ($activate == 1 || $activate == 0)) {
					$upload->setEnable($activate);
					$changes++;
				}
			}
			my $helpers = undef;
			# disable owner's files
			my $disableOwnerFiles = $S->apreq->param(FIELD_DISABLE_USER_FILES_NAME);
			if ( defined($disableOwnerFiles) && $disableOwnerFiles =~ /^[1|0]$/ ) {
				if ( !defined($helpers) ) {
					$helpers = eval { FILEX::DB::Admin::Helpers->new(); };
					if ($@) {
						$T->param(FILEX_HAS_ERROR=>1);
						$T->param(FILEX_ERROR=>$S->i18n->localizeToHtml("database error %s",$@));
						# fatal error !
						return $T
					}
				}
				# disable files
				if ( $disableOwnerFiles == 1 ) {
					# set files disabled
					if ( ! $helpers->disableUserFiles($upload->getOwnerUniqId()) ) {
						warn(__PACKAGE__," unable to disable user's files : "+$helpers->getLastErrorString());
					} else {
						# since the files is loaded before disabling it we need to change it's state
						$upload->setEnable(0);
					}
				}
				# enable files
				if ( $disableOwnerFiles == 0 ) {
					if ( ! $helpers->enableUserFiles($upload->getOwnerUniqId()) ) {
						warn(__PACKAGE__,"=> unable to disable user's files : ",$helpers->getLastErrorString());
					} else {
						$upload->setEnable(1);
					}
				}
			}
			# disable owner
			my $disableOwner = $S->apreq->param(FIELD_DISABLE_USER_NAME);
			if ( defined($disableOwner) && $disableOwner =~ /^1$/ ) {
				if ( ! autoExclude($upload->getOwner(),$S) ) {
					warn(__PACKAGE__,"=> unable to create exclude rule for : ",$upload->getOwner());
				}
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
		# password
		my $use_password = $S->apreq->param(FIELD_USE_PASSWORD_NAME);
		if ( defined($use_password) ) {
			if ( $use_password == 0 ) {
				# disable password only if enabled
				$upload->setPassword() if ( $upload->needPassword() );
				$changes++;
			}
			if ( $use_password == 1 ) {
				my $password = $S->apreq->param(FIELD_PASSWORD_NAME);
				# strip whitespace
				$password =~ s/\s//g if defined($password);
				my $bSetPassword = 1;
				if ( $upload->needPassword() ) {
					# password already set && no new password then nothing
					$bSetPassword = 0 if ( !defined($password) || !length($password) );
				} 
				if ( $bSetPassword ) {
					# check for password length
					if ( defined($password) && ( length($password) >= $S->config->getMinPasswordLength() && 
							 length($password) <= $S->config->getMaxPasswordLength() ) ) {
						$upload->setPassword($password);
						$changes++;
					}
				}
			}
		}
		if ( $changes && !$upload->save() ) {
			$T->param(FILEX_HAS_ERROR=>1);
			$T->param(FILEX_ERROR=>$upload->getLastErrorString());
			return $T;
		}
	}
	# END CHECK PARAM

	# fill
	$T->param(FILEX_RENEW_COUNT=>$upload->getRenewCount());
	$T->param(FILEX_MAX_RENEW_COUNT=>$S->config->getRenewFileExpire());
	$T->param(FILEX_FILE_NAME=>toHtml($upload->getRealName()));
	my ($fsz,$funit) = hrSize($upload->getFileSize());
	$T->param(FILEX_FILE_SIZE=>$fsz." ".$S->i18n->localizeToHtml("$funit"));
	$T->param(FILEX_FILE_DATE=>toHtml(tsToLocal($upload->getUploadDate())));
	$T->param(FILEX_FILE_EXPIRE=>toHtml(tsToLocal($upload->getExpireDate())));
	$T->param(FILEX_FILE_COUNT=>$upload->getDownloadCount());

	#
	# set expired
	#
	my $bIsExpired = $upload->isExpired();
	if ( $bIsExpired != 1 ) {
		$T->param(FILEX_CAN_EXPIRE=>1);
		$T->param(FILEX_FORM_EXPIRE_NAME=>FIELD_EXPIRE_NAME);
		$T->param(FILEX_FORM_EXPIRE_VALUE_YES=>1);
		$T->param(FILEX_FORM_EXPIRE_VALUE_NO=>0);
	} else {
		$T->param(FILEX_EXPIRED=>$S->i18n->localizeToHtml("yes"));
	}
	#
	# password
	#
	if ( $bIsExpired != 1 ) {
		$T->param(FILEX_FORM_USE_PASSWORD_NAME=>FIELD_USE_PASSWORD_NAME);
		$T->param(FILEX_FORM_PASSWORD_NAME=>FIELD_PASSWORD_NAME);
		$T->param(FILEX_FORM_USE_PASSWORD_VALUE_ACTIVATE=>1);
		$T->param(FILEX_FORM_USE_PASSWORD_VALUE_DESACTIVATE=>0);
		$T->param(FILEX_MAX_PASSWORD_LENGTH=>$S->config->getMaxPasswordLength());
		$T->param(FILEX_MIN_PASSWORD_LENGTH=>$S->config->getMinPasswordLength());
		if ( $upload->needPassword() ) {
			$T->param(FILEX_FORM_USE_PASSWORD_ACTIVATE_CHECKED=>1);
		} else {
			$T->param(FILEX_FORM_USE_PASSWORD_DESACTIVATE_CHECKED=>1);
		}
	}
	#
	# get delivery mail
	#
	if ( $bIsExpired != 1 ) {
		$T->param(FILEX_FORM_DELIVERY_NAME=>FIELD_DELIVERY_NAME);
		$T->param(FILEX_FORM_DELIVERY_VALUE_YES=>1);
		$T->param(FILEX_FORM_DELIVERY_VALUE_NO=>0);
		if ( $upload->getGetDelivery() == 1 ) {
			$T->param(FILEX_FORM_DELIVERY_VALUE_YES_CHECKED=>1);
		} else {
			$T->param(FILEX_FORM_DELIVERY_VALUE_NO_CHECKED=>1);
		}
	} else {
		if ( $upload->getGetDelivery() == 1 ) {
			$T->param(FILEX_DELIVERY=>$S->i18n->localizeToHtml("yes"));
		} else {
			$T->param(FILEX_DELIVERY=>$S->i18n->localizeToHtml("no"));
		}
	}
	#
	# get resume mail
	#
	if ( $bIsExpired != 1 ) {
		$T->param(FILEX_FORM_RESUME_NAME=>FIELD_RESUME_NAME);
		$T->param(FILEX_FORM_RESUME_VALUE_YES=>1);
		$T->param(FILEX_FORM_RESUME_VALUE_NO=>0);
		if ( $upload->getGetResume() == 1 ) {
			$T->param(FILEX_FORM_RESUME_VALUE_YES_CHECKED=>1);
		} else {
			$T->param(FILEX_FORM_RESUME_VALUE_NO_CHECKED=>1);
		}
	} else {
		if ( $upload->getGetResume() == 1 ) {
			$T->param(FILEX_RESUME=>$S->i18n->localizeToHtml("yes"));
		} else {
			$T->param(FILEX_RESUME=>$S->i18n->localizeToHtml("no"));
		}
	}
	#
	# allow renewal of expiration time
	#
	if ( $bIsExpired != 1 ) {
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
	}
	#
	# get download address
	#
	$T->param(FILEX_GET_ADDRESS=>toHtml(genGetUrl($S,$upload->getFileName()))) if ($bIsExpired != 1);

	# Administrative mode display
	if ( $mode == ADMIN_MODE ) {
		# set template to admin mode
		$T->param(FILEX_ADMIN_MODE=>1);
		# file owner's mail
		$T->param(FILEX_FILE_OWNER=>$S->getMail($upload->getOwner()));
		# file owner's id
		$T->param(FILEX_FILE_OWNER_ID=>$upload->getOwner());
		# disk name
		$T->param(FILEX_DISK_NAME=>$upload->getFileName());
		# proxy
		if ( $upload->getUseProxy() == 1 ) {
			$T->param(FILEX_USE_PROXY=>$S->i18n->localizeToHtml("yes"));
			$T->param(FILEX_IF_USE_PROXY=>1);
			$T->param(FILEX_PROXY_INFOS=>$upload->getProxyInfos());
		} else {
			$T->param(FILEX_USE_PROXY=>$S->i18n->localizeToHtml("no"));
		}
		# user agent
		my $user_agent = $upload->getUserAgent();
		if ( defined($user_agent) ) {
			$T->param(FILEX_USER_AGENT=>toHtml($user_agent));
		} else {
			$T->param(FILEX_USER_AGENT=>$S->i18n->localizeToHtml("unknown"));
		}
		# upload address
		$T->param(FILEX_UPLOAD_ADDRESS=>toHtml($upload->getIpAddress()));
		# if file has not expired
		if ($bIsExpired != 1) {
			# administrative download address
			$T->param(FILEX_ADMIN_GET_ADDRESS=>toHtml(genGetUrl($S,$upload->getFileName(),1)));
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
		}
		# 
		$T->param(FILEX_FORM_DISABLE_USER_FILES_NAME=>FIELD_DISABLE_USER_FILES_NAME);
		$T->param(FILEX_FORM_DISABLE_USER_FILES_VALUE_ACTIVATE=>1);
		$T->param(FILEX_FORM_DISABLE_USER_FILES_VALUE_DESACTIVATE=>0);
		$T->param(FILEX_FORM_DISABLE_USER_NAME=>FIELD_DISABLE_USER_NAME);
		$T->param(FILEX_FORM_DISABLE_USER_VALUE=>1);
	}
	# form url
	# with or without validate button ?
	# if expired no validate button unless mode == ADMIN_MODE
	my $bValidateButton = ( $mode == ADMIN_MODE || $bIsExpired != 1 ) ? 1 : 0;
	if ( $bValidateButton == 1 ) {
		$T->param(FILEX_WITH_SUBMIT=>1);
		$T->param(FILEX_FORM_ACTION_URL=>toHtml($ARGZ{'url'}));
		$T->param(FILEX_FORM_SUBMIT_NAME=>FIELD_SUBMIT_NAME);
		$T->param(SUB_ACTION_FIELD_NAME=>$ARGZ{'sub_action_field_name'});
		$T->param(SUB_ACTION_VALUE=>$ARGZ{'sub_action_value'});
		$T->param(FILE_ID_FIELD_NAME=>$ARGZ{'file_id_field_name'});
		$T->param(FILE_ID_VALUE=>$file_id);
	}

	# return if no downloads
	return $T if ( $upload->getDownloadCount() == 0 );

	# do access report
	my (@log,@download_loop);
	$T->param(FILEX_HAS_DOWNLOAD=>1);
	if ( !$upload->getDownloads(results=>\@log) ) {
		$T->param(FILEX_HAS_DOWNLOAD_ERROR=>1);
		$T->param(FILEX_DOWNLOAD_ERROR=>$S->i18n->localiseToHtml("database error %s",$upload->getLastErrorString()));
		return $T;
	}
	for ( my $l = 0; $l <= $#log; $l++ ) {
		my $dl_record = {};
		if ( $mode == ADMIN_MODE ) {
			$dl_record->{'FILEX_DOWNLOAD_ADMIN_MODE'} = 1;
			if ( $log[$l]->{'use_proxy'} == 1 ) {
				$dl_record->{'FILEX_DOWNLOAD_USE_PROXY'} = 1;
				$dl_record->{'FILEX_DOWNLOAD_PROXY_INFOS'} = toHtml($log[$l]->{'proxy_infos'});
			}
			if ( defined($log[$l]->{'user_agent'}) && length($log[$l]->{'user_agent'}) > 0 ) {
				$dl_record->{'FILEX_DOWNLOAD_USER_AGENT'} = toHtml($log[$l]->{'user_agent'});
			} else {
				$dl_record->{'FILEX_DOWNLOAD_USER_AGENT'} = $S->i18n->localizeToHtml("unknown");
			}
		}
		$dl_record->{'FILEX_DOWNLOAD_ADDRESS'} = toHtml($log[$l]->{'ip_address'});
		$dl_record->{'FILEX_DOWNLOAD_DATE'} = toHtml(tsToLocal($log[$l]->{'ts_date'}));
		$dl_record->{'FILEX_DOWNLOAD_STATE'} = ( $log[$l]->{'canceled'} ) ? $S->i18n->localizeToHtml("yes") : $S->i18n->localizeToHtml("no");
		push(@download_loop,$dl_record);
		$T->param(FILEX_DOWNLOAD_LOOP=>\@download_loop);
	}
	return $T;
}

sub genGetUrl {
	my $S = shift; # FILEX::System
	my $f = shift; # file_name
	my $admin = shift || 0; # admin mode ?
	my $fFile = FILE_FIELD_NAME;
	my $fAdmin = ADMIN_DOWNLOAD_FIELD_NAME;
	my $url = $S->getGetUrl();
	if ( $admin == 1 ) {
		$url .= "?".$S->genQueryString(params=>{$fFile=>$f,$fAdmin=>1});
	} else {
		$url .= "?".$S->genQueryString(params=>{$fFile=>$f});
	}
	return $url;
}

# create automaticaly an exclude rules for a given user id
# return 1 or undef on error
sub autoExclude {
	my $uid = shift;
	my $system = shift;
	return undef && warn(__PACKAGE__,"autoExclude : Require a user id !") if !defined($uid); 
	# create the Rule
	my $rule = eval { FILEX::DB::Admin::Rules->new(); };
	if ($@) {
		warn(__PACKAGE__,"=> autoExclude : unable to create Rule object : ",$@);
		return undef;
	}
	# check if rule already exists
	my $rule_id = $rule->exists(type=>$FILEX::DB::Admin::Rules::RULE_TYPE_UID,exp=>$uid);
	my $bIsNewRule = 0;
	if ( !defined($rule_id) ) {
		warn(__PACKAGE__,"=> autoExclude : unable to check for rule existence : ",$rule->getLastErrorString());
		return undef;
	}
	# rule does not exists
	if ( $rule_id == -1 ) {
		$rule_id = $rule->add(name=>"_AUTO_ $uid",exp=>$uid,type=>$FILEX::DB::Admin::Rules::RULE_TYPE_UID);
		if ( !$rule_id ) {
			warn(__PACKAGE__,"=> autoExclude : unable to create new exclude rule for [ $uid ] : ",$rule->getLastErrorString());
			return undef;
		}
		$bIsNewRule = 1; # set as a new rule
	}
	# everythings ok, create the exclude entry
	my $exclude = eval { FILEX::DB::Admin::Exclude->new(); };
	if ($@) {
		warn(__PACKAGE__,"=> autoExclude : unable to create Exclude object : ",$@);
		if ( $bIsNewRule ) { # delete only if a new rule
			warn(__PACKAGE__,"=> autoExclude : removing last create rule : ",$rule_id);
			warn(__PACKAGE__,"=> autoExclude : removing rule [ $rule_id ] failed : ",$@) if ( !$rule->del($rule_id) );
		}
		return undef;
	}
	# check if the rule is already associated if not a new rule
	my $excludeExists = -1;
	if ( !$bIsNewRule ) {
		$excludeExists = $exclude->existsRule($rule_id);
		if ( !defined($excludeExists) ) {
			warn(__PACKAGE__,"=> autoExclude : unable to check if exclude rule exists : ",$@);
			if ( $bIsNewRule ) { # delete only if a new rule
				warn(__PACKAGE__,"=> autoExclude : removing last create rule : ",$rule_id);
				warn(__PACKAGE__,"=> autoExclude : removing rule [ $rule_id ] failed : ",$@) if ( !$rule->del($rule_id) );
			}
			return undef;
		}
	}
	my $expire_days = $system->config->getExcludeExpireDays();
	# add this new exclude rule only if this rule is not already linked
	if ( $excludeExists == -1 ) {
		my %args = (
			rule_id=>$rule_id,
			enable=>1,
			description=>"AUTO created exclude rule for : $uid"
		);
		$args{'expire_days'} = $expire_days if ( $expire_days );
		if ( !$exclude->add(%args) ) {
			warn(__PACKAGE__,"=> autoExclude : unable to create Exclude rule : ",$exclude->getLastErrorString());
			if ( $bIsNewRule ) { # delete only if a new rule
				warn(__PACKAGE__,"=> autoExclude : removing last create rule : ",$rule_id);
				warn(__PACKAGE__,"=> autoExclude : removing rule [ $rule_id ] failed : ",$@) if ( !$rule->del($rule_id) );
			}
			return undef;
		}
	} else {
		warn(__PACKAGE__,"=> autoExclude : the rule [ $rule_id ] is already linked [ $excludeExists ] ... skipping");
		return 1;
	}
	# here we can send email to the excluded user
	return 1 if (!$system->config->needEmailNotification() || !$system->config->getOnExcludeNotify());

	# get email for the given uid
	my $email = $system->getMail($uid);
	warn(__PACKAGE__,"=> autoExclude : unable to retrieve mail for [ $uid ] skipping sending notification !") && return 1 if ( !$email );
	# prepare message
	my $t_msg = $system->getTemplate(name=>"mail_excluded");
	warn(__PACKAGE__,"=> autoExclude : unable to retrieve template [ mail_excluded ] skipping !") && return 1 if ( !$t_msg );
	$t_msg->param(EXCLUDE_DAYS=>$expire_days) if ($expire_days);
	$t_msg->param(FILEX_SYSTEM_EMAIL=>$system->config->getSystemEmail());
	# send message
	$system->sendMail(from=>$system->config->getSystemEmail(),
		to=>$email,
		content=>$t_msg->output(),
		subject=>$system->i18n->localize("mail excluded subject"),
		charset=>"ISO-8859-1");
	return 1;
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
