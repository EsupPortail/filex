package FILEX::DB::Admin::Exclude;
use strict;
use vars qw($VERSION @ISA @EXPORT_OK);
use FILEX::DB::base 1.0;
#use Exporter;
# inherit FILEX::DB::base
@ISA = qw(FILEX::DB::base Exporter);
$VERSION = 1.0;

# name => rule name
# rule_id => associated rule id
# rorder
# enable
sub add {
	my $self = shift;
	my %ARGZ = @_;
	$self->setLastError(query=>"",
                      string=>"Require a name",
	                    code=>-1) && return undef if ( !exists($ARGZ{'name'}) || !checkStr($ARGZ{'name'}) );
	$self->setLastError(query=>"",
	                    string=>"Require a rule_id",
	                    code=>-1) && return undef if ( !exists($ARGZ{'rule_id'}) || !checkStr($ARGZ{'rule_id'}) );
	delete($ARGZ{'rorder'}) if ( exists($ARGZ{'rorder'}) && !checkInt($ARGZ{'rorder'}) );
	$ARGZ{'enable'} = 1 if ( exists($ARGZ{'enable'}) && !checkBool($ARGZ{'enable'}) );
	my $dbh = $self->_dbh();
	my %fields = (
		'name' => $dbh->quote($ARGZ{'name'}),
		'rule_id' => $dbh->quote($ARGZ{'rule_id'}),
		'create_date' => "now()"
	);
	$fields{'rorder'} = $ARGZ{'rorder'} if exists($ARGZ{'rorder'});
	$fields{'enable'} = $ARGZ{'enable'} if exists($ARGZ{'enable'});
	my (@f,@v);
	foreach my $k ( keys(%fields) ) {
		push(@f,$k);
		push(@v,$fields{$k});
	}
	my $strQuery = "INSERT INTO exclude (".join(",",@f).") VALUES (".join(",",@v).")";
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
	                    string=>"Require a id",
	                    code=>-1) && return undef if ( !exists($ARGZ{'id'}) || !checkUInt($ARGZ{'id'}) );
	my $id = $ARGZ{'id'};
	delete($ARGZ{'id'});
	my %valid_fields = (
		rorder => { check => \&checkInt, quote=>0},
		enable => { check => \&checkBool, quote=>0},
		name => { check => \&checkStr, quote=>1},
		rule_id => 	{ check => \&checkUInt, quote=>0},
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
	my $strQuery = "UPDATE exclude SET ".join(",",@strSet)." WHERE id=$id";
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

sub checkStr {
	my $value = shift;
	return ( defined($value) && length($value) > 0 ) ? 1 : undef;
}

sub checkUInt {
	my $value = shift;
	return ( defined($value) && $value =~ /^[0-9]+$/ ) ? 1 : undef;
}
sub checkInt {
	my $value = shift;
	return ( defined($value) && $value =~ /^-?[0-9]+$/ ) ? 1 : undef;
}

sub checkType {
	my $value = shift;
	return ( defined($value) && grep($value == $_,getRuleTypes()) ) ? 1 : undef;
}

sub checkBool {
	my $value = shift;
	return ( defined($value) && $value =~ /^[0-1]$/ ) ? 1 : undef;
}

# id => rule id
# results => hash ref
sub get {
	my $self = shift;
	my %ARGZ = @_;
	$self->setLastError(query=>"",
	                    string=>"Require a id",
	                    code=>-1) && return undef if ( !exists($ARGZ{'id'}) || !checkUInt($ARGZ{'id'}) );
	$self->setLastError(query=>"",
	                    string=>"Require a results hashref",
	                    code=>-1) && return undef if ( !exists($ARGZ{'results'}) || ref($ARGZ{'results'}) ne "HASH");
	my $dbh = $self->_dbh();
	my $strQuery = "SELECT *,UNIX_TIMESTAMP(create_date) AS ts_create_date FROM exclude WHERE id = $ARGZ{'id'}";
	my $res = $ARGZ{'results'};
	eval {
		my $sth = $dbh->prepare($strQuery);
		$sth->execute();
		my $r = $sth->fetchrow_hashref();
		while ( my($k,$v) = each(%$r) ) {
			$res->{$k} = $v;
		}
		$sth->finish();
	};
	if ($@) {
		$self->setLastError(query=>$strQuery,string=>$dbh->errstr(),code=>$dbh->err());
		warn(__PACKAGE__,"-> Database Error : $@ : $strQuery");
		return undef;
	}
	return 1;
}

# list excludes (with underlying rule)
# enable => 1 (opt)
# results => ARRAY REF
sub list {
	my $self = shift;
	my %ARGZ = @_;
	$self->setLastError(query=>"",
	                    string=>"Require an ARRAY REF",
	                    code=>-1) && return undef if ( !exists($ARGZ{'results'}) || ref($ARGZ{'results'}) ne "ARRAY" );
	my $res = $ARGZ{'results'};
	my $enable = ( exists($ARGZ{'enable'}) && defined($ARGZ{'enable'}) ) ? 1 : 0;
	my $dbh = $self->_dbh();
	my $strQuery = "SELECT e.*, UNIX_TIMESTAMP(create_date) AS ts_create_date, ".
                 "r.name AS rule_name, r.exp AS rule_exp, r.type AS rule_type ".
                 "FROM exclude e,rules r ".
                 "WHERE  e.rule_id = r.id ";
	$strQuery .= "AND e.enable=1 " if ( $enable) ;
	$strQuery .= "ORDER BY e.rorder ASC";
	eval {
		my $sth = $dbh->prepare($strQuery);
		$sth->execute();
		while ( my $row = $sth->fetchrow_hashref() ) {
			push(@$res,$row);
		}
		$sth->finish();
	};
	if ($@) {
		$self->setLastError(query=>$strQuery,string=>$dbh->errstr(),code=>$dbh->err());
		warn(__PACKAGE__,"-> Database Error : $@ : $strQuery");
		return undef;
	}
	return 1;
}

# results
# including
sub listRules {
	my $self = shift;
	my %ARGZ = @_;
	$self->setLastError(query=>"",
                      string=>"Require an ARRAY REF",
                      code=>-1) && return undef if ( !exists($ARGZ{'results'}) || ref($ARGZ{'results'}) ne "ARRAY" );
	my $res = $ARGZ{'results'};
	my $include = ( exists($ARGZ{'including'}) && defined($ARGZ{'including'}) && $ARGZ{'including'} =~ /^[0-9]$/ ) ? $ARGZ{'including'} : undef;
	my $dbh = $self->_dbh();
	# the left join 
	# all row from the the rules table will be returned 
	# even if there are no match in the exclude table
	# a NULL value for the exclude table is returned if there is no match
	# so if we had a condition where exclude.rule_id IS NULL, we got only
	# rules row which are not in exclude.
	my $strQuery = "SELECT rules.* FROM rules ".
                 "LEFT JOIN exclude ON rules.id = exclude.rule_id ".
                 "WHERE exclude.rule_id IS NULL";
	$strQuery .= " OR exclude.rule_id = $include" if defined($include);
	eval {
		my $sth = $dbh->prepare($strQuery);
		$sth->execute();
		while ( my $row = $sth->fetchrow_hashref() ) {
			push(@$res,$row);
		}
		$sth->finish();
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
	my $strQuery = "DELETE FROM exclude WHERE id=$id";
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
