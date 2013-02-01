package FILEX::Apache::Handler::Admin::CurrentFiles;
use strict;
use vars qw(@ISA %ORDER_FIELDS);
use FILEX::Apache::Handler::Admin::base;
@ISA = qw(FILEX::Apache::Handler::Admin::base);

use constant SUB_FILE_INFO=>1;
use constant SUB_SORT=>2;
use constant SUB_SORT_BY=>"by";
use constant SUB_SORT_ORDER=>"order";
use constant SUB_ACTION_FIELD_NAME=>"sa";
use constant FILE_ID_FIELD_NAME=>"id";

use constant MAX_NAME_SIZE=>30;

use FILEX::DB::Download;
use FILEX::Tools::Utils qw(tsToLocal hrSize);
use FILEX::Apache::Handler::Admin::Common qw(doFileInfos);

%ORDER_FIELDS = (
	fileowner => "owner",
	filename => "real_name",
	filesize => "file_size",
	uploaddate => "upload_date",
	expiredate => "expire_date",
	diskname => "file_name",
	dlcount => "download_count"
);

sub process {
	my $self = shift;
	my $S = $self->sys();
	my $T = $S->getTemplate(name=>"admin_current_files");
	my ($order_by, $order);
	my $DB = eval { FILEX::DB::Download->new(); };
	if ($@) {
		$T->param(FILEX_HAS_ERROR=>1);
		$T->param(FILEX_ERROR=>$S->i18n->localizeToHtml("database error %s",$DB->getLastErrorString()));
		return $T;
	}
	# sub action
	my $sub_action = $S->apreq->param(SUB_ACTION_FIELD_NAME) || -1;
	SWITCH : {
		if ( $sub_action == SUB_FILE_INFO ) {
			my $file_id = $S->apreq->param(FILE_ID_FIELD_NAME);
			last SWITCH if ( !defined($file_id) );
			my $inT = doFileInfos(system=>$S, file_id=>$file_id,url=>$self->genFileInfoUrl($file_id),
														go_back=>$self->genCurrentUrl(),
			                      mode=>1,sub_action_value=>SUB_FILE_INFO,
			                      sub_action_field_name=>SUB_ACTION_FIELD_NAME,
			                      file_id_field_name=>FILE_ID_FIELD_NAME);
			return ($inT,1);
			last SWITCH;
		}
		if ( $sub_action == SUB_SORT ) {
			$order_by = $S->apreq->param(SUB_SORT_BY) || "no sort";
			$order = $S->apreq->param(SUB_SORT_ORDER);
			$order = ( defined($order) ) ? $order : 0;
			last SWITCH;
		}
		$order_by = "no sort";
		$order = 0;
	}

	my (@results,%cfParams);
	if ( defined($order_by) && grep($order_by eq $_,keys(%ORDER_FIELDS)) ) {
		$cfParams{'orderby'} = $ORDER_FIELDS{$order_by};
		$cfParams{'order'} = $order;
	}
	if ( !$DB->currentFiles(results=>\@results,%cfParams) ) {
		$T->param(FILEX_HAS_ERROR=>1);
		$T->param(FILEX_ERROR=>$S->i18n->localizeToHtml("database error %s",$DB->getLastErrorString()));
		return $T;
	}
	return $T if ( $#results < 0 );
	$T->param(FILEX_HAS_FILES=>1);
	$T->param(FILEX_FILE_COUNT=>$#results+1);
	my ($hrsize, $hrunit) = hrSize($S->getUsedDiskSpace());
	$T->param(FILEX_USED_DISK_SPACE=>"$hrsize ".$S->i18n->localizeToHtml($hrunit));
	$T->param(FILEX_SORT_NAME_ASC_URL=>$S->toHtml($self->genSortUrl("filename",0)));
	$T->param(FILEX_SORT_NAME_DESC_URL=>$S->toHtml($self->genSortUrl("filename",1)));
	$T->param(FILEX_SORT_OWNER_ASC_URL=>$S->toHtml($self->genSortUrl("fileowner",0)));
	$T->param(FILEX_SORT_OWNER_DESC_URL=>$S->toHtml($self->genSortUrl("fileowner",1)));
	$T->param(FILEX_SORT_SIZE_ASC_URL=>$S->toHtml($self->genSortUrl("filesize",0)));
	$T->param(FILEX_SORT_SIZE_DESC_URL=>$S->toHtml($self->genSortUrl("filesize",1)));
	$T->param(FILEX_SORT_UPLOAD_ASC_URL=>$S->toHtml($self->genSortUrl("uploaddate",0)));
	$T->param(FILEX_SORT_UPLOAD_DESC_URL=>$S->toHtml($self->genSortUrl("uploaddate",1)));
	$T->param(FILEX_SORT_EXPIRE_ASC_URL=>$S->toHtml($self->genSortUrl("expiredate",0)));
	$T->param(FILEX_SORT_EXPIRE_DESC_URL=>$S->toHtml($self->genSortUrl("expiredate",1)));
	$T->param(FILEX_SORT_DISK_ASC_URL=>$S->toHtml($self->genSortUrl("diskname",0)));
	$T->param(FILEX_SORT_DISK_DESC_URL=>$S->toHtml($self->genSortUrl("diskname",1)));
	$T->param(FILEX_SORT_DOWNLOAD_COUNT_ASC_URL=>$S->toHtml($self->genSortUrl("dlcount",0)));
	$T->param(FILEX_SORT_DOWNLOAD_COUNT_DESC_URL=>$S->toHtml($self->genSortUrl("dlcount",1)));
	my (@files_loop,$file_owner);
	for ( my $i = 0; $i <= $#results; $i++ ) {
		my $record = {};
		($hrsize,$hrunit) = hrSize($results[$i]->{'file_size'});
		$record->{'FILEX_FILE_INFO_URL'} = $S->toHtml($self->genFileInfoUrl($results[$i]->{'id'}));
		if ( length($results[$i]->{'real_name'}) > 0 ) {
			if ( length($results[$i]->{'real_name'}) > MAX_NAME_SIZE ) {
				$record->{'FILEX_FILE_NAME'} = $S->toHtml( substr($results[$i]->{'real_name'},0,MAX_NAME_SIZE-3)."..." );
			} else {
				$record->{'FILEX_FILE_NAME'} = $S->toHtml($results[$i]->{'real_name'});
			}
		} else {
			$record->{'FILEX_FILE_NAME'} = "???";
		}
		$record->{'FILEX_LONG_FILE_NAME'} = $S->toHtml($results[$i]->{'real_name'});
		$record->{'FILEX_FILE_SIZE'} = "$hrsize ".$S->i18n->localizeToHtml($hrunit);
		$file_owner = $results[$i]->{'owner'};
		# BEGIN - INSA
		#my $student_type = $self->isStudent($file_owner);
		#$file_owner .= " ($student_type)" if defined($student_type);
		# END - INSA
		$record->{'FILEX_FILE_OWNER'} = $S->toHtml($file_owner);
		$record->{'FILEX_UPLOAD_DATE'} = $S->toHtml(tsToLocal($results[$i]->{'ts_upload_date'}));
		$record->{'FILEX_EXPIRE_DATE'} = $S->toHtml(tsToLocal($results[$i]->{'ts_expire_date'}));
		$record->{'FILEX_DOWNLOAD_COUNT'} = $results[$i]->{'download_count'} || 0;
		$record->{'FILEX_DISK_NAME'} = $results[$i]->{'file_name'};
		push(@files_loop,$record);
	}
	$T->param(FILEX_FILES_LOOP=>\@files_loop);
	return $T;
}

# is given user's a student ?
# INSA SPECIAL
sub isStudent {
	my $self = shift;
	my $uname = shift;
	my $S = $self->sys();
	my $dn = $S->ldap->getUserDn($uname);
  $dn =~ s/\s//g;
  my $student_type = undef;
  if ( $dn =~ /ou=ETUDIANT-(.+),.*,.*/i ) {
  	$student_type = $1;
  }
  return $student_type;
}

sub genFileInfoUrl {
	my $self = shift;
	my $file_id = shift;
	my $sub_action = SUB_ACTION_FIELD_NAME;
	my $url = $self->sys->getCurrentUrl();
	$url .= "?".$self->genQueryString($sub_action => SUB_FILE_INFO,id => $file_id);
	return $url;
}

sub genCurrentUrl {
	my $self = shift;
	my $url = $self->sys->getCurrentUrl();
	$url .= "?".$self->genQueryString();
	return $url;
}

sub genSortUrl {
	my $self = shift;
	my $order_by = shift;
	my $order = shift;
	my $sub_action = SUB_ACTION_FIELD_NAME;
	my $sub_sort_by = SUB_SORT_BY;
	my $sub_sort_order = SUB_SORT_ORDER;
	my $url = $self->sys->getCurrentUrl();
	$url .= "?".$self->genQueryString(
			$sub_action => SUB_SORT,
			$sub_sort_by => $order_by,
			$sub_sort_order => $order
	);
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
