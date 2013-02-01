package FILEX::Apache::Handler::Admin::Dispatcher;
use strict;
use vars qw(%ACTIONS_BINDING);

use constant DISPATCH_NAME => "maction";

%ACTIONS_BINDING = (
	"ac1" => { package=>"FILEX::Apache::Handler::Admin::Download", label=>"action menu : current download", default=>1},
	"ac2" => { package=>"FILEX::Apache::Handler::Admin::UsrAdmin", label=>"action menu : admin user"},
	"ac3" => { package=>"FILEX::Apache::Handler::Admin::Purge", label=>"action menu : purge"},
	"ac4" => { package=>"FILEX::Apache::Handler::Admin::CurrentFiles", label=>"action menu : current files"},
	"ac5" => { package=>"FILEX::Apache::Handler::Admin::Rules", label=>"action menu : rules"},
	"ac6" => { package=>"FILEX::Apache::Handler::Admin::Exclude", label=>"action menu : excludes"},
	"ac7" => { package=>"FILEX::Apache::Handler::Admin::Quota", label=>"action menu : quotas"}
);

# system => FILEX::System
# binding => HASH REF
sub new {
	my $this = shift;
	my $class = ref($this) || $this;
	my $self = {
		'_SYS_'=>undef,
	};
	$self->{'_SYS_'} = shift;
	die(__PACKAGE__,"-> require a FILEX::System object") if (ref($self->{'_SYS_'}) ne "FILEX::System");
	return bless($self,$class);
}

sub dispatch {
	my $self = shift;
	my $event = shift;
	if ( ! exists($ACTIONS_BINDING{$event}) ) {
		warn(__PACKAGE__,"-> invalid event : $event");
		return undef;
	}
	my $module = $ACTIONS_BINDING{$event}->{'package'};
	# import into namespace
	_require($module);
	# create module
	my $handler = $module->new(sys=>$self->{'_SYS_'},id=>$event,label=>$ACTIONS_BINDING{$event}->{'label'},dname=>DISPATCH_NAME);
	return $handler->process();
}

sub getDispatchName {
	return DISPATCH_NAME;
}

sub getDefaultDispatch {
	my $name = shift;
	$name = shift if ref($name);
	return $name if (defined($name) && exists($ACTIONS_BINDING{$name}));
	my $k;
	foreach $k ( keys(%ACTIONS_BINDING) ) {
		return $k if ( exists($ACTIONS_BINDING{$k}->{'default'}) && $ACTIONS_BINDING{$k}->{'default'} == 1);
	}
	return $k;
}

sub enumDispatch {
	return keys(%ACTIONS_BINDING);
}

sub getDispatchLabel {
	my $name = shift;
	$name = shift if ref($name);
	return $ACTIONS_BINDING{$name}->{'label'} if exists($ACTIONS_BINDING{$name}->{'label'});
}

sub _require {
	my($filename) = @_;
	my($realfilename,$result,$prefix);
	### format with :: = /
	$filename =~ s/::/\//g;
	$filename.='.pm';
	return 1 if $INC{$filename};
	ITER: {
		foreach $prefix (@INC) {
			$realfilename = "$prefix/$filename";
			if (-f $realfilename) {
				$result = do $realfilename;
				last ITER;
			}
		}
		die "Can't find $filename in \@INC";
	}
	die $@ if $@;
	die "$filename did not return true value" unless $result;
	$INC{$filename} = $realfilename;
	return $result;
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
