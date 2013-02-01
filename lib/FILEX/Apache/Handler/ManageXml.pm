package FILEX::Apache::Handler::ManageXml;
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
use XML::LibXML;
use Encode;

$VERSION = 1.0;

use constant SUB_ACTION_FIELD_NAME=>"sa";
use constant SUB_SORT=>1;
use constant SUB_SORT_BY=>"by";
use constant SUB_SORT_ORDER=>"order";
use constant SUB_FILEINFO=>2;
use constant FILE_ID_FIELD_NAME => "id";
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
	my ($order_by,$order);
	$S = FILEX::System->new(shift);
	# Auth
	my $user = $S->beginSession(no_login=>1);
	# create document
	my $document = createDocument() or die("Unable to create new XML Document !");
	my $root_elem = $document->getDocumentElement();
	# if use is not authenticated 
	if ( !$user ) {
		$root_elem->appendChild(createError("Vous n'avez pas accès à ce service !"));
		display($S,$document);
	}
	# Database
	$DB = eval { FILEX::DB::Manage->new(); };
	if ($@) {
		# do something on error !
		$root_elem->appendChild(createError($@));
		display($S,$document);
	}

	# sub action
	my $sub_action = $S->apreq->param(SUB_ACTION_FIELD_NAME) || -1;
	if ( $sub_action == SUB_SORT ) {
		$order_by = $S->apreq->param(SUB_SORT_BY) || "no sort";
		$order = $S->apreq->param(SUB_SORT_ORDER);
		$order = ( defined($order) ) ? $order : 1;
	} else {
		$order_by = "no sort";
		$order = 1;
	}
	# loop
	my (@results,%cfParams);
	if ( defined($order_by) && grep($order_by eq $_,keys(%ORDER_FIELDS)) ) {
		$cfParams{'orderby'} = $ORDER_FIELDS{$order_by};
		$cfParams{'order'} = $order;
	}
	if ( !$DB->getFiles(owner_uniq_id=>$user->getUniqId(),results=>\@results,%cfParams,active=>1) ) {
		$root_elem->appendChild(createError($DB->getLastErrorString()));
		display($S,$document);
	}
	# get quota for user
	my ($quota_max_file_size,$quota_max_used_space) = $S->getQuota($user);
	#  get current used space for user	
	my $current_used_space = $user->getDiskSpace();
	my ($hrsize,$hrunit);
	# uploads element
	my $uploads_elem = XML::LibXML::Element->new("uploads"); # handle error please !
	$uploads_elem->setAttribute("active_files_count",$#results+1);
	($hrsize,$hrunit) = hrSize($current_used_space);
	$uploads_elem->setAttribute("used_space",$hrsize);
	$uploads_elem->setAttribute("used_space_unit",$S->i18n->localize($hrunit));
	if ( $quota_max_used_space > 0 ) {
		($hrsize,$hrunit) = hrSize($quota_max_used_space);
		$uploads_elem->setAttribute("max_used_space",$hrsize);
		$uploads_elem->setAttribute("max_used_space_unit",$S->i18n->localize($hrunit));
	}
	if ($#results >= 0) {
		# create sort element
		my $sorts_elem = XML::LibXML::Element->new("sorts");
		$sorts_elem->appendChild(createSort("sort_name_asc",genSortUrl($S,"filename",0)));
		$sorts_elem->appendChild(createSort("sort_name_desc",genSortUrl($S,"filename",1)));
		$sorts_elem->appendChild(createSort("sort_size_asc",genSortUrl($S,"filesize",0)));
		$sorts_elem->appendChild(createSort("sort_size_desc",genSortUrl($S,"filesize",1)));
		$sorts_elem->appendChild(createSort("sort_upload_date_asc",genSortUrl($S,"uploaddate",0)));
		$sorts_elem->appendChild(createSort("sort_upload_date_desc",genSortUrl($S,"uploaddate",1)));
		$sorts_elem->appendChild(createSort("sort_expire_date_asc",genSortUrl($S,"expiredate",0)));
		$sorts_elem->appendChild(createSort("sort_expire_date_desc",genSortUrl($S,"expiredate",1)));
		$sorts_elem->appendChild(createSort("sort_download_count_asc",genSortUrl($S,"dlcount",0)));
		$sorts_elem->appendChild(createSort("sort_download_count_desc",genSortUrl($S,"dlcount",1)));
		$uploads_elem->appendChild($sorts_elem);
		# loop on results
		for (my $i=0; $i<=$#results; $i++) {
			($hrsize,$hrunit) = hrSize($results[$i]->{'file_size'});
			my $u_elem = createUpload(
				$results[$i]->{'real_name'},
				tsToLocal($results[$i]->{'ts_upload_date'}),
				tsToLocal($results[$i]->{'ts_expire_date'}),
				sprintf("%s %s",$hrsize,$S->i18n->localize($hrunit)),
				$results[$i]->{'download_count'}||0,
				genFileInfoUrl($S,$results[$i]->{'id'})
			);
			$uploads_elem->appendChild($u_elem);
		}
	}
	$root_elem->appendChild($uploads_elem);
	# exit
	display($S,$document);
	return OK;
}

# display
sub display {
	my $S = shift;
	my $D = shift;
	# base for static include
	$S->sendHeader("Content-Type"=>"text/xml",no_cookie=>1);
	$S->apreq->print($D->toString()) if ( ! $S->apreq->header_only() );
	exit(OK);
}

sub createSort {
	my $name = shift;
	my $url = shift;
	my $element = XML::LibXML::Element->new("sort") or warn(__PACKAGE__,"Unable to create new sort Element") && return undef;
	$element->setAttribute("name",$name);
	$element->setAttribute("url",$url);
	return $element;
}

sub createDocument {
	my $doc = XML::LibXML::Document->new("1.0","utf-8") or warn(__PACKAGE__,"Unable to create new Document") && return undef;
	my $root = XML::LibXML::Element->new("filex") or warn(__PACKAGE__,"Unable to create new root Element") && return undef;
	$doc->setDocumentElement($root);
	return $doc;
}

sub createError {
	my $errorStr = shift;
	my $element = XML::LibXML::Element->new("error") or warn(__PACKAGE__,"Unable to create error Element") && return undef;
	$element->appendText($errorStr);
	return $element;
}
sub createUpload {
	my $name = shift;
	my $upload_date = shift;
	my $expire_date = shift;
	my $size = shift;
	my $download_count = shift;
	my $url = shift;
	# create element
	my $element = XML::LibXML::Element->new("upload") or warn(__PACKAGE__,"Unable to create new upload element") && return undef;
	$element->setAttribute("name",encode("utf-8",$name));
	$element->setAttribute("upload_date",$upload_date);
	$element->setAttribute("expire_date",$expire_date);
	$element->setAttribute("size",$size);
	$element->setAttribute("download_count",$download_count);
	$element->setAttribute("url",$url);	
	return $element;
}

sub genSortUrl {
	my $S = shift;
	my $order_by = shift;
	my $order = shift;
	my $sub_action = SUB_ACTION_FIELD_NAME;
	my $sub_sort_by = SUB_SORT_BY;
	my $sub_sort_order = SUB_SORT_ORDER;
	my $url = $S->getCurrentUrl();
	$url .= "?".$S->genQueryString(
		separator=>"&",
		params=> {
			$sub_action => SUB_SORT,
			$sub_sort_by => $order_by,
			$sub_sort_order => $order
		});
}

sub genFileInfoUrl {
	my $S = shift;
	my $file_id = shift;
	my $sub_action = SUB_ACTION_FIELD_NAME;
	my $file_id_field = FILE_ID_FIELD_NAME;
	my $url = $S->getManageUrl();
	$url .= "?".$S->genQueryString(
		separator=>"&",
		params => {
			$sub_action => SUB_FILEINFO,
			$file_id_field => $file_id
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
