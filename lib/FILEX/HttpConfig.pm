package FILEX::HttpConfig;
use strict;
use FILEX::System::Config;
use constant MP2 => ( exists $ENV{MOD_PERL_API_VERSION} and $ENV{MOD_PERL_API_VERSION} >= 2 );

BEGIN {
	if (MP2) {
		require Apache2::ServerUtil;
	}
}
do {
	my $filex_config = $ENV{'FILEXConfig'};
	my $conf = FILEX::System::Config->instance(file=>$filex_config);
	# 
	warn("Entering FILEX configuration under mod_perl : ",(MP2)?"2.0":"1.0");
  if ( MP2 ) {
		# under mod_perl 2.0
		# generic template for handlers
		my $tmplHandlerConfig = << 'EOC';
 PerlModule FILEX::MODULE
 <Location FILEX::URI>
  SetHandler perl-script
  PerlResponseHandler FILEX::MODULE
 </Location>
EOC
		my @apacheConfig;
		# enable libapreq if needed
		push(@apacheConfig,("<IfModule !apreq_module>","LoadModule apreq_module modules/mod_apreq2.so","APREQ2_ReadLimit 1024M","</IfModule>"));
		# upload
		my $uri = $conf->getUriUpload();
		my $config = << 'EOU';
 PerlModule FILEX::MODULE
 <Location FILEX::URI>
  SetHandler perl-script
  PerlResponseHandler FILEX::MODULE
	# LimitRequestBody 2147483647
	APREQ2_ReadLimit APREQ_READ_LIMIT
 </Location>
EOU
		# APREQ2_TempDir
		# APREQ2_ReadLimit
		# APREQ2_TempDir
		$config =~ s/FILEX::MODULE/FILEX::Apache::Handler::Upload/sg;
		$config =~ s/FILEX::URI/$uri/sg;
		my $read_limit = "1024M";
		$config =~ s/APREQ_READ_LIMIT/$read_limit/sg;
		push(@apacheConfig,split(/\n/,$config));
		# get
		$uri = $conf->getUriGet();
		$config = $tmplHandlerConfig;
		$config =~ s/FILEX::MODULE/FILEX::Apache::Handler::Get/sg;
		$config =~ s/FILEX::URI/$uri/sg;
		push(@apacheConfig,split(/\n/,$config));
		# meter
		$uri = $conf->getUriMeter();
		$config = $tmplHandlerConfig;
		$config =~ s/FILEX::MODULE/FILEX::Apache::Handler::Meter/sg;
		$config =~ s/FILEX::URI/$uri/sg;
		push(@apacheConfig,split(/\n/,$config));
		# admin
		$uri = $conf->getUriAdmin();
		$config = $tmplHandlerConfig;
		$config =~ s/FILEX::MODULE/FILEX::Apache::Handler::Admin/sg;
		$config =~ s/FILEX::URI/$uri/sg;
		push(@apacheConfig,split(/\n/,$config));
		# manage
		$uri = $conf->getUriManage();
		$config = $tmplHandlerConfig;
		$config =~ s/FILEX::MODULE/FILEX::Apache::Handler::Manage/sg;
		$config =~ s/FILEX::URI/$uri/sg;
		push(@apacheConfig,split(/\n/,$config));
		# manage xml
		$uri = $conf->getUriManageXml();
		if ( $uri ) {
			$config = $tmplHandlerConfig;
			$config =~ s/FILEX::MODULE/FILEX::Apache::Handler::ManageXml/sg;
			$config =~ s/FILEX::URI/$uri/sg;
			push(@apacheConfig,split(/\n/,$config));
		}
		# soap
#		$uri = $conf->getUriSoap();
#		if ( $uri ) {
#			$config = $tmplHandlerConfig;
#			$config =~ s/FILEX::MODULE/FILEX::SOAP::Dispatch/sg;
#			$config =~ s/FILEX::URI/$uri/sg;
#			Apache2::ServerUtil->server->add_config([split(/\n/,$config)]);
#		}
		# static media
		$uri = $conf->getUriStatic();
		my $static_path = $conf->getStaticFileDir();
		$config = << 'EOST';
	Alias FILEX::URI STATIC::PATH
	<Location FILEX::URI>
		Allow from all
  </Location>
EOST
		$config =~ s/FILEX::URI/$uri/sg;
		$config =~ s/STATIC::PATH/$static_path/sg;
		push(@apacheConfig,split(/\n/,$config));
		warn join("\n",@apacheConfig);
		Apache2::ServerUtil->server->add_config(\@apacheConfig);
	} else {
		# under mod_perl 1.0
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
		# ManageXml
		$uri = $conf->getUriManageXml();
		if ( $uri ) {
			push(@PerlModule,"FILEX::Apache::Handler::ManageXml");
			$Location{$uri} = {
				SetHandler => "perl-script",
				PerlHandler => "FILEX::Apache::Handler::ManageXml",
			};
		}
		# soap
		#$uri = $conf->getUriSoap();
		#if ( $uri ) {
		#	push(@PerlModule,"FILEX::SOAP::Dispatch");
		#	$Location{$uri} = {
		#		SetHandler => "perl-script",
		#		PerlHandler => "FILEX::SOAP::Dispatch",
		#	};
		#}
		# end
	}
};

1;

=pod

=head1 DESCRIPTION

Ce module permet de configurer apache pour FILEX de manière automatique. Il altère la configuration d'apache et met
en oeuvre les différents "handler" nécessaire au bon fonctionnement de FILEX.

=head1 USAGE

 # http.conf
 # ....
 <IfDefine MODPERL2>
  <IfModule perl_module>
   # chemin vers les librairies FILEX
   PerlSwitches -w -I/path/to/FILEX/lib
   # chemin vers le fichier de configuration FILEX
   PerlSetEnv FILEXConfig /path/to/FILEX.ini
   # configuration du serveur
   PerlModule FILEX::HttpConfig
  </IfModule>
 </IfDefine>
 <IfDefine !MODPERL2>
  <IfModule mod_perl.c>
   PerlTaintCheck off
   PerlWarn On
   # chemin vers les librairies FILEX
   <Perl>
    use lib qw(/path/to/FILEX/lib);
   </Perl>
   # Le chemin vers le fichier de configuration de FILEX
   PerlSetEnv FILEXConfig /path/to/FILEX.ini
   # configurer FILEX
   PerlModule FILEX::HttpConfig
  </IfModule>
 </IfDefine>

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
