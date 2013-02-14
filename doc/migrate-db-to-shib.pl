#!/usr/bin/perl
use strict;
use lib qw(/usr/local/FILEX/lib);
use DBI qw(:sql_types);

# FILEX
use FILEX::System::Config;
use FILEX::System::LDAP;
use FILEX::DB::ShibUser;

my $shibIdAttr = 'eduPersonPrincipalName';
my $FILEXConfig= 'conf/FILEX.ini';

-f $FILEXConfig or die "invalid FILEXConfig file $FILEXConfig\n";
my $config = FILEX::System::Config->instance(file=>$FILEXConfig) or die("Unable to load config file");
my $ldap = FILEX::System::LDAP->new() or die("Unable to create ldap object !");
my $db_ShibUser = FILEX::DB::ShibUser->new();
my $dbh = $db_ShibUser->_dbh();

# get owner
my $owners = getOwners($dbh);


# now for each owner, get uniq_id and update database 
foreach my $uid (@$owners) {
	my $shib_user = compute_shib_user($ldap, $uid, $shibIdAttr);
	if ($shib_user->{id}) {
	    warn "migrating uid $uid to $shib_user->{id}\n";
	    $db_ShibUser->setUser($shib_user);
	    migrateOwner($dbh, $uid, $shib_user->{id});
	} else {
	    warn "skipping unknown uid $uid\n";
	}
}

sub migrateOwner {
    my ($dbh, $owner, $newOwner) = @_;
    doQuery($dbh, 
	    "UPDATE upload SET owner = ?, owner_uniq_id = ? WHERE owner = ?", 
	    $newOwner, $newOwner, $owner) or warn "update $owner failed\n";
}

sub compute_shib_user {
    my ($ldap, $uid, $shibIdAttr) = @_;

    return { 
	id => $ldap->getAttr($uid, $shibIdAttr),
	mail => $ldap->getMail($uid),
	real_name => $ldap->getUserRealName($uid)
    };
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

sub doQuery {
    my ($dbh, $strQuery, @params) = @_;

    my ($res,$sth);
    eval {
	$sth = $dbh->prepare($strQuery);
	$res = $sth->execute(@params);
	$dbh->commit();
    };
    if ($@) {
	warn(__PACKAGE__,"-> Database Error : $@ : $strQuery");
	return undef;
    }
    return 1;
}
