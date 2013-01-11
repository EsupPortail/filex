package FILEX::Apache::Handler::Admin::Download;
use strict;
use vars qw(@ISA);
use FILEX::Apache::Handler::Admin::base;
@ISA = qw(FILEX::Apache::Handler::Admin::base);

use constant SUB_FILE_INFO => 1;
use constant SUB_USER_INFO => 2;
use constant SUB_PURGE_QUEUE => 3;
use constant SUB_ACTION_FIELD_NAME=>"sa";
use constant FILE_ID_FIELD_NAME=>"id";

use FILEX::DB::Download;
use FILEX::Tools::Utils qw(tsToLocal hrSize toHtml);
use FILEX::Apache::Handler::Admin::Common qw(doFileInfos);

# require at least
sub process {
	my $self = shift;
	my $S = $self->sys();
	my $T = $S->getTemplate(name=>"admin_download");
	my $DB = eval { FILEX::DB::Download->new(); };
	if ($@) {
		$T->param(FILEX_HAS_ERROR=>1);
		$T->param(FILEX_ERROR=>$S->i18n->localizeToHtml("database error %s",$@));
		return $T;
	}
	# if there a sub action
	my $sub_action = $S->apreq->param(SUB_ACTION_FIELD_NAME) || -1;
	SWITCH : {
		if ( $sub_action == SUB_FILE_INFO ) {
			my $file_id = $S->apreq->param(FILE_ID_FIELD_NAME);
			last SWITCH if ( !defined($file_id) );
			my $inT = doFileInfos(system=>$S,file_id=>$file_id,url=>$self->genFileInfoUrl($file_id),
														go_back=>$self->genCurrentUrl(),
			                      mode=>1,sub_action_value=>SUB_FILE_INFO,
			                      sub_action_field_name=>SUB_ACTION_FIELD_NAME,
			                      file_id_field_name=>FILE_ID_FIELD_NAME);
			return ($inT,1);
			last SWITCH;
		}
		if ( $sub_action == SUB_PURGE_QUEUE ) {
			$DB->purgeCurrentDownloads();
			last SWITCH;
		}
	}
	my (@results,@loop);
	$DB->currentDownloads(\@results);
	if ( $#results >= 0 ) {
		my ($hsz,$hunit);
		for (my $i=0; $i<= $#results; $i++) {
			($hsz,$hunit) = hrSize($results[$i]->{'file_size'});
			push(@loop,{
				FILEX_FILE_INFO_URL=>toHtml($self->genFileInfoUrl($results[$i]->{'id'})),
				FILEX_FILE_NAME=>toHtml($results[$i]->{'real_name'}),
				FILEX_OWNER=>$results[$i]->{'owner'},
				FILEX_SIZE=>$hsz." ".$S->i18n->localizeToHtml($hunit),
				FILEX_START=>toHtml(tsToLocal($results[$i]->{'start_date'})),
				FILEX_IP_ADDRESS=>$results[$i]->{'ip_address'}
			});
		}
		$T->param(FILEX_HAS_DOWNLOAD=>1);
		$T->param(FILEX_PURGE_QUEUE_URL=>toHtml($self->genPurgeQueueUrl()));
		$T->param(FILEX_DOWNLOAD_LOOP=>\@loop);
	}
	return $T;
}

sub genFileInfoUrl {
	my $self = shift;
	my $file_id = shift;
	my $sub_action = SUB_ACTION_FIELD_NAME;
	my $file_id_field = FILE_ID_FIELD_NAME;
	my $url = $self->sys->getCurrentUrl();
	$url .= "?".$self->genQueryString(
			$sub_action => SUB_FILE_INFO,
			$file_id_field => $file_id);
	return $url;
}

sub genPurgeQueueUrl {
	my $self = shift;
	my $sub_action = SUB_ACTION_FIELD_NAME;
	my $url = $self->sys->getCurrentUrl();
	$url .= "?".$self->genQueryString($sub_action => SUB_PURGE_QUEUE);
	return $url;
		
}

sub genCurrentUrl {
	my $self = shift;
	my $url = $self->sys->getCurrentUrl();
	$url .= "?".$self->genQueryString();
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
