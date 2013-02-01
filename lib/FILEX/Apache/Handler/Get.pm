package FILEX::Apache::Handler::Get;
use strict;
use vars qw($VERSION);
# Apache Related
use Apache::Constants qw(:common);
use Apache::File;
use Apache::Util;

# FILEX related
use FILEX::System qw(genUniqId toHtml);
use FILEX::DB::Download;
use FILEX::DB::Upload;
use FILEX::Tools::Utils qw(tsToGmt hrSize tsToLocal rDns);

# Other
use File::Spec;
use Encode;
use MIME::Words;

use constant FILEX_CONFIG_NAME => "FILEXConfig";

use constant FIELD_FILE_NAME => "k";
use constant FIELD_AUTO_MODE => "auto";

$VERSION = 1.0;

sub handler {
	# the request object
	# CHECK FOR ERRORS !
	my $S = FILEX::System->new(shift);
	my $Template = $S->getTemplate(name=>"get");
	my $db = eval { FILEX::DB::Download->new() };
	if ($@) {
		$Template->param(FILEX_HAS_ERROR=>1);
		$Template->param(FILEX_ERROR=>$S->i18n->localizeToHtml("database error %s",$@));
		display($S,$Template);
	}
	
	# get parameters
	my $file_name = $S->apreq->param(FIELD_FILE_NAME);
	my $auto_mode = $S->apreq->param(FIELD_AUTO_MODE) || 0;

	$Template->param(FILEX_SYSTEM_EMAIL=>$S->config->getSystemEmail());
	# no filename to download then show it
	if ( !$file_name ) {
		$Template->param(FILEX_HAS_ERROR=>1);
		$Template->param(FILEX_ERROR=>$S->i18n->localizeToHtml("requested file does not exists"));
		display($S,$Template);
	}

	# get file infos
	my $upload = eval { FILEX::DB::Upload->new(file_name=>$file_name); };
	if ($@) {
		$Template->param(FILEX_HAS_ERROR=>1);
		$Template->param(FILEX_ERROR=>$S->i18n->localizeToHtml("database error %s",$upload->getLastErrorString()));
		display($S,$Template);
	}
	# file record not found
	if ( !$upload->exists() ) {
		$Template->param(FILEX_HAS_ERROR=>1);
		$Template->param(FILEX_ERROR=>$S->i18n->localizeToHtml("requested file does not exists"));
		display($S,$Template);
	}
	# file expired
	if ( $upload->isExpired() == 1 ) {
		$Template->param(FILEX_HAS_ERROR=>1);
		$Template->param(FILEX_ERROR=>$S->i18n->localizeToHtml("file expire"));
		display($S,$Template);
	}
	# file disabled
	if ( $upload->getEnable() != 1 || $upload->getDeleted() == 1 ) {
		$Template->param(FILEX_HAS_ERROR=>1);
		$Template->param(FILEX_ERROR=>$S->i18n->localizeToHtml("file disabled"));
		display($S,$Template);
	}

	# get the file path
	my $source = File::Spec->catfile($S->config->getFileRepository(),$file_name);
	# stat the file
	my @fstat = stat($source);
	if ( $#fstat < 0 ) {
		$Template->param(FILEX_HAS_ERROR=>1);
		$Template->param(FILEX_ERROR=>$S->i18n->localizeToHtml("disk file not found"));
		display($S,$Template);
	}
	
	# everything is ok
	if ( $auto_mode != 1 ) {
		$Template->param(FILEX_HAS_FILE=>1);
		$Template->param(FILEX_FILE_NAME=>toHtml($upload->getRealName()));
		my ($fsz,$funit) = hrSize($fstat[7]);
		$Template->param(FILEX_FILE_SIZE=>$fsz." ".$S->i18n->localizeToHtml("$funit"));
		$Template->param(FILEX_FILE_PUBLISHED_DATE=>toHtml(tsToGmt($upload->getUploadDate())." (GMT)"));
		$Template->param(FILEX_FILE_EXPIRE_DATE=>toHtml(tsToGmt($upload->getExpireDate()). " (GMT)"));
		$Template->param(FILEX_FILE_OWNER=>$S->getMail($upload->getOwner()));
		# enable auto download
		$Template->param(FILEX_CAN_DOWNLOAD=>1);
		my $fk = FIELD_FILE_NAME;
		my $fauto = FIELD_AUTO_MODE;
		my $download_url = $S->getCurrentUrl()."?".$S->genQueryString({$fk=>$file_name,$fauto=>1});
		$Template->param(FILEX_DOWNLOAD_URL=>$download_url);
		display($S,$Template);
	}
	# oki we can push the file
	# verify http range
	#my $range = $r->header_in('Range');
	#warn("Range ? : $range");

	# if download then go
	my $fh = Apache::File->new();
	if ( ! $fh->open($source) ) {
		$Template->param(FILEX_HAS_ERROR=>1);
		$Template->param(FILEX_ERROR=>$S->i18n->localizeToHtml("unable to open file"));
		display($S,$Template);
	}
	# inform that we accept range request
	# Content-Disposition filename MUST be US-ASCII
	my $content_disposition = "attachment; filename=";
	my $real_name_ascii = $upload->getRealName();
	# convert space to "_"
	$real_name_ascii =~ s/\s/_/g;
 	if ( $S->isIE() ) {
		#$real_name_ascii = $file_infos{'real_name'};
		$content_disposition .= $real_name_ascii;
	} else {
		$real_name_ascii = MIME::Words::encode_mimewords($upload->getRealName(),Charset=>'iso-8859-1');
		$content_disposition .= "\"$real_name_ascii\"";
	}
	$real_name_ascii = "unknown" if length($real_name_ascii) <= 0;
	$S->sendHeader('Content-Type'=>$upload->getContentType(),
	               'Content-Disposition'=>$content_disposition,
	               'Content-transfert-encoding'=>"binary",
	               'Content-Length'=>$fstat[7]);
	# in header_only then return
	if ( $S->apreq->header_only() ) {
		# close the file
		$fh->close();
		# send header
		$S->apreq->send_http_header();
		return OK;
	}
	
	my $download_id = genUniqId();
	$db->logCurrentDownload(fields=>[download_id=>$download_id,
	               upload_id=>$upload->getId(),
	               ip_address=>$S->getRemoteIP()]) or warn(__PACKAGE__,"-> Unable to log current download");
	# send file
	$S->apreq->send_fd($fh);
	# check for connection
	if ( !$S->isConnected() ) {
		$upload->addDownloadRecord(
			upload_id=>$upload->getId(),
			ip_address=>$S->getRemoteIP(),
			use_proxy=>$S->isBehindProxy(),
			proxy_infos=>$S->getProxyInfos(),
			canceled=>1) or warn(__PACKAGE__,"-> Unable to log download : ".$upload->getLastErrorString());
	} else {
		# log download for later stats
		$upload->addDownloadRecord(
			upload_id=>$upload->getId(),
			ip_address=>$S->getRemoteIP(),
			use_proxy=>$S->isBehindProxy(),
			proxy_infos=>$S->getProxyInfos(),
			canceled=>0) or warn(__PACKAGE__,"-> Unable to log download : ".$upload->getLastErrorString());
			# send email on success and get_delivery == 1
			if ( $S->config->needEmailNotification() && $upload->getGetDelivery() == 1) {
				warn (__PACKAGE__,"-> Unable to send email !") if ( ! sendMail($S,$upload) );
			}
	}
	$fh->close();
	
	# delete current download log
	# maybe make it in a register_cleanup way ...
	$db->delCurrentDownload($download_id) or warn(__PACKAGE__,"-> Unable to delete current download log : $download_id");

	# everything done
	return OK;
}

sub display {
	my $S = shift;
	my $T = shift;
	# base for static include
	$T->param(FILEX_STATIC_FILE_BASE=>$S->getStaticUrl()) if ( $T->query(name=>'FILEX_STATIC_FILE_BASE') );
	$S->sendHeader("Content-Type"=>"text/html");
	$S->apreq->print($T->output()) if ( ! $S->apreq->header_only() );
	exit(OK);
}

sub sendMail {
	my $s = shift;
	my $u = shift;
	# load template
	my $t = $s->getTemplate(name=>"mail_get") or return undef;
	# fill template
	$t->param(FILEX_FILE_NAME=>$u->getRealName());
	my ($fsz,$funit) = hrSize($u->getFileSize());
	$t->param(FILEX_FILE_SIZE=>$fsz." ".$s->i18n->localize($funit));
	$t->param(FILEX_FILE_DATE=>tsToLocal($u->getUploadDate()));
	$t->param(FILEX_FILE_EXPIRE=>tsToLocal($u->getExpireDate()));
	my $remote_ip = $s->apreq->connection->remote_ip();
	my $remote_name = rDns($remote_ip) || $s->i18n->localize("unknown");
	$t->param(FILEX_DOWNLOAD_ADDRESS=>$remote_ip);
	$t->param(FILEX_DOWNLOAD_NAME=>$remote_name);
	# make reverse DNS query
	$t->param(FILEX_SYSTEM_EMAIL=>$s->config->getSystemEmail());
	# send email
	my $to = $s->getMail($u->getOwner());
	return undef if !length($to);
	return $s->sendMail(
		from=>$s->config->getSystemEmail(),
		to=>$to,
		charset=>"ISO-8859-1",
		subject=>$s->i18n->localize("file downloaded %s",$u->getRealName()),
		content=>$t->output()
	);
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
