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
	"ac7" => { package=>"FILEX::Apache::Handler::Admin::Quota", label=>"action menu : quotas"},
	"ac8" => { package=>"FILEX::Apache::Handler::Admin::BigBrother", label=>"action menu : big brother"},
	"ac9" => { package=>"FILEX::Apache::Handler::Admin::Search", label=>"action menu : search"}
);

# system => FILEX::System
# binding => HASH REF
sub new {
	my $this = shift;
	my $class = ref($this) || $this;
	my $self = {
		_SYS_=>undef,
		_route_prefix_ => undef,
		_default_mod_ => undef,
		_modules_ => undef,
	};
	$self->{'_SYS_'} = shift;
	die(__PACKAGE__,"-> require a FILEX::System object") if (ref($self->{'_SYS_'}) ne "FILEX::System");
	# loading parameters
	$self->{'_route_prefix_'} = $self->{'_SYS_'}->config()->getAdminModuleRouteParameter();
	die(__PACKAGE__,"-> require a ModuleRouteParameter") if !defined($self->{'_route_prefix_'});
	# default 
	$self->{'_default_mod_'} = $self->{'_SYS_'}->config()->getAdminDefault();
	# modules
	my @mods = $self->{'_SYS_'}->config()->getAdminModules();
	$self->{'_modules_'} = {};
	for (my $idx = 0; $idx <= $#mods; $idx++) {
		$self->{'_modules_'}->{$idx} = $mods[$idx];
		# strip white spaces
		$self->{'_modules_'}->{$idx} =~ s/\s//g;
	}
	return bless($self,$class);
}

sub dispatch {
	my $self = shift;
	my $event = shift;
	if ( ! exists($self->{'_modules_'}->{$event}) ) {
		warn(__PACKAGE__,"-> invalid event : $event");
		return undef;
	}
	my $module = $self->{'_modules_'}->{$event};
	# import into namespace
	_require($module);
	# create module
	my $handler = $module->new(sys=>$self->{'_SYS_'},
	                           id=>$event,
	                           label=>$self->{'_modules_'}->{$event},
	                           dname=>$self->getDispatchName());
	return $handler->process();
}

sub getDispatchName {
	my $self = shift;
	return $self->{'_route_prefix_'};
}

sub getDefaultDispatch {
	my $self = shift;
	my $event = shift;
	return $event if (defined($event) && exists($self->{'_modules_'}->{$event}));
	my ($k,$kfirst);
	foreach $k ( keys(%{$self->{'_modules_'}}) ) {
		$kfirst = $k if !defined($kfirst);
		return $k if ( $self->{'_modules_'}->{$k} eq $self->{'_default_mod_'} );
	}
	return $kfirst;
}

sub enumDispatch {
	my $self = shift;
	return sort(keys(%{$self->{'_modules_'}}));
}

sub getDispatchLabel {
	my $self = shift;
	my $event = shift;
	return exists($self->{'_modules_'}->{$event}) ? $self->{'_modules_'}->{$event} : "unknown";
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
