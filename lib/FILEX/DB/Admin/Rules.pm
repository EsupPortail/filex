package FILEX::DB::Admin::Rules;
use strict;
use vars qw($VERSION @ISA @EXPORT_OK);
use FILEX::DB::base 1.0;
use Exporter;
# inherit FILEX::DB::base
@ISA = qw(FILEX::DB::base Exporter);
$VERSION = 1.0;

# exporter part
@EXPORT_OK = qw(
  getRuleTypes
  getRuleTypeName
);

my %RULE_TYPES = (
  1 => "DN",
  2 => "GROUP",
	3 => "UID",
	4 => "LDAP"
);

# exported functions
sub getRuleTypes {
  return keys(%RULE_TYPES);
}

sub getRuleTypeName {
  my $rid = shift;
  return exists($RULE_TYPES{$rid}) ? $RULE_TYPES{$rid} : undef;
}

# name => rule name
# exp => expresion
# type => rule type
sub add {
	my $self = shift;
	my %ARGZ = @_;
	$self->setLastError(query=>"",
                      string=>"Require a rule name",
	                    code=>-1) && return undef if ( !exists($ARGZ{'name'}) || !$self->checkStr($ARGZ{'name'}) );
	$self->setLastError(query=>"",
	                    string=>"Require a exp",
	                    code=>-1) && return undef if ( !exists($ARGZ{'exp'}) || !$self->checkStr($ARGZ{'exp'}) );
	$self->setLastError(query=>"",
	                    string=>"Require a type",
                      code=>-1) && return undef if ( !exists($ARGZ{'type'}) || !checkType($ARGZ{'type'}) );
	my $dbh = $self->_dbh();
	my %fields = (
		'name' => $dbh->quote($ARGZ{'name'}),
		'exp' => $dbh->quote($ARGZ{'exp'}),
		'type' => $ARGZ{'type'}
	);
	my (@f,@v);
	foreach my $k ( keys(%fields) ) {
		push(@f,$k);
		push(@v,$fields{$k});
	}
	my $strQuery = "INSERT INTO rules (".join(",",@f).") VALUES (".join(",",@v).")";
	eval {
		my $sth = $dbh->prepare($strQuery);
		$sth->execute();
		$dbh->commit();
	};
	if ($@) {
		$self->setLastError(query=>$strQuery,string=>$dbh->errstr(),code=>$dbh->err());
		warn(__PACKAGE__,"-> Database Error : $@ : $strQuery");
		return undef;
	}
	return 1;
}

sub modify {
	my $self = shift;
	my %ARGZ = @_;
	$self->setLastError(query=>"",
	                    string=>"Require a rule id",
	                    code=>-1) && return undef if ( !exists($ARGZ{'id'}) || !$self->checkUInt($ARGZ{'id'}) );
	my $id = $ARGZ{'id'};
	delete($ARGZ{'id'});
	my %valid_fields = (
		name => { check => sub { $self->checkStr(shift); }, quote=>1},
		exp => 	{ check => sub { $self->checkStr(shift); }, quote=>1},
		type => { check => \&checkType, quote=>0},
	);
	my $dbh = $self->_dbh();
	my (@strSet);
	foreach my $k ( keys(%ARGZ) ) {
		warn(__PACKAGE__,"->invalid field name : $k") && next if ( ! grep($k eq $_,keys(%valid_fields)) );
		# check for the field
		if ( defined($valid_fields{$k}->{'check'}) ) {
			$self->setLastError(query=>"",
			                    string=>"invalid field format : $k",
			                    code=>-1) && return undef if !$valid_fields{$k}->{'check'}->($ARGZ{$k});
		}
		# quote if needed
		if ( $valid_fields{$k}->{'quote'} ) {
			push(@strSet,"$k=".$dbh->quote($ARGZ{$k}));
		} else {
			push(@strSet,"$k=$ARGZ{$k}");
		}
	}
	return if ($#strSet < 0);
	my $strQuery = "UPDATE rules SET ".join(",",@strSet)." WHERE id=$id";
	eval {
		my $sth = $dbh->prepare($strQuery);
		$sth->execute();
		$dbh->commit();
	};
	if ($@) {
		$self->setLastError(query=>$strQuery,string=>$dbh->errstr(),code=>$dbh->err());
		warn(__PACKAGE__,"-> Database Error : $@ : $strQuery");
		return undef;
	}
	return 1;
}

sub checkType {
	my $value = shift;
	return ( defined($value) && grep($value == $_,getRuleTypes()) ) ? 1 : undef;
}

# id => rule id
# results => hash ref
sub get {
	my $self = shift;
	my %ARGZ = @_;
	$self->setLastError(query=>"",
	                    string=>"Require a rule id",
	                    code=>-1) && return undef if ( !exists($ARGZ{'id'}) || !$self->checkUInt($ARGZ{'id'}) );
	$self->setLastError(query=>"",
	                    string=>"Require a results hashref",
	                    code=>-1) && return undef if ( !exists($ARGZ{'results'}) || ref($ARGZ{'results'}) ne "HASH");
	my $dbh = $self->_dbh();
	my $strQuery = "SELECT * FROM rules WHERE id = $ARGZ{'id'}";
	my $res = $ARGZ{'results'};
	eval {
		my $sth = $dbh->prepare($strQuery);
		$sth->execute();
		my $r = $sth->fetchrow_hashref();
		while ( my($k,$v) = each(%$r) ) {
			$res->{$k} = $v;
		}
	};
	if ($@) {
		$self->setLastError(query=>$strQuery,string=>$dbh->errstr(),code=>$dbh->err());
		warn(__PACKAGE__,"-> Database Error : $@ : $strQuery");
		return undef;
	}
	return 1;
}

# list rules
sub list {
	my $self = shift;
	my $res = shift;
	$self->setLastError(query=>"",
	                    string=>"Require an ARRAY REF",
	                    code=>-1) && return undef if (ref($res) ne "ARRAY");
	my $dbh = $self->_dbh();
	my $strQuery = "SELECT * FROM rules";
	eval {
		my $sth = $dbh->prepare($strQuery);
		$sth->execute();
		while ( my $row = $sth->fetchrow_hashref() ) {
			push(@$res,$row);
		}
	};
	if ($@) {
		$self->setLastError(query=>$strQuery,string=>$dbh->errstr(),code=>$dbh->err());
		warn(__PACKAGE__,"-> Database Error : $@ : $strQuery");
		return undef;
	}
	return 1;
}

# delete a rule
# require an id
sub del {
	my $self = shift;
	my $id = shift;
	my $dbh = $self->_dbh();
	my $strQuery = "DELETE FROM rules WHERE id=$id";
	my ($res,$sth);
	eval {
		$sth = $dbh->prepare($strQuery);
		$res = $sth->execute();
		$dbh->commit();
	};
	if ($@) {
		$self->setLastError(query=>$strQuery,string=>$dbh->errstr(),code=>$dbh->err());
		warn(__PACKAGE__,"-> Database Error : $@ : $strQuery");
		return undef;
	}
	return 1;
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
