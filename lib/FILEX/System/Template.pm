package FILEX::System::Template;
use strict;
use vars qw($VERSION);

use Config::IniFiles;
use HTML::Template;

$VERSION = 1.0;

use constant SECTEMPLATE => "Template";

# inifile => template initialization file
# [opt] lang => default lang
sub new {
	my $this = shift;
	my $class = ref($this) || $this;
	my $self = {
		inifile => undef,
		lang => undef,
		_config_ => undef,
	};
	my %ARGZ = @_;
	die(__PACKAGE__,"-> Require a template inititialization file") if ! exists($ARGZ{'inifile'});
	$self->{'inifile'} = $ARGZ{'inifile'};
	# load inifile
	$self->{'_config_'} = Config::IniFiles->new(-file=>$self->{'inifile'},
                 -reloadwarn=>1) || die(__PACKAGE__,"-> Unable to load config file : ",$self->{'inifile'});
	# last argz
	$self->{'lang'} = $ARGZ{'lang'} if exists($ARGZ{'lang'}); 

	return bless($self,$class);
}

# set language
# return old language
sub setLang {
	my $self = shift;
	my $lang = shift;
	my $old = $self->{'lang'};
	$self->{'lang'} = $lang if $lang;
	return $old;
}

# check if lang exists
sub langExists {
	my $self = shift;
	my $lang = shift;
	return undef if !$lang;
	return $self->{'_config_'}->SectionExists($lang);
}

# name
# return undef if template not found !
sub getTemplate {
	my $self = shift;
	my %ARGZ = @_;
	my $c = $self->{'_config_'};
	return undef if ! exists($ARGZ{'name'});
	my $name = $ARGZ{'name'};
	my $template = undef;
	$template = $c->val($self->{'lang'},$name);
	# do not have template then attempt to load default
	$template = $c->val($c->val(SECTEMPLATE,"Default"),$name) if ( !$template );
	return undef if ( !$template );
	# now try to load the template
	my $t = eval { HTML::Template->new(filename=>$template,
	                            path=>$self->getTemplatePath(),
	                            die_on_bad_params=>1,
	                            loop_context_vars=>1,
	                            cache=>1);
	        };
	if ($@) {
		warn(__PACKAGE__,"-> Unable to load Template $template : $@");
		return undef;
	}
	return $t;
}

# helper
sub getTemplatePath {
	my $self = shift;
	return $self->{'_config_'}->val(SECTEMPLATE,"Path");
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
