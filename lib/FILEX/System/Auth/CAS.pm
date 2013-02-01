package FILEX::System::Auth::CAS;
use strict;
use LWP::UserAgent;
use IO::Socket::SSL;
use File::Spec;
use Carp;

# olivier.franco@insa-lyon.fr
# 16/09/2005 -> no more call to escape_chars because it breaks url on a proxied application with
# uPortal : CWebProxy Module use '&' as query string parameter delimiter when requesting PT for the application
# and validatePT escape '&' to 0x26 thus PT requested by CWebProxy for this service cannot be validate :
# CWebProxy PT service request : 
# https://cas.my.domain/cas/proxy?pgt=PGT-xxx&targetService=https://proxied.my.domain/serice?p1=0&p2=1&p3=2
# Proxied app PT service validate : http://my.host.my.domain/service?p1=1%26p2=2%26p3=3
# https://cas.my.domain/cas/proxyValidate?service=https://proxied.my.domain/service?p1=0%26p2=1%26p3=2&ticket=PT-xxx

sub new {
    my($pkg, %param) = @_;
    my $cas_server = {};
    
    $cas_server->{'url'} = $param{'casUrl'};
    $cas_server->{'CAFile'} = $param{'CAFile'};
    $cas_server->{'CAPath'} = $param{'CAPath'};

    $cas_server->{'loginPath'} = $param{'loginPath'} || '/login';
    $cas_server->{'logoutPath'} = $param{'logoutPath'} || '/logout';
    $cas_server->{'serviceValidatePath'} = $param{'serviceValidatePath'} || '/serviceValidate';
    $cas_server->{'proxyPath'} = $param{'proxyPath'} || '/proxy';
    $cas_server->{'proxyValidatePath'} = $param{'proxyValidatePath'} || '/proxyValidate';
		$cas_server->{'errors'} = undef;
		# proxy mode
		$cas_server->{'pgtFile'} = undef;
		$cas_server->{'pgtUseFiles'} = undef;
		$cas_server->{'pgtCallbackUrl'} = undef;
		$cas_server->{'proxy'} = undef;
		$cas_server->{'pgtIou'} = undef;
		$cas_server->{'pgtId'} = undef;

    bless $cas_server, $pkg;

    return $cas_server;
}

## Return module errors
sub get_errors {
		my $self = shift;
    return $self->{'errors'};
}

## Use the CAS object as a proxy
## parameters :
## pgtFile -> the file where PGT's are stored
## pgtCallbackUrl -> the callback url
## pgtUseFiles -> boolean, if 1 store pgt as standalone files on disk. The pgtFile must be in this case a directory
sub proxyMode {
    my $self = shift;
    my %param = @_;

    $self->{'pgtFile'} = $param{'pgtFile'};
		# an attempt to use proxy ticket on file on disk
		$self->{'pgtUseFiles'} = (exists($param{'pgtUseFiles'})) ? 1 : undef;
    $self->{'pgtCallbackUrl'} = $param{'pgtCallbackUrl'};
    $self->{'proxy'} = 1;
    
    return 1;
}

## Escape dangerous chars in URLS
sub _escape_chars {
    my $s = shift;    

    ## Escape chars
    ##  !"#$%&'()+,:;<=>?[] AND accented chars
    ## escape % first
#   foreach my $i (0x25,0x20..0x24,0x26..0x2c,0x3a..0x3f,0x5b,0x5d,0x80..0x9f,0xa0..0xff) {
    foreach my $i (0x26) {
			my $hex_i = sprintf("%lx", $i);
			$s =~ s/\x$hex_i/%$hex_i/g;
    }

    return $s;
}

sub dump_var {
    my ($var, $level, $fd) = @_;
    
    if (ref($var)) {
			if (ref($var) eq 'ARRAY') {
				foreach my $index (0..$#{$var}) {
					print $fd "\t"x$level.$index."\n";
					&dump_var($var->[$index], $level+1, $fd);
	    	}
			} elsif (ref($var) eq 'HASH') {
				foreach my $key (sort keys %{$var}) {
					print $fd "\t"x$level.'_'.$key.'_'."\n";
					&dump_var($var->{$key}, $level+1, $fd);
	    	}    
			}
    } else {
			if (defined $var) {
				print $fd "\t"x$level."'$var'"."\n";
			} else {
				print $fd "\t"x$level."UNDEF\n";
			}
    }
}

## Parse an HTTP URL 
sub _parse_url {
		my $self = shift;
    my $url = shift;

    my ($host, $port, $path);

    if ($url =~ /^(https?):\/\/([^:\/]+)(:(\d+))?(.*)$/) {
	$host = $2;
	$path = $5;
	if ($1 eq 'http') {
	    $port = $4 || 80;
	}elsif ($1 eq 'https') {
	    $port = $4 || 443;
	}else {
	    $self->{'errors'} = sprintf("Unknown protocol '%s'", $1);
	    return undef;
	}
    }else {
	$self->{'errors'} = sprintf("Unable to parse URL '%s'", $url);
	return undef;
    }

    return ($host, $port, $path);
}

## Simple XML parser
sub _parse_xml {
    my $data = shift;

    my %xml_struct;

    while ($data =~ /^<([^\s>]+)(\s+[^\s>]+)?>([\s\S\n]*)(<\/\1>)/m) {
	my ($new_tag, $new_data) = ($1,$3);
	chomp $new_data;
	$new_data =~ s/^[\s\n]+//m;
	$data =~ s/^<$new_tag(\s+[^\s>]+)?>([\s\S\n]*)(<\/$new_tag>)//m;
	$data =~ s/^[\s\n]+//m;
	
	## Check if data still includes XML tags
	my $struct;
	if ($new_data =~/^<([^\s>]+)(\s+[^\s>]+)?>([\s\S\n]*)(<\/\1>)/m) {
	    $struct = &_parse_xml($new_data);
	}else {
	    $struct = $new_data;
	}
	push @{$xml_struct{$new_tag}}, $struct;
    }
    
    return \%xml_struct;
}

sub getServerLoginURL {
    my $self = shift;
    my $service = shift;
    
    return $self->{'url'}.$self->{'loginPath'}.'?service='.&_escape_chars($service);
    #return $self->{'url'}.$self->{'loginPath'}.'?service='.$service;
}

## Returns non-blocking login URL
## ie: if user is logged in, return the ticket, otherwise do not prompt for login
sub getServerLoginGatewayURL {
    my $self = shift;
    my $service = shift;
    
    return $self->{'url'}.$self->{'loginPath'}.'?service='.&_escape_chars($service).'&gateway=1';
    #return $self->{'url'}.$self->{'loginPath'}.'?service='.$service.'&gateway=1';
}

## Return logout URL
## After logout user is redirected back to the application
sub getServerLogoutURL {
    my $self = shift;
    my $service = shift;
    
    return $self->{'url'}.$self->{'logoutPath'}.'?service='.&_escape_chars($service).'&gateway=1';
    #return $self->{'url'}.$self->{'logoutPath'}.'?service='.$service.'&gateway=1';
}

sub getServerServiceValidateURL {
    my $self = shift;
    my $service = shift;
    my $ticket = shift;
    my $pgtUrl = shift;

    my $query_string = 'service='.&_escape_chars($service).'&ticket='.$ticket;
    #my $query_string = 'service='.$service.'&ticket='.$ticket;
    if (defined $pgtUrl) {
			$query_string .= '&pgtUrl='.&_escape_chars($pgtUrl);
			#$query_string .= '&pgtUrl='.$pgtUrl;
    }

    ## URL was /validate with CAS 1.0
    return $self->{'url'}.$self->{'serviceValidatePath'}.'?'.$query_string;
}

sub getServerProxyURL {
    my $self = shift;
    my $targetService = shift;
    my $pgt = shift;

    return $self->{'url'}.$self->{'proxyPath'}.'?targetService='.&_escape_chars($targetService).'&pgt='.&_escape_chars($pgt);
    #return $self->{'url'}.$self->{'proxyPath'}.'?targetService='.$targetService.'&pgt='.$pgt;
}

sub getServerProxyValidateURL {
    my $self = shift;
    my $service = shift;
    my $ticket = shift;

    return $self->{'url'}.$self->{'proxyValidatePath'}.'?service='.&_escape_chars($service).'&ticket='.&_escape_chars($ticket);
    #return $self->{'url'}.$self->{'proxyValidatePath'}.'?service='.$service.'&ticket='.$ticket;
}

## Validate a Service Ticket
## Also used to get a PGT
sub validateST {
    my $self = shift;
    my $service = shift;
    my $ticket = shift;
    my $pgtUrl = $self->{'pgtCallbackUrl'};

    my $xml = $self->callCAS($self->getServerServiceValidateURL($service, $ticket, $pgtUrl));
    if (defined $xml->{'cas:serviceResponse'}[0]{'cas:authenticationFailure'}) {
			$self->{'errors'} = sprintf("Failed to validate Service Ticket %s : %s", $ticket, $xml->{'cas:serviceResponse'}[0]{'cas:authenticationFailure'}[0]);
			return undef;
    }

    my $user = $xml->{'cas:serviceResponse'}[0]{'cas:authenticationSuccess'}[0]{'cas:user'}[0];
    
    ## If in Proxy mode, also retreave a PGT
    if ($self->{'proxy'}) {
			my $pgtIou;
			if (defined $xml->{'cas:serviceResponse'}[0]{'cas:authenticationSuccess'}[0]{'cas:proxyGrantingTicket'}) {
	    	$pgtIou = $xml->{'cas:serviceResponse'}[0]{'cas:authenticationSuccess'}[0]{'cas:proxyGrantingTicket'}[0];
			}
			unless (defined $self->{'pgtFile'}) {
	    	$self->{'errors'} = sprintf("pgtFile not defined");
	    	return undef;
			}

			## Check stored PGT
			# switch pgtUseFiles
			my ($pgtId);
			if ( defined($self->{'pgtUseFiles'}) ) {
				my $filename = File::Spec->catfile($self->{'pgtFile'},$pgtIou);
				unless ( open(PGTIOU,$filename) ) {
					$self->{'errors'} = sprintf("Unable to read %s",$filename);
					$pgtId = undef;
				} 
				$pgtId = <PGTIOU>;
				close(PGTIOU);
			} else {
				# the old method
				unless (open STORE, $self->{'pgtFile'}) {
					$self->{'errors'} = sprintf("Unable to read %s", $self->{'pgtFile'});
					return undef;
				}
				while (<STORE>) {
					if (/^$pgtIou\s+(.+)$/) {
						$pgtId = $1;
						last;
					}
				}
				close(STORE);
			}
			$self->{'pgtIou'}	= $pgtIou;
			$self->{'pgtId'} = $pgtId;
		}

		return ($user);
}

# get the underlying pgtIou
sub getPgtIou {
	my $self = shift;
	if ( defined($self->{'proxy'}) ) {
		return $self->{'pgtIou'};
	}
	$self->{'errors'} = "Only in proxy mode !";
	return undef;
}
# get the underlying pgtId
sub getPgtId {
	my $self = shift;
	if ( defined($self->{'proxy'}) ) {
		return $self->{'pgtId'};
	}
	$self->{'errors'} = "Only in proxy mode !";
	return undef;
}

# load a cached pgtId switch pgtIou
sub loadPgtId {
	my $self = shift;
	my $pgtIou = shift;
	my $pgtId = undef;
	# check if proxy mode
	if ( !defined($self->{'proxy'}) ) {
		$self->{'errors'} = "Cannot load pgt if not in poxy mode";
		return undef;
	}
	# handle both method
	if ( defined($self->{'pgtUseFiles'}) ) {
		my $filename = File::Spec->catfile($self->{'pgtFile'},$pgtIou);
		unless ( open(PGTIOU,"<$filename") ) {
			$self->{'errors'} = sprintf("Unable to read %s", $filename);
			return undef;
		}
		$pgtId = <PGTIOU>;
		close(PGTIOU);
	} else {
		unless ( open(STORE,$self->{'pgtFile'}) ) {
			$self->{'errors'} = sprintf("Unable to read %s",$self->{'pgtFile'});
			return undef;
		}
		while (<STORE>) {
			if (/^$pgtIou\s+(.+)$/) {
				$pgtId = $1;
				last;
			}
		}
		close(STORE);
	}
	if ( ! defined($pgtId) ) {
		$self->{'errors'} = sprintf("Unable to retrieve PGT for %s",$pgtIou);
		return undef;
	}
	# store them
	$self->{'pgtIou'} = $pgtIou; 
	$self->{'pgtId'} = $pgtId;

	return 1;
}

## Validate a Proxy Ticket
sub validatePT {
    my $self = shift;
    my $service = shift;
    my $ticket = shift;
		my $url = $self->getServerProxyValidateURL($service, $ticket);
		#$url =~ s/%26/&/gc;
		$url =~ s/%26/&/g;
    #my $xml = $self->callCAS($self->getServerProxyValidateURL($service, $ticket));
    my $xml = $self->callCAS($url);

    if (defined $xml->{'cas:serviceResponse'}[0]{'cas:authenticationFailure'}) {
			$self->{'errors'} = sprintf("Failed to validate Proxy Ticket %s : %s [%s] [%s]", 
				$ticket, $xml->{'cas:serviceResponse'}[0]{'cas:authenticationFailure'}[0],
			  $service,$url);
			return undef;
    }

    my $user = $xml->{'cas:serviceResponse'}[0]{'cas:authenticationSuccess'}[0]{'cas:user'}[0];
    
    my @proxies;
    if (defined $xml->{'cas:serviceResponse'}[0]{'cas:authenticationSuccess'}[0]{'cas:proxies'}) {
			@proxies = @{$xml->{'cas:serviceResponse'}[0]{'cas:authenticationSuccess'}[0]{'cas:proxies'}[0]{'cas:proxy'}};
    }

    return ($user, @proxies);
}

## Access a CAS URL and parses received XML
sub callCAS {
    my $self = shift;
    my $url = shift;

    my ($host, $port, $path) = $self->_parse_url($url);
    my @xml = $self->get_https2($host, $port, $path,{'cafile' =>  $self->{'CAFile'},  'capath' => $self->{'CAPath'}});
    ## Skip HTTP header fields
    my $line = shift @xml;
    while ($line !~ /^\s*$/){
			$line = shift @xml;
    }

    return &_parse_xml(join('', @xml));
}

sub storePGT {
    my $self = shift;
    my $pgtIou = shift;
    my $pgtId = shift;
  
		# New style 
		if ( defined($self->{'pgtUseFiles'}) ) {
			my $filename = File::Spec->catfile($self->{'pgtFile'},$pgtIou);
			unless(open(PGTIOU,">$filename")) {
				$self->{'errors'} = sprintf("Unable to write to %s",$filename);
				return undef;
			}
			printf PGTIOU ("%s",$pgtId);
			close(PGTIOU);
		} else {
    	unless (open STORE, ">>$self->{'pgtFile'}") {
				$self->{'errors'} = sprintf("Unable to write to %s",$self->{'pgtFile'});
				return undef;
    	}
    	printf STORE ("%s\t%s\n", $pgtIou, $pgtId);
    	close(STORE);
		}

    return 1;
}


sub retrievePT {
    my $self = shift;
    my $service = shift;
		
		my $xml = $self->callCAS($self->getServerProxyURL($service, $self->{'pgtId'}));

    if (defined $xml->{'cas:serviceResponse'}[0]{'cas:proxyFailure'}) {
			$self->{'errors'} = sprintf("Failed to get PT : %s", $xml->{'cas:serviceResponse'}[0]{'cas:proxyFailure'}[0]);
			return undef;
    }

    if (defined $xml->{'cas:serviceResponse'}[0]{'cas:proxySuccess'}[0]{'cas:proxyTicket'}) {
			return $xml->{'cas:serviceResponse'}[0]{'cas:proxySuccess'}[0]{'cas:proxyTicket'}[0];
    }

    return undef;
}

# request a document using https, return status and content
sub get_https2{
	my $self = shift;
	my $host = shift;
	my $port = shift;
	my $path = shift;

	my $ssl_data= shift;

	my $trusted_ca_file = $ssl_data->{'cafile'};
	my $trusted_ca_path = $ssl_data->{'capath'};

	if (($trusted_ca_file && !(-r $trusted_ca_file)) ||  
		 ($trusted_ca_path && !(-d $trusted_ca_path))) {
	    $self->{'errors'} = "error : incorrect access to cafile $trusted_ca_file or capath $trusted_ca_path";
	    return undef;
	}
	
	#unless (require IO::Socket::SSL) {
	#    $errors = sprintf "Unable to use SSL library, IO::Socket::SSL required, install IO-Socket-SSL (CPAN) first\n";
	#    return undef;
	#}
	
	#unless (require LWP::UserAgent) {
	#    $errors = sprintf "Unable to use LWP library, LWP::UserAgent required, install LWP (CPAN) first\n";
	#    return undef;
	#}

	my $ssl_socket;

	my %ssl_options = (SSL_use_cert => 0,
			   PeerAddr => $host,
			   PeerPort => $port,
			   Proto => 'tcp',
			   Timeout => '5'
			   );

	$ssl_options{'SSL_ca_file'} = $trusted_ca_file if ($trusted_ca_file);
	$ssl_options{'SSL_ca_path'} = $trusted_ca_path if ($trusted_ca_path);
	
	## If SSL_ca_file or SSL_ca_path => verify peer certificate
	$ssl_options{'SSL_verify_mode'} = 0x01 if ($trusted_ca_file || $trusted_ca_path);
	
	$ssl_socket = new IO::Socket::SSL(%ssl_options);
	
	unless ($ssl_socket) {
		$self->{'errors'} = sprintf("error %s unable to connect https://%s:%s/",&IO::Socket::SSL::errstr,$host,$port);
	    return undef;
	}
	
	my $request = "GET $path HTTP/1.0\n\n";
	print $ssl_socket "$request\n\n";

	my @result;
	while (my $line = $ssl_socket->getline) {
	    push  @result, $line;
	} 
	
	$ssl_socket->close(SSL_no_shutdown => 1);	

	return (@result);	
}

1;
__END__

=head1 NAME

CAS - Client library for CAS 2.0

=head1 SYNOPSIS

  A simple example with a direct CAS authentication

  use CAS;
  my $cas = new CAS(casUrl => 'https://cas.myserver, 
		    CAFile => '/etc/httpd/conf/ssl.crt/ca-bundle.crt',
		    );

  my $login_url = $cas->getServerLoginURL('http://myserver/app.cgi');

  ## The user should be redirected to the $login_url
  ## When coming back from the CAS server a ticket is provided in the QUERY_STRING

  ## $ST should contain the receaved Service Ticket
  my $user = $cas->validateST('http://myserver/app.cgi', $ST);

  printf "User authenticated as %s\n", $user;


  In the following example a proxy is requesting a Proxy Ticket for the target application

  $cas->proxyMode(pgtFile => '/tmp/pgt.txt',
	          pgtCallbackUrl => 'https://myserver/proxy.cgi?callback=1
		  );
  
  ## Same as before but the URL is the proxy URL
  my $login_url = $cas->getServerLoginURL('http://myserver/proxy.cgi');

  ## Like in the previous example we should receave a $ST

  my $user = $cas->validateST('http://myserver/proxy.cgi', $ST);

  ## Process errors
  printf STDERR "Error: %s\n", &CAS::get_errors() unless (defined $user);

  ## Now we request a Proxy Ticket for the target application
  my $PT = $cas->retrievePT('http://myserver/app.cgi');
    
  ## This piece of code is executed by the target application
  ## It received a Proxy Ticket from the proxy
  my ($user, @proxies) = $cas->validatePT('http://myserver/app.cgi', $PT);

  printf "User authenticated as %s via %s proxies\n", $user, join(',',@proxies);


=head1 DESCRIPTION

CAS is Yale University's web authentication system, heavily inspired by Kerberos.
Release 2.0 of CAS provides "proxied credential" feature that allows authentication
tickets to be carried by intermediate applications (Portals for instance), they are
called proxy.

This CAS Perl module provides required subroutines to validate and retrieve CAS tickets.

=head1 SEE ALSO

Yale Central Authentication Service (http://www.yale.edu/tp/auth/) 
 phpCAS (http://esup-phpcas.sourceforge.net/)

=head1 COPYRIGHT

Copyright (C) 2003 Comite Reseau des Universites (http://www.cru.fr). All rights reserved.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHORS

Olivier Salaun

=cut
