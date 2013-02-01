package FILEX::Apache::Handler::Admin::CurrentFiles;
use strict;
use vars qw(@ISA %ORDER_FIELDS);
use FILEX::Apache::Handler::Admin::base;
@ISA = qw(FILEX::Apache::Handler::Admin::base);

use constant SUB_FILEINFO=>1;
use constant SUB_SORT=>2;
use constant SUB_SORT_BY=>"by";
use constant SUB_SORT_ORDER=>"order";
use constant SUBACTION=>"sa";

use constant MAX_NAME_SIZE=>30;

use FILEX::DB::Admin::Stats;
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
	my $DB = FILEX::DB::Admin::Stats->new(
		name=>$S->config->getDBName(),
		user=>$S->config->getDBUsername(),
		password=>$S->config->getDBPassword(),
		host=>$S->config->getDBHost(),
		port=>$S->config->getDBPort()
	);
	# sub action
	my $sub_action = $S->apreq->param(SUBACTION) || -1;
	SWITCH : {
		if ( $sub_action == SUB_FILEINFO ) {
			my $file_id = $S->apreq->param('id');
			last SWITCH if ( !defined($file_id) );
			my $inT = doFileInfos(system=>$S, id=>$file_id,url=>$self->genFileInfoUrl($file_id),mode=>1);
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
		$T->param(HAS_ERROR=>1);
		$T->param(ERROR=>$S->i18n->localizeToHtml("database error %s",$DB->getLastErrorString()));
		return $T;
	}
	return $T if ( $#results < 0 );
	$T->param(HAS_FILES=>1);
	$T->param(FILECOUNT=>$#results+1);
	my ($hrsize, $hrunit) = hrSize($S->getUsedDiskSpace());
	$T->param(USED_DISK_SPACE=>"$hrsize ".$S->i18n->localizeToHtml($hrunit));
	$T->param(SORTNAMEURL=>$self->genSortUrl("filename",($order_by eq "filename" && $order == 0 ) ? 1 : 0));
	$T->param(SORTOWNERURL=>$self->genSortUrl("fileowner",($order_by eq "fileowner" && $order == 0 ) ? 1 : 0));
	$T->param(SORTSIZEURL=>$self->genSortUrl("filesize",($order_by eq "filesize" && $order == 0 ) ? 1 : 0));
	$T->param(SORTUPDURL=>$self->genSortUrl("uploaddate",($order_by eq "uploaddate" && $order == 0 ) ? 1 : 0));
	$T->param(SORTEXDURL=>$self->genSortUrl("expiredate",($order_by eq "expiredate" && $order == 0 ) ? 1 : 0));
	$T->param(SORTDISKURL=>$self->genSortUrl("diskname",($order_by eq "diskname" && $order == 0 ) ? 1 : 0));
	$T->param(SORTDLCURL=>$self->genSortUrl("dlcount",($order_by eq "dlcount" && $order == 0 ) ? 1 : 0));
	my (@files_loop,$file_owner);
	for ( my $i = 0; $i <= $#results; $i++ ) {
		my $record = {};
		($hrsize,$hrunit) = hrSize($results[$i]->{'file_size'});
		$record->{'FILEINFOURL'} = $self->genFileInfoUrl($results[$i]->{'id'});
		if ( length($results[$i]->{'real_name'}) > 0 ) {
			if ( length($results[$i]->{'real_name'}) > MAX_NAME_SIZE ) {
				$record->{'FILENAME'} = $S->toHtml( substr($results[$i]->{'real_name'},0,MAX_NAME_SIZE-3)."..." );
			} else {
				$record->{'FILENAME'} = $S->toHtml($results[$i]->{'real_name'});
			}
		} else {
			$record->{'FILENAME'} = "???";
		}
		$record->{'FILESIZE'} = "$hrsize ".$S->i18n->localizeToHtml($hrunit);
		$file_owner = $results[$i]->{'owner'};
		# BEGIN - INSA
		$file_owner .= " *" if $self->isStudent($file_owner);
		# END - INSA
		$record->{'FILEOWNER'} = $S->toHtml($file_owner);
		$record->{'UPLOADDATE'} = $S->toHtml(tsToLocal($results[$i]->{'ts_upload_date'}));
		$record->{'EXPIREDATE'} = $S->toHtml(tsToLocal($results[$i]->{'ts_expire_date'}));
		$record->{'DOWNLOADCOUNT'} = $results[$i]->{'download_count'};
		$record->{'DISKNAME'} = $results[$i]->{'file_name'};
		push(@files_loop,$record);
	}
	$T->param(FILES_LOOP=>\@files_loop);
	return $T;
}

# is given user's a student ?
# INSA SPECIAL
sub isStudent {
	my $self = shift;
	my $uname = shift;
	my $S = $self->sys();
	my $dn = $S->ldap->getUserDn($uname);
	return ( $dn =~ /ou=ETUDIANT-.*/i ) ? 1 : 0;
	#my $mesg = $S->ldap->getUserAttrs(uid=>$uname,attrs=>['employeeType']);
	# warning : the hash values are lowercase
	#my $etype =  ( $mesg && (ref($mesg) eq "HASH") && exists($mesg->{'employeetype'}) ) ? $mesg->{'employeetype'} : undef;
	#if ( $etype ) {
	#	return 1 if grep($_ =~ /student/i,@$etype);
	#}
	#return 0;
}

sub genFileInfoUrl {
	my $self = shift;
	my $file_id = shift;
	my $sub_action = SUBACTION;
	my $url = $self->sys->getCurrentUrl();
	$url .= "?".$self->genQueryString($sub_action => SUB_FILEINFO,id => $file_id);
	return $url;
}

sub genSortUrl {
	my $self = shift;
	my $order_by = shift;
	my $order = shift;
	my $sub_action = SUBACTION;
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
