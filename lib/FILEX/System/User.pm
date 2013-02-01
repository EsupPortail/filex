package FILEX::System::User;
use strict;
use vars qw($VERSION);
use FILEX::System::Config;
use FILEX::System::LDAP;
use FILEX::DB::User;

$VERSION = 1.0;

sub new {
	my $this = shift;
	my $class = ref($this) || $this;
	my %ARGZ = @_;

	my $self = {
		id => undef,
    uniq_id => undef,
		real_name => undef,
		_config_ => undef,
		_ldap_ => undef,
		_db_ => undef,
	};

	if ( !exists($ARGZ{'uid'}) || length($ARGZ{'uid'}) <= 0 ) {
		warn(__PACKAGE__," => require a user id !");
		return undef;
	}
	# set user id
	$self->{'id'} = $ARGZ{'uid'};

	# config
	$self->{'_config_'} = FILEX::System::Config->new();
	if ( !defined($self->{'_config_'}) ) {
		warn(__PACKAGE__,"-> unable to initialize config !");
		return undef;
	}
	# ldap
	if ( exists($ARGZ{'ldap'}) && ref($ARGZ{'ldap'}) eq "FILEX::System::LDAP" ) {
    $self->{'_ldap_'} = $ARGZ{'ldap'};
  } else {
    $self->{'_ldap_'} = eval { FILEX::System::LDAP->new(); };
    warn(__PACKAGE__,"=> unable to load FILEX::System::LDAP : $@") && return undef if ($@);
  }
	
	# now get the uniq id if needed
	warn(__PACKAGE__," => unable to retrieve user uniq id for : ".$self->{id}) && return undef if ( !_initUniqId($self) );

	return bless($self,$class);
}

sub getId {
	my $self = shift;
	return $self->{'id'};
}

sub getUniqId {
	my $self = shift;
	return $self->{'uniq_id'};
}

# get user's disk space
sub getDiskSpace {
	my $self = shift;
	my $db = $self->_db();
	return ($db) ? $db->getDiskSpace($self->{'uniq_id'}) : undef;
}
# get user's active file count
sub getActiveCount {
	my $self = shift;
	my $db = $self->_db();
	return ($db) ? $db->getActiveCount($self->{'uniq_id'}) : undef;
}
# get user's upload count
sub getUploadCount {
	my $self = shift;
	my $db = $self->_db();
	return ($db) ? $db->getUploadCount($self->{'uniq_id'}) : undef;
}

# get user's mail
sub getMail {
	my $self = shift;
	return $self->{'_ldap_'}->getMail($self->{'id'});
}

# get user's real name
sub getRealName {
	my $self = shift;
	# use cached value
	return $self->{'real_name'} if ( defined($self->{'real_name'}) );
  my $attr = $self->{'_config_'}->getLdapUsernameAttr();
  my $res = $self->{'_ldap_'}->getUserAttrs(uid=>$self->{'id'},attrs=>[$attr]);
  $attr = lc($attr);
  #return ($res) ? $res->{$attr}->[0] : "unknown";
	$self->{'real_name'} = ($res) ? $res->{$attr}->[0] : "unknown";
  return $self->{'real_name'};
}

# initialize user's uniq id
sub _initUniqId {
	my $self = shift;
  my $attr = $self->{'_config_'}->getLdapUniqAttr();
  # if undef then do not use UniqId
  $self->{'uniq_id'} = $self->{'id'} && return 1 if ( !defined($attr) );
  my $res = $self->{'_ldap_'}->getUserAttrs(uid=>$self->{'id'},attrs=>[$attr]);
  return undef if ( ! defined($res) );
  $attr = lc($attr);
  # if UniqAttrMode == 0 then we return the uid
  if ( !exists($res->{$attr}) || length($res->{$attr}->[0]) <= 0 ) {
    if ( $self->{'_config_'}->getLdapUniqAttrMode() != 1 ) {
			$self->{'uniq_id'} = $self->{'id'};
      return 1;
    } else {
      return undef;
    }
  }
  # return the value
  $self->{'uniq_id'} = $res->{$attr}->[0];
	return 1;
}

# initialize database if needed
sub _db {
	my $self = shift;
  # load on demand
  if ( !$self->{'_db_'} ) {
    $self->{'_db_'} = eval { FILEX::DB::User->new(); };
    warn(__PACKAGE__,"-> Unable to Load FILEX::DB::User object : $@") if ($@);
  }
  return $self->{'_db_'};
}

1;
