package FILEX::Apache::Handler::Meter;
use strict;
use vars qw($VERSION);

#use Apache::Request;
use Apache::Constants qw(:common);

# FILEX related
use FILEX::System qw(toHtml);
use FILEX::Tools::Utils qw(hrSize);

use POSIX qw(ceil);
use Cache::FileCache;

use constant DLID_FIELD_NAME => "dlid";
use constant INI_FIELD_NAME => "ini";

$VERSION = 1.0;

# param : uid => upload id
sub handler {
	my $r = shift; # Apache object
	my $S = FILEX::System->new($r); # FILEX::System object
	my $template = $S->getTemplate(name=>"meter");
	my $dlid = $S->apreq->param(DLID_FIELD_NAME);
	my $inireq = $S->apreq->param(INI_FIELD_NAME);
	my $url = genUrl($S->getCurrentUrl(),$dlid);
	my $end = undef;
	my %dl_info;
	# no dlid 
	if ( ! $dlid ) {
		$template->param(FILEX_HAS_ERROR=>1);
		$template->param(FILEX_ERROR=>$S->i18n->localizeToHtml("no progress meter"));
		display($S,$template,$url,1); 
	}
	my $IPCache = initIPCCache($S->config);
	if ( ! $IPCache ) {
		$template->param(FILEX_HAS_ERROR=>1);
		$template->param(FILEX_ERROR=>$S->i18n->localizeToHtml("unable to initialize IPC"));
		display($S,$template,$url,1);
	}
	# fetch cache infos
	$dl_info{'size'} = $IPCache->get($dlid."size");
	# if unable to get size : 
	# 1 - the dlid provided is false
	# 2 - the Cache latency
	my $pb = 1;
	my $tout = 15; # timeout
	# if it is the initial request the we wait for the cache to update
	if ( ! $inireq && ! $dl_info{'size'} ) {
		$template->param(FILEX_HAS_ERROR=>1);
		$template->param(FILEX_ERROR=>$S->i18n->localizeToHtml("no progress meter"));
		display($S,$template,$url,1); 
	}
	# wait on size because this is the first published key : cf Upload.pm
	for ( my $i = 0; $i < $tout; $i++ ) {
		$dl_info{'size'} = $IPCache->get($dlid."size") || undef;
		if ( $dl_info{'size'} ) {
			$pb = undef;
			last;
		}
		# else wait
		sleep 1;
		last if ! $S->isConnected();
	}
	if ( $pb ) {
		$template->param(FILEX_HAS_ERROR=>1);
		$template->param(FILEX_ERROR=>$S->i18n->localizeToHtml("no progress meter"));
		display($S,$template,$url,1); 
	}
	# fetch other datas
	$dl_info{'filename'} = $IPCache->get($dlid."filename") || "";
	$dl_info{'starttime'} = $IPCache->get($dlid."starttime");
	$dl_info{'length'} = $IPCache->get($dlid."length") || 0;
	$dl_info{'canceled'} = $IPCache->get($dlid."canceled") || 0;
	$dl_info{'end'} = $IPCache->get($dlid."end") || 0;
	$dl_info{'lastupdatetime'} = $IPCache->get($dlid."lastupdatetime") || 0;
	$dl_info{'lastupdatelength'} = $IPCache->get($dlid."lastupdatelength") || 0;
	$dl_info{'toolarge'} = $IPCache->get($dlid."toolarge") || 0;
	# fill the filename
	$template->param(FILEX_FILE_NAME=>toHtml($dl_info{'filename'}));
	# if file size toolarge
	if ( $dl_info{'toolarge'} == 1 ) {
		# reset 
		$IPCache->set($dlid."canceled",0);
		$IPCache->set($dlid."length",0);
		$IPCache->set($dlid."toolarge",0);
		$IPCache->set($dlid."lastupdatelength",0);
		$IPCache->set($dlid."lastupdatetime",0);
		$template->param(FILEX_HAS_ERROR=>1);
		$template->param(FILEX_ERROR=>$S->i18n->localizeToHtml("file size too large"));
		$template->param(FILEX_HAS_ERROR_DESC=>1);
		$template->param(FILEX_ERROR_DESC=>$S->i18n->localizeToHtml("too large desc"));
		display($S,$template,$url,1);
	}
	# if upload canceled
	if ( $dl_info{'canceled'} == 1 ) {
		# reset canceled value
		$IPCache->set($dlid."canceled",0);
		$IPCache->set($dlid."length",0);
		$IPCache->set($dlid."toolarge",0);
		$IPCache->set($dlid."lastupdatelength",0);
		$IPCache->set($dlid."lastupdatetime",0);
		# display
		$template->param(FILEX_HAS_ERROR=>1);
		$template->param(FILEX_ERROR=>$S->i18n->localizeToHtml("upload canceled"));
		display($S,$template,$url,1);
	}

	# if upload end
	if ( $dl_info{'end'} == 1 ) { 
		$template->param(FILEX_HAS_COMPLETE=>1);
		# delete the IPC
		$IPCache->remove($dlid."size");
		$IPCache->remove($dlid."canceled");
		$IPCache->remove($dlid."length");
		$IPCache->remove($dlid."toolarge");
		$IPCache->remove($dlid."lastupdatelength");
		$IPCache->remove($dlid."lastupdatetime");
		$IPCache->remove($dlid."filename");
		$IPCache->remove($dlid."starttime");
		$IPCache->remove($dlid."end");
		display($S,$template,$url,1);
	}

	# do computation
	my $curtime = time();
	$dl_info{'starttime'} = $curtime if !$dl_info{'starttime'};
	my $etime = $curtime - $dl_info{'starttime'};
	my $rtime = ( $dl_info{'end'} == 1 || $dl_info{'length'} == 0) ? 0 : int ($etime / $dl_info{'length'} * $dl_info{'size'}) - $etime;
	# data rate
	my $currate = int (($dl_info{'length'} - $dl_info{'lastupdatelength'}) / ($curtime - $dl_info{'lastupdatetime'})) if ($curtime != $dl_info{'lastupdatetime'});
	#my $rate = int ($dl_info{'length'} / ($curtime - $dl_info{'starttime'})) if ($curtime != $dl_info{'starttime'});
	$IPCache->set($dlid."lastupdatetime", $curtime);
	$IPCache->set($dlid."lastupdatelength", $dl_info{'length'});
	# progress
	my $progress = ceil( ($dl_info{'length'}*100) / $dl_info{'size'} );

	# fill template
	my ($fsz, $funit);
	$template->param(FILEX_PROGRESS=>$progress);
	($fsz,$funit) = hrSize($dl_info{'length'});
	$template->param(FILEX_DATA_RECEIVED=>$fsz." ".$S->i18n->localizeToHtml($funit));
	($fsz,$funit) = hrSize($dl_info{'size'});
	$template->param(FILEX_DATA_TOTAL=>$fsz." ".$S->i18n->localizeToHtml($funit));
	($fsz,$funit) = hrSize($currate);
	$template->param(FILEX_DATA_RATE=>$fsz." ".$S->i18n->localizeToHtml($funit)."/s");
	$template->param(FILEX_REMAINING_TIME=>$rtime." ".$S->i18n->localizeToHtml("seconds"));
	display($S,$template,$url);
	return OK;
}

sub display {
	my $s = shift;
	my $t = shift;
	my $url = shift;
	my $end = shift;
	# base for static include
	$t->param(FILEX_STATIC_FILE_BASE=>$s->getStaticUrl()) if ( $t->query(name=>'FILEX_STATIC_FILE_BASE') );
	if ( !$end ) {
		$s->sendHeader("Content-Type"=>"text/html","Refresh"=>$s->config->getMeterRefreshDelay().";url=$url");
	} else {
		$s->sendHeader("Content-Type"=>"text/html");
	}
	$s->apreq->print($t->output());
	exit(OK);
}

sub genUrl {
	my $url = shift;
	my $dlid = shift;
	$url .= "?".DLID_FIELD_NAME."=$dlid";
	return $url;
}

# initialize IPC Cache
sub initIPCCache {
	my $conf = shift; # FILEX::System::Config object
	my $cache_opt = {};
	$cache_opt->{'namespace'} = $conf->getCacheNamespace();
	$cache_opt->{'default_expires_in'} = $conf->getCacheDefaultExpire();
	$cache_opt->{'auto_purge_interval'} = $conf->getCacheAutoPurge();
	$cache_opt->{'cache_root'} = $conf->getCacheRoot() if $conf->getCacheRoot();
	# instantiate the IPC cache
	return Cache::FileCache->new($cache_opt);
}

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
