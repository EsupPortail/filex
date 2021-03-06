package FILEX::System::Quota;
use strict;
use vars qw($VERSION);
$VERSION = 1.0;

# other libs
use FILEX::DB::Admin::Quota;
use FILEX::System::LDAP;
use FILEX::System::Config;

sub new {
	my $this = shift;
	my $class = ref($this) || $this;
	my %ARGZ = @_;
	my $self = {
	};
	$self->{'_config_'} = FILEX::System::Config->instance();

	$self->{'_ruleMatcher_'} = $ARGZ{'ruleMatcher'} or die(__PACKAGE__," => ruleMatcher is mandatory!");

	$self->{'_quota_'} = eval { FILEX::DB::Admin::Quota->new(); };
	warn(__PACKAGE__,"=> unable to load FILEX::DB::Admin::Quota : $@") && return undef if ($@);
	return bless($self,$class);
}

# check if a given user have quota
# require : a username
# return (max_file_size, max_used_space)
# if max_file_size < 0 then no quota
# if max_used_space < 0 then no quota for max space
# if max_used_space == 0 || max_file_size == 0 then unable to upload
sub getQuota {
	my $self = shift;
	my $uid = shift;
	my ($quota_max_file_size,$quota_max_used_space);
	my ($config_max_file_size,$config_max_used_space);
	# default quota goes to config ones;
	$quota_max_file_size = $self->{'_config_'}->getMaxFileSize();
	$quota_max_used_space = $self->{'_config_'}->getMaxUsedSpace();
	# no uid then nothing
	return (0,0) if ( !$uid || length($uid) <= 0);
	# list all rules
	my @rules;
	if ( ! $self->{'_quota_'}->list(enable=>1,results=>\@rules) ) {
		warn(__PACKAGE__,"-> Unable to list Rules");
		# unable to list rules then default to config ones
		return ($quota_max_file_size,$quota_max_used_space);
	}
	if (my $rule = $self->{_ruleMatcher_}->findRuleMatching($uid, \@rules)) {
	    $quota_max_file_size = $rule->{'max_file_size'};
	    $quota_max_used_space = $rule->{'max_used_space'};
	}
	return ($quota_max_file_size,$quota_max_used_space);
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
