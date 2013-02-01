package FILEX::Apache::Handler::Admin::UsrAdmin;
use strict;
use vars qw(@ISA $ACTION_ID $ACTION_LABEL);
use FILEX::Apache::Handler::Admin::base;
@ISA = qw(FILEX::Apache::Handler::Admin::base);

use constant SA_DELETE => 1;
use constant SA_STATE => 2;
use constant SA_ADD => 3;

use constant SUB_ACTION_FIELD_NAME => "sa";
use constant USR_ADMIN_ADD_FIELD_NAME=>"adduser";
use constant USER_ID_FIELD_NAME=>"id";
use constant STATE_FIELD_NAME=>"state";

use FILEX::DB::Admin::UsrAdmin;
use FILEX::Tools::Utils qw(toHtml);

sub process {
	my $self = shift;
	my ($b_err,$errstr);
	my $S = $self->sys();
	my $T = $S->getTemplate(name=>"admin_usradmin");
	# fill template
	$T->param(FILEX_USR_ADMIN_FORM_ACTION=>$S->getCurrentUrl());
	$T->param(FILEX_MAIN_ACTION_FIELD_NAME=>$self->getDispatchName());
	$T->param(FILEX_MAIN_ACTION_ID=>$self->getActionId());
	$T->param(FILEX_SUB_ACTION_FIELD_NAME=>SUB_ACTION_FIELD_NAME);
	$T->param(FILEX_USR_ADMIN_ADD_FIELD_NAME=>USR_ADMIN_ADD_FIELD_NAME);
	$T->param(FILEX_SUB_ACTION_ID=>SA_ADD);
	# database
	my $DB = eval { FILEX::DB::Admin::UsrAdmin->new(); };
	if ($@) {
		$T->param(FILEX_HAS_ERROR=>1);
		$T->param(FILEX_ERROR=>$S->i18n->localizeToHtml("database error %s",$DB->getLastErrorString()));
		return $T;
	}
	# is there a sub action
	my $sub_action = $S->apreq->param(SUB_ACTION_FIELD_NAME) || -1;
	SWITCH : {
		if ( $sub_action == SA_ADD ) {
			# check if user exists
			if ( ! $S->ldap->userExists($S->apreq->param(USR_ADMIN_ADD_FIELD_NAME)) ) {
				$errstr = $S->i18n->localize("user does not exists");
				$b_err = 1;
			}
			if ( !$b_err && !$DB->addUser($S->apreq->param(USR_ADMIN_ADD_FIELD_NAME)) ) {
				$errstr = ( $DB->getLastErrorCode() == 1062 ) ? $S->i18n->localize("user already exists") : $DB->getLastErrorString();
				$b_err = 1;
			}
			last SWITCH;
		}
		if ( $sub_action == SA_DELETE ) {
			if ( ! $DB->delUser($S->apreq->param(USER_ID_FIELD_NAME)) ) {
				$errstr = $DB->getLastErrorString(); 
				$b_err = 1;
			}
			last SWITCH;
		}
		if ( $sub_action == SA_STATE ) {
			if ( ! $DB->setEnable($S->apreq->param(USER_ID_FIELD_NAME),$S->apreq->param(STATE_FIELD_NAME)) ) {
				$errstr = $DB->getLastErrorString();
				$b_err = 1;
			}
			last SWITCH;
		}
		# default action if needed
	}
	if ( $b_err ) {
		$T->param(FILEX_HAS_ERROR=>1);
		$T->param(FILEX_ERROR=>toHtml($errstr));
	}
	my (@results,@loop,$delurl,$stateurl,$state);
	$DB->listUsers(\@results);
	if ($#results >= 0) {
		for (my $i=0; $i<=$#results; $i++) {
			$delurl = $self->genDeleteUrl($results[$i]->{'id'});
			$state = $results[$i]->{'enable'};
			$stateurl = $self->genActivateUrl($results[$i]->{'id'}, ($state == 1) ? 0 : 1 );
			push(@loop, {
					FILEX_ADMIN_UID=>$results[$i]->{'uid'},
					FILEX_ADMIN_INFOS=>toHtml($S->getUserRealName($results[$i]->{'uid'})),
					FILEX_ADMIN_MAIL=>$S->getMail($results[$i]->{'uid'}),
					FILEX_ADMIN_STATE=>( $state ) ? $S->i18n->localizeToHtml("enable") : $S->i18n->localizeToHtml("disable"),
					FILEX_REMOVE_URL=>toHtml($delurl),
					FILEX_STATE_URL=>toHtml($stateurl)
			});
			$T->param(FILEX_HAS_ADMINS=>1);
			$T->param(FILEX_ADMINS_LOOP=>\@loop);
		}
	}
	return $T;
}

# require : id,state
sub genActivateUrl {
	my $self = shift;
	my $id = shift;
	my $enable = shift;
	my $sub_action = SUB_ACTION_FIELD_NAME;
	my $user_id_field = USER_ID_FIELD_NAME;
	my $state_field = STATE_FIELD_NAME;
	my $url = $self->sys->getCurrentUrl();
	$url .= "?".$self->genQueryString(
			$sub_action=>SA_STATE,
			$user_id_field=>$id,
			$state_field=>$enable);
	return $url;
}

sub genDeleteUrl {
	my $self = shift;
	my $id = shift;
	my $sub_action = SUB_ACTION_FIELD_NAME;
	my $user_id_field = USER_ID_FIELD_NAME;
	my $url = $self->sys->getCurrentUrl();
	$url .= "?".$self->genQueryString(
		$sub_action=>SA_DELETE,
		$user_id_field=>$id);
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
