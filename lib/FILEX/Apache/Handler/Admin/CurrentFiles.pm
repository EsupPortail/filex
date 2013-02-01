package FILEX::Apache::Handler::Admin::CurrentFiles;
use strict;
use vars qw(@ISA);
use FILEX::Apache::Handler::Admin::base;
@ISA = qw(FILEX::Apache::Handler::Admin::base);

use constant SUB_FILE_INFO=>1;
use constant SUB_ACTION_FIELD_NAME=>"sa";
use constant FILE_ID_FIELD_NAME=>"id";

use constant SORT_VALIDATE_FIELD_NAME => "go";
use constant SORT_FIELD_NAME => "sort";
use constant SORT_O_FIELD_NAME => "order";

use constant MAX_NAME_SIZE=>30;

use FILEX::DB::Admin::Search qw(:J_OP :T_OP :S_FI :S_OR);
use FILEX::Tools::Utils qw(tsToLocal hrSize toHtml);
use FILEX::Apache::Handler::Admin::Common qw(doFileInfos);

my @SORT_FIELDS = (S_F_NAME,S_F_OWNER,S_F_SIZE,S_F_UDATE,S_F_EDATE,S_F_COUNT,S_F_ENABLE);
my @SORT_ORDER = (S_O_ASC,S_O_DESC);

sub process {
	my $self = shift;
	my $S = $self->sys();
	my $session = $S->getUser()->getSession();
	my $T = $S->getTemplate(name=>"admin_current_files");
	my ($order_by, $order);
	my $DB = eval { FILEX::DB::Admin::Search->new(); };
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
	}

	my $sort_params;
	if ( defined($S->apreq->param(SORT_VALIDATE_FIELD_NAME)) ) {
		$sort_params = {};
		$sort_params->{sort_value} = $S->apreq->param(SORT_FIELD_NAME); 
		$sort_params->{sort_order} = $S->apreq->param(SORT_O_FIELD_NAME);
		# store to cache
		$session->setParam("sort_params",$sort_params);
	} else {
		# get from cache
		$sort_params = $session->getParam("sort_params");
		if (!$sort_params || ref($sort_params) ne "HASH") {
			$sort_params = {}; 
			$sort_params->{sort_value} = S_F_UDATE;
			$sort_params->{sort_order} = S_O_ASC;
			$session->setParam("sort_params",$sort_params);
		}
	}
	# fill template
	$T->param(FILEX_SORT_FORM_ACTION=>$S->getCurrentUrl());
	$T->param(FILEX_MAIN_ACTION_FIELD_NAME=>$self->getDispatchName());
	$T->param(FILEX_MAIN_ACTION_ID=>$self->getActionId());
	$T->param(FILEX_SORT_VALIDATE_FIELD_NAME=>SORT_VALIDATE_FIELD_NAME);

	# sort field
	$T->param(FILEX_SORT_FIELD_NAME=>SORT_FIELD_NAME);
	$T->param(FILEX_SORT_O_FIELD_NAME=>SORT_O_FIELD_NAME);
	my ($sort_value,$sort_order,@query_opts);
	$sort_value = $sort_params->{sort_value};
	# check for errors
	if ( !grep($sort_value eq $_,@SORT_FIELDS) ) {
		$sort_value = S_F_UDATE;
	} else {
		push(@query_opts,("sort",$sort_value));
	}
	$sort_order = $sort_params->{sort_order};
	# check for errors
	if ( !grep($sort_order eq $_,@SORT_ORDER) ) {
		$sort_order = S_O_ASC;
	} else {
		push(@query_opts,("order",$sort_order));
	}
	makeSortLoop($S,$T,"FILEX_SORT_LOOP",$sort_value);
	makeSortOrderLoop($S,$T,"FILEX_SORT_O_LOOP",$sort_order);

	my @results;
	if ( !$DB->search(fields=>[{field=>"expire_date_now",test=>T_OP_GT,'join'=>J_OP_AND,value=>""}],results=>\@results,@query_opts) ) {
		$T->param(FILEX_HAS_ERROR=>1);
		$T->param(FILEX_ERROR=>$S->i18n->localizeToHtml("database error %s",$DB->getLastErrorString()));
		return $T;
	}
	return $T if ( $#results < 0 );
	$T->param(FILEX_HAS_FILES=>1);
	$T->param(FILEX_FILE_COUNT=>$#results+1);
	my ($hrsize, $hrunit) = hrSize($S->getUsedDiskSpace());
	$T->param(FILEX_USED_DISK_SPACE=>"$hrsize ".$S->i18n->localizeToHtml($hrunit));
	my (@files_loop,$file_owner);
	for ( my $i = 0; $i <= $#results; $i++ ) {
		my $record = {};
		($hrsize,$hrunit) = hrSize($results[$i]->{'file_size'});
		$record->{'FILEX_FILE_INFO_URL'} = toHtml($self->genFileInfoUrl($results[$i]->{'id'}));
		if ( length($results[$i]->{'real_name'}) > 0 ) {
			if ( length($results[$i]->{'real_name'}) > MAX_NAME_SIZE ) {
				$record->{'FILEX_FILE_NAME'} = toHtml( substr($results[$i]->{'real_name'},0,MAX_NAME_SIZE-3)."..." );
			} else {
				$record->{'FILEX_FILE_NAME'} = toHtml($results[$i]->{'real_name'});
			}
		} else {
			$record->{'FILEX_FILE_NAME'} = "???";
		}
		$record->{'FILEX_LONG_FILE_NAME'} = toHtml($results[$i]->{'real_name'});
		$record->{'FILEX_FILE_SIZE'} = "$hrsize ".$S->i18n->localizeToHtml($hrunit);
		$file_owner = $results[$i]->{'owner'};
		# BEGIN - INSA
		#my $student_type = $self->isStudent($file_owner);
		#$file_owner .= " ($student_type)" if defined($student_type);
		# END - INSA
		$record->{'FILEX_FILE_OWNER'} = toHtml($file_owner);
		$record->{'FILEX_ENABLE'} = $S->i18n->localizeToHtml($results[$i]->{'enable'}?"yes":"no");
		$record->{'FILEX_UPLOAD_DATE'} = toHtml(tsToLocal($results[$i]->{'ts_upload_date'}));
		$record->{'FILEX_EXPIRE_DATE'} = toHtml(tsToLocal($results[$i]->{'ts_expire_date'}));
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

sub makeSortLoop {
	my $system = shift;
	my $template = shift;
	my $loop_name = shift;
	my $selected_value = shift;
	my @loop;
	for (my $i=0; $i <= $#SORT_FIELDS; $i++) {
		my $s = { VALUE=>$SORT_FIELDS[$i], TEXT=>$system->i18n->localizeToHtml($SORT_FIELDS[$i]) };
		$s->{'SELECTED'} = 1 if ( defined($selected_value) && ($SORT_FIELDS[$i] eq $selected_value) );
		push(@loop,$s);
	}
	$template->param($loop_name=>\@loop);
}

sub makeSortOrderLoop {
	my $system = shift;
	my $template = shift;
	my $loop_name = shift;
	my $selected_value = shift;
	my @loop;
	for (my $i=0; $i <=$#SORT_ORDER; $i++) {
		my $s = { VALUE=>$SORT_ORDER[$i], TEXT=>$system->i18n->localizeToHtml($SORT_ORDER[$i]) };
		$s->{'SELECTED'} = 1 if ( defined($selected_value) && ($SORT_ORDER[$i] eq $selected_value) );
		push(@loop,$s);
	}
	$template->param($loop_name=>\@loop);
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
