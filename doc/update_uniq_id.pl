#!/usr/bin/perl
use strict;
use lib qw(/home/ofranco/projets/FILEX/1.4/lib);
use Getopt::Std;
use DBI qw(:sql_types);

# FILEX
use FILEX::System::Config;
use FILEX::System::LDAP;

my %PARAMS = (
	c => undef, # config file path
);

if ( !getParams(\%PARAMS) ) {
	print sprintf("usage : %s -c /path/to/FILEX.ini\n",$0);
	exit(1);
}

$FILEX::System::Config::ConfigPath=$PARAMS{'c'};
my $config = FILEX::System::Config->new() or die("Unable to load config file : $PARAMS{'c'}");
my $ldap = FILEX::System::LDAP->new() or die("Unable to create ldap object !");
# connect to the database
my $dbh = dbConnect($config);

# get owner
my $owners = getOwners($dbh);
# check if we need 
my $uniq_id_attr = $config->getLdapUniqAttr();
my $uniq_id_attr_mode = $config->getLdapUniqAttrMode();
my $uniq_id_attr_lc = lc($uniq_id_attr) if ($uniq_id_attr);

my $str_query = "UPDATE upload SET owner_uniq_id = ? WHERE owner = ?";
my $sth = $dbh->prepare($str_query);
if ( !$sth ) {
	warn("unable to prepare statement [ $str_query ]");
	dbDisconnect($dbh);
	exit(1);
}

# now for each owner, get uniq_id and update database 
my ($uid,$uniq_id,$success);
$success = 0;
foreach $uid (@$owners) {
	print "updating $uid\t";
	# if we do not use uniq_id
	if ( ! defined($uniq_id_attr) ) {
		$uniq_id = $uid;
	} else {
		my $res = $ldap->getUserAttrs(uid=>$uid,attrs=>[$uniq_id_attr]);
		# error ?
		if ( !defined($res) ) {
			warn("an error occured while getting ldap attributes !");
			print "[FAILED]\n";
			next;
		}
		# if attribute does not exists !
		if ( !exists($res->{$uniq_id_attr_lc}) || length($res->{$uniq_id_attr_lc}->[0] <= 0) ) {
			# if not in strict mode
			if ($uniq_id_attr_mode != 1) {
				$uniq_id = $uid;
			} else {
				warn("unable to get uniq_id for $uid; skipping ...");
				print "[FAILED]\n";
				next;
			}
		} else {
			$uniq_id = $res->{$uniq_id_attr_lc}->[0];
		}
	}
	print "$uniq_id\t";
  # now we can update the database
	eval {
		$sth->bind_param(1,$uniq_id,SQL_VARCHAR);
		$sth->bind_param(2,$uid,SQL_VARCHAR);
		$sth->execute();
	};
	if ($@) {
		warn("query failed for [$uid, $uniq_id] : $@");
		print "[FAILED]\n";
	}
	print "[OK]\n";
	$success++;
}
if ( $success ) {
	eval {
		$dbh->commit();
	};
	if ($@) {
		warn("commit failed : $@");
	}
}

# the end
dbDisconnect($dbh);

sub getUniqId {
	my $user = shift;
	my $attr = shift;
}
sub getOwners {
	my $db = shift;
	
	my $str_query = "SELECT DISTINCT owner FROM upload";
	my @res;
	eval {
		my $sth = $db->prepare($str_query);
		$sth->execute();
		my $owner;
		while ( $owner = $sth->fetchrow() ) {
			push(@res,$owner);
		}
	};
	if ($@) {
		warn("Unable to retrieve owners : $@");
		return undef;
	}
	return \@res;
}

# get parameters
sub getParams {
	my $params = shift;
	getopt('c:',$params);
	if ( !defined($params->{'c'}) || !-f $params->{'c'} ) {
		warn("please provide a valid configuration file !");
		return undef;
	}
	return 1;
}

sub dbConnect {
	my $conf = shift;
	my $dbname = $config->getDBName();
  my $dbuser = $config->getDBUsername();
  my $dbpassword = $config->getDBPassword();
  my $dbhost = $config->getDBHost();
  my $dbport = $config->getDBPort();
  # attempt to connect
  my $db = eval {
    my $dsn = "DBI:mysql:database=".$dbname.";host=".$dbhost;
    $dsn .= ";port=".$dbport if $dbport;
    DBI->connect($dsn,$dbuser,$dbpassword,{AutoCommit=>0,RaiseError=>1});
  };
  die(__PACKAGE__,"-> Unable to Connect to the Database : $@") if ($@);
	return $db;
}

sub dbDisconnect {
	my $db = shift;
	return $db->disconnect();
}
