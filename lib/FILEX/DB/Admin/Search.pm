package FILEX::DB::Admin::Search;
use strict;
use vars qw($VERSION @ISA %EXPORT_TAGS);
use FILEX::DB::base 1.0;
use Exporter;
BEGIN {
	# inherit FILEX::DB::base
	@ISA = qw(FILEX::DB::base Exporter);
	$VERSION = 1.0;
	%EXPORT_TAGS = (
		J_OP => [ qw(J_OP_AND J_OP_OR) ],
		T_OP => [ qw(T_OP_EQ T_OP_NEQ T_OP_LT T_OP_GT T_OP_LTE T_OP_GTE T_OP_LIKE T_OP_NLIKE) ],
		S_OR => [ qw(S_O_ASC S_O_DESC) ],
		S_FI => [ qw(S_F_NAME S_F_OWNER S_F_SIZE S_F_UDATE S_F_EDATE S_F_COUNT S_F_ENABLE) ],
		B_OP => [ qw(B_OP_TRUE B_OP_FALSE) ]
	);
	Exporter::export_ok_tags('J_OP','T_OP','S_FI','S_OR','B_OP');
}
# test operators
use constant T_OP_EQ => '=';
use constant T_OP_NEQ => '!=';
use constant T_OP_LT => '<';
use constant T_OP_GT => '>';
use constant T_OP_LTE => '<=';
use constant T_OP_GTE => '>=';
use constant T_OP_LIKE => 'like';
use constant T_OP_NLIKE => 'not like';
# join operators
use constant J_OP_AND => 'and';
use constant J_OP_OR => 'or';
# boolean op
use constant B_OP_TRUE => 1;
use constant B_OP_FALSE => 0;
# sort fields
use constant S_F_NAME => 'real_name';
use constant S_F_OWNER => 'owner';
use constant S_F_SIZE => 'size';
use constant S_F_UDATE => 'upload_date';
use constant S_F_EDATE => 'expire_date';
use constant S_F_COUNT => 'download_count';
use constant S_F_ENABLE => 'enable';
# sort order
use constant S_O_ASC => 'asc';
use constant S_O_DESC => 'desc';

my %SEARCH_FIELDS = (
	real_name => { quote=>1, query_left=>"u.real_name" },
	owner => { quote=>1, query_left=>"u.owner" },
	owner_uniq_id => { quote=>1, query_left=>"u.owner_uniq_id" },
	upload_date => { quote=>0, query_left=>"TO_DAYS(u.upload_date)", query_right=>"TO_DAYS(FROM_UNIXTIME(\%V))"},
	expire_date => { quote=>0, query_left=>"TO_DAYS(u.expire_date)", query_right=>"TO_DAYS(FROM_UNIXTIME(\%V))"},
	expire_date_now => { quote => 0, query_left=>"u.expire_date", query_right=>"NOW()" },
	enable => { quote=>0, query_left=>"u.enable" }
);

my %SORT_NAME = (
	real_name => "u.real_name",
	owner => "u.owner",
	size => "u.file_size",
	upload_date => "u.upload_date",
	expire_date => "u.expire_date",
	download_count => "download_count",
	enable => "u.enable"
);

my @JOIN_OPERATORS = (J_OP_AND,J_OP_OR );
my @TEST_OPERATORS = (T_OP_EQ,T_OP_NEQ,T_OP_LT,T_OP_LTE,T_OP_GT,T_OP_GTE,T_OP_LIKE,T_OP_NLIKE);
my @SORT_FIELDS = (S_F_NAME,S_F_OWNER,S_F_SIZE,S_F_UDATE,S_F_EDATE,S_F_COUNT,S_F_ENABLE);
my @SORT_ORDER = (S_O_ASC,S_O_DESC);

# fields => {field=>,test=>,join=>,value=>}
# search on
# real_name
# owner
# owner_uniq_id
# upload_date
# expire_date
# results => ARRAY REF
# sort => sort field
# order => order by
sub search {
	my $self = shift;
	my %ARGZ = @_;
	$self->setLastError(query=>"",
	                    string=>"Require an ArrayRef of query parameters",
	                    code=>-1) && return undef if ( !exists($ARGZ{'fields'}) || ref($ARGZ{'fields'}) ne "ARRAY");
	my $search_fields = $ARGZ{'fields'};
	$self->setLastError(query=>"",
	                    string=>"Require an ArrayRef for results",
	                    code=>-1) && return undef if ( !exists($ARGZ{'results'}) || ref($ARGZ{'results'}) ne "ARRAY");
	my $results = $ARGZ{'results'};
	my $dbh = $self->_dbh();
	my $strQueryBegin = "SELECT u.*, ".
	               "UNIX_TIMESTAMP(u.upload_date) AS ts_upload_date, ".
	               "UNIX_TIMESTAMP(u.expire_date) AS ts_expire_date, ".
                 "COUNT(g.upload_id) - SUM(g.admin_download) AS download_count, ".
								 "NOW() > u.expire_date AS expired ".
	               "FROM upload AS u ".
	               "LEFT JOIN get AS g ON u.id = g.upload_id ";

	# return if no fields set
	return 1 if ($#$search_fields < 0 );
	# build the query 
	my (@clause,@strClause,$strField,$strJoin,$strTest,$strValue);
	for (my $i=0; $i<=$#$search_fields; $i++) {
		$strJoin = $search_fields->[$i]->{'join'};
		$strTest = $search_fields->[$i]->{'test'};
		$strField = $search_fields->[$i]->{'field'};
		$strValue = $search_fields->[$i]->{'value'};
		# reset 
		splice(@strClause);
		# first clause
		if ( $i == 0 ) {
			push(@strClause,"WHERE");
		} else {
			if ( _validJoin($strJoin) ) {
				push(@strClause,uc($strJoin));
			} else {
				$self->setLastError(query=>"",
				                    string=>"Invalid join operator : $strJoin for : $strField",
				                    code=>-2);
				return undef;
			}
		}
		# the field itself
		if ( !exists($SEARCH_FIELDS{$strField}) ) {
			$self->setLastError(query=>"",
			                    string=>"Invalid search field : $strField",
			                    code=>-2);
			return undef;
		}
	  # the test op
		if ( ! _validTest($strTest) ) {
			$self->setLastError(query=>"",
			                    string=>"Invalid test field : $strTest for : $strField",
			                    code=>-2);
			return undef;
		}
		# left part is mandatory
		push(@strClause,$SEARCH_FIELDS{$strField}->{'query_left'});
		# test op
		push(@strClause,uc($strTest));
		# the value
		if ( exists($SEARCH_FIELDS{$strField}->{'query_right'}) ) {
			# if right part exists
			my $right_parts = $SEARCH_FIELDS{$strField}->{'query_right'};
			my $replace_value = $strValue;
			$replace_value = $dbh->quote($replace_value) if ($SEARCH_FIELDS{$strField}->{'quote'});
			# check for positionnal parameter
			$right_parts =~ s/\%V/$replace_value/ if ($right_parts =~ /\%V/);
			push(@strClause,$right_parts);
		} else {
			push(@strClause,($SEARCH_FIELDS{$strField}->{'quote'})?$dbh->quote($strValue):$strValue);
		}
		push(@clause,join(' ',@strClause));
	}
	
	my $strQuery = $strQueryBegin.join(' ',@clause)." GROUP BY u.id";
	# check for sort fields
	if ( exists($ARGZ{'sort'}) ) {
		my $sort_field = $ARGZ{'sort'};
		if ( !defined($sort_field) || !_validSort($sort_field) || !exists($SORT_NAME{$sort_field}) ) {
			warn(__PACKAGE__," => invalid sort fields : $sort_field ; skipping");
		} else {
			$strQuery .= " ORDER BY $SORT_NAME{$sort_field}";
			if ( exists($ARGZ{'order'}) && defined($ARGZ{'order'}) && _validOrder($ARGZ{'order'}) ) {
				$strQuery .= " ".uc($ARGZ{'order'});
			}
		}
	}
	eval {
		my $sth = $dbh->prepare($strQuery);
		$sth->execute();
		while (my $r = $sth->fetchrow_hashref() ) {
			push(@$results,$r);
		}
	};
	if ($@) {
		$self->setLastError(string=>$dbh->errstr(),code=>$dbh->err(),query=>$strQuery);
		warn(__PACKAGE__,"-> Database Error : $@ : $strQuery");
		return undef;
	}
	return 1;
}

sub _validOrder {
	my $op = shift;
	return grep($op =~ /^$_$/i,@SORT_ORDER);
}
sub _validSort {
	my $op = shift;
	return grep($op =~ /^$_$/i,@SORT_FIELDS);
}
sub _validTest {
	my $op = shift;
	return grep($op =~ /^$_$/i,@TEST_OPERATORS);
}
sub _validJoin {
	my $op = shift;
	return grep($op =~ /^$_$/i,@JOIN_OPERATORS);
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
