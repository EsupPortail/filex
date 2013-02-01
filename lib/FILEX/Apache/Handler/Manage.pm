package FILEX::Apache::Handler::Manage;
use strict;
use vars qw($VERSION %ORDER_FIELDS);

# Apache Related
use constant MP2 => (exists $ENV{MOD_PERL_API_VERSION} and $ENV{MOD_PERL_API_VERSION} >= 2);

# FILEX
use FILEX::System;
#use FILEX::DB::Manage; # deprecated
use FILEX::DB::Admin::Search qw(:T_OP :J_OP :S_FI :S_OR);
use FILEX::Tools::Utils qw(hrSize tsToLocal toHtml);
use FILEX::Apache::Handler::Admin::Common qw(doFileInfos);

$VERSION = 1.0;

use constant SUB_ACTION_FIELD_NAME=>"sa";
use constant SUB_FILEINFO=>2;
use constant FILE_ID_FIELD_NAME => "id";
use constant MAX_NAME_SIZE => 50;

use constant MANAGE_VALIDATE_FIELD_NAME => "search";
use constant MANAGE_SORT_FIELD_NAME => "sort";
use constant MANAGE_SORT_O_FIELD_NAME => "order";
use constant MANAGE_HIDE_EXPIRED_FIELD_NAME => "hide_exp";

my @SORT_FIELDS = (S_F_NAME,S_F_SIZE,S_F_UDATE,S_F_EDATE,S_F_COUNT);
my @SORT_ORDER = (S_O_ASC,S_O_DESC);

BEGIN {
	if (MP2) {
		require Apache2::Const;
		Apache2::Const->import(-compile=>qw(OK));
	} else {
		require Apache::Constants;
		Apache::Constants->import(qw(OK));
	}
}

# handler between MP1 && MP2 have changed
sub handler_mp1($$) { &run; }
sub handler_mp2 : method { &run; }
*handler = MP2 ? \&handler_mp2 : \&handler_mp1;

sub run {
	my $class = shift;
	my $r = shift;
	my $S = FILEX::System->new($r);
	my $DB; 
	my $T;
	my ($order_by,$order);
	# Auth
	my $user = $S->beginSession();
	# load template
	$T = $S->getTemplate(name=>"manage");
	# Database
	$DB = FILEX::DB::Admin::Search->new();
	$T->param(FILEX_USER_NAME=>toHtml($user->getRealName()));
	$T->param(FILEX_SYSTEM_EMAIL=>$S->config->getSystemEmail());
	$T->param(FILEX_UPLOAD_URL=>toHtml($S->getUploadUrl()));
	# sub action
	my $sub_action = $S->apreq->param(SUB_ACTION_FIELD_NAME) || -1;
	SWITCH : {
		if ( $sub_action == SUB_FILEINFO ) {
			my $file_id = $S->apreq->param(FILE_ID_FIELD_NAME);
			last SWITCH if ( !defined($file_id) );
			my $inT = doFileInfos(system=>$S,
			                      sub_action_field_name=>SUB_ACTION_FIELD_NAME,
			                      sub_action_value=>SUB_FILEINFO,
			                      file_id_field_name=>FILE_ID_FIELD_NAME,
			                      file_id=>$file_id,
			                      url=>$S->getCurrentUrl(),
														go_back=>$S->getCurrentUrl());
			display($S,$inT);
			last SWITCH;
		}
	}

	my $manage_params;
	if ( defined($S->apreq->param(MANAGE_VALIDATE_FIELD_NAME)) ) {
		$manage_params = {};
		$manage_params->{sort_value} = $S->apreq->param(MANAGE_SORT_FIELD_NAME);
		$manage_params->{sort_order} = $S->apreq->param(MANAGE_SORT_O_FIELD_NAME);
		$manage_params->{b_hide_expired} = $S->apreq->param(MANAGE_HIDE_EXPIRED_FIELD_NAME) || 0;
		$user->getSession()->setParam(manage_params=>$manage_params);
	} else {
		# get from cache
		$manage_params = $user->getSession()->getParam("manage_params");
		if ( !defined($manage_params) || ref($manage_params) ne "HASH" ) {
			$manage_params = {};
			$manage_params->{sort_value} = S_F_UDATE;
			$manage_params->{sort_order} = S_O_DESC;
			$manage_params->{b_hide_expired} = 0;
			$user->getSession()->setParam("manage_params",$manage_params);
		}
	}
	# form
	$T->param(FILEX_MANAGE_FORM_ACTION=>$S->getCurrentUrl());
	$T->param(FILEX_MANAGE_VALIDATE_FIELD_NAME=>MANAGE_VALIDATE_FIELD_NAME);
	my (@results,@query_opts,@query);
	push(@query,{field=>"owner_uniq_id",test=>T_OP_EQ,'join'=>J_OP_AND,value=>$user->getUniqId()});
	# hide expired
	$T->param(FILEX_MANAGE_HIDE_EXPIRED_FIELD_NAME=>MANAGE_HIDE_EXPIRED_FIELD_NAME);
	if ( $manage_params->{b_hide_expired} && ($manage_params->{b_hide_expired} == 1) ) {
		$T->param(FILEX_MANAGE_HIDE_EXPIRED_CHECKED=>1);
		push(@query,{field=>"expire_date_now",test=>T_OP_GT,'join'=>J_OP_AND,value=>""});
	}
	# sort on
	$T->param(FILEX_MANAGE_SORT_FIELD_NAME=>MANAGE_SORT_FIELD_NAME);
	$manage_params->{sort_value} = S_F_UDATE if ( !grep($manage_params->{sort_value} eq $_,@SORT_FIELDS) );
	push(@query_opts,("sort",$manage_params->{sort_value}));
	makeSortLoop($S,$T,"FILEX_MANAGE_SORT_LOOP",$manage_params->{sort_value});
  # order
	$T->param(FILEX_MANAGE_SORT_O_FIELD_NAME=>MANAGE_SORT_O_FIELD_NAME);
	$manage_params->{sort_order} = S_O_DESC if ( !grep($manage_params->{sort_order} eq $_,@SORT_ORDER) );
	push(@query_opts,("order",$manage_params->{sort_order}));
	makeSortOrderLoop($S,$T,"FILEX_MANAGE_SORT_O_LOOP",$manage_params->{sort_order});

	if ( !$DB->search(fields=>\@query,results=>\@results,@query_opts) ) {
		$T->param(FILEX_HAS_ERROR=>1);
		$T->param(FILEX_ERROR=>$S->i18n->localizeToHtml("database error %s",$DB->getLastErrorString()));
		display($S,$T);
	}
	if ($#results >= 0) {
		$T->param(FILEX_HAS_FILES=>1);
		$T->param(FILEX_FILE_COUNT=>$#results+1);
		my ($quota_max_file_size,$quota_max_used_space) = $user->getQuota();
		my $current_used_space = $user->getDiskSpace();
		my ($hrsize,$hrunit) = hrSize($current_used_space);
		$T->param(FILEX_USED_SPACE=>"$hrsize ".$S->i18n->localizeToHtml($hrunit));
		if ( $quota_max_used_space > 0 ) {
			$T->param(FILEX_HAVE_QUOTA=>1);
			($hrsize,$hrunit) = hrSize($quota_max_used_space);
			$T->param(FILEX_MAX_USED_SPACE=>"$hrsize ".$S->i18n->localizeToHtml($hrunit));
		}
		my (@files_loop);
		for ( my $i = 0; $i <= $#results; $i++ ) {
			my $record = {};
			my ($hrsize,$hrunit) = hrSize($results[$i]->{'file_size'});
			$record->{'FILEX_FILE_SIZE'} = "$hrsize ".$S->i18n->localizeToHtml($hrunit);
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
			$record->{'FILEX_FILE_INFO_URL'} = toHtml(genFileInfoUrl($S,$results[$i]->{'id'}));
			$record->{'FILEX_UPLOAD_DATE'} = toHtml(tsToLocal($results[$i]->{'ts_upload_date'}));
			$record->{'FILEX_EXPIRE_DATE'} = toHtml(tsToLocal($results[$i]->{'ts_expire_date'}));
			$record->{'FILEX_DOWNLOAD_COUNT'} = $results[$i]->{'download_count'} || 0;
			$record->{'FILEX_HAS_EXPIRED'} = 1 if ($results[$i]->{'expired'} == 1);
			push(@files_loop,$record);
		}
		$T->param(FILEX_FILES_LOOP=>\@files_loop);
	}
	# exit
	display($S,$T);
	return (MP2) ? Apache2::Const::OK : Apache::Constants::OK;
}

# display
sub display {
	my $S = shift;
	my $T = shift;
	# base for static include
	$T->param(FILEX_STATIC_FILE_BASE=>$S->getStaticUrl()) if ( $T->query(name=>'FILEX_STATIC_FILE_BASE') );
	$S->sendHeader("Content-Type"=>"text/html");
	$S->apreq->print($T->output()) if ( ! $S->apreq->header_only() );
	exit( (MP2) ? Apache2::Const::OK : Apache::Constants::OK);
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

sub genFileInfoUrl {
	my $S = shift;
	my $file_id = shift;
	my $sub_action = SUB_ACTION_FIELD_NAME;
	my $url = $S->getCurrentUrl();
	$url .= "?".$S->genQueryString(
		params=>{
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
