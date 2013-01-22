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

# rule type
our $RULE_TYPE_DN = 1;
our $RULE_TYPE_GROUP = 2;
our $RULE_TYPE_UID = 3;
our $RULE_TYPE_LDAP = 4;
our $RULE_TYPE_SHIB = 5;

my %RULE_TYPES = (
  $RULE_TYPE_DN => "DN",
  $RULE_TYPE_GROUP => "GROUP",
	$RULE_TYPE_UID => "UID",
	$RULE_TYPE_LDAP => "LDAP",
	$RULE_TYPE_SHIB => "SHIB",
);


# exported functions
sub getRuleTypes {
    my ($isShib) = @_;
    $isShib ? $RULE_TYPE_SHIB : grep { $_ != $RULE_TYPE_SHIB } keys(%RULE_TYPES);
}

sub getRuleTypeName {
  my $rid = shift;
  return exists($RULE_TYPES{$rid}) ? $RULE_TYPES{$rid} : undef;
}

# name => rule name
# exp => expresion
# type => rule type
# return rule insert id
sub add {
	my $self = shift;
	my %ARGZ = @_;
	$self->setLastError(query=>"",
                      string=>"require a rule name",
	                    code=>-1) && return undef if ( !exists($ARGZ{'name'}) || !$self->checkStr($ARGZ{'name'}) );
	$self->setLastError(query=>"",
	                    string=>"require a rule",
	                    code=>-1) && return undef if ( !exists($ARGZ{'exp'}) || !$self->checkStr($ARGZ{'exp'}) );
	$self->setLastError(query=>"",
	                    string=>"require a type",
                      code=>-1) && return undef if ( !exists($ARGZ{'type'}) || !checkType($self, $ARGZ{'type'}) );
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
	my $insertId = undef;
	eval {
		my $sth = $dbh->prepare($strQuery);
		$sth->execute();
		$insertId = $dbh->{'mysql_insertid'};
		$dbh->commit();
	};
	if ($@) {
		$self->setLastError(query=>$strQuery,string=>$dbh->errstr(),code=>$dbh->err());
		warn(__PACKAGE__,"-> Database Error : $@ : $strQuery");
		return undef;
	}
	return $insertId;
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
		type => { check => sub { $self->checkType(shift) }, quote=>0},
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
	return $self->doQuery($strQuery);
}

sub checkType {
	my $self = shift;
	my $value = shift;
	my @ruleTypes = getRuleTypes($self->_config->isShib);
	return ( defined($value) && grep($value == $_, @ruleTypes) ) ? 1 : undef;
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
	my $strQuery = "SELECT * FROM rules";
	my $rows = $self->queryAllRows($strQuery) or return undef;
	push(@$res, @$rows);
	return 1;
}

# extended list of rules 
sub listEx {
	my $self = shift;
	my $res = shift;
	$self->setLastError(query=>"",
	                    string=>"Require an ARRAY REF",
	                    code=>-1) && return undef if (ref($res) ne "ARRAY");
	my $strQuery = "SELECT r.*, count(e.rule_id) AS exclude, ".
		"count(q.rule_id) AS quota, count(b.rule_id) AS big_brother ".
		"FROM rules r ".
		"LEFT JOIN exclude e ON r.id = e.rule_id ".
		"LEFT JOIN quota q ON r.id = q.rule_id ".
		"LEFT JOIN big_brother b ON r.id = b.rule_id ".
		"GROUP BY r.id";
	my $rows = $self->queryAllRows($strQuery) or return undef;
	push(@$res, @$rows);
	return 1;
}

# delete a rule
# require an id
sub del {
	my $self = shift;
	my $id = shift;
	my $strQuery = "DELETE FROM rules WHERE id=$id";
	return $self->doQuery($strQuery);
}

# type=>rule type
# exp => rule expession
# or 
# name => rule name
#
# return : 
# undef on error
# -1 if not exists
# rule id if exists
sub exists {
	my $self = shift;
	my %ARGZ = @_;
	my %fields = ();
	my $dbh = $self->_dbh();
	if ( exists($ARGZ{'name'}) ) {
		$fields{'name'} = $dbh->quote($ARGZ{'name'});
	} elsif ( exists($ARGZ{'type'}) && exists($ARGZ{'type'}) ) {
		$fields{'exp'} = $dbh->quote($ARGZ{'exp'});
		$fields{'type'} = $ARGZ{'type'};
	} else {
		warn(__PACKAGE__,"=> must be called either with type=>xx,exp=>xx or name=>xx");
		return undef;
	}
	my $strQuery = "SELECT id FROM rules WHERE ";
	my $strQueryNext = undef;
	foreach my $k ( keys(%fields) ) {
		$strQueryNext .= " AND " if  defined($strQueryNext);
		$strQueryNext .= sprintf("%s = %s",$k,$fields{$k});
	}
	if ( !defined($strQueryNext) ) {
		warn(__PACKAGE__,"=> no field set for query !");
		return undef;
	}
	$strQuery .= $strQueryNext;
	my $result = undef;
	eval {
		my $sth = $dbh->prepare($strQuery);
		$sth->execute();
		$result = $sth->fetchrow()||-1;
		$sth->finish();
	};
	if ($@) {
		$self->setLastError(query=>$strQuery,string=>$dbh->errstr(),code=>$dbh->err());
		warn(__PACKAGE__,"=> Database Error : $@ : $strQuery");
		return undef;
	}
	return $result;
}

# delete rules without associations
sub delNoAssoc {
	my $self = shift;
	my $strQuery = "DELETE rules ".
		"FROM rules ".
		"LEFT JOIN exclude ON rules.id = exclude.rule_id ".
		"LEFT JOIN quota ON rules.id = quota.rule_id ".
		"LEFT JOIN big_brother ON rules.id = big_brother.rule_id ".
		"WHERE exclude.rule_id IS NULL ".
		"AND quota.rule_id IS NULL ".
		"AND big_brother.rule_id IS NULL";
	return $self->doQuery($strQuery);
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
