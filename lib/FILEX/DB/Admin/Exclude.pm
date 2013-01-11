package FILEX::DB::Admin::Exclude;
use strict;
use vars qw($VERSION @ISA @EXPORT_OK);
use FILEX::DB::base 1.0;
#use Exporter;
# inherit FILEX::DB::base
@ISA = qw(FILEX::DB::base Exporter);
$VERSION = 1.0;

# description => rule description
# rule_id => associated rule id
# rorder
# enable
# reason
# expire_days
sub add {
	my $self = shift;
	my %ARGZ = @_;
	$self->setLastError(query=>"",
	                    string=>"Require a rule_id",
	                    code=>-1) && return undef if ( !exists($ARGZ{'rule_id'}) || !$self->checkUInt($ARGZ{'rule_id'}) );
	delete($ARGZ{'rorder'}) if ( exists($ARGZ{'rorder'}) && !$self->checkInt($ARGZ{'rorder'}) );
	$ARGZ{'enable'} = 1 if ( exists($ARGZ{'enable'}) && !$self->checkBool($ARGZ{'enable'}) );
	delete($ARGZ{'expire_days'}) if (exists($ARGZ{'expire_days'}) && !$self->checkInt($ARGZ{'expire_days'}));
	$ARGZ{'expire_days'} = abs($ARGZ{'expire_days'}) if (exists($ARGZ{'expire_days'}));
	my $dbh = $self->_dbh();
	my %fields = (
		'rule_id' => $ARGZ{'rule_id'},
		'create_date' => "now()"
	);
	$fields{'rorder'} = $ARGZ{'rorder'} if exists($ARGZ{'rorder'});
	$fields{'enable'} = $ARGZ{'enable'} if exists($ARGZ{'enable'});
	$fields{'expire_days'} = $ARGZ{'expire_days'} if exists($ARGZ{'expire_days'});
	# description
	if ( exists($ARGZ{'description'}) && $self->checkStrLength($ARGZ{'description'},0,51) ) {
		$fields{'description'} = $dbh->quote($ARGZ{'description'});
	}
	# reason
	if ( exists($ARGZ{'reason'}) && $self->checkStrLength($ARGZ{'reason'},0,256) ) {
		$fields{'reason'} = $dbh->quote($ARGZ{'reason'});
	}
	my (@f,@v);
	foreach my $k ( keys(%fields) ) {
		push(@f,$k);
		push(@v,$fields{$k});
	}
	my $strQuery = "INSERT INTO exclude (".join(",",@f).") VALUES (".join(",",@v).")";
	return $self->doQuery($strQuery);
}

sub modify {
	my $self = shift;
	my %ARGZ = @_;
	$self->setLastError(query=>"",
	                    string=>"Require a id",
	                    code=>-1) && return undef if ( !exists($ARGZ{'id'}) || !$self->checkUInt($ARGZ{'id'}) );
	my $id = $ARGZ{'id'};
	delete($ARGZ{'id'});
	my %valid_fields = (
		rorder => { check => sub { $self->checkInt(shift); }, quote=>0},
		enable => { check => sub { $self->checkBool(shift); }, quote=>0},
		description => { check => sub { $self->checkStrLength(shift,-1,51); }, quote=>1},
		reason => { check => sub { $self->checkStrLength(shift,-1,256); }, quote=>1},
		rule_id => 	{ check => sub { $self->checkUInt(shift); }, quote=>0},
		expire_days => { check => sub { $self->checkUInt(shift); }, quote=>0}
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
	return $self->doQuery($strQuery);
}

# id => rule id
# results => hash ref
sub get {
	my $self = shift;
	my %ARGZ = @_;
	$self->setLastError(query=>"",
	                    string=>"Require a id",
	                    code=>-1) && return undef if ( !exists($ARGZ{'id'}) || !$self->checkUInt($ARGZ{'id'}) );
	$self->setLastError(query=>"",
	                    string=>"Require a results hashref",
	                    code=>-1) && return undef if ( !exists($ARGZ{'results'}) || ref($ARGZ{'results'}) ne "HASH");
	my $dbh = $self->_dbh();
	my $strQuery = "SELECT *,UNIX_TIMESTAMP(create_date) AS ts_create_date, UNIX_TIMESTAMP(DATE_ADD(create_date,INTERVAL expire_days DAY)) AS ts_expire_date FROM exclude WHERE id = $ARGZ{'id'}";
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

# list excludes (with underlying rule)
# enable => 1 (opt)
# expired => 0 | 1
# results => ARRAY REF
sub list {
	my $self = shift;
	my %ARGZ = @_;
	$self->setLastError(query=>"",
	                    string=>"Require an ARRAY REF",
	                    code=>-1) && return undef if ( !exists($ARGZ{'results'}) || ref($ARGZ{'results'}) ne "ARRAY" );
	my $res = $ARGZ{'results'};
	my $enable = ( exists($ARGZ{'enable'}) && defined($ARGZ{'enable'}) ) ? 1 : 0;
	my $expired = ( exists($ARGZ{'expired'}) && defined($ARGZ{'expired'}) && $ARGZ{'expired'} =~ /^0$/ ) ? 0 : 1;
	my $strQuery = "SELECT e.*, UNIX_TIMESTAMP(e.create_date) AS ts_create_date, ".
								 "UNIX_TIMESTAMP(DATE_ADD(e.create_date,INTERVAL e.expire_days DAY)) AS ts_expire_date, ".
                 "r.name AS rule_name, r.exp AS rule_exp, r.type AS rule_type ".
                 "FROM exclude e,rules r ".
                 "WHERE  e.rule_id = r.id ";
	$strQuery .= "AND e.enable=1 " if ( $enable) ;
	$strQuery .= "AND (e.expire_days = 0 OR DATE_ADD(e.create_date, INTERVAL e.expire_days DAY) > NOW()) " if ( !$expired );
	$strQuery .= "ORDER BY e.rorder ASC";

	my $rows = $self->queryAllRows($strQuery) or return undef;
	push(@$res, @$rows);
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
	my $include = ( exists($ARGZ{'including'}) && defined($ARGZ{'including'}) && $ARGZ{'including'} =~ /^[0-9]+$/ ) ? $ARGZ{'including'} : undef;
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

	my $rows = $self->queryAllRows($strQuery) or return undef;
	push(@$res, @$rows);
	return 1;
}

# delete a rule
# require an id
sub del {
	my $self = shift;
	my $id = shift;
	my $strQuery = "DELETE FROM exclude WHERE id=$id";
	return $self->doQuery($strQuery);	
}

# check if an exculsion exists switch a given rule
sub existsRule {
	my $self = shift;
	my $rule_id = shift;
	my $dbh = $self->_dbh();
	my $strQuery = "SELECT id FROM exclude WHERE rule_id = $rule_id";
	my $result = undef;
	eval {
		my $sth = $dbh->prepare($strQuery);
		$sth->execute();
		$result = $sth->fetchrow()||-1;
		$sth->finish();
	};
	if ($@) {
		$self->setLastError(query=>$strQuery,string=>$dbh->errstr(),code=>$dbh->err());
		warn(__PACKAGE__,"-> Database Error : $@ : $strQuery");
		return undef;
	}
	return $result;
}

# delete expired rules
#
sub delExpired {
	my $self = shift;
	my $strQuery = "DELETE FROM exclude WHERE expire_days > 0 AND DATE_ADD(create_date, INTERVAL expire_days DAY) < NOW()";
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
