package FILEX::System::User;
use strict;
use vars qw($VERSION);
use FILEX::System::Config;
use FILEX::System::LDAP;
use FILEX::System::Quota;
use FILEX::System::BigBrother;
use FILEX::DB::User;

$VERSION = 1.0;

sub new {
	my $this = shift;
	my $class = ref($this) || $this;
	my %ARGZ = @_;

	my $self = {
		id => undef,
    uniq_id => undef,
		_config_ => undef,
		_ldap_ => undef,
		_db_ => undef,
		_watch_ => undef,
		_quota_ => undef,
		_session_ => undef
	};

	if ( !exists($ARGZ{'uid'}) || length($ARGZ{'uid'}) <= 0 ) {
		warn(__PACKAGE__," => require a user id !");
		return undef;
	}
	# set user id
	$self->{'id'} = $ARGZ{'uid'};

	$self->{'_getUserInfo_'} = $ARGZ{'getUserInfo'} or die(__PACKAGE__," => getUserInfo is mandatory!");

	# config
	$self->{'_config_'} = FILEX::System::Config->instance();

	# ldap
	if ( exists($ARGZ{'ldap'}) && ref($ARGZ{'ldap'}) eq "FILEX::System::LDAP" ) {
    $self->{'_ldap_'} = $ARGZ{'ldap'};
  } else {
    $self->{'_ldap_'} = eval { FILEX::System::LDAP->new(); };
    warn(__PACKAGE__,"=> unable to load FILEX::System::LDAP : $@") && return undef if ($@);
  }

	# session
	$self->{'_session_'} = $ARGZ{'session'} if ( exists($ARGZ{'session'}) && 
		ref($ARGZ{'session'}) eq "FILEX::System::Session"); 

	bless($self,$class);

	# now get the uniq id 
	my $uniq_id = $self->getUniqId();
	warn(__PACKAGE__," => unable to retrieve user uniq id for : ".$self->{id}) && return undef if !defined($uniq_id);
	$self->{'uniq_id'} = $uniq_id;

	return $self;
}

sub setSession {
	my $self = shift;
	my $session = shift;
	if ( defined($session) && ref($session) eq "FILEX::System::Session" ) {
		$self->{'_session_'} = $session; 
		# set the uniq_id into session
		$self->_toSession(uniq_id=>$self->{'uniq_id'},1);
	}
}

sub getSession {
	my $self = shift;
	return $self->{_session_};
}

sub getId {
	my $self = shift;
	return $self->{'id'};
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
	# get from session
	my $mail = $self->_fromSession("mail");
	return $mail if $mail;
	# get from data source
	$mail = $self->{'_getUserInfo_'}->getMail($self->{'id'});
	# store
	$self->_toSession(mail=>$mail,1);
	return $mail;
}

# get user's real name
sub getRealName {
	my $self = shift;

	# get from session
	my $rn = $self->_fromSession("real_name");
	return $rn if defined($rn);

	$rn = $self->{'_getUserInfo_'}->getUserRealName($self->{'id'});
	defined($rn) or $rn = "unknown";

	# store
	$self->_toSession(real_name=>$rn,1);
	
	return $rn;
}

# get quota
sub getQuota {
	my $self = shift;
	# from session
	my $max_file_size = $self->_fromSession("quota_max_file_size");
	my $max_used_space = $self->_fromSession("quota_max_used_space");
	return ($max_file_size,$max_used_space) if ( defined($max_file_size) && defined($max_used_space) );

	# retrieve quota
	my $q = $self->_quota();
	($max_file_size,$max_used_space) = ( $q ) ? $q->getQuota($self->{'id'}) : (0,0);

	# store quota
	$self->_toSession(quota_max_file_size=>$max_file_size,1);
	$self->_toSession(quota_max_used_space=>$max_used_space,1);
	return ($max_file_size,$max_used_space);
}

# get max file size
sub getMaxFileSize {
	my $self = shift;
	my ($quota_max_file_size,$quota_max_used_space) = $self->getQuota();
	my $current_user_space = $self->getDiskSpace() || 0;
	# compute
	# if ( quota_max_file_size == 0 || quota_max_used_space == 0 ) then disable
  return 0 if ( $quota_max_file_size == 0 || $quota_max_used_space == 0 );
  # if $quota_max_used_space <= $current_user_space then no more upload
  # since quota_max_used_space == -1 if unlimited it's always < current_user_space
  # because the minimal value of current_user_space is ZERO
  return 0 if (  $quota_max_used_space <= $current_user_space && $quota_max_used_space != -1 );
  # if quota_max_used_space == unlimited ( < 0 ) then return the max permitted file size
  return $quota_max_file_size if ( $quota_max_used_space < 0 );
  # now we have a remaining space
  my $remaining_space = $quota_max_used_space - $current_user_space;
  # if quota_max_file_size == unlimited ( < 0 ) then return the remaining space
  return $remaining_space if ( $quota_max_file_size < 0 || $quota_max_file_size >= $remaining_space );
  # otherwise return the quota_max_file_size
  return $quota_max_file_size;
}

# check if user is admin
sub isAdmin {
	my $self = shift;
	my $db = $self->_db();
	return ($db) ? $db->isAdmin($self->{'id'}) : undef;
}

# check if user is watched
sub isWatched {
	my $self = shift;
  # check if usemail and watchuser
  if ( $self->{'_config_'}->needEmailNotification() && $self->{'_config_'}->useBigBrother() ) {
		my $isWatched = $self->_fromSession("is_watched");
		return $isWatched if defined($isWatched);
    my $watch = $self->_watch();
		$isWatched = ($watch) ? $watch->isWatched($self->getId()) : 0;
		# store
		$self->_toSession(is_watched=>$isWatched,1); 
		return $isWatched;
  }
  return undef;
}

sub _watch {
	my $self = shift;
	# load on demand
	if ( !$self->{'_watch_'} ) {
		$self->{'_watch_'} = FILEX::System::BigBrother->new(ldap=>$self->{'_ldap_'});
	}
	return $self->{'_watch_'};
}

# check if a given user is exclude 
sub isExclude {
	my $self = shift;
	# get exclude object
	my $exclude = $self->_exclude();
	if ( $exclude ) {
		return $exclude->isExclude($self->getId());
	} 
	# deny everybody if failed
	return 1;
}

# return exclude object
sub _exclude {
	my $self = shift;
	# load on demand
	if ( !$self->{'_exclude_'} ) {
		$self->{'_exclude_'} = FILEX::System::Exclude->new(ldap=>$self->{'_ldap_'});
	}
	return $self->{'_exclude_'};
}

# initialize user's uniq id
sub getUniqId {
	my $self = shift;

	# from session
	my $uniq_id = $self->_fromSession("uniq_id");
	return $uniq_id if defined($uniq_id);
	
	# not in session then get it

	if ( $self->{'_config_'}->getUniqAttrMode() != 1 ) {
	    $uniq_id = $self->{'id'};
	} else {	
	    $uniq_id = $self->{'_getUserInfo_'}->getUniqId($self->{'id'});
	}

	# store
	if ( defined($uniq_id) ) {
		$self->_toSession(uniq_id=>$uniq_id,1);
		$self->{'uniq_id'} = $uniq_id;
	}
	return $uniq_id;
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

sub _quota {
	my $self = shift;
	if ( !$self->{'_quota_'} ) {
		$self->{'_quota_'} = FILEX::System::Quota->new(config=>$self->{'_config_'},ldap=>$self->{'_ldap_'});
	}
	return $self->{'_quota_'};
}

# get attribute from session
# param : attribute name
sub _fromSession {
	my $self = shift;
	my $attr = shift or return undef;
	return undef if !defined($self->{'_session_'});
	my $section = __PACKAGE__;
	return $self->{'_session_'}->getParam($attr);
}

# set attribute to session
# param : attribute name, attribute value
sub _toSession {
	my $self = shift;
	my ($attr,$value,$ts) = @_;
	warn(__PACKAGE__,"_toSession() require attr=>value") && return undef if !defined($attr) || !defined($value);
	warn(__PACKAGE__,"_toSession() session does not exists") && return undef if !defined($self->{'_session_'});
	my $section = __PACKAGE__;
	my @params;
	push(@params,$attr);
	push(@params,$value);
	push(@params,$ts) if ($ts && $ts =~ /^1$/);
	return $self->{'_session_'}->setParam(@params);
}

1;
