package FILEX::System::RuleMatcherBase;
use strict;
use vars qw($VERSION);
$VERSION = 1.0;

sub isRuleMatching {
    warn(__PACKAGE__,"-> isRuleMatching method need to be overriden and must return 0 or 1");
}

sub findRuleMatching {
   my $self = shift;
   my $uid = shift;
   my $rules = shift;

   foreach my $rule (@$rules) {
       if ($self->isRuleMatching($uid, $rule)) {
	   return $rule;
       }
   }
   return undef;
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
