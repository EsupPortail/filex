#!/usr/bin/perl
use strict;
use CPAN;

my @REQUIREMENT = (
	{package=>"Socket",version=>0,install=>0},
	{package=>"File::stat",version=>0,install=>0},
	{package=>"Getopt::Std",version=>0,install=>0},
	{package=>"DBI",version=>1.5,install=>1},
	{package=>"DBD::mysql",version=>3,install=>1},
	{package=>"CGI::Util",version=>1.5,install=>1},
	{package=>"CGI::Cookie",version=>1.27,install=>1},
	{package=>"Class::Singleton",version=>1.03,install=>1},
	{package=>"Cache::FileCache",version=>,install=>1},
	{package=>"Config::IniFiles",version=>2.38,install=>1},
	{package=>"Data::Dumper",version=>2,install=>1},
	{package=>"Data::Uniqid",version=>0.11,install=>1},
	{package=>"Digest::MD5",version=>2.36,install=>1},
	{package=>"Encode", version=>2,install=>1},
	{package=>"File::Spec",version=>3,install=>1},
	{package=>"HTML::Entities",version=>1.35,install=>1},
	{package=>"HTML::Template",version=>2.8,install=>1},
	{package=>"IO::Select",version=>1.17,install=>1},
	{package=>"IO::Socket::SSL",version=>1,install=>1},
	{package=>"LWP::UserAgent",version=>2.033,install=>1},
	{package=>"MIME::Entity",version=>5.420,install=>1},
	{package=>"MIME::Words",version=>5.420,install=>1},
	{package=>"Net::DNS",version=>0.57,install=>1},
	{package=>"Net::LDAP",version=>0.33,install=>1},
	{package=>"Net::SMTP",version=>2.29,install=>1},
	{package=>"Time::HiRes",version=>1.87,install=>1},
	{package=>"XML::LibXML",version=>1.58,install=>1},
	{package=>"Apache::Session::File",version=>1.54,install=>1},
);

my $errors = 0;
if ( ! check_mod_perl() ) {
	print STDERR "Votre installation de mod_perl est incomplète !";
	exit(1);
}
foreach my $mod (@REQUIREMENT) {
	print sprintf("Module:\t%s ...",$mod->{package});
	my $obj = CPAN::Shell->expand("Module",$mod->{package});
	my $res = check_requirement($obj,$mod->{version});
	# check 
	SWITCH : {
		if ( $res == 1 ) {
			print("[OK]\n");
		}
		# not exists
		if ( $res == 2 ) {
			print STDERR sprintf("\nle module [%s] n'existe pas ! impossible de l'installer !\n",$mod->{package});
			$errors++;
			last SWITCH;
		}
		# not installed
		if ( $res == 3 ) {
			$errors++ if ( ! do_install($mod,$obj) );
			last SWITCH;
		}
		# need update
		if ( $res == 4 ) {
			$errors++ if ( !do_update($mod,$obj) );
			last SWITCH;
		}
	}
}
if ( $errors ) {
	print STDERR "Les modules prérequis ne sont pas tous installés !\n";
	exit(1);
} else {
	print "L'environnement est correcte\n";
	exit(0);
}

sub do_install {
	my $mod = shift;
	my $obj = shift;
	if ( $mod->{install} != 1 ) {
		print STDERR sprintf("\nle module [%s] ne peut pas être installé automatiquement ...\n",$mod->{package});
		return 0;
	}
	print sprintf("\nle module [%s] n'est pas installé; voulez vous l'installer ? (o/n) ",$mod->{package});
	my $response = <>;
	if ($response =~ /[oy]/i) {
		install($obj);
		return 1;
	}
	return 0;
}

sub do_update {
	my $mod = shift;
	my $obj = shift;
	if ( $mod->{install} != 1 ) {
                print sprintf("le module [%s] ne peut pas être installé automatiquement ...\n",$mod->{package});
                return 0;
        }
	print sprintf("version installée : %s, requise >= %s, version disponible : %s; voulez vous mettre à jour ?(o/n)",$obj->inst_version(),$mod->{version},$obj->cpan_version);
	my $response = <>;
	if ( $response =~ /[oy]/i ) {
		install($obj);
		return 1;
	}
	return 0;
}

# return :
# 1 if ok
# 2 if not exists
# 3 if not installed
# 4 if version does not match
sub check_requirement {
	my $obj = shift;
	my $version = shift;
	# if no exists at all
	return 2 if ( !$obj );
	return 3 if ( !$obj->inst_file() );
	return 4 if ( $obj->inst_version() < $version );
	return 1;
}

sub install {
	my $obj = shift;
	print sprintf("Récupération du paquetage : %s\n",$obj->cpan_file());
	$obj->get();
	print sprintf("Compilation du paquetage : %s\n",$obj->cpan_file());
	$obj->make();
	print sprintf("Installation du paquetage : %s\n",$obj->cpan_file());
	$obj->install();
}

sub install_module {
	my $mod = shift;
	my $obj = CPAN::Shell->expand("Module",$mod);
	if ( $obj ) {
		print sprintf("Installation du paquetage [%s]\n",$obj->cpan_file());
		install($obj);
	}
}

sub check_mod_perl {
	print("Quel environnement Apache utilisez vous ? (1 => Apache 1x / 2 => Apache 2x)");
	my $apache = <>;
	if ( $apache =~ /1/i ) {
		#test MP1
		print("Test si mod_perl est présent pour Apache 1x ... ");
		my $mp1 = check_mp1();
		if ( !$mp1 ) {
			print("[NON]\n");
			print("Installez mod_perl depuis les paquetages de votre distribution ou depuis : http://perl.apache.org\n");
			return 0;
		} else {
			print("[OUI]\n");
		}
		print("Test si libapreq présente ... ");
		my $obj = CPAN::Shell->expand("Module","Apache::Request");
		my $mp1_apreq = check_requirement($obj,1.3);
		my $ret = 0;
		SWITCH : {
			if ( $mp1_apreq == 1 ) {
				print("[OUI]\n");
				$ret = 1;
				last SWITCH;
			}
			if ( $mp1_apreq == 3 ) {
				print("[NON]\n");
				$ret = do_install($obj,{package=>"Apache::Request",version=>1.3,install=>1});
			}
			if ( $mp1_apreq == 4 ) {
				print("[NON]\n");
				$ret = do_update($obj,{package=>"Apache::Request",version=>1.3,install=>1});
			}
		}
		return $ret;
	} elsif ( $apache =~ /2/i ) {
		#test MP2
		print("Test si mod_perl est présent pour Apache 2x ... ");
		my $mp2 = check_mp2();
		if ( !$mp2 ) {
			print("[NON]\n");
			print("Installez mod_perl depuis les paquetages de votre distribution ou depuis : http://perl.apache.org\n");
			return 0;
		} else {
			print("[OUI]\n");
		}
		print("Test si libapreq présente ... ");
		my $obj = CPAN::Shell->expand("Module","Apache2::Request");
		my $mp2_apreq = check_requirement($obj,2);
		my $ret = 0;
		SWITCH : {
			if ( $mp2_apreq == 1 ) {
				print("[OUI]\n");
				$ret = 1;
				last SWITCH;
			}
			if ( $mp2_apreq == 3 ) {
				print("[NON]\n");
				$ret = do_install($obj,{package=>"Apache2::Request",version=>2,install=>1});
			}
			if ( $mp2_apreq == 4 ) {
				print("[NON]\n");
				$ret = do_update($obj,{package=>"Apache2::Request",version=>2,install=>1});
			}
		}
		return $ret;
	} else {
		print("Choix invalide [$apache]");
		return 0;
	}
	return 1;
}

sub check_mp1 {
	eval {
		require Apache::Constants;
	};
	return 0 if ($@);
	return 1;
}

sub check_mp2 {
	eval {
		require Apache2::Const;
	};
	return 0 if($@);
	return 1;
}

