package FILEX::Apache::Handler::Admin::Download;
use strict;
use vars qw(@ISA);
use FILEX::Apache::Handler::Admin::base;
@ISA = qw(FILEX::Apache::Handler::Admin::base);

use constant SUB_FILEINFO => 1;
use constant SUB_USERINFO => 2;
use constant SUBACTION => "sa";

use FILEX::DB::Admin::Download;
use FILEX::Tools::Utils qw(tsToLocal hrSize);
use FILEX::Apache::Handler::Admin::Common qw(doFileInfos);

# require at least
sub process {
	my $self = shift;
	my $S = $self->sys();
	my $T = $S->getTemplate(name=>"admin_download");
	my $DB = FILEX::DB::Admin::Download->new(
		name=>$S->config->getDBName(),
		user=>$S->config->getDBUsername(),
		password=>$S->config->getDBPassword(),
		host=>$S->config->getDBHost(),
		port=>$S->config->getDBPort()
	);
	# if there a sub action
	my $sub_action = $S->apreq->param(SUBACTION) || -1;
	SWITCH : {
		if ( $sub_action == SUB_FILEINFO ) {
			my $file_id = $S->apreq->param('id');
			last SWITCH if ( !defined($file_id) );
			my $inT = doFileInfos(system=>$S,id=>$file_id,url=>$self->genFileInfoUrl($file_id),mode=>1);
			return ($inT,1);
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
				URLFILEINFO=>$self->genFileInfoUrl($results[$i]->{'id'}),
				FILENAME=>$S->toHtml($results[$i]->{'real_name'}),
				OWNER=>$results[$i]->{'owner'},
				SIZE=>$hsz." ".$S->i18n->localizeToHtml($hunit),
				START=>$S->toHtml(tsToLocal($results[$i]->{'start_date'})),
				IPADDRESS=>$results[$i]->{'ip_address'}
			});
		}
		$T->param(HAS_DOWNLOAD=>1);
		$T->param(DOWNLOAD_LOOP=>\@loop);
	}
	return $T;
}

sub genFileInfoUrl {
	my $self = shift;
	my $file_id = shift;
	my $sub_action = SUBACTION;
	my $url = $self->sys->getCurrentUrl();
	$url .= "?".$self->genQueryString(
			$sub_action => SUB_FILEINFO,
			id => $file_id);
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
