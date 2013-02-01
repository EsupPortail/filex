package FILEX::Tools::Utils;
use strict;
use vars qw($VERSION @ISA @EXPORT_OK %EXPORT_TAGS @EXPORT);
use POSIX qw(strftime modf floor ceil);
use Net::DNS;
use Socket;
use CGI::Util;
use Time::HiRes qw(alarm);
use Data::Uniqid;
use HTML::Entities ();
require Exporter;

@ISA = qw(Exporter);
@EXPORT = qw();
@EXPORT_OK = qw(
	tsToLocal
	tsToGmt
	hrSize
	getUnitTable
	round
	unit2byte
	unit2idx
	unitLength
	unitLabel
	rDns
	rDns2
	genUniqId
	toHtml
);
%EXPORT_TAGS = (all=>[@EXPORT_OK]);
$VERSION = 1;

my @UNIT_TABLE = qw(byte kbyte mbyte);
my %UNIT_IDX = (byte=>{idx=>0,mul=>1},kbyte=>{idx=>1,mul=>1024},mbyte=>{idx=>2,mul=>1024*1024});

# timestamp to locale TZ
sub tsToLocal {
	my $ts = shift;
	return strftime("%d/%m/%Y %H:%M:%S",localtime($ts));
}

# timestamp to GMT
sub tsToGmt {
	my $ts = shift;
	return strftime("%d/%m/%Y %H:%M:%S",gmtime($ts));
}

sub hrSize {
	my $size = shift;
	# less than 1kb
	#return ($size,"byte") 
	return ($size,$UNIT_TABLE[0]) if ($size < 1024);
	return (sprintf("%.2f",$size/1024),$UNIT_TABLE[1]) if ( $size < (1024*1024));
	return (sprintf("%.2f",$size/(1024*1024)),$UNIT_TABLE[2]);
}

sub unitLength {
	return $#UNIT_TABLE;
}

sub unitLabel {
	my $idx = shift;
	return $UNIT_TABLE[$idx];
}

sub unit2idx {
	my $unit = shift;
	return ( exists($UNIT_IDX{$unit}) ) ? $UNIT_IDX{$unit}->{'idx'} : undef;
}

sub unit2byte {
	my $unit = shift;
	my $value = shift;
	return $value if !exists($UNIT_IDX{$unit});
	return round($value*$UNIT_IDX{$unit}->{'mul'});
}

sub round {
	my $value = shift;
	my ($frac,$int) = modf($value);
	return ( $frac < 0.5 ) ? $int : $int+1;
}

# string to modify
# inserted char
# every
sub insChar($$$) {
	my $v = shift;
	my $char = shift;
	my $every = shift;
	my $o = length($v);
	my $r;
	my $l = $every;
	while ( $o > 0) {
		$o -= $every;
		if ( $o < 0 ) {
			$l = $o + $every;
			$o = 0;
		}
		$r = ($o == 0) ? substr($v,$o,$l).$r : $char.substr($v,$o,$l).$r;
	}
	return $r;
}

# make reverse DNS lookup over a given IP
# return undef if no PTR datatype found
sub rDns($) {
	my $ip = shift;
	my $res = Net::DNS::Resolver->new();
	# set timeout in case of invalid address (in seconds)
	$res->tcp_timeout(1);
	$res->udp_timeout(1);
	my $query = $res->search($ip);
	return undef if ! $query;
	foreach my $rr ( $query->answer() ) {
		my $type = $rr->type();
		return $rr->rdatastr() if ($type eq "PTR");
	}
	return undef;
}

# the same thing as rdns but in a simple manner & without timeout
sub rDns2($) {
	my $ip = shift;
	my $addr = inet_aton($ip);
	my $fqdn;
	# because on invalid address we need to set a timeout
	eval {
		local $SIG{ALRM} = sub { die "resolv_timeout\n"; };
		# 1 second
		alarm(0.5); 
		$fqdn = gethostbyaddr($addr,AF_INET);
		alarm(0);
	};
	if ($@) {
		warn($@) unless $@ eq "resolv_timeout\n";
		warn("resolving $ip timed out");
		return undef;
	}
	return ($fqdn) ? $fqdn : undef;
}

# retrive query string parameters 
# 
sub qsParams($) {
	my $qs = shift;
  my %res;
	return wantarray ? %res : \%res if !defined($qs);
  # split on & or ;
  my @pairs = split(/[&;]/,$qs);
  my ($param,$value);
  foreach my $p (@pairs) {
    ($param,$value) = split(/=/,$p,2);
    # no param defined then go next
    next unless defined $param;
    $value = undef if !defined($value);
    # escape param & value
    $param = CGI::Util::unescape($param);
    $value = CGI::Util::unescape($value) if defined($value);
    if ( exists($res{$param}) ) {
      if ( defined($res{$param}) ) {
        $res{$param} = [$res{$param}] if ( ref($res{$param}) ne "ARRAY" );
        push(@{$res{$param}},$value);
      } else {
        $res{$param} = $value;
      }
    } else {
      $res{$param} = $value;
    }
  }
  return wantarray ? %res : \%res;
}

sub genUniqId() {
	return Data::Uniqid::luniqid();
}

# encode string to html entities
sub toHtml {
	my $str = shift;
	return HTML::Entities::encode_entities($str);
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
