package FILEX::Apache::Handler::Manage;
use strict;
use vars qw($VERSION %ORDER_FIELDS);

# Apache
use Apache::Constants qw(:common);
use Apache::Request;

# FILEX
use FILEX::System;
use FILEX::DB::Manage;
use FILEX::Tools::Utils qw(hrSize tsToLocal);
use FILEX::Apache::Handler::Admin::Common qw(doFileInfos);

$VERSION = 1.0;

use constant SUBACTION=>"sa";
use constant SUB_SORT=>1;
use constant SUB_SORT_BY=>"by";
use constant SUB_SORT_ORDER=>"order";
use constant SUB_FILEINFO=>2;

use constant MAX_NAME_SIZE => 50;

%ORDER_FIELDS = (
	filename => "real_name",
	filesize => "file_size",
	uploaddate => "upload_date",
	expiredate => "expire_date",
	dlcount => "download_count"
);

sub handler {
	my $S; # FILEX::System
	my $DB; # FILEX::DB::Manage
	my $T;
	my ($order_by,$order);
	$S = FILEX::System->new(shift);
	# Auth
	$S->beginSession();
	# load template
	$T = $S->getTemplate(name=>"manage");
	# Database
	$DB = FILEX::DB::Manage->new(
		name=>$S->config->getDBName(),
		user=>$S->config->getDBUsername(),
		password=>$S->config->getDBPassword(),
		host=>$S->config->getDBHost(),
		port=>$S->config->getDBPort()
	);
	my $username = $S->getAuthUser();
	$T->param(USERNAME=>$S->toHtml($S->getUserRealName($username)));
	$T->param(SYSTEMEMAIL=>$S->config->getSystemEmail());
	$T->param(UPLOADURL=>$S->getUploadUrl());

	# sub action
	my $sub_action = $S->apreq->param(SUBACTION) || -1;
	SWITCH : {
		if ( $sub_action == SUB_FILEINFO ) {
			my $file_id = $S->apreq->param('id');
			last SWITCH if ( !defined($file_id) );
			my $inT = doFileInfos(system=>$S,id=>$file_id,url=>genFileInfoUrl($S,$file_id));
			display($S,$inT);
			last SWITCH;
		}
		if ( $sub_action == SUB_SORT ) {
			$order_by = $S->apreq->param(SUB_SORT_BY) || "no sort";
			$order = $S->apreq->param(SUB_SORT_ORDER);
			$order = ( defined($order) ) ? $order : 1;
			last SWITCH;
		}
		$order_by = "no sort";
		$order = 1;
	}
	# loop
	my (@results,%cfParams);
	if ( defined($order_by) && grep($order_by eq $_,keys(%ORDER_FIELDS)) ) {
		$cfParams{'orderby'} = $ORDER_FIELDS{$order_by};
		$cfParams{'order'} = $order;
	}
	if ( !$DB->getFiles(owner=>$username,results=>\@results,%cfParams) ) {
		$T->param(HAS_ERROR=>1);
		$T->param(ERROR=>$S->i18n->localizeToHtml("database error %s",$DB->getLastErrorString()));
		display($S,$T);
	}
	if ($#results >= 0) {
		$T->param(HAS_FILES=>1);
		$T->param(FILECOUNT=>$#results+1);
		my ($quota_max_file_size,$quota_max_used_space) = $S->getQuota($username);
		my $current_used_space = $S->getUserDiskSpace($username);
		my ($hrsize,$hrunit) = hrSize($current_used_space);
		$T->param(USED_SPACE=>"$hrsize ".$S->i18n->localizeToHtml($hrunit));
		if ( $quota_max_used_space > 0 ) {
			$T->param(HAVE_QUOTA=>1);
			($hrsize,$hrunit) = hrSize($quota_max_used_space);
			$T->param(MAX_USED_SPACE=>"$hrsize ".$S->i18n->localizeToHtml($hrunit));
		}
		$T->param(SORTNAMEURL=>genSortUrl($S,"filename",($order_by eq "filename" && $order == 0 ) ? 1 : 0));
		$T->param(SORTSIZEURL=>genSortUrl($S,"filesize",($order_by eq "filesize" && $order == 0 ) ? 1 : 0));
		$T->param(SORTUPDURL=>genSortUrl($S,"uploaddate",($order_by eq "uploaddate" && $order == 0 ) ? 1 : 0));
		$T->param(SORTEXDURL=>genSortUrl($S,"expiredate",($order_by eq "expiredate" && $order == 0 ) ? 1 : 0));
		$T->param(SORTDLCURL=>genSortUrl($S,"dlcount",($order_by eq "dlcount" && $order == 0 ) ? 1 : 0));
		my (@files_loop);
		for ( my $i = 0; $i <= $#results; $i++ ) {
			my $record = {};
			my ($hrsize,$hrunit) = hrSize($results[$i]->{'file_size'});
			$record->{'FILESIZE'} = "$hrsize ".$S->i18n->localizeToHtml($hrunit);
			if ( length($results[$i]->{'real_name'}) > 0 ) {
				if ( length($results[$i]->{'real_name'}) > MAX_NAME_SIZE ) {
					$record->{'FILENAME'} = $S->toHtml( substr($results[$i]->{'real_name'},0,MAX_NAME_SIZE-3)."..." );
				} else {
					$record->{'FILENAME'} = $S->toHtml($results[$i]->{'real_name'});
				}
			} else {
				$record->{'FILENAME'} = "???";
			}
			$record->{'FILEINFOURL'} = genFileInfoUrl($S,$results[$i]->{'id'});
			$record->{'UPLOADDATE'} = $S->toHtml(tsToLocal($results[$i]->{'ts_upload_date'}));
			$record->{'EXPIREDATE'} = $S->toHtml(tsToLocal($results[$i]->{'ts_expire_date'}));
			$record->{'DOWNLOADCOUNT'} = $results[$i]->{'download_count'};
			push(@files_loop,$record);
		}
		$T->param(FILES_LOOP=>\@files_loop);
	}
	# exit
	display($S,$T);
	return OK;
}

# display
sub display {
	my $S = shift;
	my $T = shift;
	# base for static include
	$T->param(STATIC_FILE_BASE=>$S->getStaticUrl()) if ( $T->query(name=>'STATIC_FILE_BASE') );
	$S->sendHeader("Content-Type"=>"text/html");
	$S->apreq->print($T->output()) if ( ! $S->apreq->header_only() );
	exit(OK);
}

sub genSortUrl {
	my $S = shift;
	my $order_by = shift;
	my $order = shift;
	my $sub_action = SUBACTION;
	my $sub_sort_by = SUB_SORT_BY;
	my $sub_sort_order = SUB_SORT_ORDER;
	my $url = $S->getCurrentUrl();
	$url .= "?".$S->genQueryString(
		{
			$sub_action => SUB_SORT,
			$sub_sort_by => $order_by,
			$sub_sort_order => $order
		});
}

sub genFileInfoUrl {
	my $S = shift;
	my $file_id = shift;
	my $sub_action = SUBACTION;
	my $url = $S->getCurrentUrl();
	$url .= "?".$S->genQueryString(
		{
			$sub_action => SUB_FILEINFO,
			id => $file_id
		}
	);
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
