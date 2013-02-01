#!/usr/bin/perl
use strict;
use File::Spec;
use Getopt::Std;

my %PARAMS = (
	l => undef, # library path
	c => undef, # configuration path
);

usage() && exit(1) if ( getParams(\%PARAMS) );

print STDOUT <<EOCONF;
<IfModule mod_perl.c>
	# Positionner le chemin vers les librairies FEX
	<Perl>
		use lib qw($PARAMS{'l'});
	</Perl>
	# positionner le chemin vers le fichier de configuration
	PerlSetEnv FILEXConfig $PARAMS{'c'}
	# configurer les différents handler
	PerlModule FILEX::HttpConfig
</IfModule>
EOCONF

exit(0);

sub getParams {
	my $params = shift;
	my $bUsage = 0;
	getopt('l:c:',$params);
	if ( !defined($params->{'l'}) || ! -d $params->{'l'} ) {
		$bUsage++;
		if ( ! defined($params->{'l'}) ) {
			warn("Veuillez indiquer le chemin vers le répertoire de librairies\n\n");
		} else {
			warn("Le répertoire de librairies [ ",$params->{'l'},"] n'existe pas !\n\n");
		}
	} else {
		my $tst_libs = File::Spec->catdir($params->{'l'},"FILEX");
		if ( ! -d $tst_libs ) {
			$bUsage++;
			warn("Le répertoire [ ",$params->{'l'}," ] ne contient pas les librairies FILEX !\n\n");
		}
	}
	if ( !defined($params->{'c'}) || ! -f $params->{'c'} ) {
		$bUsage++;
		if ( defined($params->{'c'}) ) {
			warn("Le Fichier de configuration [ ",$params->{'c'}," ] n'existe pas !\n\n");
		} else {
			warn("Veuillez indiquer un fichier de configuration !\n\n");
		}
	}
	return $bUsage;
}

sub usage {
	print STDOUT <<EOU;

usage :
	$0 -l /path/to/filex/lib -c /path/to/FILEX.ini

EOU
}
