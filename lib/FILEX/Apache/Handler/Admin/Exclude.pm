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
use constant SUBACTION => "sa";

use FILEX::DB::Admin::Exclude;
use FILEX::Tools::Utils qw(tsToLocal);

sub process {
	my $self = shift;
	my ($b_err,$errstr,$form_sub_action);
	my $S = $self->sys();
	my $T = $S->getTemplate(name=>"admin_exclude");
	# Exclude database
	my $exclude_DB = FILEX::DB::Admin::Exclude->new(
		name=>$S->config->getDBName(),
		user=>$S->config->getDBUsername(),
		password=>$S->config->getDBPassword(),
		host=>$S->config->getDBHost(),
		port=>$S->config->getDBPort()
	);

	my $selected_rule = undef;
	# is there a sub action
	my $sub_action = $S->apreq->param(SUBACTION) || -1;
	SWITCH : {
		# add a new rule
		if ( $sub_action == SA_ADD ) {
			if ( ! $exclude_DB->add(name=>$S->apreq->param('exclude_name'),
				rule_id=>$S->apreq->param('exclude_rule_id'),
				rorder=>$S->apreq->param('exclude_rorder')) ) {
				$errstr = ($exclude_DB->getLastErrorCode() == 1062) ? $S->i18n->localize("rule already exists") : $exclude_DB->getLastErrorString();
				$b_err = 1;
			}
			last SWITCH;
		}
		# delete rule
		if ( $sub_action == SA_DELETE ) {
			if ( ! $exclude_DB->del($S->apreq->param('exclude_id')) ) {
				$errstr = $exclude_DB->getLastErrorString(); 
				$b_err = 1;
			}
			last SWITCH;
		}
		# change rule state
		if ( $sub_action == SA_STATE ) {
			if ( ! $exclude_DB->modify(id=>$S->apreq->param('exclude_id'),enable=>$S->apreq->param('exclude_state')) ) {
				$errstr = $exclude_DB->getLastErrorString();
				$b_err = 1;
			}
			last SWITCH;
		}
		# show a selected rule
		if ( $sub_action == SA_SHOW_MODIFY ) {
			my (%hexclude,$hkey,$hid);
			$hid = $S->apreq->param('exclude_id');
			if ( ! $exclude_DB->get(id=>$hid,results=>\%hexclude) ) {
				$errstr = $exclude_DB->getLastErrorString();
				$b_err = 1;
			}
			$hkey = keys(%hexclude);
			if ( $hkey > 0 ) {
				# fill modify template
				$T->param(FORM_EXCLUDE_NAME=>$hexclude{'name'});
				$T->param(FORM_EXCLUDE_ID=>$hid);
				$T->param(FORM_EXCLUDE_RORDER=>$hexclude{'rorder'});
				$selected_rule = $hexclude{'rule_id'};
				$form_sub_action = SA_MODIFY;
			}
			last SWITCH;
		}
		# modify a selected rule
		if ( $sub_action == SA_MODIFY ) {
			if ( ! $exclude_DB->modify(id=>$S->apreq->param('exclude_id'),
					name=>$S->apreq->param('exclude_name'),
					rule_id=>$S->apreq->param('exclude_rule_id'),
					rorder=>$S->apreq->param('exclude_rorder')) ) {
				$b_err = 1;
				$errstr = ( $exclude_DB->getLastErrorCode() == 1062 ) ? $S->i18n->localize("rule already exists") : $exclude_DB->getLastErrorString();
			}
			last SWITCH;
		}
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
		$record->{'RULE_ID'} = $rules[$ridx]->{'id'};
		$record->{'RULE_NAME'} = $rules[$ridx]->{'name'};
		$record->{'RULE_SELECTED'} = "selected" if ( defined($selected_rule) && $selected_rule == $rules[$ridx]->{'id'} );
		push(@rules_loop,$record);
	}
	$T->param(RULES_LOOP=>\@rules_loop);
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
	my (@results,@exclude_loop,$state);
	$b_err = $exclude_DB->list(results=>\@results);
	if ($#results >= 0) {
		for (my $i=0; $i<=$#results; $i++) {
			my $record = {};
			$record->{'EXCLUDE_DATE'} = tsToLocal($results[$i]->{'ts_create_date'});
			$record->{'EXCLUDE_ORDER'} = $results[$i]->{'rorder'};
			$record->{'EXCLUDE_NAME'} = $S->toHtml($results[$i]->{'name'});
			$record->{'EXCLUDE_STATE'} = ($results[$i]->{'enable'} == 1) ? $S->i18n->localizeToHtml("enable") : $S->i18n->localizeToHtml("disable");
			$record->{'EXCLUDE_RULE'} = $S->toHtml($results[$i]->{'rule_name'});
			$state = $results[$i]->{'enable'};
			$record->{'STATEURL'} = $self->genStateUrl($results[$i]->{'id'}, ($state == 1) ? 0 : 1 );
			$record->{'REMOVEURL'} = $self->genRemoveUrl($results[$i]->{'id'});
			$record->{'MODIFYURL'} = $self->genModifyUrl($results[$i]->{'id'});
			push(@exclude_loop,$record);
		}
		$T->param(HAS_EXCLUDE=>1);
		$T->param(EXCLUDE_LOOP=>\@exclude_loop);
	}
	return $T;
}

# require : id,state
sub genStateUrl {
	my $self = shift;
	my $id = shift;
	my $enable = shift;
	my $sub_action = SUBACTION;
	my $url = $self->sys->getCurrentUrl();
	$url .= "?".$self->genQueryString(
			$sub_action=>SA_STATE,
			exclude_id=>$id,
			exclude_state=>$enable);
	return $url;
}

sub genModifyUrl {
	my $self = shift;
	my $id = shift;
	my $sub_action = SUBACTION;
	my $url = $self->sys->getCurrentUrl();
	$url .= "?".$self->genQueryString(
			$sub_action=>SA_SHOW_MODIFY,
			exclude_id=>$id);
	return $url;
}

sub genRemoveUrl {
	my $self = shift;
	my $id = shift;
	my $sub_action = SUBACTION;
	my $url = $self->sys->getCurrentUrl();
	$url .= "?".$self->genQueryString(
		$sub_action=>SA_DELETE,
		exclude_id=>$id);
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
