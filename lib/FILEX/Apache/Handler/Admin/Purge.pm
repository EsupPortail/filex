package FILEX::Apache::Handler::Admin::Purge;
use strict;
use vars qw(@ISA);
use FILEX::Apache::Handler::Admin::base;
@ISA = qw(FILEX::Apache::Handler::Admin::base);

use constant SUB_PURGE_ALL => 1;
use constant SUB_ACTION_FIELD_NAME => "sa";

use FILEX::System::Purge;
use FILEX::Tools::Utils qw(tsToLocal hrSize rDns toHtml);

sub process {
	my $self = shift;
	my $S = $self->sys();
	my $T = $S->getTemplate(name=>"admin_purge");
	my $Purge = eval { FILEX::System::Purge->new(); };
	if ($@) {
		$T->param(FILEX_HAS_ERROR=>1);
		$T->param(FILEX_ERROR=>$S->i18n->localizeToHtml("database error %s",$Purge->getLastError()));
		return $T;
	}

	my $sub_action = $S->apreq->param(SUB_ACTION_FIELD_NAME) || -1;
	SWITCH : {
		if ( $sub_action == SUB_PURGE_ALL ) {
			my @errors;
			$self->purgeAll($Purge,\@errors);
			if ( $#errors >= 0 ) {
warn($#errors);
				$T->param(FILEX_HAS_PURGE_ERROR=>1);
				$T->param(FILEX_PURGE_ERROR=>toHtml(join("<br>",@errors)));
			}
			last SWITCH;
		}
	}
	# fill template
	my (@results,@loop,$fsz,$funit);
	splice(@results);
	if ( ! $Purge->getExpiredFiles(\@results) ) {
		$T->param(FILEX_HAS_ERROR=>1);
		$T->param(FILEX_ERROR=>$S->i18n->localizeToHtml("database error %s",$Purge->getLastError()));
	}
	if ($#results >= 0) {
		for (my $i=0; $i <=$#results; $i++) {
			($fsz,$funit) = hrSize($results[$i]->{'file_size'});
			push(@loop, {
					FILEX_FILE_NAME=>toHtml($results[$i]->{'real_name'}),
					FILEX_OWNER=>$results[$i]->{'owner'},
					FILEX_SIZE=>$fsz." ".$S->i18n->localizeToHtml($funit),
					FILEX_UPLOAD_DATE=>toHtml(tsToLocal($results[$i]->{'ts_upload_date'})),
					FILEX_EXPIRE_DATE=>toHtml(tsToLocal($results[$i]->{'ts_expire_date'}))
				}
			);
		}
		$T->param(FILEX_PURGE_ALL_URL=>toHtml($self->genPurgeAllUrl()));
		$T->param(FILEX_HAS_PURGE=>1);
		$T->param(FILEX_PURGE_LOOP=>\@loop);
	}
	return $T;
}

sub purgeAll {
	my $self = shift;
	my $Purge = shift;
	my $errors = shift;
	my $S = $self->sys();
	my @res = ();
	if ( !$Purge->getExpiredFiles(\@res) ) {
		push(@$errors,$S->i18n->localize("database error")." : ".$Purge->getLastError());
		return undef;
	}
	# loop
	my ($upload,$idx);
	foreach $idx (0 .. $#res) {
		$upload = $Purge->purge($res[$idx]->{'id'});
		if ( !$upload ) {
			push(@$errors,$Purge->getLastError());
			next;
		}
		if ( $S->config->needEmailNotification() && $upload->getGetResume() == 1 ) {	
			$self->sendResume($upload,$errors);
		}
	}
	return 1;
}

# 
sub sendResume {
	my $self = shift;
	my $upload = shift;
	my $errors = shift;
	my $S = $self->sys();
	# get mail template
	my $t = $S->getTemplate(name=>"mail_resume");
	push(@$errors,"Unable to load mail_resume template") && return undef if !$t;
	# get owner mail
	my $usr_mail = $S->getMail($upload->getOwner());
	push(@$errors,"Cannot get user mail address for : ".$upload->getOwner()) && return undef if !$usr_mail;
	# fill template
	$t->param(FILEX_SYSTEM_EMAIL=>$S->config->getSystemEmail());
	$t->param(FILEX_FILE_NAME=>$upload->getRealName());
	$t->param(FILEX_FILE_DATE=>tsToLocal($upload->getUploadDate()));
	$t->param(FILEX_FILE_EXPIRE=>tsToLocal($upload->getExpireDate()));
	my ($sz,$su) = hrSize($upload->getFileSize());
	$t->param(FILEX_FILE_SIZE=>"$sz ".$S->i18n->localize($su));
	$t->param(FILEX_DOWNLOAD_COUNT=>$upload->getDownloadCount());
	# loop
	my (@dl,@dl_loop);
	if ( $upload->getDownloads(results=>\@dl) ) {
		for ( my $i=0; $i <= $#dl; $i++ ) {
			push(@dl_loop,
				{ 
					FILEX_DOWNLOAD_ADDRESS=>rDns($dl[$i]->{'ip_address'}) || $dl[$i]->{'ip_address'},
					FILEX_DOWNLOAD_DATE=>tsToLocal($dl[$i]->{'ts_date'}),
				});
		}
	}
	$t->param(FILEX_DOWNLOAD_LOOP=>\@dl_loop) if ($#dl_loop >= 0);
		# send mail
	if ( ! $S->sendMail(
			from=>$S->config->getSystemEmail(),
			to=>$usr_mail,
			encoding=>"ISO-8859-1",
			subject=>$S->i18n->localize("mail subject %s",$upload->getRealName()),
			content=>$t->output()) ) {
		push(@$errors,"Unable to send mail to : $usr_mail");
		return undef;
	}
	return 1;
}

sub genPurgeAllUrl {
	my $self = shift;
	my $sub_action = SUB_ACTION_FIELD_NAME;
	my $url = $self->sys->getCurrentUrl();
	$url .= "?".$self->genQueryString($sub_action => SUB_PURGE_ALL);
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
