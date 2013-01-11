package FILEX::System::Exclude;
use strict;
use vars qw($VERSION);
$VERSION = 1.0;

# other libs
use FILEX::DB::Admin::Exclude;
use FILEX::System::LDAP;

sub new {
	my $this = shift;
	my $class = ref($this) || $this;
	my %ARGZ = @_;
	my $self = {
	};
	$self->{'_ruleMatcher_'} = $ARGZ{'ruleMatcher'} or die(__PACKAGE__," => ruleMatcher is mandatory!");

	$self->{'_exclude_'} = eval { FILEX::DB::Admin::Exclude->new(); };
	warn(__PACKAGE__,"=> unable to load FILEX::DB::Admin::Exclude : $@") && return undef if ($@);
	return bless($self,$class);
}

# check if a given user is excluded
# require : a username
# return 1 if excluded
sub isExclude {
	my $self = shift;
	my $uid = shift;
	return 0 if (!$uid || length($uid) <= 0);
	# list all rules
	my @rules;
	if ( ! $self->{'_exclude_'}->list(enable=>1,expired=>0,results=>\@rules) ) {
		warn(__PACKAGE__,"-> Unable to list Rules");
		# exclude all
		return 1;
	}
	my $bIsExclude = 0;
	my $excludeReason;
	if (my $rule = $self->{_ruleMatcher_}->findRuleMatching($uid, \@rules)) {
	    $bIsExclude = 1;
	    $excludeReason = $rule->{'reason'};
	}
	return wantarray?($bIsExclude,$excludeReason):$bIsExclude;
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
