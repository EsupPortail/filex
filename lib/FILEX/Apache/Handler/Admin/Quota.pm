package FILEX::Apache::Handler::Admin::Quota;
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
use constant QUOTA_RULE_ID_FIELD_NAME=>"quota_rule_id";
use constant QUOTA_DESCRIPTION_FIELD_NAME=>"quota_desc";
use constant QUOTA_QORDER_FIELD_NAME=>"quota_qorder";
use constant QUOTA_MAX_FILE_SIZE_FIELD_NAME=>"quota_max_file_size";
use constant QUOTA_MAX_FILE_SIZE_UNIT_FIELD_NAME=>"quota_max_file_size_unit";
use constant QUOTA_MAX_USED_SPACE_FIELD_NAME=>"quota_max_used_space";
use constant QUOTA_MAX_USED_SPACE_UNIT_FIELD_NAME=>"quota_max_used_space_unit";
use constant QUOTA_ID_FIELD_NAME=>"quota_id";
use constant QUOTA_STATE_FIELD_NAME=>"quota_state";

use FILEX::DB::Admin::Quota;
use FILEX::Tools::Utils qw(tsToLocal hrSize unit2idx round unit2byte unitLabel unitLength toHtml);

sub process {
	my $self = shift;
	my ($b_err,$errstr,$form_sub_action);
	my $S = $self->sys();
	my $T = $S->getTemplate(name=>"admin_quota");
	# fill template
	$T->param(FILEX_QUOTA_FORM_ACTION=>$S->getCurrentUrl());
	$T->param(FILEX_QUOTA_RULE_ID_FIELD_NAME=>QUOTA_RULE_ID_FIELD_NAME);
	$T->param(FILEX_QUOTA_DESCRIPTION_FIELD_NAME=>QUOTA_DESCRIPTION_FIELD_NAME);
	$T->param(FILEX_QUOTA_QORDER_FIELD_NAME=>QUOTA_QORDER_FIELD_NAME);
	$T->param(FILEX_QUOTA_MAX_FILE_SIZE_FIELD_NAME=>QUOTA_MAX_FILE_SIZE_FIELD_NAME);
	$T->param(FILEX_QUOTA_MAX_FILE_SIZE_UNIT_FIELD_NAME=>QUOTA_MAX_FILE_SIZE_UNIT_FIELD_NAME);
	$T->param(FILEX_QUOTA_MAX_USED_SPACE_FIELD_NAME=>QUOTA_MAX_USED_SPACE_FIELD_NAME);
	$T->param(FILEX_QUOTA_MAX_USED_SPACE_UNIT_FIELD_NAME=>QUOTA_MAX_USED_SPACE_UNIT_FIELD_NAME);
	$T->param(FILEX_QUOTA_ID_FIELD_NAME=>QUOTA_ID_FIELD_NAME);
	$T->param(FILEX_MAIN_ACTION_FIELD_NAME=>$self->getDispatchName());
	$T->param(FILEX_MAIN_ACTION_ID=>$self->getActionId());
	$T->param(FILEX_SUB_ACTION_FIELD_NAME=>SUB_ACTION_FIELD_NAME);

	# Exclude database
	my $quota_DB = eval { FILEX::DB::Admin::Quota->new(); };
	if ($@) {
		$T->param(FILEX_HAS_ERROR=>1);
		$T->param(FILEX_ERROR=>$S->i18n->localizeToHtml("database error %s",$quota_DB->getLastErrorString()));
		return $T;
	}
	my $selected_rule = undef;
	my $selected_mfsunit = undef;
	my $selected_musunit = undef;
	# is there a sub action
	my $sub_action = $S->apreq->param(SUB_ACTION_FIELD_NAME) || -1;
	SWITCH : {
		# add a new rule
		if ( $sub_action == SA_ADD ) {
			my $max_file_size = $self->getMaxFileSize();
			my $max_used_space = $self->getMaxUsedSpace();
			if ( ! $quota_DB->add(description=>$S->apreq->param(QUOTA_DESCRIPTION_FIELD_NAME),
				rule_id=>$S->apreq->param(QUOTA_RULE_ID_FIELD_NAME),
				qorder=>$S->apreq->param(QUOTA_QORDER_FIELD_NAME),
				max_file_size=>$max_file_size,
				max_used_space=>$max_used_space) ) {
				$errstr = ($quota_DB->getLastErrorCode() == 1062) ? $S->i18n->localize("rule already exists") : $quota_DB->getLastErrorString();
				$b_err = 1;
			}
			last SWITCH;
		}
		# delete rule
		if ( $sub_action == SA_DELETE ) {
			if ( ! $quota_DB->del($S->apreq->param(QUOTA_ID_FIELD_NAME)) ) {
				$errstr = $quota_DB->getLastErrorString(); 
				$b_err = 1;
			}
			last SWITCH;
		}
		# change rule state
		if ( $sub_action == SA_STATE ) {
			if ( ! $quota_DB->modify(id=>$S->apreq->param(QUOTA_ID_FIELD_NAME),enable=>$S->apreq->param(QUOTA_STATE_FIELD_NAME)) ) {
				$errstr = $quota_DB->getLastErrorString();
				$b_err = 1;
			}
			last SWITCH;
		}
		# show a selected rule
		if ( $sub_action == SA_SHOW_MODIFY ) {
			my (%hquota,$hkey,$hid,$hrsize,$hrunit);
			$hid = $S->apreq->param(QUOTA_ID_FIELD_NAME);
			if ( ! $quota_DB->get(id=>$hid,results=>\%hquota) ) {
				$errstr = $quota_DB->getLastErrorString();
				$b_err = 1;
			}
			$hkey = keys(%hquota);
			if ( $hkey > 0 ) {
				# fill modify template
				$T->param(FILEX_QUOTA_FORM_QUOTA_DESCRIPTION=>$hquota{'description'});
				$T->param(FILEX_QUOTA_FORM_QUOTA_ID=>$hid);
				$T->param(FILEX_QUOTA_FORM_QUOTA_QORDER=>$hquota{'qorder'});
				($hrsize,$hrunit) = hrSize($hquota{'max_file_size'});
				$selected_mfsunit = unit2idx($hrunit);
				$T->param(FILEX_QUOTA_FORM_QUOTA_MAX_FILE_SIZE=>round($hrsize));
				($hrsize,$hrunit) = hrSize($hquota{'max_used_space'});
				$selected_musunit = unit2idx($hrunit);
				$T->param(FILEX_QUOTA_FORM_QUOTA_MAX_USED_SPACE=>round($hrsize));
				$selected_rule = $hquota{'rule_id'};
				$form_sub_action = SA_MODIFY;
			}
			last SWITCH;
		}
		# modify a selected rule
		if ( $sub_action == SA_MODIFY ) {
			my $max_file_size = $self->getMaxFileSize();
			my $max_used_space = $self->getMaxUsedSpace();
			if ( ! $quota_DB->modify(id=>$S->apreq->param(QUOTA_ID_FIELD_NAME),
					description=>$S->apreq->param(QUOTA_DESCRIPTION_FIELD_NAME),
					rule_id=>$S->apreq->param(QUOTA_RULE_ID_FIELD_NAME),
					qorder=>$S->apreq->param(QUOTA_QORDER_FIELD_NAME),
					max_file_size=>$max_file_size,
					max_used_space=>$max_used_space) ) {
				$b_err = 1;
				$errstr = ( $quota_DB->getLastErrorCode() == 1062 ) ? $S->i18n->localize("rule already exists") : $quota_DB->getLastErrorString();
			}
			last SWITCH;
		}
	}
	if ( !defined($form_sub_action) ) {
		$form_sub_action = SA_ADD;
		# load default for max_file_size && max_used_space
		my ($hrsize,$hrunit) = hrSize($S->config->getMaxFileSize());
		$selected_mfsunit = unit2idx($hrunit);
		$T->param(FILEX_QUOTA_FORM_QUOTA_MAX_FILE_SIZE=>round($hrsize));
		($hrsize,$hrunit) = hrSize($S->config->getMaxUsedSpace());
		$selected_musunit = unit2idx($hrunit);
		$T->param(FILEX_QUOTA_FORM_QUOTA_MAX_USED_SPACE=>round($hrsize));
	}
	#
	# fill template
	#
	# loop on rule 
	my (@rules,@rules_loop);
	# selected_rule might be undef because the method check for it
	$quota_DB->listRules(results=>\@rules,including=>$selected_rule);
	for ( my $ridx = 0; $ridx <= $#rules; $ridx++ ) {
		my $record = {};
		$record->{'FILEX_QUOTA_RULE_ID'} = $rules[$ridx]->{'id'};
		$record->{'FILEX_QUOTA_RULE_NAME'} = $rules[$ridx]->{'name'};
		$record->{'FILEX_QUOTA_RULE_SELECTED'} = 1 if ( defined($selected_rule) && $selected_rule == $rules[$ridx]->{'id'} );
		push(@rules_loop,$record);
	}
	$T->param(FILEX_QUOTA_RULES_LOOP=>\@rules_loop);
	# unit table
	my @mfsunit_loop;
	for ( my $uidx = 0; $uidx <= unitLength(); $uidx++ ) {
		my $record = {};
		$record->{'FILEX_QUOTA_FORM_MFS_UNIT_ID'} = $uidx;
		$record->{'FILEX_QUOTA_FORM_MFS_UNIT_NAME'} = $S->i18n->localize(unitLabel($uidx));
		$record->{'FILEX_QUOTA_FORM_MFS_UNIT_SELECTED'} = 1 if ( defined($selected_mfsunit) && $selected_mfsunit == $uidx );
		push(@mfsunit_loop,$record);
	} 
	$T->param(FILEX_QUOTA_FORM_MFS_UNIT_LOOP=>\@mfsunit_loop);
	my @musunit_loop;
	for ( my $uidx = 0; $uidx <= unitLength(); $uidx++ ) {
		my $record = {};
		$record->{'FILEX_QUOTA_FORM_MUS_UNIT_ID'} = $uidx;
		$record->{'FILEX_QUOTA_FORM_MUS_UNIT_NAME'} = $S->i18n->localize(unitLabel($uidx));
		$record->{'FILEX_QUOTA_FORM_MUS_UNIT_SELECTED'} = 1 if ( defined($selected_musunit) && $selected_musunit == $uidx );
		push(@musunit_loop,$record);
	} 
	$T->param(FILEX_QUOTA_FORM_MUS_UNIT_LOOP=>\@musunit_loop);

	# the rest
	$T->param(FILEX_SUB_ACTION_ID=>$form_sub_action);
	if ( $b_err ) { 
		$T->param(FILEX_HAS_ERROR=>1);
		$T->param(FILEX_ERROR=>toHtml($errstr));
	}
	# already defined rules
	my (@results,@exclude_loop,$state,$hrsize,$hrunit);
	$b_err = $quota_DB->list(results=>\@results);
	if ($#results >= 0) {
		for (my $i=0; $i<=$#results; $i++) {
			my $record = {};
			$record->{'FILEX_QUOTA_DATE'} = tsToLocal($results[$i]->{'ts_create_date'});
			$record->{'FILEX_QUOTA_ORDER'} = $results[$i]->{'qorder'};
			$record->{'FILEX_QUOTA_DESCRIPTION'} = toHtml($results[$i]->{'description'}||'');
			$record->{'FILEX_QUOTA_STATE'} = ($results[$i]->{'enable'} == 1) ? $S->i18n->localizeToHtml("enable") : $S->i18n->localizeToHtml("disable");
			$record->{'FILEX_QUOTA_RULE'} = toHtml($results[$i]->{'rule_name'});
			($hrsize,$hrunit) = hrSize($results[$i]->{'max_file_size'});
			$record->{'FILEX_QUOTA_MAX_FILE_SIZE'} = "$hrsize ".$S->i18n->localizeToHtml($hrunit);
			($hrsize,$hrunit) = hrSize($results[$i]->{'max_used_space'});
			$record->{'FILEX_QUOTA_MAX_USED_SPACE'} = "$hrsize ".$S->i18n->localizeToHtml($hrunit);
			$state = $results[$i]->{'enable'};
			$record->{'FILEX_STATE_URL'} = toHtml($self->genStateUrl($results[$i]->{'id'}, ($state == 1) ? 0 : 1 ));
			$record->{'FILEX_REMOVE_URL'} = toHtml($self->genRemoveUrl($results[$i]->{'id'}));
			$record->{'FILEX_MODIFY_URL'} = toHtml($self->genModifyUrl($results[$i]->{'id'}));
			push(@exclude_loop,$record);
		}
		$T->param(FILEX_HAS_QUOTA=>1);
		$T->param(FILEX_QUOTA_LOOP=>\@exclude_loop);
	}
	return $T;
}

sub getMaxFileSize {
	my $self = shift;
	my $mfs_unit = $self->sys->apreq->param(QUOTA_MAX_FILE_SIZE_UNIT_FIELD_NAME) || 0;
	$mfs_unit = ( $mfs_unit > unitLength() ) ? 0 : $mfs_unit;
	my $max_file_size = $self->sys->apreq->param(QUOTA_MAX_FILE_SIZE_FIELD_NAME) || 0;
	$max_file_size = unit2byte(unitLabel($mfs_unit),round($max_file_size));
	return ( $max_file_size < 0 ) ? -1 : $max_file_size;
}

sub getMaxUsedSpace {
	my $self = shift;
	my $mus_unit = $self->sys->apreq->param(QUOTA_MAX_USED_SPACE_UNIT_FIELD_NAME) || 0;
	$mus_unit = ( $mus_unit > unitLength() ) ? 0 : $mus_unit;
	my $max_used_space = $self->sys->apreq->param(QUOTA_MAX_USED_SPACE_FIELD_NAME) || 0;
	$max_used_space = unit2byte(unitLabel($mus_unit),round($max_used_space));
	return ( $max_used_space < 0 ) ? -1 : $max_used_space;
}

# require : id,state
sub genStateUrl {
	my $self = shift;
	my $id = shift;
	my $enable = shift;
	my $sub_action = SUB_ACTION_FIELD_NAME;
	my $quota_id = QUOTA_ID_FIELD_NAME;
	my $quota_state = QUOTA_STATE_FIELD_NAME;
	my $url = $self->sys->getCurrentUrl();
	$url .= "?".$self->genQueryString(
			$sub_action=>SA_STATE,
			$quota_id=>$id,
			$quota_state=>$enable);
	return $url;
}

sub genModifyUrl {
	my $self = shift;
	my $id = shift;
	my $sub_action = SUB_ACTION_FIELD_NAME;
	my $quota_id = QUOTA_ID_FIELD_NAME;
	my $url = $self->sys->getCurrentUrl();
	$url .= "?".$self->genQueryString(
			$sub_action=>SA_SHOW_MODIFY,
			$quota_id=>$id);
	return $url;
}

sub genRemoveUrl {
	my $self = shift;
	my $id = shift;
	my $sub_action = SUB_ACTION_FIELD_NAME;
	my $quota_id = QUOTA_ID_FIELD_NAME;
	my $url = $self->sys->getCurrentUrl();
	$url .= "?".$self->genQueryString(
		$sub_action=>SA_DELETE,
		$quota_id=>$id);
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
