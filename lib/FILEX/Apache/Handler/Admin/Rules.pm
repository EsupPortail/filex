package FILEX::Apache::Handler::Admin::Rules;
use strict;
use vars qw(@ISA);
use FILEX::Apache::Handler::Admin::base;
@ISA = qw(FILEX::Apache::Handler::Admin::base);

use constant SA_DELETE => 1;
use constant SA_MODIFY => 2;
use constant SA_ADD => 3;
use constant SA_SHOW_MODIFY => 4;

use constant SUB_ACTION_FIELD_NAME=>"sa";
use constant RULES_RULE_TYPE_FIELD_NAME=>"rule_type";
use constant RULES_RULE_NAME_FIELD_NAME=>"rule_name";
use constant RULES_RULE_EXP_FIELD_NAME=>"rule_exp";
use constant RULES_RULE_ID_FIELD_NAME=>"rule_id";

use FILEX::DB::Admin::Rules qw(getRuleTypes getRuleTypeName);
use FILEX::Tools::Utils qw(toHtml);

sub process {
	my $self = shift;
	my ($b_err,$errstr,$form_sub_action);
	my $S = $self->sys();
	my $T = $S->getTemplate(name=>"admin_rules");
	# fille template
	$T->param(FILEX_RULES_FORM_ACTION=>$S->getCurrentUrl());
	$T->param(FILEX_SUB_ACTION_FIELD_NAME=>SUB_ACTION_FIELD_NAME);
	$T->param(FILEX_MAIN_ACTION_FIELD_NAME=>$self->getDispatchName());
	$T->param(FILEX_MAIN_ACTION_ID=>$self->getActionId());
	$T->param(FILEX_RULES_RULE_TYPE_FIELD_NAME=>RULES_RULE_TYPE_FIELD_NAME);
	$T->param(FILEX_RULES_RULE_NAME_FIELD_NAME=>RULES_RULE_NAME_FIELD_NAME);
	$T->param(FILEX_RULES_RULE_EXP_FIELD_NAME=>RULES_RULE_EXP_FIELD_NAME);
	$T->param(FILEX_RULES_RULE_ID_FIELD_NAME=>RULES_RULE_ID_FIELD_NAME);
	my $DB = eval { FILEX::DB::Admin::Rules->new(); };
	if ($@) {
		$T->param(FILEX_HAS_ERROR=>1);
		$T->param(FILEX_ERROR=>$S->i18n->localizeToHtml("database error %s",$DB->getLastErrorString()));
		return $T;
	}

	my $selected_rule_type = undef;
	# is there a sub action
	my $sub_action = $S->apreq->param(SUB_ACTION_FIELD_NAME) || -1;
	SWITCH : {
		# add a new rule
		if ( $sub_action == SA_ADD ) {
			if ( ! $DB->add(name=>$S->apreq->param(RULES_RULE_NAME_FIELD_NAME),
				exp=>$S->apreq->param(RULES_RULE_EXP_FIELD_NAME),
				type=>$S->apreq->param(RULES_RULE_TYPE_FIELD_NAME)) ) {
				$errstr = ($DB->getLastErrorCode() == 1062) ? $S->i18n->localize("rule already exists") : $S->i18n->localize($DB->getLastErrorString());
				$b_err = 1;
			}
			last SWITCH;
		}
		# delete rule
		if ( $sub_action == SA_DELETE ) {
			if ( ! $DB->del($S->apreq->param(RULES_RULE_ID_FIELD_NAME)) ) {
				$errstr = $DB->getLastErrorString(); 
				$b_err = 1;
			}
			last SWITCH;
		}
		# show a selected rule
		if ( $sub_action == SA_SHOW_MODIFY ) {
			my (%hrule,$hkey,$hid);
			$hid = $S->apreq->param(RULES_RULE_ID_FIELD_NAME);
			if ( ! $DB->get(id=>$hid,results=>\%hrule) ) {
				$errstr = $DB->getLastErrorString();
				$b_err = 1;
			}
			$hkey = keys(%hrule);
			if ( $hkey > 0 ) {
				# fill modify template
				$T->param(FILEX_RULES_FORM_RULE_NAME=>$hrule{'name'});
				$T->param(FILEX_RULES_FORM_RULE_EXP=>$hrule{'exp'});
				$T->param(FILEX_RULES_FORM_RULE_ID=>$hid);
				$selected_rule_type = $hrule{'type'};
				$form_sub_action = SA_MODIFY;
			}
			last SWITCH;
		}
		# modify a selected rule
		if ( $sub_action == SA_MODIFY ) {
			if ( ! $DB->modify(id=>$S->apreq->param(RULES_RULE_ID_FIELD_NAME),
					name=>$S->apreq->param(RULES_RULE_NAME_FIELD_NAME),
					exp=>$S->apreq->param(RULES_RULE_EXP_FIELD_NAME),
					type=>$S->apreq->param(RULES_RULE_TYPE_FIELD_NAME)) ) {
				$b_err = 1;
				$errstr = ( $DB->getLastErrorCode() == 1062 ) ? $S->i18n->localize("rule already exists") : $DB->getLastErrorString();
			}
			last SWITCH;
		}
	}
	$form_sub_action = SA_ADD if (!defined($form_sub_action));
	#
	# fill template
	#
	# loop on rule type
	my @rules_type = getRuleTypes();
	my @rt_loop;
	foreach my $rt (@rules_type) {
		my $record = {};
		$record->{'FILEX_RULES_TYPE_ID'} = $rt;
		$record->{'FILEX_RULES_TYPE_NAME'} = getRuleTypeName($rt);
		$record->{'FILEX_RULES_TYPE_SELECTED'} = 1 if ( defined($selected_rule_type) && $selected_rule_type == $rt );
		push(@rt_loop,$record);
	}
	$T->param(FILEX_RULES_TYPE_LOOP=>\@rt_loop);
	# the rest
	$T->param(FILEX_SUB_ACTION_ID=>$form_sub_action);
	if ( $b_err ) { 
		$T->param(FILEX_HAS_ERROR=>1);
		$T->param(FILEX_ERROR=>toHtml($errstr));
	}
	# already defined rules
	my (@results,@rules_loop,$state);
	$b_err = $DB->listEx(\@results);
	if ($#results >= 0) {
		for (my $i=0; $i<=$#results; $i++) {
			my $record = {};
			$record->{'FILEX_RULE_TYPE'} = getRuleTypeName($results[$i]->{'type'});
			$record->{'FILEX_RULE_NAME'} = toHtml($results[$i]->{'name'});
			$record->{'FILEX_RULE_EXP'} = toHtml($results[$i]->{'exp'});
			$state = $results[$i]->{'enable'};
			$record->{'FILEX_RULE_LINK_EX'} = toHtml(($results[$i]->{'exclude'} == 1)?$S->i18n->localize("yes"):$S->i18n->localize("no"));
			$record->{'FILEX_RULE_LINK_QT'} = toHtml(($results[$i]->{'quota'} == 1)?$S->i18n->localize("yes"):$S->i18n->localize("no"));
			$record->{'FILEX_RULE_LINK_SP'} = toHtml(($results[$i]->{'big_brother'} == 1)?$S->i18n->localize("yes"):$S->i18n->localize("no"));
			$record->{'FILEX_REMOVE_URL'} = toHtml($self->genRemoveUrl($results[$i]->{'id'}));
			$record->{'FILEX_MODIFY_URL'} = toHtml($self->genModifyUrl($results[$i]->{'id'}));
			push(@rules_loop,$record);
		}
		$T->param(FILEX_HAS_RULES=>1);
		$T->param(FILEX_RULES_LOOP=>\@rules_loop);
	}
	return $T;
}

sub genModifyUrl {
	my $self = shift;
	my $id = shift;
	my $sub_action = SUB_ACTION_FIELD_NAME;
	my $rule_id_field = RULES_RULE_ID_FIELD_NAME;
	my $url = $self->sys->getCurrentUrl();
	$url .= "?".$self->genQueryString($sub_action=>SA_SHOW_MODIFY,$rule_id_field=>$id);
	return $url;
}

sub genRemoveUrl {
	my $self = shift;
	my $id = shift;
	my $sub_action = SUB_ACTION_FIELD_NAME;
	my $rule_id_field = RULES_RULE_ID_FIELD_NAME;
	my $url = $self->sys->getCurrentUrl();
	$url .= "?".$self->genQueryString($sub_action=>SA_DELETE,$rule_id_field=>$id);
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
