package FILEX::Apache::Handler::Admin::Search;
use strict;
use vars qw(@ISA);
use FILEX::Apache::Handler::Admin::base;
use POSIX;
@ISA = qw(FILEX::Apache::Handler::Admin::base);

use constant SUB_FILE_INFO=>1;
use constant SUB_ACTION_FIELD_NAME=>"sa";
use constant FILE_ID_FIELD_NAME=>"id";

use constant SEARCH_NAME_FIELD_NAME=>"name";
use constant SEARCH_OWNER_FIELD_NAME=>"owner";
use constant SEARCH_UDATE_FIELD_NAME=>"udate";
use constant SEARCH_UDATE2_FIELD_NAME=>"udate2";
use constant SEARCH_EDATE_FIELD_NAME=>"edate";
use constant SEARCH_EDATE2_FIELD_NAME=>"edate2";
use constant SEARCH_SORT_FIELD_NAME=>"sort";
use constant SEARCH_ENABLE_FIELD_NAME=>"enable";

use constant SEARCH_NAME_E_FIELD_NAME=>"enable_name";
use constant SEARCH_OWNER_E_FIELD_NAME=>"enable_owner";
use constant SEARCH_UDATE_E_FIELD_NAME=>"enable_udate";
use constant SEARCH_UDATE2_E_FIELD_NAME=>"enable_udate2";
use constant SEARCH_EDATE_E_FIELD_NAME=>"enable_edate";
use constant SEARCH_EDATE2_E_FIELD_NAME=>"enable_edate2";
use constant SEARCH_SORT_E_FIELD_NAME=>"enable_sort";
use constant SEARCH_ENABLE_E_FIELD_NAME=>"enable_enable";

use constant SEARCH_NAME_J_FIELD_NAME=>"join_name";
use constant SEARCH_OWNER_J_FIELD_NAME=>"join_owner";
use constant SEARCH_UDATE_J_FIELD_NAME=>"join_udate";
use constant SEARCH_UDATE2_J_FIELD_NAME=>"join_udate2";
use constant SEARCH_EDATE_J_FIELD_NAME=>"join_edate";
use constant SEARCH_EDATE2_J_FIELD_NAME=>"join_edate2";
use constant SEARCH_ENABLE_J_FIELD_NAME=>"join_enable";

use constant SEARCH_NAME_T_FIELD_NAME=>"test_name";
use constant SEARCH_OWNER_T_FIELD_NAME=>"test_owner";
use constant SEARCH_UDATE_T_FIELD_NAME=>"test_udate";
use constant SEARCH_UDATE2_T_FIELD_NAME=>"test_udate2";
use constant SEARCH_EDATE_T_FIELD_NAME=>"test_edate";
use constant SEARCH_EDATE2_T_FIELD_NAME=>"test_edate2";

use constant SEARCH_SORT_O_FIELD_NAME=>"order";

use constant MAX_NAME_SIZE=>30;

use FILEX::DB::Admin::Search qw(:J_OP :T_OP :S_FI :S_OR :B_OP);
use FILEX::Tools::Utils qw(tsToLocal hrSize);
use FILEX::Apache::Handler::Admin::Common qw(doFileInfos);

my %TEST_OPERATORS = ( 
	1 => T_OP_EQ,
  2 => T_OP_NEQ,
  3 => T_OP_LT,
  4 => T_OP_LTE,
  5 => T_OP_GT,
  6 => T_OP_GTE,
  7 => T_OP_LIKE,
  8 => T_OP_NLIKE
);

my %JOIN_OPERATORS = (
	1 => J_OP_AND,
	2 => J_OP_OR
);

my @SORT_FIELDS = (S_F_NAME,S_F_OWNER,S_F_SIZE,S_F_UDATE,S_F_EDATE,S_F_COUNT);
my @SORT_ORDER = (S_O_ASC,S_O_DESC);

sub process {
	my $self = shift;
	my $S = $self->sys();
	my $T = $S->getTemplate(name=>"admin_search");
	my @errors;

	# check if we need to show file properties
	my $sub_action = $S->apreq->param(SUB_ACTION_FIELD_NAME) || -1;
	if ( $sub_action == SUB_FILE_INFO ) {
		my $file_id = $S->apreq->param(FILE_ID_FIELD_NAME);
		if ( defined($file_id) ) {
			my $inT = doFileInfos(system=>$S,
			                      file_id=>$file_id,
			                      url=>$self->genFileInfoUrl($file_id),
														go_back=>$self->genCurrentUrl(),
			                      mode=>1,sub_action_value=>SUB_FILE_INFO,
			                      sub_action_field_name=>SUB_ACTION_FIELD_NAME,
			                      file_id_field_name=>FILE_ID_FIELD_NAME);
			return ($inT,1);
		}
	}
	# basic template 
	$T->param(FILEX_SEARCH_FORM_ACTION=>$S->getCurrentUrl());
	$T->param(FILEX_MAIN_ACTION_FIELD_NAME=>$self->getDispatchName());
	$T->param(FILEX_MAIN_ACTION_ID=>$self->getActionId());
	# real_name
	$T->param(FILEX_SEARCH_NAME_FIELD_NAME=>SEARCH_NAME_FIELD_NAME);
	$T->param(FILEX_SEARCH_NAME_E_FIELD_NAME=>SEARCH_NAME_E_FIELD_NAME);
	$T->param(FILEX_SEARCH_NAME_T_FIELD_NAME=>SEARCH_NAME_T_FIELD_NAME);
	$T->param(FILEX_SEARCH_NAME_J_FIELD_NAME=>SEARCH_NAME_J_FIELD_NAME);
	# maybe check for value == 1
	my $b_name_checked = $S->apreq->param(SEARCH_NAME_E_FIELD_NAME);
	$b_name_checked = undef if ! ( defined($b_name_checked) && ($b_name_checked =~ /^1$/) );
	$T->param(FILEX_SEARCH_NAME_E_CHECKED=>1) if $b_name_checked;
	my ($name_value,$name_join,$name_test);
	if ( $b_name_checked ) {
		# value
		$name_value = $S->apreq->param(SEARCH_NAME_FIELD_NAME);
		$name_value = undef if ( length($name_value) <= 0 );
		$T->param(FILEX_SEARCH_NAME_VALUE=>$name_value) if defined($name_value);
		push(@errors,"[name] field not set") if !defined($name_value);
		# join
		$name_join = $S->apreq->param(SEARCH_NAME_J_FIELD_NAME);
		# make test on join value
		if ( !defined($name_join) || !grep($name_join eq $_,keys(%JOIN_OPERATORS)) ) {
			push(@errors,"Invalid [name] join operator : $name_join");
		}
		# test
		$name_test = $S->apreq->param(SEARCH_NAME_T_FIELD_NAME);
		if ( !defined($name_test) || !grep($name_test eq $_,keys(%TEST_OPERATORS)) ) {
			push(@errors,"Invalid [name] test operator : $name_test");
		}
	}
	makeJoinLoop($T,"FILEX_SEARCH_NAME_J_LOOP",$name_join);
	makeTestLoop($T,"FILEX_SEARCH_NAME_T_LOOP",$name_test,[1,2,7,8]);
	# owner
	$T->param(FILEX_SEARCH_OWNER_FIELD_NAME=>SEARCH_OWNER_FIELD_NAME);
	$T->param(FILEX_SEARCH_OWNER_E_FIELD_NAME=>SEARCH_OWNER_E_FIELD_NAME);
	$T->param(FILEX_SEARCH_OWNER_T_FIELD_NAME=>SEARCH_OWNER_T_FIELD_NAME);
	$T->param(FILEX_SEARCH_OWNER_J_FIELD_NAME=>SEARCH_OWNER_J_FIELD_NAME);
	my $b_owner_checked = $S->apreq->param(SEARCH_OWNER_E_FIELD_NAME);
	$b_owner_checked = undef if ! ( defined($b_owner_checked) && ($b_owner_checked =~ /^1$/) );
	$T->param(FILEX_SEARCH_OWNER_E_CHECKED=>1) if $b_owner_checked;
	my ($owner_value,$owner_join,$owner_test);
	if ( $b_owner_checked ) {
		$owner_value = $S->apreq->param(SEARCH_OWNER_FIELD_NAME);
		$owner_value = undef if ( length($owner_value) <= 0 );
		push(@errors,"[owner] field not set") if !defined($owner_value);
		$T->param(FILEX_SEARCH_OWNER_VALUE=>$owner_value) if defined($owner_value);
		$owner_join = $S->apreq->param(SEARCH_OWNER_J_FIELD_NAME);
		if ( !defined($owner_join) || !grep($owner_join eq $_,keys(%JOIN_OPERATORS)) ) {
			push(@errors,"Invalid [owner] join operator : $owner_join");
		}
		$owner_test = $S->apreq->param(SEARCH_OWNER_T_FIELD_NAME);
		if ( !defined($owner_test) || !grep($owner_test eq $_,keys(%TEST_OPERATORS)) ) {
			push(@errors,"Invalid [owner] test operator : $owner_test");
		}
	}
	makeJoinLoop($T,"FILEX_SEARCH_OWNER_J_LOOP",$owner_join);
	makeTestLoop($T,"FILEX_SEARCH_OWNER_T_LOOP",$owner_test,[1,2,7,8]);
	# upload_date
	$T->param(FILEX_SEARCH_UDATE_FIELD_NAME=>SEARCH_UDATE_FIELD_NAME);
	$T->param(FILEX_SEARCH_UDATE_E_FIELD_NAME=>SEARCH_UDATE_E_FIELD_NAME);
	$T->param(FILEX_SEARCH_UDATE_T_FIELD_NAME=>SEARCH_UDATE_T_FIELD_NAME);
	$T->param(FILEX_SEARCH_UDATE_J_FIELD_NAME=>SEARCH_UDATE_J_FIELD_NAME);
	my $b_udate_checked = $S->apreq->param(SEARCH_UDATE_E_FIELD_NAME);
	$b_udate_checked = undef if ! ( defined($b_udate_checked) && ($b_udate_checked =~ /^1$/) );
	$T->param(FILEX_SEARCH_UDATE_E_CHECKED=>1) if $b_udate_checked;
	my ($udate_value,$udate_join,$udate_test);
	if ( $b_udate_checked ) {
		$udate_value = $S->apreq->param(SEARCH_UDATE_FIELD_NAME);
		$udate_value = makeTimeStamp($udate_value);
		push(@errors,"Invalid [upload_date] format : use JJ/MM/AAAA") if !defined($udate_value);
		$T->param(FILEX_SEARCH_UDATE_VALUE=>$S->apreq->param(SEARCH_UDATE_FIELD_NAME)) if defined($udate_value);
		$udate_join = $S->apreq->param(SEARCH_UDATE_J_FIELD_NAME);
		if ( !defined($udate_join) || !grep($udate_join eq $_,keys(%JOIN_OPERATORS)) ) {
			push(@errors,"Invalid [upload_date] join operator : $udate_join");
		}
		$udate_test = $S->apreq->param(SEARCH_UDATE_T_FIELD_NAME);
		if ( !defined($udate_test) || !grep($udate_test eq $_,keys(%TEST_OPERATORS)) ) {
			push(@errors,"Invalid [upload_date] test operator : $udate_test");
		}
	}
	makeJoinLoop($T,"FILEX_SEARCH_UDATE_J_LOOP",$udate_join);
	makeTestLoop($T,"FILEX_SEARCH_UDATE_T_LOOP",$udate_test,[1,2,3,4,5,6]);
	# upload_date2
	$T->param(FILEX_SEARCH_UDATE2_FIELD_NAME=>SEARCH_UDATE2_FIELD_NAME);
	$T->param(FILEX_SEARCH_UDATE2_E_FIELD_NAME=>SEARCH_UDATE2_E_FIELD_NAME);
	$T->param(FILEX_SEARCH_UDATE2_T_FIELD_NAME=>SEARCH_UDATE2_T_FIELD_NAME);
	$T->param(FILEX_SEARCH_UDATE2_J_FIELD_NAME=>SEARCH_UDATE2_J_FIELD_NAME);
	my $b_udate2_checked = $S->apreq->param(SEARCH_UDATE2_E_FIELD_NAME);
	$b_udate2_checked = undef if ! ( defined($b_udate2_checked) && ($b_udate2_checked =~ /^1$/) );
	$T->param(FILEX_SEARCH_UDATE2_E_CHECKED=>1) if $b_udate2_checked;
	my ($udate2_value,$udate2_join,$udate2_test);
	if ( $b_udate2_checked ) {
		$udate2_value = $S->apreq->param(SEARCH_UDATE2_FIELD_NAME);
		$udate2_value = makeTimeStamp($udate2_value);
		push(@errors,"Invalid [upload_date2] format : use JJ/MM/AAAA") if !defined($udate2_value);
		$T->param(FILEX_SEARCH_UDATE2_VALUE=>$S->apreq->param(SEARCH_UDATE2_FIELD_NAME)) if defined($udate2_value);
		$udate2_join = $S->apreq->param(SEARCH_UDATE2_J_FIELD_NAME);
		if ( !defined($udate2_join) || !grep($udate2_join eq $_,keys(%JOIN_OPERATORS)) ) {
			push(@errors,"Invalid [upload_date2] join operator : $udate2_join");
		}
		$udate2_test = $S->apreq->param(SEARCH_UDATE2_T_FIELD_NAME);
		if ( !defined($udate2_test) || !grep($udate2_test eq $_,keys(%TEST_OPERATORS)) ) {
			push(@errors,"Invalid [upload_date2] test operator : $udate2_test");
		}
	}
	makeJoinLoop($T,"FILEX_SEARCH_UDATE2_J_LOOP",$udate2_join);
	makeTestLoop($T,"FILEX_SEARCH_UDATE2_T_LOOP",$udate2_test,[1,2,3,4,5,6]);
	# expire_date
	$T->param(FILEX_SEARCH_EDATE_FIELD_NAME=>SEARCH_EDATE_FIELD_NAME);
	$T->param(FILEX_SEARCH_EDATE_E_FIELD_NAME=>SEARCH_EDATE_E_FIELD_NAME);
	$T->param(FILEX_SEARCH_EDATE_T_FIELD_NAME=>SEARCH_EDATE_T_FIELD_NAME);
	$T->param(FILEX_SEARCH_EDATE_J_FIELD_NAME=>SEARCH_EDATE_J_FIELD_NAME);
	my $b_edate_checked = $S->apreq->param(SEARCH_EDATE_E_FIELD_NAME);
	$b_edate_checked = undef if ! ( defined($b_edate_checked) && ($b_edate_checked =~ /^1$/) );
	$T->param(FILEX_SEARCH_EDATE_E_CHECKED=>1) if $b_edate_checked;
	my ($edate_value,$edate_join,$edate_test);
	if ( $b_edate_checked ) {
		$edate_value = $S->apreq->param(SEARCH_EDATE_FIELD_NAME);
		$edate_value = makeTimeStamp($edate_value);
		push(@errors,"Invalid [expire_date] format : use JJ/MM/AAAA") if !defined($edate_value);
		$T->param(FILEX_SEARCH_EDATE_VALUE=>$S->apreq->param(SEARCH_EDATE_FIELD_NAME)) if defined($edate_value);
		$edate_join = $S->apreq->param(SEARCH_EDATE_J_FIELD_NAME);
		if ( !defined($edate_join) || !grep($edate_join eq $_,keys(%JOIN_OPERATORS)) ) {
			push(@errors,"Invalid [expire_date] join operator : $edate_join");
		}
		$edate_test = $S->apreq->param(SEARCH_EDATE_T_FIELD_NAME);
		if ( !defined($edate_test) || !grep($edate_test eq $_,keys(%TEST_OPERATORS)) ) {
			push(@errors,"Invalid [expire_date] test operator : $edate_test");
		}
	}
	makeJoinLoop($T,"FILEX_SEARCH_EDATE_J_LOOP",$edate_join);
	makeTestLoop($T,"FILEX_SEARCH_EDATE_T_LOOP",$edate_test,[1,2,3,4,5,6]);
	# expire_date2
	$T->param(FILEX_SEARCH_EDATE2_FIELD_NAME=>SEARCH_EDATE2_FIELD_NAME);
	$T->param(FILEX_SEARCH_EDATE2_E_FIELD_NAME=>SEARCH_EDATE2_E_FIELD_NAME);
	$T->param(FILEX_SEARCH_EDATE2_T_FIELD_NAME=>SEARCH_EDATE2_T_FIELD_NAME);
	$T->param(FILEX_SEARCH_EDATE2_J_FIELD_NAME=>SEARCH_EDATE2_J_FIELD_NAME);
	my $b_edate2_checked = $S->apreq->param(SEARCH_EDATE2_E_FIELD_NAME);
	$b_edate2_checked = undef if ! ( defined($b_edate2_checked) && ($b_edate2_checked =~ /^1$/) );
	$T->param(FILEX_SEARCH_EDATE2_E_CHECKED=>1) if $b_edate2_checked;
	my ($edate2_value,$edate2_join,$edate2_test);
	if ( $b_edate2_checked ) {
		$edate2_value = $S->apreq->param(SEARCH_EDATE2_FIELD_NAME);
		$edate2_value = makeTimeStamp($edate2_value);
		push(@errors,"Invalid [expire_date] format : use JJ/MM/AAAA") if !defined($edate2_value);
		$T->param(FILEX_SEARCH_EDATE2_VALUE=>$S->apreq->param(SEARCH_EDATE2_FIELD_NAME)) if defined($edate2_value);
		$edate2_join = $S->apreq->param(SEARCH_EDATE2_J_FIELD_NAME);
		if ( !defined($edate2_join) || !grep($edate2_join eq $_,keys(%JOIN_OPERATORS)) ) {
			push(@errors,"Invalid [expire_date] join operator : $edate2_join");
		}
		$edate2_test = $S->apreq->param(SEARCH_EDATE2_T_FIELD_NAME);
		if ( !defined($edate2_test) || !grep($edate2_test eq $_,keys(%TEST_OPERATORS)) ) {
			push(@errors,"Invalid [expire_date] test operator : $edate2_test");
		}
	}
	makeJoinLoop($T,"FILEX_SEARCH_EDATE2_J_LOOP",$edate2_join);
	makeTestLoop($T,"FILEX_SEARCH_EDATE2_T_LOOP",$edate2_test,[1,2,3,4,5,6]);
	# enable
	$T->param(FILEX_SEARCH_ENABLE_E_FIELD_NAME=>SEARCH_ENABLE_E_FIELD_NAME);
	$T->param(FILEX_SEARCH_ENABLE_FIELD_NAME=>SEARCH_ENABLE_FIELD_NAME);
	$T->param(FILEX_SEARCH_ENABLE_J_FIELD_NAME=>SEARCH_ENABLE_J_FIELD_NAME);
	my $b_enable_checked = $S->apreq->param(SEARCH_ENABLE_E_FIELD_NAME);
	$b_enable_checked = undef if ! ( defined($b_enable_checked) && ($b_enable_checked =~ /^1$/) );
	$T->param(FILEX_SEARCH_ENABLE_E_CHECKED=>1) if $b_enable_checked;
	my ($enable_value,$enable_join);
	if ( $b_enable_checked ) {
		$enable_value = $S->apreq->param(SEARCH_ENABLE_FIELD_NAME);
		if ( !defined($enable_value) || !grep($enable_value eq $_,(B_OP_TRUE,B_OP_FALSE)) ) {
			push(@errors,"Invalid [enable] value : $enable_value");
		}
		# check for errors
		$enable_join = $S->apreq->param(SEARCH_ENABLE_J_FIELD_NAME);
		if ( !defined($enable_join) || !grep($enable_join eq $_,keys(%JOIN_OPERATORS)) ) {
			push(@errors,"Invalid [enable] join operator : $enable_join");
		}
	}
	makeJoinLoop($T,"FILEX_SEARCH_ENABLE_J_LOOP",$enable_join);
	makeEnableLoop($S,$T,"FILEX_SEARCH_ENABLE_LOOP",$enable_value);
	# sort field
	$T->param(FILEX_SEARCH_SORT_FIELD_NAME=>SEARCH_SORT_FIELD_NAME);
	$T->param(FILEX_SEARCH_SORT_E_FIELD_NAME=>SEARCH_SORT_E_FIELD_NAME);
	$T->param(FILEX_SEARCH_SORT_O_FIELD_NAME=>SEARCH_SORT_O_FIELD_NAME);
	my $b_sort_checked = $S->apreq->param(SEARCH_SORT_E_FIELD_NAME);
	$b_sort_checked = undef if ! ( defined($b_sort_checked) && ($b_sort_checked =~ /^1$/) );
	$T->param(FILEX_SEARCH_SORT_E_CHECKED=>1) if $b_sort_checked;
	my ($sort_value,$order_value);
	if ( $b_sort_checked ) {
		$sort_value = $S->apreq->param(SEARCH_SORT_FIELD_NAME);
		# check for errors
		if ( !defined($sort_value) || !grep($sort_value eq $_,@SORT_FIELDS) ) {
			push(@errors,"Invalid sort field : $sort_value");
		}
		$order_value = $S->apreq->param(SEARCH_SORT_O_FIELD_NAME);
		# check for errors
		if ( !defined($order_value) || !grep($order_value eq $_,@SORT_ORDER) ) {
			push(@errors,"Invalid sort order : $order_value");
		}
	}
	makeSortLoop($S,$T,"FILEX_SEARCH_SORT_LOOP",$sort_value);
	makeSortOrderLoop($S,$T,"FILEX_SEARCH_SORT_O_LOOP",$order_value);

	if ( $#errors >= 0 ) {
		$T->param(FILEX_HAS_ERROR=>$S->toHtml(join(';',@errors)));
		return $T;
	}

	# time to generate query
	my @query_fields;
	# process in order
	push(@query_fields,{field=>'real_name',test=>$TEST_OPERATORS{$name_test},join=>$JOIN_OPERATORS{$name_join},value=>$name_value}) if $b_name_checked;
	push(@query_fields,{field=>'owner',test=>$TEST_OPERATORS{$owner_test},join=>$JOIN_OPERATORS{$owner_join},value=>$owner_value}) if $b_owner_checked;
	push(@query_fields,{field=>'upload_date',test=>$TEST_OPERATORS{$udate_test},join=>$JOIN_OPERATORS{$udate_join},value=>$udate_value}) if $b_udate_checked;
	push(@query_fields,{field=>'upload_date',test=>$TEST_OPERATORS{$udate2_test},join=>$JOIN_OPERATORS{$udate2_join},value=>$udate2_value}) if $b_udate2_checked;
	push(@query_fields,{field=>'expire_date',test=>$TEST_OPERATORS{$edate_test},join=>$JOIN_OPERATORS{$edate_join},value=>$edate_value}) if $b_edate_checked;
	push(@query_fields,{field=>'expire_date',test=>$TEST_OPERATORS{$edate2_test},join=>$JOIN_OPERATORS{$edate2_join},value=>$edate2_value}) if $b_edate2_checked;
	push(@query_fields,{field=>'enable',test=>T_OP_NEQ,join=>$JOIN_OPERATORS{$enable_join},value=>$enable_value}) if $b_enable_checked;
	# sort and sort order
	my @query_opts;
	push(@query_opts,("order",$order_value)) if $b_sort_checked && $order_value;
	push(@query_opts,("sort",$sort_value)) if $b_sort_checked && $sort_value;

	my $db =  eval { FILEX::DB::Admin::Search->new(); };
	if ($@) {
		$T->param(FILEX_HAS_ERROR=>$S->i18n->localizeToHtml("database error %s",$db->getLastErrorString()));
		return $T;
	}
	my @results;
	if ( ! $db->search(fields=>\@query_fields,results=>\@results,@query_opts) ) {
		$T->param(FILEX_HAS_ERROR=>$S->i18n->localizeToHtml("database error %s",$db->getLastErrorString()));
		return $T;
	}
	return $T if ($#results < 0);
	# time to display
	$T->param(FILEX_HAS_RESULTS=>1);
	$T->param(FILEX_SEARCH_COUNT=>$#results+1);
	# TO CONTINUE !
	#return $T;
	my (@files_loop,$file_owner,$hrsize,$hrunit);
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
	$T->param(FILEX_RESULTS_LOOP=>\@files_loop);
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

sub genCurrentUrl {
	my $self = shift;
	my $url = $self->sys->getCurrentUrl();
	$url .= "?".$self->genQueryString();
	return $url;
}

sub genFileInfoUrl {
	my $self = shift;
	my $file_id = shift;
	my $sub_action = SUB_ACTION_FIELD_NAME;
	my $url = $self->sys->getCurrentUrl();
	$url .= "?".$self->genQueryString($sub_action => SUB_FILE_INFO,id => $file_id);
	return $url;
}

# date format = JJ/MM/AAAA
# return undef on invalid format
sub makeTimeStamp {
	my $date = shift;
	my ($jj,$mm,$yy);
	if ( $date =~ /^([0-9]{1,2})\/([0-9]{1,2})\/([0-9]{4})$/ ) {
		$jj = $1;
		$mm = $2;
		$yy = $3;
	} else {
		return undef;
	}
	#mktime(sec,min,hour,mday,mon,year)
	my $time_t = POSIX::mktime(0,0,0,$jj,$mm-1,$yy-1900);
}
# template,loop name,selected value
sub makeJoinLoop {
	my $template = shift;
	my $loop_name = shift;
	my $selected_value = shift;
	
	my @loop;
	foreach my $k ( keys(%JOIN_OPERATORS) ) {
		my $s = { VALUE=>$k, TEXT=>$JOIN_OPERATORS{$k} };
		$s->{'SELECTED'} = 1 if ( defined($selected_value) && ($k == $selected_value) );
		push(@loop,$s);
	}
	$template->param($loop_name=>\@loop);
}

# template,loop name, selected value, arrayref of test operators
sub makeTestLoop {
	my $template = shift;
	my $loop_name = shift;
	my $selected_value = shift;
	my $array_op = shift;

	my @loop;
	for (my $i=0; $i <= $#$array_op; $i++) {
		if ( exists($TEST_OPERATORS{$array_op->[$i]}) ) {
			my $s = { VALUE=>$array_op->[$i], TEXT=>$TEST_OPERATORS{$array_op->[$i]} };
			$s->{'SELECTED'} = 1 if ( defined($selected_value) && ($array_op->[$i] == $selected_value) );
			push(@loop,$s);
		}
	}
	$template->param($loop_name=>\@loop);
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

sub makeEnableLoop {
	my $system = shift;
	my $template = shift;
	my $loop_name = shift;
	my $selected_value = shift;

	my @loop;
	push(@loop,{VALUE=>B_OP_TRUE,TEXT=>$system->i18n->localizeToHtml("yes"),SELECTED=>(defined($selected_value) && $selected_value == B_OP_TRUE) ? 1 : 0});
	push(@loop,{VALUE=>B_OP_FALSE,TEXT=>$system->i18n->localizeToHtml("no"),SELECTED=>(defined($selected_value) && $selected_value == B_OP_FALSE) ? 1 : 0});
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
