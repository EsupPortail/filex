package FILEX::HttpConfig;
use strict;
use FILEX::System::Config;
# PerlPassEnv ENV
# PerlModule FILEX::HttpConfig
#
do {
	my $filex_config = $ENV{'FILEXConfig'};
	my $conf = FILEX::System::Config->new(file=>$filex_config) or die("Unable to load FILEXConfig file");
	# 
	package Apache::ReadConfig;
	no strict;
	push(@PerlSetVar,"FILEXConfig",$filex_config);
	# Upload
	my $uri = $conf->getUriUpload();
	push(@PerlModule,"FILEX::Apache::Handler::Upload");
	$Location{$uri} = {
		SetHandler => "perl-script",
		PerlHandler => "FILEX::Apache::Handler::Upload",
	};
	# Get
	$uri = $conf->getUriGet();
	push(@PerlModule,"FILEX::Apache::Handler::Get");
	$Location{$uri} = {
		SetHandler => "perl-script",
		PerlHandler => "FILEX::Apache::Handler::Get",
	};
	# Meter
	$uri = $conf->getUriMeter();
	push(@PerlModule,"FILEX::Apache::Handler::Meter");
	$Location{$uri} = {
		SetHandler => "perl-script",
		PerlHandler => "FILEX::Apache::Handler::Meter",
	};
	# Admin
	$uri = $conf->getUriAdmin();
	push(@PerlModule,"FILEX::Apache::Handler::Admin");
	$Location{$uri} = {
		SetHandler => "perl-script",
		PerlHandler => "FILEX::Apache::Handler::Admin",
	};
	# Manage
	$uri = $conf->getUriManage();
	push(@PerlModule,"FILEX::Apache::Handler::Manage");
	$Location{$uri} = {
		SetHandler => "perl-script",
		PerlHandler => "FILEX::Apache::Handler::Manage",
	};
	# static media
	$uri = $conf->getUriStatic();
	my $static_path = $conf->getStaticFileDir();
	push(@Alias,$uri,$static_path);

	# end
};

1;

=pod

=head1 DESCRIPTION

Ce module permet de configurer apache pour FILEX de manière automatique. Il altère la configuration d'apache et met
en oeuvre les différents "handler" nécessaire au bon fonctionnement de FILEX.

=head1 USAGE

 # http.conf
 # ....
 <IfModule mod_perl.c>
   # votre fichier startup - idéal pour placer les chemins de librairie -
   PerlRequire /path/to/startup.pl
	 # ou directement
   <Perl>
     use lib qw(/path/to/FILEX/lib);
   </Perl>
   # Le chemin vers le fichier de configuration de FILEX
   PerlSetEnv FILEXConfig /path/to/FILEX.ini
   # configurer FILEX
   PerlModule FILEX::HttpConfig
   # fin 
 </IfModule>

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
