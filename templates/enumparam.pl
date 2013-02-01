#!/usr/bin/perl
use strict;
use HTML::Template;
my ($file,$t);

# get arg
die("need a file ...") if ( $#ARGV < 0 || length($ARGV[0]) == 0 );
$file = $ARGV[0];
die("invalid file - $file - ...") if ( ! -f $file );
$t = HTML::Template->new(filename=>$file,case_sensitive=>1) or die($@);
print join("\n",$t->param()),"\n";
