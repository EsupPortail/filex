package FILEX::Apache::Handler::Admin::Rules;
use strict;
use vars qw(@ISA);
use FILEX::Apache::Handler::Admin::base;
@ISA = qw(FILEX::Apache::Handler::Admin::base);

use constant SA_DELETE => 1;
use constant SA_MODIFY => 2;
use constant SA_ADD => 3;
use constant SA_SHOW_MODIFY => 4;
use constant SUBACTION => "sa";

use FILEX::DB::Admin::Rules qw(getRuleTypes getRuleTypeName);

sub process {
	my $self = shift;
	my ($b_err,$errstr,$form_sub_action);
	my $S = $self->sys();
	my $T = $S->getTemplate(name=>"admin_rules");
	my $DB = FILEX::DB::Admin::Rules->new(
		name=>$S->config->getDBName(),
		user=>$S->config->getDBUsername(),
		password=>$S->config->getDBPassword(),
		host=>$S->config->getDBHost(),
		port=>$S->config->getDBPort()
	);
	my $selected_rule_type = undef;
	# is there a sub action
	my $sub_action = $S->apreq->param(SUBACTION) || -1;
	SWITCH : {
		# add a new rule
		if ( $sub_action == SA_ADD ) {
			if ( ! $DB->add(name=>$S->apreq->param('rule_name'),
				exp=>$S->apreq->param('rule_exp'),
				type=>$S->apreq->param('rule_type')) ) {
				$errstr = ($DB->getLastErrorCode() == 1062) ? $S->i18n->localize("rule already exists") : $DB->getLastErrorString();
				$b_err = 1;
			}
			last SWITCH;
		}
		# delete rule
		if ( $sub_action == SA_DELETE ) {
			if ( ! $DB->del($S->apreq->param('rule_id')) ) {
				$errstr = $DB->getLastErrorString(); 
				$b_err = 1;
			}
			last SWITCH;
		}
		# show a selected rule
		if ( $sub_action == SA_SHOW_MODIFY ) {
			my (%hrule,$hkey,$hid);
			$hid = $S->apreq->param('rule_id');
			if ( ! $DB->get(id=>$hid,results=>\%hrule) ) {
				$errstr = $DB->getLastErrorString();
				$b_err = 1;
			}
			$hkey = keys(%hrule);
			if ( $hkey > 0 ) {
				# fill modify template
				$T->param(FORM_RULE_NAME=>$hrule{'name'});
				$T->param(FORM_RULE_EXP=>$hrule{'exp'});
				$T->param(FORM_RULE_ID=>$hid);
				$selected_rule_type = $hrule{'type'};
				$form_sub_action = SA_MODIFY;
			}
			last SWITCH;
		}
		# modify a selected rule
		if ( $sub_action == SA_MODIFY ) {
			if ( ! $DB->modify(id=>$S->apreq->param('rule_id'),
					name=>$S->apreq->param('rule_name'),
					exp=>$S->apreq->param('rule_exp'),
					type=>$S->apreq->param('rule_type')) ) {
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
		$record->{'RULETYPE_ID'} = $rt;
		$record->{'RULETYPE_NAME'} = getRuleTypeName($rt);
		$record->{'RULETYPE_SELECTED'} = "selected" if ( defined($selected_rule_type) && $selected_rule_type == $rt );
		push(@rt_loop,$record);
	}
	$T->param(RULETYPE_LOOP=>\@rt_loop);
	# the rest
	$T->param(FORM_ACTION=>$S->getCurrentUrl());
	$T->param(MACTION=>$self->getDispatchName());
	$T->param(MACTIONID=>$self->getActionId());
	$T->param(SUBACTION=>SUBACTION);
	$T->param(SUBACTIONID=>$form_sub_action);
	if ( $b_err ) { 
		$T->param(HAS_ERROR=>1);
		$T->param(ERROR=>$S->toHtml($errstr));
	}
	# already defined rules
	my (@results,@rules_loop,$state);
	$b_err = $DB->list(\@results);
	if ($#results >= 0) {
		for (my $i=0; $i<=$#results; $i++) {
			my $record = {};
			$record->{'RULE_TYPE'} = getRuleTypeName($results[$i]->{'type'});
			$record->{'RULE_NAME'} = $S->toHtml($results[$i]->{'name'});
			$record->{'RULE_EXP'} = $S->toHtml($results[$i]->{'exp'});
			$state = $results[$i]->{'enable'};
			$record->{'REMOVEURL'} = $self->genRemoveUrl($results[$i]->{'id'});
			$record->{'MODIFYURL'} = $self->genModifyUrl($results[$i]->{'id'});
			push(@rules_loop,$record);
		}
		$T->param(HAS_RULES=>1);
		$T->param(RULES_LOOP=>\@rules_loop);
	}
	return $T;
}

sub genModifyUrl {
	my $self = shift;
	my $id = shift;
	my $sub_action = SUBACTION;
	my $url = $self->sys->getCurrentUrl();
	$url .= "?".$self->genQueryString($sub_action=>SA_SHOW_MODIFY,rule_id=>$id);
	return $url;
}

sub genRemoveUrl {
	my $self = shift;
	my $id = shift;
	my $sub_action = SUBACTION;
	my $url = $self->sys->getCurrentUrl();
	$url .= "?".$self->genQueryString($sub_action=>SA_DELETE,rule_id=>$id);
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
