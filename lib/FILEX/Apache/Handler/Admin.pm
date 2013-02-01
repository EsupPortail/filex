package FILEX::Apache::Handler::Admin;
use strict;
use vars qw($VERSION);

# Apache
use Apache::Constants qw(:common);
use Apache::Request;

# FILEX
use FILEX::System;

# Admins Modules
use FILEX::Apache::Handler::Admin::Dispatcher;

$VERSION = 1.0;

# the main handler
sub handler {
	my $S; # FILEX::System
	my $DB; # FILEX::DB::Admin
	my $disp; # the event dispatcher
	my $main_template; # the Main admin template
	# Auth
	$S = FILEX::System->new(shift);
	my $user = $S->beginSession();
	# verify if admin
	if ( !$S->isAdmin($user) ) {
		$S->denyAccess();
	}
	# create the dispatcher
	$disp = FILEX::Apache::Handler::Admin::Dispatcher->new($S);
	# switch menu action
	my $main_action = $disp->getDefaultDispatch($S->apreq->param($disp->getDispatchName()));
	# go action
	my ($T,$passthru) = $disp->dispatch($main_action);
	# fill the main template part if required
	if ( !$passthru ) {
		# load the main template
		$main_template = $S->getTemplate(name=>"admin");
		do_action_menu($S,$main_template,$disp,$main_action); 
		$main_template->param(FILEX_MAIN_CONTENT=>$T->output());
		$main_template->param(FILEX_SYSTEM_EMAIL=>$S->config->getSystemEmail());
		$main_template->param(FILEX_USER_NAME=>$S->toHtml($user->getRealName()));
		$main_template->param(FILEX_UPLOAD_URL=>$S->toHtml($S->getUploadUrl()));
	} else {
		$main_template = $T;
	}
	display($S,$main_template);# if $T;
	return OK;
}

# display
sub display {
	my $S = shift;
	my $T = shift;
	# base for static include
	$T->param(FILEX_STATIC_FILE_BASE=>$S->getStaticUrl()) if ( $T->query(name=>'FILEX_STATIC_FILE_BASE') );
	$S->sendHeader("Content-Type"=>"text/html");
	$S->apreq->print($T->output()) if ( ! $S->apreq->header_only() );
	exit(OK);
}

# do form menu
sub do_action_menu {
	my $s = shift;
	my $t = shift; # HTML::Template
	my $disp = shift; # dispatcher
	my $ca = shift; # current menu action
	my @form_menu;
	my $k;
	foreach $k ( $disp->enumDispatch() ) {
		my $r = {
			FILEX_FORM_MENU_OPT_VALUE=>$k,
			FILEX_FORM_MENU_OPT_LABEL=>$s->i18n->localizeToHtml($disp->getDispatchLabel($k))
		};
		# current action
		$r->{'FILEX_FORM_MENU_OPT_SELECTED'} = 1 if ( $ca eq $k );
		push(@form_menu,$r);
	}
	# the form action
	$t->param(FILEX_FORM_SELECT_FIELD_NAME=>$disp->getDispatchName());
	$t->param(FILEX_FORM_MENU_ACTION=>$s->getCurrentUrl());
	# the menu
	$t->param(FILEX_ACTION_MENU_LOOP=>\@form_menu);
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
