package FILEX::System::Session;
use strict;
use Apache::Session::File;
use FILEX::System::Config;

sub new {
	my $this = shift;
	my $class = $this || ref($this);

	my $self = {
		_config_ => undef,
		_session_ => undef
	};
	# load config or die
	$self->{_config_} = FILEX::System::Config->instance();
	return bless($self,$class);
}

sub save {
	my $self = shift;
	if ( defined($self->{_session_}) ) {
		tied(%{$self->{_session_}})->save();
	}
}

# return the sid
sub start {
	my $self = shift;
	# check if exists one
	$self->drop();
	# start new one
	eval {
    tie %{$self->{_session_}},'Apache::Session::File',undef,{
      Directory=>$self->{_config_}->getSessionDirectory(),
      LockDirectory=>$self->{_config_}->getSessionLockDirectory()
    };
  };
  if ($@) {
    warn(__PACKAGE__," => Unable to start new session : ",$@);
		$self->{_session_} = undef;
    return undef;
  }
	# insert session start time
	$self->{_session_}->{_start_time} = time();
	$self->{_session_}->{_last_update} = $self->{_session_}->{_start_time};
	# 
  return $self->{_session_}->{_session_id};
}
# get session start time in "time" format
sub getStartTime {
	my $self = shift;
	return ( defined($self->{_session_}) && exists($self->{_session_}->{_start_time}) ) ? $self->{_session_}->{_start_time} : undef;
}
# check if the current session is expired 
sub isExpired {
	my $self = shift;
	my $ctime = time();
	my $etime = $self->{_session_}->{_start_time} || 0;
	$etime += $self->{_config_}->getCookieExpires(); # add expire time
	return ( $ctime > $etime ) ? 1 : 0;
}
# delete session
sub drop {
	my $self = shift;
	if ( defined($self->{_session_}) ) {
		tied(%{$self->{_session_}})->delete;
	}
	$self->{_session_} = undef;
}
# load session
sub load {
	my $self = shift;
	my $sid = shift or warn(__PACKAGE__," => require a sid !") && return undef;
	$self->drop();
	eval {
    tie %{$self->{_session_}},'Apache::Session::File',$sid,{
      Directory=>$self->{_config_}->getSessionDirectory(),
      LockDirectory=>$self->{_config_}->getSessionLockDirectory()
    };
  };
  if ($@) {
    warn(__PACKAGE__," => Unable to load session $sid : ",$@);
    $self->{_session_} = undef;
    return undef;
  }
  return 1;
}

# get sid
sub getSid {
	my $self = shift;
	return ( defined($self->{_session_}) && exists($self->{_session_}->{_session_id}) ) ? $self->{_session_}->{_session_id} : undef;
}

# access session data
sub _data {
	my $self = shift;
	return $self->{_session_};
}

sub _setParam {
	my $self = shift;
	my ($attr,$value,$ts,$section) = @_;
	warn(__PACKAGE__," => _setParam() no session defined !") && return undef if !defined($self->{_session_});
	warn(__PACKAGE__," => _setParam() require attr,value pair") && return undef 
		if !defined($attr) || ref($attr) || !defined($value);
	# timestamp
	$ts = ( $ts && $ts =~ /^1$/ ) ? 1 : 0;
	# get right section
	my $current_hash = ($self->_create_section($section)) ? $self->_get_section($section) : $self->{_session_};
	# append parameter
	my $old_value = $self->_getParam($attr,$section);
	$current_hash->{$attr} = $value;
	$current_hash->{"_t_$attr"} = time if ($ts);
	# set timestamp
	$self->_mark_update();
	return $old_value;
}

sub _mark_update {
	my $self = shift;
	$self->{_session_}->{_last_update} = time if (defined $self->{_session_});
}

sub _delParam {
	my $self = shift;
	my ($attr,$section) = @_;
	warn(__PACKAGE__," => _getParam() no session defined !") && return undef if !defined($self->{_session_});
	warn(__PACKAGE__," => _getParam() require a parameter") && return undef if !defined($attr) || ref($attr);
	my $old_value = $self->_getParam($attr,$section);
	return undef if !defined($old_value);
	my $current_hash = ($section && length($section))?$self->_get_section($section):$self->{_session_};
	delete($current_hash->{$attr}) if ($current_hash && exists($current_hash->{$attr}));
	delete($current_hash->{"_t_$attr"}) if ($current_hash && exists($current_hash->{"_t_$attr"}));
	# set timestamp
	$self->_mark_update();
	return $old_value;
}

sub _getParam {
	my $self = shift;
	my $attr = shift;
	my $section = shift;
	warn(__PACKAGE__," => _getParam() no session defined !") && return undef if !defined($self->{_session_});
	warn(__PACKAGE__," => _getParam() require a parameter") && return undef if !defined($attr) || ref($attr);
	my $current_hash = ($section && length($section))?$self->_get_section($section):$self->{_session_};
	warn(__PACKAGE__," => _getParam() $attr does not exists") && return undef if (!$current_hash || !exists($current_hash->{$attr}));
	# check for timestamp
	if ( exists($current_hash->{"_t_$attr"}) && $attr ne "_t_$attr") {
		my $sessionCacheTimeout = $self->{_config_}->getSessionCacheTimeout();
		if ( $sessionCacheTimeout ) {
			my $t_out = $current_hash->{"_t_$attr"}+$sessionCacheTimeout;
			my $t_cur = time;
			if ( $t_out < $t_cur ) {
				warn(__PACKAGE__," => _getParam() $attr expired : $t_out $t_cur");
				delete($current_hash->{$attr});
				delete($current_hash->{"_t_$attr"});
				return undef;
			}
		}
	}
	return $current_hash->{$attr};
}

sub _section_exists {
	my $self = shift;
	my $section = shift;
	return 0 if !defined($self->{_session_});
	return 0 if (!$section || length($section) <= 0);
	return 1 if ( exists($self->{_session_}->{"_s_$section"}) && ref($self->{_session_}->{"_s_$section"}) eq "HASH");
	return 0;
}

# create a new section 
# return 1 if section exists or is created otherwise 0
sub _create_section {
	my $self = shift;
	my $section = shift;
	return 0 if !defined($self->{_session_});
	return 0 if (!$section || !length($section));
	if ( ! $self->_section_exists($section) ) {
		$self->{_session_}->{"_s_$section"} = {};
		# set timestamp
		$self->_mark_update();
	}
	return 1;
}

sub _get_section {
	my $self = shift;
	my $section = shift;
	return undef if (!$section || !length($section));
	return (exists($self->{_session_}->{"_s_$section"}) && ref($self->{_session_}->{"_s_$section"}) eq "HASH")?$self->{_session_}->{"_s_$section"}:undef;
}

sub getTimestamp {
	my $self = shift;
	my $attr = shift;
	my ($p,$f,$c) = caller;
	warn(__PACKAGE__," => getTimestamp() require a parameter") && return undef if !defined($attr) || ref($attr);
	# param name cannot begin with _
	warn(__PACKAGE__," => getTimestap() attr cannot begin with '_'") && return undef if ( $attr =~ /^_/ );
	return $self->_getParam("_t_$attr",$p);
}

sub getParam {
	my $self = shift;
	my $attr = shift;
	my ($p,$f,$l) = caller;
	# param name cannot begin with _
	warn(__PACKAGE__," => getParam() attr cannot begin with '_'") && return undef if ( $attr =~ /^_/ );
	return $self->_getParam($attr,$p);
}

# set parameter
# name=>value,[timestamp]
# return old value if any
sub setParam {
	my $self = shift;
	my ($attr,$value,$ts) = @_;
	my ($p,$f,$l) = caller;
	warn(__PACKAGE__," => setParam() require attr,value pair") && return undef 
		if !defined($attr) || ref($attr) || !defined($value);
	warn(__PACKAGE__," => setParam() attr cannot begin with '_'") && return undef if ( $attr =~ /^_/ );
	return $self->_setParam($attr,$value,$ts,$p);
}

sub delParam {
	my $self = shift;
	my $attr = shift;
	my ($p,$f,$l) = caller;
	warn(__PACKAGE__," => delParam() require a parameter") && return undef if !defined($attr) || ref($attr);
	# param name cannot begin with _
	warn(__PACKAGE__," => delParam() attr cannot begin with '_'") && return undef if ( $attr =~ /^_/ );
	return $self->_delParam($attr,$p);
}

1;
