package FILEX::Apache::Handler::Admin::BigBrother;
use strict;
use vars qw(@ISA);
use FILEX::Apache::Handler::Admin::base;
@ISA = qw(FILEX::Apache::Handler::Admin::base);

use constant SA_DELETE => 1;
use constant SA_STATE => 2;
use constant SA_MODIFY => 4;
use constant SA_SHOW_MODIFY => 5;
use constant SA_ADD => 3;

use constant SUB_ACTION_FIELD_NAME => "sa";
use constant BB_RULE_ID_FIELD_NAME=>"bb_rule_id";
use constant BB_DESCRIPTION_FIELD_NAME=>"bb_desc";
use constant BB_NORDER_FIELD_NAME=>"bb_norder";
use constant BB_MAIL_FIELD_NAME=>"bb_mail";
use constant BB_ID_FIELD_NAME=>"bb_id";
use constant BB_STATE_FIELD_NAME=>"bb_state";

use FILEX::DB::Admin::BigBrother;
use FILEX::Tools::Utils qw(tsToLocal hrSize unit2idx round unit2byte unitLabel unitLength);

sub process {
	my $self = shift;
	my ($b_err,$errstr,$form_sub_action);
	my $S = $self->sys();
	my $T = $S->getTemplate(name=>"admin_big_brother");
	# fill template
	$T->param(FILEX_BB_FORM_ACTION=>$S->getCurrentUrl());
	$T->param(FILEX_BB_RULE_ID_FIELD_NAME=>BB_RULE_ID_FIELD_NAME);
	$T->param(FILEX_BB_DESCRIPTION_FIELD_NAME=>BB_DESCRIPTION_FIELD_NAME);
	$T->param(FILEX_BB_NORDER_FIELD_NAME=>BB_NORDER_FIELD_NAME);
	$T->param(FILEX_BB_MAIL_FIELD_NAME=>BB_MAIL_FIELD_NAME);
	$T->param(FILEX_BB_ID_FIELD_NAME=>BB_ID_FIELD_NAME);
	$T->param(FILEX_MAIN_ACTION_FIELD_NAME=>$self->getDispatchName());
	$T->param(FILEX_MAIN_ACTION_ID=>$self->getActionId());
	$T->param(FILEX_SUB_ACTION_FIELD_NAME=>SUB_ACTION_FIELD_NAME);

	# Exclude database
	my $bb_DB = eval { FILEX::DB::Admin::BigBrother->new(); };
	if ($@) {
		$T->param(FILEX_HAS_ERROR=>1);
		$T->param(FILEX_ERROR=>$S->i18n->localizeToHtml("database error %s",$bb_DB->getLastErrorString()));
		return $T;
	}
	my $selected_rule = undef;
	# is there a sub action
	my $sub_action = $S->apreq->param(SUB_ACTION_FIELD_NAME) || -1;
	SWITCH : {
		# add a new rule
		if ( $sub_action == SA_ADD ) {
			if ( ! $bb_DB->add(description=>$S->apreq->param(BB_DESCRIPTION_FIELD_NAME),
				rule_id=>$S->apreq->param(BB_RULE_ID_FIELD_NAME),
				norder=>$S->apreq->param(BB_NORDER_FIELD_NAME),
				mail=>$S->apreq->param(BB_MAIL_FIELD_NAME) ) ) {
				$errstr = ($bb_DB->getLastErrorCode() == 1062) ? $S->i18n->localize("rule already exists") : $bb_DB->getLastErrorString();
				$b_err = 1;
			}
			last SWITCH;
		}
		# delete rule
		if ( $sub_action == SA_DELETE ) {
			if ( ! $bb_DB->del($S->apreq->param(BB_ID_FIELD_NAME)) ) {
				$errstr = $bb_DB->getLastErrorString(); 
				$b_err = 1;
			}
			last SWITCH;
		}
		# change rule state
		if ( $sub_action == SA_STATE ) {
			if ( ! $bb_DB->modify(id=>$S->apreq->param(BB_ID_FIELD_NAME),enable=>$S->apreq->param(BB_STATE_FIELD_NAME)) ) {
				$errstr = $bb_DB->getLastErrorString();
				$b_err = 1;
			}
			last SWITCH;
		}
		# show a selected rule
		if ( $sub_action == SA_SHOW_MODIFY ) {
			my (%hres,$hkey,$hid,$hrsize,$hrunit);
			$hid = $S->apreq->param(BB_ID_FIELD_NAME);
			if ( ! $bb_DB->get(id=>$hid,results=>\%hres) ) {
				$errstr = $bb_DB->getLastErrorString();
				$b_err = 1;
			}
			$hkey = keys(%hres);
			if ( $hkey > 0 ) {
				# fill modify template
				$T->param(FILEX_BB_FORM_BB_DESCRIPTION=>$hres{'description'});
				$T->param(FILEX_BB_FORM_BB_ID=>$hid);
				$T->param(FILEX_BB_FORM_BB_NORDER=>$hres{'norder'});
				$T->param(FILEX_BB_FORM_BB_MAIL=>$hres{'mail'});
				$selected_rule = $hres{'rule_id'};
				$form_sub_action = SA_MODIFY;
			}
			last SWITCH;
		}
		# modify a selected rule
		if ( $sub_action == SA_MODIFY ) {
			if ( ! $bb_DB->modify(id=>$S->apreq->param(BB_ID_FIELD_NAME),
					description=>$S->apreq->param(BB_DESCRIPTION_FIELD_NAME),
					rule_id=>$S->apreq->param(BB_RULE_ID_FIELD_NAME),
					norder=>$S->apreq->param(BB_NORDER_FIELD_NAME),
					mail=>$S->apreq->param(BB_MAIL_FIELD_NAME)) ) {
				$b_err = 1;
				$errstr = ( $bb_DB->getLastErrorCode() == 1062 ) ? $S->i18n->localize("rule already exists") : $bb_DB->getLastErrorString();
			}
			last SWITCH;
		}
	}
	if ( !defined($form_sub_action) ) {
		$form_sub_action = SA_ADD;
	}
	#
	# fill template
	#
	# loop on rule 
	my (@rules,@rules_loop);
	# selected_rule might be undef because the method check for it
	$bb_DB->listRules(results=>\@rules,including=>$selected_rule);
	for ( my $ridx = 0; $ridx <= $#rules; $ridx++ ) {
		my $record = {};
		$record->{'FILEX_BB_RULE_ID'} = $rules[$ridx]->{'id'};
		$record->{'FILEX_BB_RULE_NAME'} = $rules[$ridx]->{'name'};
		$record->{'FILEX_BB_RULE_SELECTED'} = 1 if ( defined($selected_rule) && $selected_rule == $rules[$ridx]->{'id'} );
		push(@rules_loop,$record);
	}
	$T->param(FILEX_BB_RULES_LOOP=>\@rules_loop);
	# the rest
	$T->param(FILEX_SUB_ACTION_ID=>$form_sub_action);
	if ( $b_err ) { 
		$T->param(FILEX_HAS_ERROR=>1);
		$T->param(FILEX_ERROR=>$S->toHtml($errstr));
	}
	# already defined rules
	my (@results,@exclude_loop,$state,$hrsize,$hrunit);
	$b_err = $bb_DB->list(results=>\@results);
	if ($#results >= 0) {
		for (my $i=0; $i<=$#results; $i++) {
			my $record = {};
			$record->{'FILEX_BB_DATE'} = tsToLocal($results[$i]->{'ts_create_date'});
			$record->{'FILEX_BB_ORDER'} = $results[$i]->{'norder'};
			$record->{'FILEX_BB_DESCRIPTION'} = $S->toHtml($results[$i]->{'description'}||'');
			$record->{'FILEX_BB_STATE'} = ($results[$i]->{'enable'} == 1) ? $S->i18n->localizeToHtml("enable") : $S->i18n->localizeToHtml("disable");
			$record->{'FILEX_BB_RULE'} = $S->toHtml($results[$i]->{'rule_name'});
			$record->{'FILEX_BB_MAIL'} = $S->toHtml($results[$i]->{'mail'});
			$state = $results[$i]->{'enable'};
			$record->{'FILEX_STATE_URL'} = $S->toHtml($self->genStateUrl($results[$i]->{'id'}, ($state == 1) ? 0 : 1 ));
			$record->{'FILEX_REMOVE_URL'} = $S->toHtml($self->genRemoveUrl($results[$i]->{'id'}));
			$record->{'FILEX_MODIFY_URL'} = $S->toHtml($self->genModifyUrl($results[$i]->{'id'}));
			push(@exclude_loop,$record);
		}
		$T->param(FILEX_HAS_BB=>1);
		$T->param(FILEX_BB_LOOP=>\@exclude_loop);
	}
	return $T;
}

# require : id,state
sub genStateUrl {
	my $self = shift;
	my $id = shift;
	my $enable = shift;
	my $sub_action = SUB_ACTION_FIELD_NAME;
	my $bb_id = BB_ID_FIELD_NAME;
	my $bb_state = BB_STATE_FIELD_NAME;
	my $url = $self->sys->getCurrentUrl();
	$url .= "?".$self->genQueryString(
			$sub_action=>SA_STATE,
			$bb_id=>$id,
			$bb_state=>$enable);
	return $url;
}

sub genModifyUrl {
	my $self = shift;
	my $id = shift;
	my $sub_action = SUB_ACTION_FIELD_NAME;
	my $bb_id = BB_ID_FIELD_NAME;
	my $url = $self->sys->getCurrentUrl();
	$url .= "?".$self->genQueryString(
			$sub_action=>SA_SHOW_MODIFY,
			$bb_id=>$id);
	return $url;
}

sub genRemoveUrl {
	my $self = shift;
	my $id = shift;
	my $sub_action = SUB_ACTION_FIELD_NAME;
	my $bb_id = BB_ID_FIELD_NAME;
	my $url = $self->sys->getCurrentUrl();
	$url .= "?".$self->genQueryString(
		$sub_action=>SA_DELETE,
		$bb_id=>$id);
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
