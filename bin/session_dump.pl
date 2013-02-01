#!/usr/bin/perl
use strict;
use lib qw(/home/ofranco/projets/FILEX/1.7-2/lib/);
use FILEX::System::Config;
use FILEX::System::Session;
use Data::Dumper;
use constant FILEX_INI => "/home/ofranco/projets/FILEX/conf/FILEX.ini.1.7";
$FILEX::System::Config::FILE = FILEX_INI;

my $sid = shift or die("Require a session ID");
my $session = new FILEX::System::Session();
$session->load($sid) or die("Unable to load session : $sid");
$Data::Dumper::Indent = 2;
$Data::Dumper::Purity = 1;
print Data::Dumper->Dump([$session->_data()]);

