package FILEX::System::I18N;
use strict;
use vars qw($VERSION);
use Config::IniFiles;
use HTML::Entities ();

$VERSION = 1.0;

use constant SECI18N => "i18n";

# inifile =>
# [opt] lang =>
sub new {
	my $this = shift;
	my $class = ref($this) || $this;

	my $self = {
		inifile => undef,
		lang => undef,
		_config_ => undef,
	};

	my %ARGZ = @_;
	# do not die
	warn(__PACKAGE__,"-> Require an initialization file") if ! exists($ARGZ{'inifile'});
	$self->{'inifile'} = $ARGZ{'inifile'};
	# load inifile
	$self->{'_config_'} = Config::IniFiles->new(-file=>$self->{'inifile'},
	                      -reloadwarn=>1);
	warn(__PACKAGE__,"-> Unable to load config file : ",$self->{'inifile'}) if !$self->{'_config_'};
	# check if we have a lang
	$self->{'lang'} = $ARGZ{'lang'} if exists($ARGZ{'lang'});
	
	bless($self,$class);
	return $self;
}

# check if lang exists in file
sub langExists {
	my $self = shift;
	my $lang = shift;
	return undef if !$lang;
	return $self->{'_config_'}->SectionExists($lang);
}

# set default lang
# return old lang
sub setLang {
	my $self = shift;
	my $lang = shift;
	my $old = $self->{'lang'};
	$self->{'lang'} = $lang if $lang;
	return $old;
}

# localize
# first arg : string to localize
# next args : interpolated strings
sub localize {
	my $self = shift;
	my $inloc = shift;
	my $c = $self->{'_config_'};
	my $outloc;

	# first check if section for current language exists
	if ( $c ) {
		# load the string
		$outloc = $c->val($self->{'lang'},$inloc) if ( $c->SectionExists($self->{'lang'}) );
		# try with the default if any
		$outloc = $c->val($c->val(SECI18N,"Default"),$inloc) if ( !$outloc && $c->SectionExists(SECI18N) );
	}
	# else outloc = inloc
	$outloc = $inloc if !$outloc;
	return sprintf($outloc,@_);
}

sub localizeToHtml {
	my $self = shift;
	return HTML::Entities::encode_entities($self->localize(@_));
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
