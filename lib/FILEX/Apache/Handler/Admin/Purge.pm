package FILEX::Apache::Handler::Admin::Purge;
use strict;
use vars qw(@ISA);
use FILEX::Apache::Handler::Admin::base;
@ISA = qw(FILEX::Apache::Handler::Admin::base);

use constant SUB_PURGEALL => 1;
use constant SUBACTION => "sa";

use FILEX::DB::Sys;
use FILEX::DB::Admin::Stats;
use FILEX::Tools::Utils qw(tsToLocal hrSize rDns);

sub process {
	my $self = shift;
	my $S = $self->sys();
	my $T = $S->getTemplate(name=>"admin_purge");
	my $DB = FILEX::DB::Sys->new(
		name=>$S->config->getDBName(),
		user=>$S->config->getDBUsername(),
		password=>$S->config->getDBPassword(),
		host=>$S->config->getDBHost(),
		port=>$S->config->getDBPort()
	);

	my $sub_action = $S->apreq->param(SUBACTION) || -1;
	SWITCH : {
		if ( $sub_action == SUB_PURGEALL ) {
			my @errors;
			$self->purgeAll($DB,\@errors);
			if ( $#errors >= 0 ) {
				$T->param(HAS_PURGE_ERROR=>1);
				$T->param(PURGE_ERROR=>$S->toHtml(join("<br>",@errors)));
			}
			last SWITCH;
		}
	}
	# fill template
	my (@results,@loop,$fsz,$funit);
	if ( ! $DB->getExpiredFiles(\@results) ) {
		$T->param(HAS_ERROR=>1);
		$T->param(ERROR=>$S->i18n->localizeToHtml("database error %s",$DB->getLastErrorString()));
	}
	if ($#results >= 0) {
		for (my $i=0; $i <=$#results; $i++) {
			($fsz,$funit) = hrSize($results[$i]->{'file_size'});
			push(@loop, {
					FILENAME=>$S->toHtml($results[$i]->{'real_name'}),
					OWNER=>$results[$i]->{'owner'},
					SIZE=>$fsz." ".$S->i18n->localizeToHtml($funit),
					UPLOADDATE=>$S->toHtml(tsToLocal($results[$i]->{'ts_upload_date'})),
					EXPIREDATE=>$S->toHtml(tsToLocal($results[$i]->{'ts_expire_date'}))
				}
			);
		}
		$T->param(PURGEALLURL=>$self->genPurgeAllUrl());
		$T->param(HAS_PURGE=>1);
		$T->param(PURGE_LOOP=>\@loop);
	}
	return $T;
}

sub purgeAll {
	my $self = shift;
	my $DB = shift;
	my $errors = shift;
	my $S = $self->sys();
	my @results;
	if ( !$DB->getExpiredFiles(\@results) ) {
		push(@$errors,$S->i18n->localize("database error")." : ".$DB->getLastErrorString());
		return undef;
	}
	# loop
	my ($idx,$filerepbase,$bnotfound,$filename,$id,$is_downloaded,$path,$usr_mail);
	$filerepbase = $S->config->getFileRepository();
	foreach $idx (0 .. $#results) {
		$bnotfound = undef;
		$filename = $results[$idx]->{'file_name'};
		$id = $results[$idx]->{'id'};
		$is_downloaded = $results[$idx]->{'is_downloaded'};
		$path = File::Spec->catfile($filerepbase,$filename);
		# is downloaded
		if ( $is_downloaded ) {
			push(@$errors,"file is currently downloaded [name=>$filename,id=>$id,path=>$path]");
			next;
		}
		# is file
		if ( ! -f $path ) {
			$bnotfound = 1;
			push(@$errors,"File not found [name=>$filename,id=>$id,path=>$path] marking as deleted");
		}
		# mark deleted
		push(@$errors,"Cannot mark file as deleted [name=>$filename,id=>$id,path=>$path]") if !$DB->markDeleted($id);
		# if file not found then next
		next if $bnotfound;
		unlink($path) or push(@$errors,"Cannot delete file [name=>$filename,id=>$id,path=>$path]");
		# now notify the user
		$self->sendResume($results[$idx],$errors) if ( $results[$idx]->{'get_resume'} == 1 );
	}
	return 1;
}

# 
sub sendResume {
	my $self = shift;
	my $file_infos = shift;
	my $errors = shift;
	my $S = $self->sys();
	my $DB = eval { FILEX::DB::Admin::Stats->new(
		name=>$S->config->getDBName(),
		user=>$S->config->getDBUsername(),
		password=>$S->config->getDBPassword(),
		host=>$S->config->getDBHost(),
		port=>$S->config->getDBPort()
	); };
	if ($@) {
		push(@$errors,"Unable to connect to the database : $@");
		return undef;
	}
	# get downloads stats
	my (@file_downloads,$usr_mail,@dl_loop);
	if ( ! $DB->listDownload(id=>$file_infos->{'id'},results=>\@file_downloads) ) {
		push(@$errors,"Unable to get download list for file : ".$file_infos->{'id'}." : ".$DB->getLastErrorString());
		return undef;
	}
	# get owner mail
	$usr_mail = $S->getMail($file_infos->{'owner'});
	push(@$errors,"Cannot get user mail address for : ".$file_infos->{'owner'}) && return undef if !$usr_mail;
	# get mail template
	my $t = $S->getTemplate(name=>"mail_resume");
	push(@$errors,"Unable to load mail_resume template") && return undef if !$t;
	# fill template
	$t->param(SYSTEMEMAIL=>$S->config->getSystemEmail());
	$t->param(FILENAME=>$file_infos->{'real_name'});
	$t->param(FILEDATE=>tsToLocal($file_infos->{'ts_upload_date'}));
	$t->param(FILEEXPIRE=>tsToLocal($file_infos->{'ts_expire_date'}));
	my ($sz,$su) = hrSize($file_infos->{'file_size'});
	$t->param(FILESIZE=>"$sz ".$S->i18n->localize($su));
	$t->param(DOWNLOADCOUNT=>($#file_downloads+1));
	for ( my $i=0; $i <= $#file_downloads; $i++ ) {
		push(@dl_loop,
			{ 
				DLADDRESS=>rDns($file_downloads[$i]->{'ip_address'}) || $file_downloads[$i]->{'ip_address'},
				DLDATE=>tsToLocal($file_downloads[$i]->{'ts_date'}),
			});
	}
	$t->param(DL_LOOP=>\@dl_loop) if ($#dl_loop >= 0);
	# send mail
	if ( ! $S->sendMail(
			from=>$S->config->getSystemEmail(),
			to=>$usr_mail,
			encoding=>"ISO-8859-1",
			subject=>$S->i18n->localize("mail subject %s",$file_infos->{'real_name'}),
			content=>$t->output()) ) {
		push(@$errors,"Unable to send mail to : $usr_mail");
		return undef;
	}
	return 1;
}

sub genPurgeAllUrl {
	my $self = shift;
	my $sub_action = SUBACTION;
	my $url = $self->sys->getCurrentUrl();
	$url .= "?".$self->genQueryString($sub_action => SUB_PURGEALL);
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
