package FILEX::System::RuleMatcherShib;
use strict;
use vars qw(@ISA $VERSION);
use FILEX::DB::Admin::Rules;
use FILEX::System::RuleMatcherBase;

@ISA = qw(FILEX::System::RuleMatcherBase);
$VERSION = 1.0;


sub new {
	my $this = shift;
	my $class = ref($this) || $this;
	my %ARGZ = @_;
	my $self = {};
	$self->{'_attrs_'} = $ARGZ{'attrs'} or die(__PACKAGE__," => attrs is mandatory!");
	return bless($self,$class);
}

sub attrs {
    my ($self) = @_;
    return $self->{_attrs_};
}

sub isRuleMatching {
    my $self = shift;
    my $uid = shift;
    my $rule = shift;

    if ( $rule->{'rule_type'} == $FILEX::DB::Admin::Rules::RULE_TYPE_SHIB ) {
	my $re = $rule->{'rule_exp'};
	my $b = $self->{_attrs_} =~ /$re/ms;
	#warn "$re ", $b ? "matches": "do not match", " ", $self->{_attrs_};
	return $b;
    } else {
	warn(__PACKAGE__,"-> unknown rule type (",$rule->{'rule_type'},") : ",$rule->{'rule_exp'});
	return 0;
    }
}


1;
=pod

=head1 AUTHOR AND COPYRIGHT

FileX - a web file exchange system.

Copyright (c) 2013 - Pascal Rigaux

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
