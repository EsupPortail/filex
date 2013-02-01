package FILEX::DB::Upload;
use strict;
use vars qw($VERSION @ISA);
use FILEX::DB::base;
use Digest::MD5 qw(md5_hex);

@ISA = qw(FILEX::DB::base);
$VERSION = 1.2;

# the constructor
# without values, create a new upload entry
# with id or file_name, populate the object with database field
sub new {
	my $this = shift;
	my $class = ref($this)||$this;
	# explicitely call the super class
	my $self = $class->SUPER::new();
	# beware of name clash when feeding the class properties
	$self->{'_UPLOAD_'} = {
		is_new => 1,
		exist => 0,
		expired => 0,
		data_change => 0,
		expire_change => 0,
		expire_days => 0,
		fields => {
			id => undef,
			real_name => undef,
			file_name => undef,
			file_size => undef,
			ts_upload_date => undef,
			ts_expire_date => undef,
			download_count => undef,
		  is_downloaded => undef,
			owner => undef,
			content_type => undef,
			enable => undef,
			deleted => undef, 
			get_delivery => undef,
			get_resume => undef,
			ip_address => undef,
			use_proxy => undef,
			proxy_infos => undef,
			renew_count => undef,
			with_password => undef,
			password => undef,
			user_agent => undef,
			owner_uniq_id => undef
		}
	};
	my %ARGZ = @_;
	if ( exists($ARGZ{'id'}) || exists($ARGZ{'file_name'}) ) {
		$self->_initialize(@_);
	}
	bless($self,$class);
	return $self;
}

# initialize
sub _initialize(%){
	my $self = shift;
	my %argz = @_;

	my ($where,$dbh);
	$dbh = $self->_dbh();
	if ( exists($argz{'id'}) ) {
		$where = "WHERE u.id = ".$argz{'id'}." ";
	} else {
		$where = "WHERE u.file_name = ".$dbh->quote($argz{'file_name'})." ";
	}
	my $strQuery = "SELECT u.*, NOW() > expire_date AS expired, ".
                 "UNIX_TIMESTAMP(upload_date) AS ts_upload_date,".
                 "UNIX_TIMESTAMP(expire_date) AS ts_expire_date,".
	               "COUNT(g.upload_id) - SUM(g.admin_download) AS download_count, ".
	               "COUNT(cd.upload_id) AS is_downloaded ".
                 "FROM upload AS u ".
                 "LEFT JOIN get AS g ON u.id = g.upload_id ".
	               "LEFT JOIN current_download AS cd ON u.id = cd.upload_id ".
                 $where.
                 "GROUP BY id";
	my $res;
	eval {
		my $sth = $dbh->prepare($strQuery);
		$sth->execute();
		$res = $sth->fetchrow_hashref();
	};
	if ($@) {
		$self->setLastError(string=>$dbh->errstr(),code=>$dbh->err(),query=>$strQuery);
		warn(__PACKAGE__,"-> Database Error : $@ : $strQuery");
		return undef;
	}
	# fill in the fields
	if ( !$res ) {
		$self->setLastError(string=>"[ $where ] record does not exists !",code=>-1,query=>$strQuery);
		$self->{'_UPLOAD_'}->{'exist'} = 0;
		return 1;
	}
	# populate
	foreach my $k ( keys(%{$self->{'_UPLOAD_'}->{'fields'}}) ) {
		warn(__PACKAGE__,"field [ $k ] does not exists in resulting query !") && next if ( ! exists($res->{$k}) );
		$self->{'_UPLOAD_'}->{'fields'}->{$k} = $res->{$k};
	}
	$self->{'_UPLOAD_'}->{'is_new'} = 0;
	$self->{'_UPLOAD_'}->{'expired'} = $res->{'expired'};
	$self->{'_UPLOAD_'}->{'exist'} = 1;
	$self->{'_UPLOAD_'}->{'data_change'} = 0;
	$self->{'_UPLOAD_'}->{'expire_change'} = 0;
	return 1;
}

sub save {
	my $self = shift;
	my $res;
	#return 1 if !$self->exists();
	if ( $self->{'_UPLOAD_'}->{'is_new'} == 1 ) {
		$res = $self->_create();
	} else {
		$res = $self->_update();
	}
	return $res;
}

# update record
sub _update {
	my $self = shift;
	my $dbh = $self->_dbh();
	my ($strQuery,$value,@fields);
	return 1 if ( $self->{'_UPLOAD_'}->{'data_change'} == 0 );
	# enable
	$value = $self->{'_UPLOAD_'}->{'fields'}->{'enable'};
	if ( defined($value) ) {
		if ( !$self->checkBool($value) ) {
			$self->setLastError(string=>"[ enable ] invalid field format",code=>-3,query=>$value);
		} else {
			push(@fields,"enable=$value");
		}
	}
	# deleted
	$value = $self->{'_UPLOAD_'}->{'fields'}->{'deleted'};
	if ( defined($value) ) {
		if ( !$self->checkBool($value) ) {
			$self->setLastError(string=>"[ deleted ] invalid field format",code=>-3,query=>$value);
		} else {
			push(@fields,"deleted=$value");
		}
	}
	# get_delivery
	$value = $self->{'_UPLOAD_'}->{'fields'}->{'get_delivery'};
	if ( defined($value) ) {
		if ( !$self->checkBool($value) ) {
			$self->setLastError(string=>"[ get_delivery ] invalid field format",code=>-3,query=>$value);
		} else {
			push(@fields,"get_delivery=$value");
		}
	}
	# get_resume
	$value = $self->{'_UPLOAD_'}->{'fields'}->{'get_resume'};
	if ( defined($value) ) {
		if ( !$self->checkBool($value) ) {
			$self->setLastError(string=>"[ get_resume ] invalid field format",code=>-3,query=>$value);
		} else {
			push(@fields,"get_resume=$value");
		}
	}
	# expire_change
	$value = $self->{'_UPLOAD_'}->{'fields'}->{'ts_expire_date'};
	if ( defined($value) ) {
		if ( !$self->checkUInt($value) ) {
			$self->setLastError(string=>"[ expire_date ] invalid field format",code=>-3,query=>$value);
		} else {
			push(@fields,"expire_date=FROM_UNIXTIME($value)");
		}
	}
	# need password
	# TODO : voir si nécéssaire de ne pas positionner le flag with_password
	# si problème sur password ! dans _create aussi
	$value = $self->{'_UPLOAD_'}->{'fields'}->{'with_password'};
	if ( defined($value) ) {
		if ( !$self->checkBool($value) ) {
			$self->setLastError(string=>"[ with_password ] invalid field format",code=>-3,query=>$value);
		} else {
			push(@fields,"with_password=$value");
			if ( $value ) {
				$value = $self->{'_UPLOAD_'}->{'fields'}->{'password'};
				if ( !$self->checkStrLength($value,0,33) ) {
          $self->setLastError(string=>"[ password ] invalid field format",code=>-3,query=>"$value");
        } else {
        	push(@fields,"password=".$dbh->quote($value));
        }
			}
		}
	}
	# renew_count (if expire_change)
	if ( $self->{'_UPLOAD_'}->{'expire_change'} ) {
		push(@fields,"renew_count=renew_count+1");
	}
	# generate query
	return 1 if ( $#fields < 0 );
	$strQuery = "UPDATE upload SET ".
              join(",",@fields).
              " WHERE id=".$self->{'_UPLOAD_'}->{'fields'}->{'id'};
	# go on
	eval {
		my $sth = $dbh->prepare($strQuery);
		$sth->execute();
		$dbh->commit();
	};
	if ($@) {
		$self->setLastError(string=>$dbh->errstr(),code=>$dbh->err(),query=>$strQuery);
		return undef;
	}
	$self->{'_UPLOAD_'}->{'data_change'} = 0;
	$self->{'_UPLOAD_'}->{'expire_change'} = 0;
	# reload datas
	return $self->_initialize(id=>$self->{'_UPLOAD_'}->{'fields'}->{'id'});
}

# create new record
sub _create {
	my $self = shift;
	my $dbh = $self->_dbh();
	my ($strQuery,$value,@fields,@values);
	# no change nothing to do
	return 1 if ($self->{'_UPLOAD_'}->{'data_change'} == 0);
	# real_name
	$value = $self->{'_UPLOAD_'}->{'fields'}->{'real_name'};
	if ( !defined($value) || ! $self->checkStrLength($value,0,256) ) {
		$self->setLastError(string=>"[ real_name ] must exists or invalid field format",code=>-2,query=>"$value");
		return undef;
	} else {
		push(@fields,"real_name");
		push(@values,$dbh->quote($value));
	}
	# file_name
	$value = $self->{'_UPLOAD_'}->{'fields'}->{'file_name'};
  if ( !defined($value) || !$self->checkStrLength($value,0,256) ) {
    $self->setLastError(string=>"[ file_name ] must exists or invalid field format",code=>-2,query=>"$value");
    return undef;
  } else {
		push(@fields,"file_name");
		push(@values,$dbh->quote($value));
  }
	# file_size
	$value = $self->{'_UPLOAD_'}->{'fields'}->{'file_size'};
  if ( !defined($value) || !$self->checkUInt($value) ) {
    $self->setLastError(string=>"[ file_size ] must exists or invalid field format",code=>-2,query=>"$value");
    return undef;
  } else {
		push(@fields,"file_size");
		push(@values,$value);
  }
	# owner
	$value = $self->{'_UPLOAD_'}->{'fields'}->{'owner'};
  if ( !defined($value) || !$self->checkStrLength($value,0,256) ) {
    $self->setLastError(string=>"[ owner ] must exists or invalid field format",code=>-2,query=>"$value");
    return undef;
  } else {
		push(@fields,"owner");
		push(@values,$dbh->quote($value));
  }
	# owner_uniq_id
	$value = $self->{'_UPLOAD_'}->{'fields'}->{'owner_uniq_id'};
  if ( !defined($value) || !$self->checkStrLength($value,0,256) ) {
    $self->setLastError(string=>"[ owner_uniq_id ] must exists or invalid field format",code=>-2,query=>"$value");
    return undef;
  } else {
		push(@fields,"owner_uniq_id");
		push(@values,$dbh->quote($value));
  }
	# get_resume (not mandatory)
	$value = $self->{'_UPLOAD_'}->{'fields'}->{'get_resume'};
	if ( defined($value) ) {
		if ( !$self->checkBool($value) ) {
			$self->setLastError(string=>"[ get_resume ] invalid field format",code=>-3,query=>"$value");
		} else {
			push(@fields,"get_resume");
			push(@values,$value);
		}
	}
	# get_delivery (not mandatory)
	$value = $self->{'_UPLOAD_'}->{'fields'}->{'get_delivery'};
	if ( defined($value) ) {
		if ( !$self->checkBool($value) ) {
			$self->setLastError(string=>"[ get_delivery ] invalid field format",code=>-3,query=>"$value");
		} else {
			push(@fields,"get_delivery");
			push(@values,$value);
		}
	}
	# content_type (not mandatory)
	$value = $self->{'_UPLOAD_'}->{'fields'}->{'content_type'};
	if ( defined($value) ) {
		if ( !$self->checkStrLength($value,0,256) ) {
			$self->setLastError(string=>"[ content_type ] invalid field format",code=>-3,query=>"$value");
		} else {
			push(@fields,"content_type");
			push(@values,$dbh->quote($value));
		}
	}
	# ip_address (not mandatory)
	$value = $self->{'_UPLOAD_'}->{'fields'}->{'ip_address'};
	if ( defined($value) ) {
		if ( !$self->checkStr($value) ) {
			$self->setLastError(string=>"[ ip_address ] invalid field format",code=>-3,query=>"$value");
		} else {
			push(@fields,"ip_address");
			push(@values,$dbh->quote($value));
		}
	}
	# use_proxy (not mandatory)
	$value = $self->{'_UPLOAD_'}->{'fields'}->{'use_proxy'};
	if ( defined($value) ) {
		if ( !$self->checkBool($value) ) {
			$self->setLastError(string=>"[ use_proxy ] invalid field format",code=>-3,query=>"$value");
		} else {
			push(@fields,"use_proxy");
			push(@values,$value);
		}
	}
	# proxy_info (not mandatory)
	$value = $self->{'_UPLOAD_'}->{'fields'}->{'proxy_infos'};
	if ( defined($value) ) {
		if ( !$self->checkStrLength($value,0,256) ) {
			$self->setLastError(string=>"[ proxy_infos ] invalid field format",code=>-3,query=>"$value");
		} else {
			push(@fields,"proxy_infos");
			push(@values,$dbh->quote($value));
		}
	}
	# user_agent (not mandatory)
	$value = $self->{'_UPLOAD_'}->{'fields'}->{'user_agent'};
	if ( defined($value) ) {
		if ( !$self->checkStrLength($value,0,256) ) {
			$self->setLastError(string=>"[ user_agent ] invalid field format",code=>-3,query=>"$value");
		} else {
			push(@fields,"user_agent");
			push(@values,$dbh->quote($value));
		}
	}
	# password (not mandatory)
	$value = $self->{'_UPLOAD_'}->{'fields'}->{'with_password'};
	if ( defined($value) ) {
		if ( !$self->checkBool($value) ) {
			$self->setLastError(string=>"[ with_password ] invalid field format",code=>-3,query=>"$value");
		} else {
			push(@fields,"with_password");
			push(@values,$value);
			# go for the real password
			# TODO
			if ( $value ) {
				$value = $self->{'_UPLOAD_'}->{'fields'}->{'password'};
				if ( defined($value) ) {
					if ( !$self->checkStrLength($value,0,33) ) {
						$self->setLastError(string=>"[ password ] invalid field format",code=>-3,query=>"$value");
					} else {
						push(@fields,"password");
						push(@values,$dbh->quote($value));
					}
				}
			}
		}
	}
	
	# upload_date && expire_date
	my ($def_days,$u_date,$exp_date,$res_up,$res_exp);
	$def_days = $self->_config->getDefaultFileExpire();
	$u_date = $self->{'_UPLOAD_'}->{'fields'}->{'ts_upload_date'};
	#$exp_date = $self->{'_UPLOAD_'}->{'fields'}->{'ts_expire_date'};
	# default time
	my $current_gmtime = time();
	# delta days
	my $delta_days = ( $self->{'_UPLOAD_'}->{'expire_days'} ) ? $self->{'_UPLOAD_'}->{'expire_days'} : $def_days;
	if (  !defined($u_date) || !$self->checkUInt($u_date) ) {
			$self->setLastError("[ upload_date ] invalid field format setting default",code=>-3,query=>"$u_date");
			$u_date = $current_gmtime;
	}
	$exp_date = addDeltaDays($u_date,$delta_days);
	$self->{'_UPLOAD_'}->{'fields'}->{'ts_expire_date'} = $exp_date;
	$res_up = "FROM_UNIXTIME($u_date)";
	$res_exp = "FROM_UNIXTIME($exp_date)";
	push(@fields,"upload_date");
	push(@values,$res_up);
	push(@fields,"expire_date");
	push(@values,$res_exp);
	# build the query sting
	$strQuery = "INSERT INTO upload (".join(",",@fields).") VALUES (".join(",",@values).")";
	eval {
		my $sth = $dbh->prepare($strQuery);
		$sth->execute();
		$dbh->commit();
	};
	# everythings ok ?
	if ($@) {
		$self->setLastError(string=>$dbh->errstr(),code=>$dbh->err(),query=>$strQuery);
		return undef;
	}
	# reload the entire content	
	return $self->_initialize(file_name=>$self->{'_UPLOAD_'}->{'fields'}->{'file_name'});
}

# set only if new
sub setRealName {
	my $self = shift;
	my $value = shift;
	if ( $self->{'_UPLOAD_'}->{'is_new'} != 1 ) {
    warn(__PACKAGE__,"-> Can only set [ real_name ] on new record");
    return;
  }
	$self->{'_UPLOAD_'}->{'fields'}->{'real_name'} = $value;
	$self->{'_UPLOAD_'}->{'data_change'} ++;
}
sub getRealName {
	my $self = shift;
	return $self->{'_UPLOAD_'}->{'fields'}->{'real_name'};
}

# set only if new
sub setFileName {
	my $self = shift;
	my $value = shift;
	if ( $self->{'_UPLOAD_'}->{'is_new'} != 1 ) {
    warn(__PACKAGE__,"-> Can only set [ file_name ] on new record");
    return;
  }
	$self->{'_UPLOAD_'}->{'fields'}->{'file_name'} = $value;
	$self->{'_UPLOAD_'}->{'data_change'} ++;
}
sub getFileName {
	my $self = shift;
	return $self->{'_UPLOAD_'}->{'fields'}->{'file_name'};
}

# set only if new
sub setFileSize {
	my $self = shift;
	my $value = shift;
	if ( $self->{'_UPLOAD_'}->{'is_new'} != 1 ) {
    warn(__PACKAGE__,"-> Can only set [ file_size ] on new record");
    return;
  }
	$self->{'_UPLOAD_'}->{'fields'}->{'file_size'} = $value;
	$self->{'_UPLOAD_'}->{'data_change'} ++;
}
sub getFileSize {
	my $self = shift;
	return $self->{'_UPLOAD_'}->{'fields'}->{'file_size'};
}

# set only if new
sub setUploadDate {
	my $self = shift;
	my $value = shift;
	if ( $self->{'_UPLOAD_'}->{'is_new'} != 1 ) {
    warn(__PACKAGE__,"-> Can only set [ upload_date ] on new record");
    return;
  }
	$self->{'_UPLOAD_'}->{'fields'}->{'ts_upload_date'} = $value;
	$self->{'_UPLOAD_'}->{'data_change'} ++;
}
sub getUploadDate {
	my $self = shift;
	return $self->{'_UPLOAD_'}->{'fields'}->{'ts_upload_date'};
}

# set number of days before expirations
sub setExpireDays {
	my $self = shift;
	my $value = shift;
	if ( $self->{'_UPLOAD_'}->{'is_new'} != 1 ) {
		warn(__PACKAGE__,"-> Can only be set on new record");
		return;
	}
	$self->{'_UPLOAD_'}->{'expire_days'} = $value;
	$self->{'_UPLOAD_'}->{'data_change'}++;
}

# unneeded : internal computing
# set only if new
#sub setExpireDate {
#	my $self = shift;
#	my $value = shift;
#	if ( $self->{'_UPLOAD_'}->{'is_new'} != 1 ) {
#   warn(__PACKAGE__,"-> Can only set [ upload_date ] on new record");
#    return;
#  }
#	$self->{'_UPLOAD_'}->{'fields'}->{'ts_expire_date'} = $value;
#	$self->{'_UPLOAD_'}->{'data_change'} ++;
#}

sub getExpireDate {
	my $self = shift;
	return $self->{'_UPLOAD_'}->{'fields'}->{'ts_expire_date'};
}

sub makeExpire {
	my $self = shift;
	$self->{'_UPLOAD_'}->{'fields'}->{'ts_expire_date'} = time()-3600;
	$self->{'_UPLOAD_'}->{'data_change'} ++;
}
# set only if new
sub setOwner {
	my $self = shift;
	my $value = shift;
	if ( $self->{'_UPLOAD_'}->{'is_new'} != 1 ) {
		warn(__PACKAGE__,"-> Can only set [ owner ] on new record");
		return;
	}
	$self->{'_UPLOAD_'}->{'fields'}->{'owner'} = $value;
	$self->{'_UPLOAD_'}->{'data_change'} ++;
}
sub getOwner {
	my $self = shift;
	return $self->{'_UPLOAD_'}->{'fields'}->{'owner'};
}
# set only if new
sub setOwnerUniqId {
	my $self = shift;
	my $value = shift;
	if ( $self->{'_UPLOAD_'}->{'is_new'} != 1 ) {
		warn(__PACKAGE__,"-> Can only set [ owner_uniq_id ] on new record");
		return;
	}
	$self->{'_UPLOAD_'}->{'fields'}->{'owner_uniq_id'} = $value;
	$self->{'_UPLOAD_'}->{'data_change'} ++;
}
sub getOwnerUniqId {
	my $self = shift;
	return $self->{'_UPLOAD_'}->{'fields'}->{'owner_uniq_id'};
}
# set only if new
sub setContentType {
	my $self = shift;
	my $value = shift;
	if ( $self->{'_UPLOAD_'}->{'is_new'} != 1 ) {
		warn(__PACKAGE__,"-> Can only set [ content_type ] on new record");
		return;
	}
	$self->{'_UPLOAD_'}->{'fields'}->{'content_type'} = $value;
	$self->{'_UPLOAD_'}->{'data_change'} ++;
}
sub getContentType {
	my $self = shift;
	return $self->{'_UPLOAD_'}->{'fields'}->{'content_type'};
}

sub setEnable {
	my $self = shift;
	my $value = shift;
	$self->{'_UPLOAD_'}->{'fields'}->{'enable'} = $value;
	$self->{'_UPLOAD_'}->{'data_change'} ++;
}
sub getEnable {
	my $self = shift;
	return $self->{'_UPLOAD_'}->{'fields'}->{'enable'};
}

sub setDeleted {
	my $self = shift;
	my $value = shift;
	$self->{'_UPLOAD_'}->{'fields'}->{'deleted'} = $value;
	$self->{'_UPLOAD_'}->{'data_change'} ++;
}
sub getDeleted {
	my $self = shift;
	return $self->{'_UPLOAD_'}->{'fields'}->{'deleted'};
}

sub setGetDelivery {
	my $self = shift;
	my $value = shift;
	$self->{'_UPLOAD_'}->{'fields'}->{'get_delivery'} = $value;
	$self->{'_UPLOAD_'}->{'data_change'} ++;
}
sub getGetDelivery {
	my $self = shift;
	return $self->{'_UPLOAD_'}->{'fields'}->{'get_delivery'};
}

sub setGetResume {
	my $self = shift;
	my $value = shift;
	$self->{'_UPLOAD_'}->{'fields'}->{'get_resume'} = $value;
	$self->{'_UPLOAD_'}->{'data_change'} ++;
}
sub getGetResume {
	my $self = shift;
	return $self->{'_UPLOAD_'}->{'fields'}->{'get_resume'};
}

# set the password for file download
# without args, unset the password
sub setPassword {
	my $self = shift;
	my $password = shift;
	# password exists then set it
	if ( defined($password) && length($password) ) {
		$self->{'_UPLOAD_'}->{'fields'}->{'with_password'} = 1;
		$self->{'_UPLOAD_'}->{'fields'}->{'password'} = md5_hex($password);
	} else {
		$self->{'_UPLOAD_'}->{'fields'}->{'with_password'} = 0;
		$self->{'_UPLOAD_'}->{'fields'}->{'password'} = undef;
	}
	$self->{'_UPLOAD_'}->{'data_change'} ++;
}

sub verifyPassword {
	my $self = shift;
	my $password = shift;
	return 1 if ( ! $self->needPassword() );
	return 1 if ( $self->{'_UPLOAD_'}->{'fields'}->{'password'} eq md5_hex($password) );
	return 0;
}

sub needPassword {
	my $self = shift;
	return $self->{'_UPLOAD_'}->{'fields'}->{'with_password'};
}


# set only if new
sub setIpAddress {
	my $self = shift;
	my $value = shift;
	if ( $self->{'_UPLOAD_'}->{'is_new'} != 1 ) {
		warn(__PACKAGE__,"-> Can only set [ ip_address ] on new record");
		return;
	}
	$self->{'_UPLOAD_'}->{'fields'}->{'ip_address'} = $value;
	$self->{'_UPLOAD_'}->{'data_change'} ++;
}
sub getIpAddress {
	my $self = shift;
	return $self->{'_UPLOAD_'}->{'fields'}->{'ip_address'};
}

# set only if new
sub setUseProxy {
	my $self = shift;
	my $value = shift;
	if ( $self->{'_UPLOAD_'}->{'is_new'} != 1 ) {
		warn(__PACKAGE__,"-> Can only set [ use_proxy ] on new record");
		return;
	}
	$self->{'_UPLOAD_'}->{'fields'}->{'use_proxy'} = $value;
	$self->{'_UPLOAD_'}->{'data_change'} ++;
}
sub getUseProxy {
	my $self = shift;
	return $self->{'_UPLOAD_'}->{'fields'}->{'use_proxy'};
}

# set only if new
sub setProxyInfos {
	my $self = shift;
	my $value = shift;
	if ( $self->{'_UPLOAD_'}->{'is_new'} != 1 ) {
		warn(__PACKAGE__,"-> Can only set [ proxy_info ] on new record");
		return;
	}
	$self->{'_UPLOAD_'}->{'fields'}->{'proxy_infos'} = $value;
	$self->{'_UPLOAD_'}->{'data_change'} ++;
}
sub getProxyInfos {
	my $self = shift;
	return $self->{'_UPLOAD_'}->{'fields'}->{'proxy_infos'};
}

# set user_agent string
sub setUserAgent {
	my $self = shift;
	my $value = shift;
	if ( $self->{'_UPLOAD_'}->{'is_new'} != 1 ) {
		warn(__PACKAGE__,"-> Can only set [ user_agent ] on new record");
		return;
	}
	$self->{'_UPLOAD_'}->{'fields'}->{'user_agent'} = $value;
	$self->{'_UPLOAD_'}->{'data_change'}++;
}
sub getUserAgent {
	my $self = shift;
	return $self->{'_UPLOAD_'}->{'fields'}->{'user_agent'};
}

# 
sub getRenewCount {
	my $self = shift;
	$self->{'_UPLOAD_'}->{'fields'}->{'renew_count'};
}

sub getId {
	my $self = shift;
	$self->{'_UPLOAD_'}->{'fields'}->{'id'};
}

# HELPER METHODS
# check if current record has expired
sub isExpired {
	my $self = shift;
	return $self->{'_UPLOAD_'}->{'expired'};
}
# check if current record exists
sub exists {
	my $self = shift;
	return $self->{'_UPLOAD_'}->{'exist'};
}
# add n days to expire_date
sub extendExpireDate {
	my $self = shift;
	my $days = shift;
	if ( defined($self->{'_UPLOAD_'}->{'fields'}->{'ts_expire_date'}) ) {
		$self->{'_UPLOAD_'}->{'fields'}->{'ts_expire_date'} = addDeltaDays($self->{'_UPLOAD_'}->{'fields'}->{'ts_expire_date'},$days);
		# set mark
		$self->{'_UPLOAD_'}->{'data_change'} ++;
		$self->{'_UPLOAD_'}->{'expire_change'} = 1;
	}
}
# check owner
sub checkOwner {
	my $self = shift;
	my $owner = shift;
	return ( $owner eq $self->{'_UPLOAD_'}->{'fields'}->{'owner_uniq_id'} )?1:0;
}
# add download record
sub addDownloadRecord {
	my $self = shift;
	my %ARGZ = @_;
	my %fields;
	my $dbh = $self->_dbh();
	if ( !exists($ARGZ{'upload_id'}) || !defined($ARGZ{'upload_id'}) ) {
		$self->setLastError(string=>"require a upload id",query=>"",code=>-1);
		return undef;
	}
	$fields{'upload_id'} = $ARGZ{'upload_id'};
	$fields{'ip_address'} = $dbh->quote($ARGZ{'ip_address'});
	# proxy infos
  if ( exists($ARGZ{'proxy_infos'}) && defined($ARGZ{'proxy_infos'}) && $self->checkStrLength($ARGZ{'proxy_infos'},0,256) ) {
		$fields{'proxy_infos'} = $dbh->quote($ARGZ{'proxy_infos'});
	}
	$fields{'use_proxy'} = ( exists($ARGZ{'use_proxy'}) && $ARGZ{'use_proxy'} == 1 ) ? 1 : 0;
	$fields{'date'} = "NOW()";
	$fields{'canceled'} = ( exists($ARGZ{'canceled'}) && $ARGZ{'canceled'} == 1 ) ? 1 : 0;
	# user agent
  if ( exists($ARGZ{'user_agent'}) && defined($ARGZ{'user_agent'}) && $self->checkStrLength($ARGZ{'user_agent'},0,256) ) {
		$fields{'user_agent'} = $dbh->quote($ARGZ{'user_agent'});
	}
	# administrative download
	$fields{'admin_download'} = ( exists($ARGZ{'admin_download'}) && $ARGZ{'admin_download'} == 1 ) ? 1 : 0;

	my (@f,@v);
	while ( my($k,$i) = each(%fields) ) {
		push(@f,$k);
		push(@v,$i);
	}
	my $strQuery = "INSERT INTO get(".join(",",@f).") VALUES (".join(",",@v).")";
	eval {
		my $sth = $dbh->prepare($strQuery);
		$sth->execute();
		$dbh->commit();
	};
	if ($@) {
		$self->setLastError(query=>$strQuery,string=>$dbh->errstr(),code=>$dbh->err());
		return undef;
	}
	return 1;
}
# get Download count
sub getDownloadCount {
	my $self = shift;
	return $self->{'_UPLOAD_'}->{'fields'}->{'download_count'} || 0;
}
# is downloaded
sub isDownloaded {
	my $self = shift;
	return ( $self->{'_UPLOAD_'}->{'fields'}->{'is_downloaded'} ) ? 1 : 0;
}
# list downloads for this file
# results => require a ref to an ARRAY
# admin_mode => 1|0. if 1 the retrieve also administrative download 
sub getDownloads {
	my $self = shift;
	my %ARGZ = @_;
	my $results = ( exists($ARGZ{'results'}) && (ref($ARGZ{'results'}) eq "ARRAY") ) ? $ARGZ{'results'} : undef;
	my $admin_mode = ( exists($ARGZ{'admin_mode'}) && defined($ARGZ{'admin_mode'}) && ($ARGZ{'admin_mode'} =~ /^1$/) ) ? 1 : 0;
	#my $results = shift;
	#$self->setLastError(string=>"Require an ArrayRef",code=>-1,query=>"") && return undef if ( ref($results) ne "ARRAY" );
	$self->setLastError(string=>"Require an ArrayRef",code=>-1,query=>"") && return undef if ( !defined($results) );
	return 1 if ( $self->{'_UPLOAD_'}->{'is_new'} == 1 );
	my $dbh = $self->_dbh();
	my $strQuery = "SELECT *, UNIX_TIMESTAMP(date) AS ts_date ".
	               "FROM get ".
	               "WHERE upload_id = ".$self->{'_UPLOAD_'}->{'fields'}->{'id'}." ";
	$strQuery .= "AND admin_download != 1 " if ( $admin_mode == 0 );
	$strQuery .= "ORDER BY date DESC";
	eval {
		my $sth = $dbh->prepare($strQuery);
		$sth->execute();
		while ( my $r = $sth->fetchrow_hashref() ) {
			push(@$results,$r);
		}
	};
	if ($@) {
		$self->setLastError(string=>$dbh->errstr(),code=>$dbh->err(),query=>$strQuery);
		return undef;
	}
  return 1;              
}

sub addDeltaDays {
	my $time = shift;
	my $days = shift;
	return int($time) + (int($days)*(24*3600));
}

1;
