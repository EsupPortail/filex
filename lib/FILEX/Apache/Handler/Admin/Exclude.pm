package FILEX::Apache::Handler::Admin::Exclude;
use strict;
use vars qw(@ISA);
use FILEX::Apache::Handler::Admin::base;
@ISA = qw(FILEX::Apache::Handler::Admin::base);

use constant SA_DELETE => 1;
use constant SA_STATE => 2;
use constant SA_MODIFY => 4;
use constant SA_SHOW_MODIFY => 5;
use constant SA_ADD => 3;
use constant SA_DELETE_EXPIRED => 6;

use constant SUB_ACTION_FIELD_NAME=>"sa";
use constant EXCLUDE_RULE_ID_FIELD_NAME=>"exclude_rule_id";
use constant EXCLUDE_RULE_DESCRIPTION_FIELD_NAME=>"exclude_desc";
use constant EXCLUDE_RULE_RORDER_FIELD_NAME=>"exclude_rorder";
use constant EXCLUDE_RULE_EXCLUDE_ID_FIELD_NAME=>"exclude_id";
use constant EXCLUDE_RULE_EXCLUDE_STATE_FIELD_NAME=>"exclude_state";
use constant EXCLUDE_RULE_REASON_FIELD_NAME=>"exclude_rule_reason";
use constant EXCLUDE_RULE_EXPIRE_DAYS_FIELD_NAME=>"expire_days";

use FILEX::DB::Admin::Exclude;
use FILEX::Tools::Utils qw(tsToLocal toHtml);

sub process {
	my $self = shift;
	my ($b_err,$errstr,$form_sub_action);
	my $S = $self->sys();
	my $T = $S->getTemplate(name=>"admin_exclude");
	# fill basic template fields
	$T->param(FILEX_EXCLUDE_FORM_ACTION=>$S->getCurrentUrl());
	$T->param(FILEX_EXCLUDE_RULE_ID_FIELD_NAME=>EXCLUDE_RULE_ID_FIELD_NAME);
	$T->param(FILEX_EXCLUDE_RULE_DESCRIPTION_FIELD_NAME=>EXCLUDE_RULE_DESCRIPTION_FIELD_NAME);
	$T->param(FILEX_EXCLUDE_RULE_RORDER_FIELD_NAME=>EXCLUDE_RULE_RORDER_FIELD_NAME);
	$T->param(FILEX_EXCLUDE_RULE_EXCLUDE_ID_FIELD_NAME=>EXCLUDE_RULE_EXCLUDE_ID_FIELD_NAME);
	$T->param(FILEX_EXCLUDE_RULE_REASON_FIELD_NAME=>EXCLUDE_RULE_REASON_FIELD_NAME);
	$T->param(FILEX_EXCLUDE_RULE_EXPIRE_DAYS_FIELD_NAME=>EXCLUDE_RULE_EXPIRE_DAYS_FIELD_NAME);
	$T->param(FILEX_MAIN_ACTION_FIELD_NAME=>$self->getDispatchName());
	$T->param(FILEX_MAIN_ACTION_ID=>$self->getActionId());
	$T->param(FILEX_SUB_ACTION_FIELD_NAME=>SUB_ACTION_FIELD_NAME);
	$T->param(FILEX_DELETE_EXPIRED_URL=>toHtml($self->genDelExpiredUrl()));
	# Exclude database
	my $exclude_DB = eval { FILEX::DB::Admin::Exclude->new(); };
	if ($@) {
		$T->param(FILEX_HAS_ERROR=>1);
		$T->param(FILEX_ERROR=>$S->i18n->localizeToHtml("database error %s",$@));
		return $T;
	}

	my $selected_rule = undef;
	# is there a sub action
	my $sub_action = $S->apreq->param(SUB_ACTION_FIELD_NAME) || -1;
	SWITCH : {
		# add a new rule
		if ( $sub_action == SA_ADD ) {
			if ( ! $exclude_DB->add(description=>$S->apreq->param(EXCLUDE_RULE_DESCRIPTION_FIELD_NAME),
				reason=>$S->apreq->param(EXCLUDE_RULE_REASON_FIELD_NAME),
				rule_id=>$S->apreq->param(EXCLUDE_RULE_ID_FIELD_NAME),
				rorder=>$S->apreq->param(EXCLUDE_RULE_RORDER_FIELD_NAME),
				expire_days=>$S->apreq->param(EXCLUDE_RULE_EXPIRE_DAYS_FIELD_NAME)) ) {
				$errstr = ($exclude_DB->getLastErrorCode() == 1062) ? $S->i18n->localize("rule already exists") : $exclude_DB->getLastErrorString();
				$b_err = 1;
			}
			$T->param(FILEX_EXCLUDE_FORM_EXPIRE_DAYS=>$S->config->getExcludeExpireDays());
			last SWITCH;
		}
		# delete rule
		if ( $sub_action == SA_DELETE ) {
			if ( ! $exclude_DB->del($S->apreq->param(EXCLUDE_RULE_EXCLUDE_ID_FIELD_NAME)) ) {
				$errstr = $exclude_DB->getLastErrorString(); 
				$b_err = 1;
			}
			last SWITCH;
		}
		# change rule state
		if ( $sub_action == SA_STATE ) {
			if ( ! $exclude_DB->modify(id=>$S->apreq->param(EXCLUDE_RULE_EXCLUDE_ID_FIELD_NAME),
			                           enable=>$S->apreq->param(EXCLUDE_RULE_EXCLUDE_STATE_FIELD_NAME)) ) {
				$errstr = $exclude_DB->getLastErrorString();
				$b_err = 1;
			}
			last SWITCH;
		}
		# show a selected rule
		if ( $sub_action == SA_SHOW_MODIFY ) {
			my (%hexclude,$hkey,$hid);
			$hid = $S->apreq->param(EXCLUDE_RULE_EXCLUDE_ID_FIELD_NAME);
			if ( !$exclude_DB->get(id=>$hid,results=>\%hexclude) ) {
				$errstr = $exclude_DB->getLastErrorString();
				$b_err = 1;
			}
			$hkey = keys(%hexclude);
			if ( $hkey > 0 ) {
				# fill modify template
				$T->param(FILEX_EXCLUDE_FORM_EXCLUDE_DESCRIPTION=>$hexclude{'description'});
				$T->param(FILEX_EXCLUDE_FORM_EXCLUDE_ID=>$hid);
				$T->param(FILEX_EXCLUDE_FORM_EXCLUDE_RORDER=>$hexclude{'rorder'});
				$T->param(FILEX_EXCLUDE_FORM_EXCLUDE_REASON=>$hexclude{'reason'});
				$T->param(FILEX_EXCLUDE_FORM_EXPIRE_DAYS=>$hexclude{'expire_days'});
				$selected_rule = $hexclude{'rule_id'};
				$form_sub_action = SA_MODIFY;
			}
			last SWITCH;
		}
		# modify a selected rule
		if ( $sub_action == SA_MODIFY ) {
			if ( ! $exclude_DB->modify(id=>$S->apreq->param(EXCLUDE_RULE_EXCLUDE_ID_FIELD_NAME),
					description=>$S->apreq->param(EXCLUDE_RULE_DESCRIPTION_FIELD_NAME),
					reason=>$S->apreq->param(EXCLUDE_RULE_REASON_FIELD_NAME),
					rule_id=>$S->apreq->param(EXCLUDE_RULE_ID_FIELD_NAME),
					rorder=>$S->apreq->param(EXCLUDE_RULE_RORDER_FIELD_NAME),
					expire_days=>$S->apreq->param(EXCLUDE_RULE_EXPIRE_DAYS_FIELD_NAME)) ) {
				$b_err = 1;
				$errstr = ( $exclude_DB->getLastErrorCode() == 1062 ) ? $S->i18n->localize("rule already exists") : $exclude_DB->getLastErrorString();
			}
			$T->param(FILEX_EXCLUDE_FORM_EXPIRE_DAYS=>$S->config->getExcludeExpireDays());
			last SWITCH;
		}
		# delete expired rules
		if ( $sub_action == SA_DELETE_EXPIRED ) {
			if ( ! $exclude_DB->delExpired() ) {
				$b_err = 1;
				$errstr = $exclude_DB->getLastErrorString();
			}
			last SWITCH;
		}
		# no such action
		$T->param(FILEX_EXCLUDE_FORM_EXPIRE_DAYS=>$S->config->getExcludeExpireDays());
	}
	$form_sub_action = SA_ADD if (!defined($form_sub_action));
	#
	# fill template
	#
	# loop on rule 
	my (@rules,@rules_loop);
	$exclude_DB->listRules(results=>\@rules,including=>$selected_rule);
	for ( my $ridx = 0; $ridx <= $#rules; $ridx++ ) {
		my $record = {};
		$record->{'FILEX_EXCLUDE_RULE_ID'} = $rules[$ridx]->{'id'};
		$record->{'FILEX_EXCLUDE_RULE_NAME'} = $rules[$ridx]->{'name'};
		$record->{'FILEX_EXCLUDE_RULE_SELECTED'} = 1 if ( defined($selected_rule) && $selected_rule == $rules[$ridx]->{'id'} );
		push(@rules_loop,$record);
	}
	$T->param(FILEX_EXCLUDE_RULES_LOOP=>\@rules_loop);
	# the rest
	$T->param(FILEX_SUB_ACTION_ID=>$form_sub_action);
	if ( $b_err ) { 
		$T->param(FILEX_HAS_ERROR=>1);
		$T->param(FILEX_ERROR=>toHtml($errstr));
	}
	# already defined rules
	my (@results,@exclude_loop,$state);
	$b_err = $exclude_DB->list(results=>\@results);
	if ($#results >= 0) {
		for (my $i=0; $i<=$#results; $i++) {
			my $record = {};
			$record->{'FILEX_EXCLUDE_DATE'} = tsToLocal($results[$i]->{'ts_create_date'});
			$record->{'FILEX_EXCLUDE_EXPIRE_DAYS'} = $results[$i]->{'expire_days'};
			my $now = time();
			my $exclude_expired = (($results[$i]->{'ts_expire_date'} != $results[$i]->{'ts_create_date'})&&($results[$i]->{'ts_expire_date'}<$now)) ? 1 : 0;
			$record->{'FILEX_EXCLUDE_EXPIRED'} = ($exclude_expired) ? $S->i18n->localizeToHtml("yes") : $S->i18n->localizeToHtml("no");
			$record->{'FILEX_EXCLUDE_ORDER'} = $results[$i]->{'rorder'};
			$record->{'FILEX_EXCLUDE_DESCRIPTION'} = toHtml($results[$i]->{'description'}||'');
			$record->{'FILEX_EXCLUDE_STATE'} = ($results[$i]->{'enable'} == 1) ? $S->i18n->localizeToHtml("enable") : $S->i18n->localizeToHtml("disable");
			$record->{'FILEX_EXCLUDE_RULE'} = toHtml($results[$i]->{'rule_name'});
			$state = $results[$i]->{'enable'};
			$record->{'FILEX_STATE_URL'} = toHtml($self->genStateUrl($results[$i]->{'id'}, ($state == 1) ? 0 : 1 ));
			$record->{'FILEX_REMOVE_URL'} = toHtml($self->genRemoveUrl($results[$i]->{'id'}));
			$record->{'FILEX_MODIFY_URL'} = toHtml($self->genModifyUrl($results[$i]->{'id'}));
			push(@exclude_loop,$record);
		}
		$T->param(FILEX_HAS_EXCLUDE=>1);
		$T->param(FILEX_EXCLUDE_LOOP=>\@exclude_loop);
	}
	return $T;
}

# require : id,state
sub genStateUrl {
	my $self = shift;
	my $id = shift;
	my $enable = shift;
	my $sub_action = SUB_ACTION_FIELD_NAME;
	my $exclude_id = EXCLUDE_RULE_EXCLUDE_ID_FIELD_NAME;
	my $exclude_state = EXCLUDE_RULE_EXCLUDE_STATE_FIELD_NAME;
	my $url = $self->sys->getCurrentUrl();
	$url .= "?".$self->genQueryString(
			$sub_action=>SA_STATE,
			$exclude_id=>$id,
			$exclude_state=>$enable);
	return $url;
}

sub genModifyUrl {
	my $self = shift;
	my $id = shift;
	my $sub_action = SUB_ACTION_FIELD_NAME;
	my $exclude_id = EXCLUDE_RULE_EXCLUDE_ID_FIELD_NAME;
	my $url = $self->sys->getCurrentUrl();
	$url .= "?".$self->genQueryString(
			$sub_action=>SA_SHOW_MODIFY,
			$exclude_id=>$id);
	return $url;
}

sub genRemoveUrl {
	my $self = shift;
	my $id = shift;
	my $sub_action = SUB_ACTION_FIELD_NAME;
	my $exclude_id = EXCLUDE_RULE_EXCLUDE_ID_FIELD_NAME;
	my $url = $self->sys->getCurrentUrl();
	$url .= "?".$self->genQueryString(
		$sub_action=>SA_DELETE,
		$exclude_id=>$id);
	return $url;
}

sub genDelExpiredUrl {
	my $self = shift;
	my $sub_action = SUB_ACTION_FIELD_NAME;
	my $url = $self->sys->getCurrentUrl();
	$url .= "?".$self->genQueryString($sub_action=>SA_DELETE_EXPIRED);
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
