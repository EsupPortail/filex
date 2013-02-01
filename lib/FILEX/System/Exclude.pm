package FILEX::System::Exclude;
use strict;
use vars qw($VERSION);
$VERSION = 1.0;

# other libs
use FILEX::DB::Admin::Exclude;
use FILEX::System::LDAP;

# sortir DnExclude de Auth.pm
# [ldap=>FILEX::System::LDAP object]
sub new {
	my $this = shift;
	my $class = ref($this) || $this;
	my %ARGZ = @_;
	my $self = {
		username => undef,
		_ldap_ => undef,
		_exclude_ => undef,
	};
	# ldap
	if ( exists($ARGZ{'ldap'}) && ref($ARGZ{'ldap'}) eq "FILEX::System::LDAP" ) {
		$self->{'_ldap_'} = $ARGZ{'ldap'};
	} else {
		$self->{'_ldap_'} = eval { FILEX::System::LDAP->new(); };
		warn(__PACKAGE__,"=> unable to load FILEX::System::LDAP : $@") && return undef if ($@);
	}
	# dnexclude
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
	# now for each rules 
	my $bIsExclude = 0;
	my $excludeReason;
	for (my $i = 0; $i <= $#rules; $i++) {
		# switch rule type (1=DN, 2=GROUP)
		SWITCH : {
			# user's DN
			if ( $rules[$i]->{'rule_type'} == 1 ) {
				$bIsExclude = $self->isDnExclude($uid,$rules[$i]->{'rule_exp'});
				$excludeReason = $rules[$i]->{'reason'};
				last SWITCH;
			}
			# groups
			if ( $rules[$i]->{'rule_type'} == 2 ) {
				$bIsExclude = $self->{'_ldap_'}->inGroup(uid=>$uid,gid=>$rules[$i]->{'rule_exp'});
				$excludeReason = $rules[$i]->{'reason'};
				last SWITCH;
			}
			# users UID
			if ( $rules[$i]->{'rule_type'} == 3 ) {
				$bIsExclude = ( $uid eq $rules[$i]->{'rule_exp'} ) ? 1 : 0;
				$excludeReason = $rules[$i]->{'reason'};
				last SWITCH;
			}
			# ldap query
			if ( $rules[$i]->{'rule_type'} == 4 ) {
				$bIsExclude = $self->{'_ldap_'}->inQuery(uid=>$uid,query=>$rules[$i]->{'rule_exp'});
				$excludeReason = $rules[$i]->{'reason'};
				last SWITCH;
			}
			warn(__PACKAGE__,"-> unknown rule type (",$rules[$i]->{'rule_type'},") : ",$rules[$i]->{'rule_exp'});
		}
		last if ($bIsExclude);
	}
	# return
	return wantarray?($bIsExclude,$excludeReason):$bIsExclude;
}

# load rules
# check if given Dn Excluded
sub isDnExclude {
  my $self = shift;
  my $uid = shift;
	my $rule = shift;
	return 0 if (!$rule || length($rule) <= 0);
	# get DN for this user
	my $dn = $self->{'_ldap_'}->getUserDn($uid);
	return ( $dn =~ qr/$rule/i ) ? 1 : 0;
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
