package FILEX::DB::Admin::Quota;
use strict;
use vars qw($VERSION @ISA @EXPORT_OK);
use FILEX::DB::base 1.0;
#use Exporter;
# inherit FILEX::DB::base
@ISA = qw(FILEX::DB::base Exporter);
$VERSION = 1.0;

# description => rule description
# rule_id => associated rule id
# max_file_size
# max_used_space
# qorder
# enable
sub add {
	my $self = shift;
	my %ARGZ = @_;
	$self->setLastError(query=>"",
	                    string=>"Require a rule_id",
	                    code=>-1) && return undef if ( !exists($ARGZ{'rule_id'}) || !$self->checkUInt($ARGZ{'rule_id'}) );
	delete($ARGZ{'qorder'}) if ( exists($ARGZ{'qorder'}) && !$self->checkInt($ARGZ{'qorder'}) );
	$ARGZ{'enable'} = 1 if ( exists($ARGZ{'enable'}) && !$self->checkBool($ARGZ{'enable'}) );
	delete($ARGZ{'max_file_size'}) if ( exists($ARGZ{'max_file_size'}) && !$self->checkInt($ARGZ{'max_file_size'}) );
	delete($ARGZ{'max_used_space'}) if ( exists($ARGZ{'max_file_size'}) && !$self->checkInt($ARGZ{'max_used_space'}) );
	my $dbh = $self->_dbh();
	my %fields = (
		'rule_id' => $ARGZ{'rule_id'},
		'create_date' => "now()"
	);
	$fields{'qorder'} = $ARGZ{'qorder'} if exists($ARGZ{'qorder'});
	$fields{'enable'} = $ARGZ{'enable'} if exists($ARGZ{'enable'});
	$fields{'max_file_size'} = $ARGZ{'max_file_size'} if exists($ARGZ{'max_file_size'});
	$fields{'max_used_space'} = $ARGZ{'max_used_space'} if exists($ARGZ{'max_used_space'});
	# description
	if ( exists($ARGZ{'description'}) && $self->checkStrLength($ARGZ{'description'},0,51) ) {
		$fields{'description'} = $dbh->quote($ARGZ{'description'});
	}
	my (@f,@v);
	foreach my $k ( keys(%fields) ) {
		push(@f,$k);
		push(@v,$fields{$k});
	}
	my $strQuery = "INSERT INTO quota (".join(",",@f).") VALUES (".join(",",@v).")";
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
		qorder => { check => sub { $self->checkInt(shift); }, quote=>0},
		enable => { check => sub { $self->checkBool(shift); }, quote=>0},
		description => { check => sub { $self->checkStrLength(shift,-1,51); }, quote=>1 },
		rule_id => 	{ check => sub { $self->checkUInt(shift); }, quote=>0 },
		max_file_size => { check => sub { $self->checkInt(shift); }, quote=>0 },
		max_used_space => { check => sub { $self->checkInt(shift); }, quote=> 0 }
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
	my $strQuery = "UPDATE quota SET ".join(",",@strSet)." WHERE id=$id";
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
	my $strQuery = "SELECT *,UNIX_TIMESTAMP(create_date) AS ts_create_date FROM quota WHERE id = $ARGZ{'id'}";
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

# list quotas (with underlying rule)
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
	my $strQuery = "SELECT q.*, UNIX_TIMESTAMP(create_date) AS ts_create_date, ".
                 "r.name AS rule_name, r.exp AS rule_exp, r.type AS rule_type ".
                 "FROM quota q,rules r ".
                 "WHERE  q.rule_id = r.id ";
	$strQuery .= "AND q.enable=1 " if ( $enable) ;
	$strQuery .= "ORDER BY q.qorder ASC";
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
	my $dbh = $self->_dbh();
	my $strQuery = "SELECT rules.* FROM rules ".
                 "LEFT JOIN quota ON rules.id = quota.rule_id ".
                 "WHERE quota.rule_id IS NULL";
	$strQuery .= " OR quota.rule_id = $include" if defined($include);
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

# delete a quota
# require an id
sub del {
	my $self = shift;
	my $id = shift;
	my $strQuery = "DELETE FROM quota WHERE id=$id";
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
