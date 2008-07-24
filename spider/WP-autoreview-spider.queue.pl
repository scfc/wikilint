#!/usr/bin/perl

#
#    Program: Autoreview for Wikipedia articles
#    Copyright (C) 2007  arnim rupp, email: arnim at rupp.de
#
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

# DESCRIPTION: review all articles found in a webpage

# TODO: 
# haeckchen fuer "nur artikel in abschnitts-wikilinl"
# haeckchen fuer in liste nur mit: mindestens einmal rot, 5 mal gruen, level > X, quote > X, gruene spalten weg
# taeglich tabelle kandidaten, top 100
# lesenwert, ex & kandidaten markieren!
# liste der artikel ohne bild (mit ohne koordinaten, commons)
# vermeiden die gleiche link-page zweimal hintereinander (kann vom eintragen passieren!)
# abfangen wenn nur fehlerseite kommt ohne links
#### rote links, 404
# eigene tabelle: keine oder schlechte bilder
# ankreuzable: bilder checken und/oder artikel checken
# prettytable sortable langsam

# KÜR:
# http://de.wikipedia.org/wiki/Spezial:Exportieren
# regelmaessige tabellen (abo)
# ueberwachung mit schwellwert im level (nicht quote!), passt sich nach unten an, nicht nach oben
# datenbank mit letzten review datum und review_letters, checken vor erneutem download
# excel-sheets (mailen?)
# markierung lesenqwert & exzel


$debug = 10;
$developer=1;
$|=1;
$do_typo_check  = 1;
#$dont_increase_queue=1;
#$dont_upload = 1;

# no downloading, use local files for testing
#$debugcat = 1;

################################################################
# ATTENTION: include proxy-line in next two!!!!!!!!!!!!!!!!!!!!!!
################################################################
use MediaWiki;
use Net::Anura;

use LWP::UserAgent;
use URI::Escape; 
use URI::Escape 'uri_escape_utf8';

use Proc::Pidfile;

use Benchmark::Timer;

use utf8;
use POSIX qw(locale_h);
setlocale(LC_CTYPE, "german");
setlocale(LC_ALL, "german");

binmode STDOUT, ":utf8";
use open ':utf8';

require "config.pm";
require "autoreview.pm";

my @months = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);
my @weekDays = qw(Sun Mon Tue Wed Thu Fri Sat Sun);
my ($second, $minute, $hour, $dayOfMonth, $month, $yearOffset, $dayOfWeek, $dayOfYear, $daylightSavings) = localtime();
$year = 1900 + $yearOffset;
$minute = "0$minute" if ( length( $minute ) == 1 );
$second = "0$second" if ( length( $second ) == 1 );
$now = "$hour:$minute:$second, $weekDays[$dayOfWeek] $months[$month] $dayOfMonth, $year";

print "##########################################################\n";
print "# starting at: $now \n";
print "##########################################################\n";


$language="de";

&read_files($language);

my $lolaaa;

# check that only one instance runs using Proc::Pidfile
my $pp = Proc::Pidfile->new( pidfile => "$spider_queue_file_semaphore" );
$pidfile = $pp->pidfile();

open (LAST, "< $spider_queue_file_last") || die "cant open $spider_queue_file_last\n";
$last_queue = <LAST>;
close(LAST);

print "last-queue: $last_queue\n" if ( $debug );
$last_queue++;

open (QUEUE, "< $spider_queue_file") || die "cant open $spider_queue_file\n";
while(<QUEUE>) {
	chop;
	my ($num, $link_page_tmp, $result_page_tmp, $real_evil_only_tmp, $section_links_only_tmp ) = split(/\t/);
	if ( $num == $last_queue ) {
		$link_page = $link_page_tmp;	
		$result_page = $result_page_tmp;	
		$real_evil_only = $real_evil_only_tmp;
		$section_links_only = $section_links_only_tmp;
		$found = 1;
	}
	
}
close(QUEUE);

# remove trailing spaces
$result_page =~ s/ +$//g;
$link_page =~ s/ +$//g;

# nothing found, nothing to do
if ( !$found ) {
	#print "nothing to do\n" if ($debug );
	exit;
}

if ( !$link_page || !$result_page ) {
	&open_error_log();
	print ERRORLOG "ich kann so nicht arbeiten: link_page: $link_page - result_page: $result_page\n";
	&write_new_last_queue( $last_queue );
	die "ich kann so nicht arbeiten: link_page: $link_page - result_page: $result_page\n";
}

my $result_page_tmp = $result_page;
$result_page_tmp =~s#http://\w\w\.wikipedia\.org/w(iki)?/##i;

if ( $result_page_tmp !~ /^Benutzer:.+?\/Autoreview/i ) {
	&open_error_log();
	print ERRORLOG "result_page ist keine Benutzer-Seite oder beginnt nicht mit \"Autoreview\": $result_page\n";
	&write_new_last_queue( $last_queue );
	die "result_page beginnt nicht mit \"Autoreview\": $result_page\n";
}

# check if $result_page exists
$mediawiki_connection = MediaWiki->new;
$mediawiki_connection->setup({
        'wiki' => {
                'host' => 'de.wikipedia.org',
                'path' => 'w'
        }});


my $exist = $mediawiki_connection->exists($result_page_tmp);

if ( !$exist && $result_page !~ m#^http://de\.wikipedia\.org/wiki/Benutzer:Arnomane# ) {
	&open_error_log();
	print ERRORLOG "result_page doesnt exist: $result_page\n";
	&write_new_last_queue( $last_queue );
	die "result_page doesnt exist: $result_page\n";
}


###############################################################
# everything OK, let's go 
###############################################################

open (LOG, ">> $spider_queue_log") || die "cant write $spider_queue_log\n";
print LOG "--------\n$now\n";
print LOG "link_page: $link_page - result_page: $result_page\n";

$link_page_x = $link_page;
$link_page_x =~ s/ /_/g;

# create table heading
$table_lines .= "
{| class=\"prettytable sortable\"
|+ style=\"padding-bottom:1em\" | Autoreview-Spider von $link_page_x am $now
|-
";

$table_lines .="!Nummer\n";
$table_lines .="!width=\"10%\"|Artikel aktuell\n";
##$table_lines .="!width=\"10%\"|Version des Auto-Reviews\n";
$table_lines .="!Problem-Quote\n";
$table_lines .="!Level\n";
$table_lines .="!Wörter\n";

$farbe{"3"} = "hintergrundfarbe7";
$farbe{"2"} = "hintergrundfarbe8";
$farbe{"1"} = "hintergrundfarbe9";


my ( @order_letters ) = split(//, $table_order );
foreach my $letter ( @order_letters ) {
	my ( $level, $summary, $message ) = split(/\|/, $text{"de|$letter"});

	if ( !$real_evil_only || ( $real_evil_only && $level > 1 )) {
		$table_lines .="! class=\"".$farbe{$level}."\"|$message\n";
	}
}
$table_lines .="\n";

print "link-page: $link_page\n" if ( $debug );

# collect liste of articles without picture to include in result-page
local ( $no_pic);

if ( $debugcat ) {
	$page =' <a href="/wiki/Alessandro_Bausani" title="Alessandro Bausani">Alessandro Bausani</a>';
}
else {
	################################################# here we go
	&review_link_page( $link_page );
}

# finish stuff, create summary, ...

$table_lines .= "\n|}\n";

my ($second, $minute, $hour, $dayOfMonth, $month, $yearOffset, $dayOfWeek, $dayOfYear, $daylightSavings) = localtime();
$year = 1900 + $yearOffset;
$minute = "0$minute" if ( length( $minute ) == 1 );
$second = "0$second" if ( length( $second ) == 1 );
$now = "$hour:$minute:$second, $weekDays[$dayOfWeek] $months[$month] $dayOfMonth, $year";


# this one not "sortable" because just one row
$table_lines_2 .= "
{| class=\"prettytable\"
|+ style=\"padding-bottom:1em\" | Zusammenfassung Autoreview-Spider von $link_page am $now
|-
";

$table_lines_2 .="!Anzahl Artikel\n";
$table_lines_2 .="!Problem-Quote Durchschnitt\n";
$table_lines_2 .="!Level Durchschnitt\n";
$table_lines_2 .="!Wörter Summe\n";

my ( @order_letters ) = split(//, $table_order );
foreach my $letter ( @order_letters ) {
	my ( $level, $summary, $message ) = split(/\|/, $text{"de|$letter"});

	if ( !$real_evil_only || ( $real_evil_only && $level > 1 )) {
		if ( $summary eq "S" ) {
			$table_lines_2 .="! class=\"".$farbe{$level}."\"|Summe: $message\n";
		}
		elsif ( $summary eq "C" ) {
			$table_lines_2 .="! class=\"".$farbe{$level}."\"|Anzahl Artikel: $message\n";
		}
		elsif ( $summary eq "X" ) {
			$table_lines_2 .="! class=\"".$farbe{$level}."\"|Maximum: $message\n";
		}
	}
}
$table_lines_2 .="\n";

$num_words_total = $num_words_total || 1;
$count_articles = $count_articles || 1;

$quotient_avg = int (( $review_level_total / $num_words_total *1000 +0.5)*100)/100;
$review_level_avg = int (( $review_level_total / $count_articles +0.5)*100)/100;


$table_lines_2 .= "|-\n";
$table_lines_2 .= "|$count_articles\n";
$table_lines_2 .= "|$quotient_avg\n";
$table_lines_2 .= "|$review_level_avg\n";
$table_lines_2 .= "|$num_words_total\n";

foreach my $letter ( @order_letters ) {
	my ( $level, $summary, $message ) = split(/\|/, $text{"de|$letter"});

	if ( !$real_evil_only || ( $real_evil_only && $level > 1 )) {
		$table_lines_2 .= "||".$count_letters_total{ $letter };
	}

}

$table_lines_2 .= "\n|}\n";

# print wiki-table to file
my $link_page_tmp = $link_page;
$link_page_tmp =~ s/https?:\/\///gi;
$link_page_tmp = uri_escape ( $link_page_tmp );
$table_file = $link_page_tmp." AM ".$now;

$table_file =~ s/ /_/g;

$table_lines = "==Zusammenfassung==\n\n$table_lines_2\n\n==Ergebnisse==\n".$table_hint{"$language"}."\n\n.$table_lines\n";

if ( $no_pic ) {
	$table_lines .= "\n\n==Artikel ohne Bild==\n$no_pic\n";
}

print "DEBUG table_file: $table_file\n";
die "fehler: punkt punkt\n" if ( $table_file =~ /\.\./ || $table_file =~ /\/\// );
open (TABLE, "> $spider_queue_table_dir/$table_file") || die "cant write $spider_queue_table_dir/table_file\n";
print TABLE "$table_lines\n";
close(TABLE);

# captcha bot-problem with Mediawiki-cpan-module 1.11 !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
&upload_to_wikipedia_anura( $table_lines, $result_page_tmp ) if ( !$dont_upload );

&write_new_last_queue( $last_queue );

print LOG "DONE: --------\n$now\n";
print LOG "DONE: link_page: $link_page - result_page: $result_page\n";

exit;
###########################################################
# end of main()
###########################################################

sub review_link_page {

	my ( $link_page, $recursion_depth ) = @_;

	my ( $first_link_ignored);

	# to avoid doing the same page twice
	$count_linkpage{ "$link_page" }++;

	$link_page =~ s/ /_/g;

	last if ( $recursion_depth > $max_recursion_depth );

	print "PAGE: $link_page - RECURSION DEPTH: $recursion_depth\n" if ( $debug > 5 );

	my $page = &http_download( $link_page );

	if ( !$page ) {
		&open_error_log();
		print ERRORLOG "ich kann so nicht arbeiten, link-page nicht downloadbar oder ohne inhalt: $page - $link_page - $result_page\n";
		&write_new_last_queue( $last_queue );
		die "ich kann so nicht arbeiten, link-page nicht downloadbar oder ohne inhalt: $page - $link_page - $result_page\n";

	}

	my ( @lines ) = split(/\n/, $page);

	print "----------------------------------------------------------------------\n" if ( $debug );


	# loop over all lines in linkpage
	LINES: foreach my $line ( @lines ) {

		#print "LINE: $line\n" if ($debug );


		if ( $line =~ /CategoryTreeSection/ ) {
			$sub_category_ahead=1;
print "sub_category_ahead: $line\n" if ( $debug );
		}
		else {
			$sub_category_ahead=0;
		}

		if ( $line =~ /nächste/ ) {

			# don't follow first link to next page because the order of the reuslt-table would be backwards
			if ($first_link_ignored++) {
				$next_page_ahead=1;
				# avoid splitting of "nächste" by ">" (to be able to distinguish from "vorherige"
				$line =~ s/">nächste /"-NEXT-nächste /;
print "next_page_ahead: $line\n" if ( $debug );
			}
		}
		else {
			$next_page_ahead=0;
		}

		# split by HTML-tags	
		my ( @words ) = split(/[<>]/, $line );

		foreach my $word ( @words ) {

			my ($link , $lemma , $lemma_list) = "";

			# recurse into subcategory
			if ( $sub_category_ahead ) {
				if ( $word =~ m#^a class="CategoryTreeLabel.+? href="(/wiki/Kategorie:.+?)"$#i ) {
					my $link_page_sub = "http://de.wikipedia.org$1";

					if ( !$count_linkpage{ "$link_page_sub" } ) {
						$recursion_depth++;
print "Subkategorie: $link_page_sub - rec: $recursion_depth - word: $word\n" if ( $debug > 5 );
						$table_lines .= &review_link_page( $link_page_sub, $recursion_depth );

					}
					else {
print "Subcategory already crawled: $link_page_sub - rec: $recursion_depth - word: $word\n" if ( $debug > 5 );
					}
				}
				$link = "";
			}
			# check for pages split into several hundreds
			elsif ( $next_page_ahead ) {
				#if ( $word =~ m#^a class="CategoryTreeLabel.+? href="(/wiki/Kategorie:.+?)"$#i ) {
				print "might be nextpage: $word\n" if ( $debug > 5 );
				if ( $word =~ m#^a href="(/w/index\.php\?title=Kategorie:.+?&(amp;)?from=.+?)" title="Kategorie:.+?"-NEXT-nächste#i ) {
					my $link_page_sub = "http://de.wikipedia.org$1";

					# why is there &amp; in the URL ?
					$link_page_sub =~ s/&amp;/&/g;

					if ( !$count_linkpage{ "$link_page_sub" } ) {
						$recursion_depth++;
print "Next Page: $link_page_sub - rec: $recursion_depth - word: $word\n" if ( $debug > 5 );
						$table_lines .= &review_link_page( $link_page_sub, $recursion_depth );

					}
					else {
print "Next Page already crawled: $link_page_sub - rec: $recursion_depth - word: $word\n" if ( $debug > 5 );
					}
				}
				$link = "";
			}
			else {
				# follow: <a href="/wiki/Alessandro_Bausani" title="Alessandro Bausani">Alessandro Bausani</a>
				# follow: <a href="/wiki/Computertechnik" title="Computertechnik">Computertechnik</a>
				# nofollow red links: <a href="/w/index.php?title=Amavisd&amp;action=edit" class="new" title="Amavisd">Amavisd</a>
				# wikilink
				if ( $word =~ m#^a href="/wiki/([^"]+?)" title="([^"]+?)"$#i ) {

					$link = $1;
					$lemma = $2;
					$lemma =~ s/&amp;/&/;
					$lemma_list = uri_escape_utf8($lemma);

					if ( !$section_links_only || $line =~ /mw-headline/ ) {
					}
					else {
						print "looking for section_links_only but not: $word - $line\n" if ( $debug );
						$link = "";
					}
				}
				# weblink to wikipedia
				elsif ( $word =~ m#^a href='http://de\.wikipedia\.org/wiki/([^'\?]+?)\?#i ) {
					$lemma = $1;
					$lemma_list = $1;
					$lemma =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;
					utf8::decode($lemma) ;
					$link = $lemma;
				}
				else {
					#print "NOT: $word\n" if ($debug );
				}
			}



			# ignore ocmments, Spezial:, ...
			if ( 
				$link && 
				!$count_reviewed{ "$lemma_list" } &&
				$link !~ /^(Spezial:|Portal:|Liste|Wikipedia:|WP:|Hauptseite|Nekrolog|Kategorie:|Bild:|\w+[ _]Diskussion:|Benutzer:|Hilfe:|Vorlage:|Diskussion:)/ 
			) {
	print "link: $link - lemma: $lemma - lemma_list: $lemma_list\n" if ( $debug );
	# link: Lost_%26_Found_1961-1962 - lemma: Lost &amp; Found 1961-1962 - lemma_list: Lost%20%26amp%3B%20Found%201961-1962

				$review_number++;
				print LOG "$review_number: lemma_list: $lemma_list - link: $link - lemma: $lemma\n";

				$count_reviewed{ "$lemma_list" }++;

				my ( $page, $review_level, $num_words, $extra_message );
			
				if ( $debugcat ) {
					$page = `cat test.html`;
				}
				else {
					# be polite and don't download more than one page per second,
					# but also don't wait the second if the last review took more than one seoncd anyway
					$now_ts = time;
					if ( $now_ts - $last_download_ts <= 1 ) {
						sleep 1;
					}

					# do download
					$page = &download_page("",$lemma_list, $language, "", "ignore_error");

					# don't wait if $do_typo_check because that takes long enough anyway
					&wait_in_rush_hour() if (!$do_typo_check);

					$last_download_ts = time;
				}

				if ( $page ) {

					# don't build perm-links for time of review, doubles traffic and the tables get too big and slow
					### wait 1 sec because last download just happened
					##sleep 1;
					##sleep $rush_hour_extra_seconds;
					##my ($permid) = &get_permid( $lemma, $mediawiki_connection );

					( $page, $review_level, $num_words, $extra_message, $quotient , $review_letters ) = &do_review( $page, $language,"" , $lemma_list, $do_typo_check );

					
					print "$quotient - done: $lemma_list: $review_level \n";

					print $extra_message."\n###########\n\n" if ( $debug > 9 );

					print "$review_letters\n";

					$edit_link = &create_edit_link($lemma_list, "de", "bearbeiten");
					$ar_link = &create_ar_link($lemma_list, "de", "", $do_typo_check );

					##$perma_link = &create_perma_link($lemma_list, "de", $permid );
					##$perma_ar_link = &create_ar_link($lemma_list, "de", $permid, $do_typo_check );

					$count_articles++;
					$table_lines .= "|-\n";
					$table_lines .= "|$count_articles\n";
					$table_lines .= "|[[$lemma]] <br />([$edit_link Bearbeiten] [$ar_link Autoreview])\n";
					##$table_lines .= "|([$perma_link Anzeigen] [$perma_ar_link Autoreview])\n";
					$table_lines .= "|$quotient\n";
					$table_lines .= "|$review_level\n";
					$table_lines .= "|$num_words\n";
					$table_lines .= &create_table_line( $review_letters, $real_evil_only )."\n";

					$num_words_total += $num_words;
					$review_level_total += $review_level;
					$quotient_total += $quotient;

					last LINES if ( $count_articles == $max_links_spider_review );

					if ( $review_letters =~ /h/ ) {
						$no_pic .= "* [[$lemma]]\n";
					}

				}
			}
		}
	}

}


sub create_table_line {

	my ( $review_letters, $real_evil_only ) = @_;
	my ( $line );



	my ( @letters ) = split(//, $review_letters );
	my %count_letters;
	foreach my $letter ( @letters ) {
		$count_letters{ $letter }++;
	}

	my ( @order_letters ) = split(//, $table_order );

	foreach my $letter ( @order_letters ) {

                my ( $level, $summary, $message ) = split(/\|/, $text{"$language|$letter"});

		if ( !$real_evil_only || ( $real_evil_only && $level > 1 )) {
			$line .= "||".$count_letters{ $letter };
			#print "$letter - ".$count_letters{ $letter }."<br>\n";

			# sum up everything
			if ( $summary eq "S" ) {
				$count_letters_total{ $letter } += $count_letters{ $letter };
			}
			# count
			if ( $summary eq "C" ) {
				if ( $count_letters{ $letter } ) {
					$count_letters_total{ $letter }++;
				}
			}
			# max
			if ( $summary eq "X" ) {
				if ( $count_letters_total{ $letter } < $count_letters{ $letter } ) {
					$count_letters_total{ $letter } = $count_letters{ $letter };
				}
			}
		}
	}

	( $line );
}

sub open_error_log {
	open (ERRORLOG, "> $spider_queue_error_log") || die "cant write $spider_queue_error_log\n";
	print ERRORLOG "------\nnow: $now\n";
}

sub write_new_last_queue {
	my ( $last_queue ) = @_;
	if ( !$dont_increase_queue ) {
		# overwrite last-file with new highest number
		open (LAST, "> $spider_queue_file_last") || die "cant open $spider_queue_file_last\n";
		print LAST $last_queue;
		close(LAST);
	}
}

sub upload_to_wikipedia_anura {
	my ( $table_lines, $result_page_tmp ) = @_;
	print "DEBUG: table_lines: $table_lines, -$result_page_tmp-\n"; 

	utf8::encode($table_lines);

	system "rm ~/.anura/cookies";

	my $tries = 0 ;
	my $upload_ok = 0 ;

	my $wikipedia = Net::Anura->new(
		wiki => 'http://de.wikipedia.org/wiki',
		username => "$botname",
		password => "$botpw"
	);

	do {

		my ($is_ok) = $wikipedia->get( "$result_page_tmp");

		if(!$is_ok) {
			print "errror downloading resultpage -$result_page_tmp-\n";
			exit;
		}
		else {
 
			($is_ok ) = $wikipedia->put( "$result_page_tmp", $table_lines, "Autoreview Spider Ergebnis geschrieben" ), "\n";

			if(!$is_ok) {
				print "err3: $err - is_ok: $is_ok - tries: $tries\n";
			}
			else {
				$upload_ok = "hurray!";
				print "upload to $result_page_tmp OK\n";
			}
		}

		# don't care if down- or upload failed, just wait X seconds if it didn't work
		if ( !$upload_ok ) {
			sleep $wait_between_http_retry;
		}

		# try maximum $http_retry times
		$tries++;
	} until ( $tries > $http_retry || $upload_ok );

	if ( !$upload_ok ) {
		print "UPLOAD FAILED\n";
	}

	$wikipedia->logout;


}

# this one stopped working someday without reasonalbe error message. tcpdump found in "previewnote": "session expired, log off/on"
sub upload_to_wikipedia {
	my ( $table_lines, $mediawiki_connection, $result_page_tmp ) = @_;
	#print " $table_lines, $mediawiki_connection, $result_page_tmp\n"; 
	$mediawiki_connection->login("$botname", "$botpw");

	utf8::encode($table_lines);

	my $tries = 0 ;
	my $upload_ok = 0 ;

	do {

		$is_ok = $pg =  $mediawiki_connection->get("$result_page_tmp","rw");

		if(!$is_ok) {
			$err = $c->{error};
			print "err2: $err - is_ok: $is_ok \n";
			exit;
		}
		else {

			# overwrite old page, there is a versioning in wikipedia
			$pg->{content} = $table_lines;
			$pg->{summary} = "Autoreview Spider Ergebnis geschrieben";
			$is_ok = $pg->save();
			if(!$is_ok) {
				$err = $c->{error};
				print "err3: $err - is_ok: $is_ok - tries: $tries\n";
			}
			else {
				$upload_ok = "hurray!";
				print "upload to $result_page_tmp OK\n";
			}
		}

		# don't care if down- or upload failed, just wait X seconds if it didn't work
		if ( !$upload_ok ) {
			sleep $wait_between_http_retry;
		}

	# try maximum $http_retry times
	$tries++;
	} until ( $tries > $http_retry || $upload_ok );

	if ( !$upload_ok ) {
		print "UPLOAD FAILED\n";
	}

}

sub get_permid {
	my ( $lemma_list, $mediawiki_connection ) = @_;

	my $tries = 0 ;
	my $get_ok = 0 ;
	my ( $user, $comment, $date, $time, $oldid);

	do {

		$is_ok = $pg =  $mediawiki_connection->get("$lemma_list");

		if(!$is_ok) {
			$err = $c->{error};
			print "err2: $err - is_ok: $is_ok \n";
			sleep $wait_between_http_retry;
		}
		else {
			$get_ok = 1;
		}


		my $edit_p = $pg->last_edit;

		$user = $edit_p->{"user"};
		$oldid  = $edit_p->{"oldid"};
		$comment = $edit_p->{"comment"};
		$date = $edit_p->{"date"};
		$time = $edit_p->{"time"};

		print "$user-\t-$comment-\t-$date-\t-$time\t-$oldid\n" if ( $debug > 1 );

		$tries++;
	} until ( $tries > $http_retry || $get_ok );

	($oldid );
}

sub wait_in_rush_hour {

	# slow down in daytime

	my ($second, $minute, $hour, $dayOfMonth, $month, $yearOffset, $dayOfWeek, $dayOfYear, $daylightSavings) = localtime();
	# a bit slower in rush hour
	if ( $hour > $rush_hour_start && $hour < $rush_hour_end ) {
		# otherwise this one is filled in config.pm
		sleep $rush_hour_extra_seconds;
	}
}
