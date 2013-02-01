package FILEX::DB::base;
use strict;
use vars qw($VERSION);
use FILEX::System::Config;
use DBI;

$VERSION = 1.0;

# name => dbname
# user => db username
# password => db password
# host => db host
# port => db port
sub new {
	my $this = shift;
	my $class = ref($this)||$this;

	my $self = {
		_DBH_ => undef,
		_LASTERRORSTRING_ => undef,
		_LASTERRORQUERY_ => undef,
		_LASTERRORCODE_ => undef,
		_CONFIG_ => undef,
	};
	
	# first initialize config
	$self->{'_CONFIG_'} = FILEX::System::Config->instance();

	my $dbname = $self->{'_CONFIG_'}->getDBName();
	my $dbuser = $self->{'_CONFIG_'}->getDBUsername();
	my $dbpassword = $self->{'_CONFIG_'}->getDBPassword();
	my $dbhost = $self->{'_CONFIG_'}->getDBHost();
	my $dbport = $self->{'_CONFIG_'}->getDBPort();
	my $dbsocket = $self->{'_CONFIG_'}->getDBSocket();
	# attempt to connect
	$self->{'_DBH_'} = eval {
		my $dsn = "DBI:mysql:database=".$dbname.";host=".$dbhost;
		$dsn .= ";port=".$dbport if $dbport;
		$dsn .= ";mysql_socket=".$dbsocket if $dbsocket;
		DBI->connect($dsn,$dbuser,$dbpassword,{AutoCommit=>0,RaiseError=>1});
	};
	die(__PACKAGE__,"-> Unable to Connect to the Database : $@") if ($@);
	bless($self,$class);
	return $self;
}

sub DESTROY {
	my $self = shift;
	$self->{_DBH_}->disconnect() if ( $self->{'_DBH_'} );
}

# helper, return current database handle
sub _dbh {
	my $self = shift;
	return $self->{'_DBH_'};
}

# return underlying config module
sub _config {
	my $self = shift;
	return $self->{'_CONFIG_'};
}

# set last error
# string => db handle error string
# query => db handle query string
# code => db handle error code
sub setLastError {
	my $self = shift;
	my %ARGZ = @_;
	$self->{'_LASTERRORSTRING_'} = $ARGZ{'string'} if exists($ARGZ{'string'});
	$self->{'_LASTERRORQUERY_'} = $ARGZ{'query'} if exists($ARGZ{'query'});
	$self->{'_LASTERRORCODE_'} = $ARGZ{'code'} if exists($ARGZ{'code'});
}

sub getLastErrorString {
	my $self = shift;
	return $self->{'_LASTERRORSTRING_'};
}

sub getLastErrorCode {
	my $self = shift;
	return $self->{'_LASTERRORCODE_'};
}

sub getLastErrorQuery {
	my $self = shift;
	return $self->{'_LASTERRORQUERY_'};
}

sub checkInt {
	my $self = shift;
	my $value = ( ref($self) ) ? shift : $self;
	return ( defined($value) && $value =~ /^-?[0-9]+$/ ) ? 1 : undef;
}

sub checkBool {
	my $self = shift;
	my $value = ( ref($self) ) ? shift : $self;
	return ( defined($value) && $value =~ /^[0-1]$/ ) ? 1 : undef;
}

sub checkUInt {
	my $self = shift;
	my $value = ( ref($self) ) ? shift : $self;
	return ( defined($value) && $value =~ /^[0-9]+$/ ) ? 1 : undef;
}

sub checkStr {
	my $self = shift;
	my $value = ( ref($self) ) ? shift : $self;
	return ( defined($value) && length($value) > 0 ) ? 1 : undef;
}

sub checkStrLength {
	my $self = shift;
	my $value = ( ref($self) ) ? shift : $self;
	my $min = shift;
	my $max = shift;
	return ( defined($value) && (length($value) > $min && length($value) < $max) ) ? 1 : undef;
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
