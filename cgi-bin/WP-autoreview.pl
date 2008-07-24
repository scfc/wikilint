#!/usr/bin/perl
###!/usr/bin/perl -CS
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

#### DESCRIPTION:
# wikipedia autoreviewer
# checks a wikipedia-page for "things that should be changed"
# code-level: quick hacked proof of concept!
# contains UTF8-characters so take care with editor and terminal-settings, win98 doesn't work!
#


#$debug =10;
#$debugcat=1;

# use test.html, no downloading from WP
$debugdry=0;

# removed debug condition temporarily (Arnomane)
$debug=0;

$title = "Wikipedia Autoreviewer (Beta Version)";
$tool_base = "http://tools.wikimedia.de";
$tool_path = "/~arnomane/cgi-bin";
$tool_url = "$tool_base$tool_path";

use Benchmark::Timer;

if ( $ENV{"REMOTE_ADDR"} ) {
	$online = 1;
}


#############################################################
# no config below here
#############################################################

local $start_ts = time;

$bench = Benchmark::Timer->new();
$bench->start('total');





use CGI qw/:standard/;
use LWP::UserAgent;
use URI::Escape;

#############################################################
# i don't get all this utf8-stuff but it kind of works now
# IMPORTANT!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
# i had to change usr/lib/perl5/5.8.6/unicore/CaseFolding.txt and SpecialCasing.txt
# to prevent perl from matching ß to ss (don't know if there is a better way)
# to be able to look for "daß" without finding "dass".
# in both files in uncommented the line starting with 00DF
# and called "perl mktables" in the same directory. 
# this change is of course for the whole system!
# IMPORTANT!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

use utf8;
use POSIX qw(locale_h);
use URI::Escape 'uri_escape_utf8';


setlocale(LC_CTYPE, "german");
setlocale(LC_ALL, "german");


binmode STDOUT, ":utf8";
use open ':utf8';
#############################################################

# prod
require "config.pm";
require "autoreview.pm";
$myname ="WP-autoreview.pl";
# test
#require "config_t.pm";
#require "autoreview_t.pm";
#$myname ="WP-autoreview_t.pl";


if (param() || $debugdry ) {

	# override stuff for testing
	if ( $ARGV[0] eq "test" ) {
		$debugdry=1;
		$selftest=1;
		$do_typo_check = 1;
		$url = "http://de.wikipedia.org/wiki/Amphetamin";
		$language = "de";
		$remove_century=1;
		$developer =1;
		#$debug =9;
	}
	elsif ( !$debugdry ) {
		($url, $language, $random_page, $testpage, $remove_century, $action, $oldid, $do_typo_check) = &parse_form();
	}
	else {
		$language = "de";
	}

	if ( $random_page ) {
		$url = &find_random_page($language);
	}

	my $link_lemma;

	if ( $url=~ /title=/ ) {
		$url =~ /title=(.+)&/;
		$link_lemma = $1;
	}
	else {
		# get last part of url as lemma
		$url =~ /.+\/(.+)/;
		$link_lemma = $1;
	}
	$title_lemma = $link_lemma if ( !$debugcat );
	$title_lemma =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;
	utf8::decode($title_lemma);
	$title_lemma =~ s/_/ /g;
	$title_lemma = "Testseite" if ( $testpage );

	&begin_html();

	if ( $debug ) {
		print "debug:<p>\n";
		print 
		"URL from form: <a href=\"$url\">$url</a>",p,
		"Language: ",$language,p,
		"Random: ",$random_page,p,
		"link_lemma: ",$link_lemma,p,
		hr;
	}

$bench->start('readfiles');
	&read_files($language);
$bench->stop('readfiles');



	# write some log
	my @months = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);
	my @weekDays = qw(Sun Mon Tue Wed Thu Fri Sat Sun);
	my ($second, $minute, $hour, $dayOfMonth, $month, $yearOffset, $dayOfWeek, $dayOfYear, $daylightSavings) = localtime();
	$year = 1900 + $yearOffset;
	$minute = "0$minute" if ( length( $minute ) == 1 );
	$second = "0$second" if ( length( $second ) == 1 );
	$now = "$hour:$minute:$second, $weekDays[$dayOfWeek] $months[$month] $dayOfMonth, $year";

	if ( $url && !$testpage ) {
		open(LOG, ">> ./$0.log") || die "cant write $0.log\n";
		print LOG "$now:".localtime().":$language:$url:$random_page:".$ENV{"REMOTE_ADDR"}."\n";
		close(LOG);
	}

	if ( $testpage || $debugdry ) {
		open(TEST, "< ./test.html") || die "cant open test.html\n";
		while(<TEST>) {
			$page .= $_;
		}
		close(TEST);
		#$page = `cat test.html`;
	}
	else {
		$page = &download_page($url, "", $language, $oldid);
	}
#print "seiteA: <pre>$page</pre>" if ( $developer);


	# [^'] to avoid jumping on #REDIRECT [[',']]
	if ( $page =~ /#REDIRECT ?\[\[([^']+?)\]\]/ ) {
		$to = $1;
		print "<h3>Wikipedia redirect, please follow this link: <a href=\"$toolurl/$myname?l=de&lemma=$to\">$1</a></h3><p>\n";
	}
	else {

		($page, $review_level, $num_words, $extra_message, $quotient, $review_letters, $propose_page, $removed_links, $count_ref, $count_fillwords ) = &do_review( $page, $language, $remove_century, $link_lemma, $do_typo_check );


		# to avoid strange reactions in <textarea>, e.g. wth comments like <!-- -- -- -- -->
		$propose_page =~ s/&/&amp;/g;
		$propose_page =~ s/</&lt;/g;
		$propose_page =~ s/>/&gt;/g;

		$propose_page = "" if ( $removed_links == 0 );

		if ( !$selftest ) {
			&output( $page, $url, $language, $review_level, $extra_message, $propose_page, $link_lemma, $quotient, $review_letters, $removed_links, $oldid, $count_fillwords, $num_words );
		}
		else {
			&selftest( $page, $extra_message );
		}
	}
}
else {
	&begin_html();
	&print_explanation();
	&print_form();
	print p,
		br,
		"<b>Liste der <a href=\"$tool_path/$myname?action=show_avoid_words_de\">zu vermeidenden Wörter</a>, <a href=\"$tool_path/$myname?action=show_fill_words_de\">Füllwörter</a> und der <a href=\"$tool_path/$myname?action=show_abbr_de\">Abkürzungen</a></b><br>\n",
               "<hr />Veröffentlicht unter GPL: <a href=\"http://tools.wikimedia.de/~arnomane/download/\">Download</a><br />Kontakt: <a href=\"http://de.wikipedia.org/wiki/Benutzer:Arnomane\">Arnomane</a>";

# spider commented out (performance reasons and not much requested, Arnomane)
#	print "<center><table border=1><tr><td><b><font color=red>Neues:</font></b> 100 Seiten auf einmal autoreviewern: <a href=\"http://rupp.de/cgi-bin/WP-autoreview-spider.pl\">Beta-Test Autoreview-Spider</a></table>";
}
$bench->stop('total');

if ( $developer && $debug ) {
print "#####".$bench->report('total')."<br>";
print "#####".$bench->report('readfiles')."<br>";
}


print "</body></html>\n" if ( $online );
exit;

sub begin_html {

	if ( $online ) {

		# removed debug condition (Arnomane)

		print header (-type => 'text/html; charset=utf-8'),
		       start_html(-title=>"$title $title_lemma",
				-encoding=>'utf-8',
				-head=>meta({-http_equiv=>'Content-Type',
					       -content=>'text/html; charset=utf-8'})
				-lang=>'de-DE',
				 -bgcolor=>'#FFFFFF'),
				"<link rel=stylesheet type=\"text/css\" href=\"/~arnomane/wp-autoreviewer/wp.css\">",
				"<center>",
			       h1("<font face=helvetica,arial>$title</font>"),"</center>";

	}

}
#######################################################################

sub print_explanation {
	print "<table border=0>";
	print "<tr><td><img src=/~arnomane/wp-autoreviewer/deflag.jpg><td><b>Dieser Dienst pr&uuml;ft automatisch Wikipedia-Seiten auf h&auml;ufige Fehler. Bisher wird nur Deutsch und Englisch unterst&uuml;tzt.</b><br> \n";
	print "<b>Bitte Kommentare, Fehler und Ideen <a href=\"http://de.wikipedia.org/wiki/Benutzer_Diskussion:Arnomane\">hier</a> eintragen.\n";
	print "( <a href=\"#explanations\">Liste der Funktionen</a> )</b> \n";

	print "<tr><td><img src=/~arnomane/wp-autoreviewer/gbflag.gif><td>This service automatically reviews Wikipedia-articles for some common problems. So far only German and English are supported as article languages. Leave comments, bugs & ideas <a href=\"http://de.wikipedia.org/wiki/Benutzer_Diskussion:Arnomane\">here</a>.<p>\n";

	print "</table>\n";
}

sub print_form {

	my ( $url ) = @_;

	$url = $url || "http://de.wikipedia.org/wiki/Amphetamin";

	param ('url', $url );

	print 
               start_form ( -method=>"GET",
				-action=>"$tool_path/$myname",
				-'accept-charset'=>"utf8",
				-enctype=>"application/x−www−form−urlencoded"),
               " URL / Lemma: ",textfield(-name =>'url',
						-default => "$url", 
						-size => 70)," (Bei Problemen mit deutschen Umlauten die URL von Wikipedia kopieren)", p,
		checkbox(-name=>'remove_century',
                           -checked=>0,
                           -value=>'ON',
			-label=>""),
                           "<b>[[18. Jahrhundert]], [[April]], [[1960er]] auch entfernen</b> / also remove century links ",br,
		checkbox(-name=>'do_typo_check',
                           -checked=>1,
                           -value=>'ON',
			-label=>""),
                           "<b>Tippfehler-Prüfung (dauert etwas länger)</b> / Typo check","&nbsp;&nbsp;&nbsp;",
		checkbox(-name=>'rnd',
                           -checked=>0,
                           -value=>'ON',
			-label=>""),
                           "<b>Zuf&auml;llige Seite</b> / Random Page ","&nbsp;&nbsp;&nbsp;",
		checkbox(-name=>'testpage',
                           -checked=>0,
                           -value=>'ON',
			-label=>""),
                           "<b>Test Seite</b> / Testpage ",br,
               " <b>Sprache</b> / Language: ",
               popup_menu(-name=>'l',
                          -values=>['de','en'])," (English language limited)",br,

               submit(-name=>'Go!') ,
               end_form;


}

sub parse_form {

	my $url = param('url');
	my $language =param('l');
	my $random_page=param('rnd');
	my $lemma = param('lemma');
	my $testpage = param('testpage');
	my $remove_century = param('remove_century');
	my $action = param('action');
	my $oldid = param('oldid');
	my $do_typo_check = param('do_typo_check');

	$do_typo_check = 1 if ( $do_typo_check );
	$random_page = 1 if ( $random_page );
	$testpage = 1 if ( $testpage );

	die if ( $oldid && $oldid =~ /\D/ );
	die if ( $language && $language !~ /^\w\w$/ );

begin_html() if ( $developer && $debug > 8 );
print "url: $url<br>\n" if ( $developer && $debug > 8 );
	utf8::decode($url);
	utf8::decode($lemma);
print "url: $url<br>\n" if ( $developer && $debug > 8 );
print "lemma: $lemma - $lemma_conv<p>\n" if ( $developer && $debug > 8 );

	if ( $action eq "show_avoid_words_de" ) {
		&begin_html();
		&show_textfile("avoid_words_de.txt");
		exit;
	}
	elsif ( $action eq "show_fill_words_de" ) {
		&begin_html();
		&show_textfile("fill_words_de.txt");
		exit;
	}
	elsif ( $action eq "show_abbr_de" ) {
		&begin_html();
		&show_textfile("abbreviations_de.txt");
		exit;
	}

	# empty url/lemma
	if ( !$url && !$lemma ) {
		&begin_html();
		print "<h3>FEHLER: Keine URL angegeben</h3><hr><p>\n";
		&print_form();
		exit;
	}

#print "XX: $url<p>\n";
	# if people enter only the lemma in url-field
	if ( $url =~ /^[\w öäüÖÄÜß\-()]+$/ && !$lemma ) {
		$lemma = $url;
		$url = "";
	}

#print "lemma: $lemma<p>\n";

	# strip http://ix.de#section
	$url =~ s/(.+?)#.*/$1/g;

	if ( !$language ) {
		$language =param('language');
	}
	
	# check URL
	if ( $url && (
		$url =~ /\.\./ || 
		$url =~ /;/ || 
		length($url)> 150 ||
		( 
			# if URL is passed only to wikipedia.org
			( 
				$url =~ /https?:/ ||
				$url =~ /:\/\// 
			) && 
			$url !~ /^http:\/\/\w\w\.wikipedia.org\/w(iki)?\//i 
		)
	)) {
		&begin_html();
		print "wrong URL or Lemma $url<p>\n";
		exit;
	}

	#$url =~ /([^\w\d\%\_\-\:\.\/\?\&=\(\)\s-])/ 

	# only german or english so far
	if ( ($language ne "de" && $language ne "en") ) {
		&begin_html();
		print "wrong language<p>\n";
		exit;
	}

	# nicer in logfile
	if ( $random_page ) {
		$random_page = 1 ;
	}
	else {
		$random_page = 0 ;
	}

	if ( !$url && $lemma ) {
		#&begin_html() if ( $developer );
		print "lemma: $lemma - $lemma_conv<p>\n" if ( $developer );
		my $lemma_conv = uri_escape_utf8($lemma);
		print "lemma: $lemma - $lemma_conv<p>\n" if ( $developer );

		# default to typo-check if lemma is passed
		$do_typo_check = 1;


		if ( $language eq "de" ) {
			$url = "http://de.wikipedia.org/wiki/$lemma_conv";
		}
		elsif ( $language eq "en" ) {
			$url = "http://en.wikipedia.org/wiki/$lemma_conv";
		}
		else {
			&begin_html();
			print "unsupported language<p>\n";
			exit;
			
		}
	}

			#&begin_html();
	#print '$url, $language, $random_pagem, $testpage, $remove_century, $action, $oldid);<br>' if ( $debug &&  $developer);
	#print "($url, $language, $random_pagem, $testpage, $remove_century, $action, $oldid);<br>" if ( $debug &&  $developer);
	($url, $language, $random_page, $testpage, $remove_century, $action, $oldid, $do_typo_check);
}



sub output {
	my ( $page, $url, $lang, $review_level, $extra_message, $propose_page, $link_lemma, $quotient, $review_letters, $removed_links, $oldid, $count_fillwords, $num_words ) = @_;

	# include HTML-linebreaks
	$page =~ s/\n/<br>\n/g;

	# include <a name> for each ==section==, tricky because of my own HTML in section-titles, e.g.:
	# ==Veröffentlichungs<span class="sometimes">-</span><sup class="reference"><a href=#colon_minus_section>[CMS]</a></sup> und Rezeptionsgeschichte==<br>
	$page =~ s/(={2,9})\s*(.*?)(<.*?>)(.*?)(<.*>)(.*?)\s*(={2,9})/<a name=\"$2$4$6\">$1$2$3$4$5$6$7<\/a>/g;
	# now sections without HTML aka [^<] 
	$page =~ s/(={2,9})\s*([^<]+?)\s*(={2,9})/<a name=\"$2\">$1$2$3<\/a>/g;

	if ( $language eq "de" ) {
		$edit_link = &create_edit_link($lemma_org, "de");
		print "\n<font face=arial,helvetica>",h3("Geprüfter Artikel: <a href=\"$url\">$search_lemma</a> <font size=-1> [<a href=\"$edit_link\" target=\"_blank\">Bearbeiten in Wikipedia</a>]");
		my $link = &create_ar_link($link_lemma, "de");
		$link .= "&oldid=$oldid" if ( $oldid );
		print "Link zu dieser Seite: $link<br>\n";

		
		if ( $oldid ) {
			print "<h1>Achtung, dieses Review betrifft eine alte Version dieses Artikels!</h1>\n";
		}

		print "<p><table border=1><tr><td bgcolor=#CCCCCC><font face=\"arial,helvetica\">\n";
		&print_explanation();
#print "XXX: $url<p>\n";
		&print_form($url);
		print "</table>\n";

		print "<p><b><font color=red>Obacht!</font> Dieses Programm gibt nur Anregungen nach den deutschen Wikipedia-Empfehlungen vom 22.04.2007. Bitte die Hinweise nicht unreflektiert übernehmen, wenn sich das automatisieren lassen würde, hätte ich einen <a href=\"http://de.wikipedia.org/wiki/Wikipedia:Bots\">Bot</a> draus gemacht ;) Der Inhalt ist immer wichtiger als die Formatierung!</b><p>\n";

		print br,"Problem-Quote f&uuml;r <a href=\"$url\">$search_lemma</a>: <b>$quotient</b> (nur bedingt aussagekräfig und vergleichbar, insbesondere weil dieser Dienst manchmal auch Falschmeldungen produziert!)", p;


		if ( $developer && $debug ) {
			foreach my $grades ( @problem_quotient_grades ) {
				my ( $from, $to, $grade ) = split(/-/, $grades );
				if ( $quotient >= $from && $quotient <= $to ) {
					$this_grade = $grade;	
				}
			}
			
			print br,"Grobe Schulnote zum Vergleich: <b>$this_grade</b>", p;

		}
		&create_review_summary_html( $review_letters, $language );
		#&create_review_summary_html( $review_letters, $language ) if ( !$developer);

		print "<br>Anzahl der Einzelnachweise: <b>$count_ref</b><p>\n";
		my $fillwords_quot;
		# avopid DIV 0
		if ( $count_fillwords ) {
			$fillwords_quot = int( $num_words / $count_fillwords );
		}
		else {
			$fillwords_quot =0;
		}
		print "Anzahl der potentiellen Füllwörter: $count_fillwords von $num_words Wörtern = 1 Füllwort pro $fillwords_quot Wörter im Artikel (Durchschnitt der Exzellenten: 1/147, mehr als 1/$fillwords_per_words geht nicht in die Problem-Quote ein)<p>\n";

	}
	elsif ( $language eq "en" ) {
		print h3("Auto-Review: <a href=\"$url\">$search_lemma</a> <font size=-1>[<a href=\"http://en.wikipedia.org/w/index.php?title=$lemma_org&action=edit\">edit in Wikipedia</a>] [<a href=\"$tool_path/$myname\">New review</a>]</font>"),br,"Level: <b>$review_level</b>", p;
		&print_explanation();
	}


	print p,hr,p;

	#print "TTT: $review_level<p>" if ( $developer );
	my $times = $review_letters =~ s/K/K/g;
	$times += $review_letters =~ s/L/L/g;
	if ( $language eq "de" &&  $propose_page  && $removed_links > 1 ) {

		print h3("Wiki-Quelltext mit entfernten Links zu Jahreszahlen und Tagen ($removed_links St&uuml;ck).")," (Am einfachsten kopieren durch \"reinklicken\", STRG-A & STRG-C, in Wikipedia einfügen mit STRG-A, STRG-V und dann mit \"Änderungen zeigen\" kontrollieren.)<br>\n";
		print "\n\n<textarea readonly name=\"page_without_links_to_years_and_dates\" rows=10 cols=80>$propose_page\n</textarea>\n";
	}

	if ( $extra_message ) {
		$extra_message =~ s/^/<li>/gm;
		if ( $language eq "de" ) {
			print hr, h3("Allgemeine Anmerkungen (weitere unten im Wiki-Quelltext):\n");
			print "<table border=1><tr><td><font face=arial,helvetica><b>Legende:</b><br>\n";
			print "Ist ".$never."sehr selten</span> sinnvoll<br>\n";
			print "Ist ".$seldom."selten</span> sinnvoll, bitte prüfen.<br>\n";
			print "Ist ".$sometimes."manchmal</span> sinnvoll, bitte prüfen.<br>\n";
			print $proposal."Vorschlag</span>, bitte prüfen ob sinnvoll.<br>\n";
			print "</table>\n";
			print p,"\n",ul($extra_message),p,hr,p;
		
		}
		elsif ( $language eq "en" ) {
			print hr, h3("General comments:");
			print "Is ".$never."never</span> reasonable  <br>\n";
			print "Is ".$seldom."seldom</span> reasonable, please check.<br>\n";
			print "Is ".$sometimes."sometimes</span> reasonable, please check.<br>\n";
			print p,ul($extra_message),p,hr,p;
		}
		else {
		}
	}

	print hr;

	# order is important here!!!
	# to preserve &nbsp; in browser-view, do only 3-5 to avoid doing &lt; and &gt; which this script abuses
	$page =~ s/&([a-zA-Z]{3,5};)/&amp;$1/g;
	# to preserve &#x2011; in browser-view
	$page =~ s/&(#x?\d{1,5};)/&amp;$1/g;
	# to preserve trailing spaces in browser-view
	$page =~ s/^ /&nbsp;/gm;

	print h3("Wiki-Quelltext mit Anmerkungen:");
	print "<font face=courier>\n\n$page\n\n</font>\n";
	print hr;

	if ( $language eq "de" ) {
		print "<h3><a name=\"explanations\">Erläuterungen:</a></h3>\n";
		print "<a name=\"links_to_numbers\">LTN = Links to numbers: Jahre und Jahrestage sollten im Allgemeinen nicht verlinkt werden, da es sehr selten jemandem hilft, auf das Jahr XY zu klicken (Ausnahme u.a. Geburts- und Sterbedaten in Personenartikeln), siehe <a href=\"http://de.wikipedia.org/wiki/WP:VL#Daten_verlinken\">WP:VL#Daten_verlinken<\/a> Das Verlinken von Monaten, Jahrzehnten und Jahrhunderten ist auch nur in Ausnahmef&auml;llen sinnvoll. Dazu gibt es auch ein <a href=\"http://de.wikipedia.org/wiki/Wikipedia:Browser-Unterst%C3%BCtzung#Bookmarklet_zum_Entlinken_von_Jahreszahlen\">Bookmarklet</a><p>\n";
		print "<a name=\"plenk\">Plenk = Leerzeichen vor Satzzeichen, siehe <a href=\"http://de.wikipedia.org/wiki/Plenk\">Plenk<\/a><p>\n";
		print "<a name=\"klemp\">Klempen = Kein Leerzeichen nach Satzzeichen (oder fehlendes Leerzeichen nach Abkürzung ?), siehe <a href=\"http://de.wikipedia.org/wiki/Klempen\">Klempen<\/a><p>\n";
		print "<a name=\"link_in_section_title\">LiST = Zwischenüberschriften sollten keine Wikilinks sein oder enthalten. In der Regel lässt sich derselbe Link genauso gut in den ersten Sätzen des folgenden Abschnitts setzen. Eine Ausnahme sind listenartige Artikel, bei denen die Überschriften nur der Gruppierung von Einzelpunkten dienen. Siehe auch <a href=\"http://de.wikipedia.org/wiki/Wikipedia:Wie_schreibe_ich_gute_Artikel#.C3.9Cberschriften_und_Abs.C3.A4tze\">WP:WSIGA</a> und <a href=\"http://de.wikipedia.org/wiki/WP:VL#.C3.9Cberschriften\">WP:VL#Überschriften</a>. Achtung, wenn der Link sinnvoll zum Textverständnis sein kann, bitte nicht einfach entfernen sondern in den Text übernehmen.<p>\n";
		print "<a name=\"colon_minus_section\">CMS = : - ! ?  in Überschrift, siehe <a href=\"http://de.wikipedia.org/wiki/Wikipedia:Wie_schreibe_ich_gute_Artikel#.C3.9Cberschriften_und_Abs.C3.A4tze\">Wikipedia:Wie schreibe ich gute Artikel#Überschriften und Absätze</a><p>\n";
		print "<a name=\"DL\">DL = Doppelter Link hintereinander, für den Leser ist die Grenze nicht ersichtlich, siehe <a href=\"http://de.wikipedia.org/wiki/WP:VL#Verlinkung_von_Teilw.C3.B6rtern\">Wikipedia:Verlinken#Verlinkung von Teilwörtern</a><p>\n";
		print "<a name=\"EM\">EM = Ausrufezeichen vermeiden<p>\n";
		print "<a name=\"WORDS\">WORDS = Wörter, die man vermeiden sollte. Dies sind beispielsweise Wörter, die den <a href=\"http://de.wikipedia.org/wiki/WP:NPOV\">neutralen Standpunkt</a> verletzen, <a href=\"http://de.wikipedia.org/wiki/Wikipedia:Schreibweise_von_Zahlen#Zahlen_null_bis_zw.C3.B6lf_als_Flie.C3.9Ftext\">Zahlen über zwölf</a> (mit Ausnahmen!), relative Zeitangaben, die bald nicht mehr stimmen (z.B. \"derzeit\") und Anglizismen. Siehe <a href=\"http://meta.wikimedia.org/wiki/W%C3%B6rter%2C_die_nicht_in_Wikipedia_stehen_sollten\">Wörter, die nicht in Wikipedia stehen sollten</a>. (<a href=\"$tool_path/$myname?action=show_avoid_words_de\">Liste der zu vermeidenden Wörter</a> die hervorgehoben werden.)<p>\n";
		print "<a name=\"FILLWORD\">Maybe fillword = Potentielle Füllwörter, die man <b>manchmal</b> ersatzlos streichen kann. Bitte den Satz oder Absatz vorher komplett lesen, ob dass Wort nicht doch sinnvoll ist oder das Verständnis erleichtert. Ein gewisse Menge an Füllwörtern ist normal. Siehe <a href=\"http://de.wikipedia.org/wiki/Wikipedia:Wie_schreibe_ich_gute_Artikel#Wortwahl\">Wikipedia:Wie schreibe ich gute Artikel#Wortwahl</a>. (<a href=\"$tool_path/$myname?action=show_fill_words_de\">Liste der Füllwörter</a> die hervorgehoben werden.)<p>\n";
		print "<a name=\"BOLD\">BOLD = Fettschrift ist zu vermeiden. Nur am Artikelanfang wird das Lemma eines Artikels noch einmal fett geschrieben, sowie Synonyme (für den dann auch Redirects angelegt sein sollten). Fremdwörter bitte nicht fett sondern kursiv schreiben (<a href=\"http://de.wikipedia.org/wiki/Wikipedia:Fremdwortformatierung\">WP:Fremdwortformatierung</a>). Manchmal ist Fettschrift noch sinnvoll in Formeln und bei Tabellenüberschriften. Siehe auch <a href=\"http://de.wikipedia.org/wiki/Wikipedia:Wie_gute_Artikel_aussehen#Sonstiges\">WP:WGAA#Sonstiges</a> und <a href=\"http://de.wikipedia.org/wiki/Wikipedia:Typografie#Auszeichnung\">Wikipedia:Typografie#Auszeichnung</a><p>\n";
		print "<a name=\"BOLD-INSTEAD-OF-SECTION\">BOLD-INSTEAD-OF-SECTION = Hier wurde eventuell Fettschrift statt eines Wikipedia-Abschnitts mit ==XYZ== verwendet. Bitte prüfen, ob sich ein Abschnitt lohnt. Eventuell mehrere Pseudo-Abschnitte zusammenfassen.<p>\n";
		print "<a name=\"LC\">LC = Lowercase = Zeile oder Überschrift, die mit einem Kleinbuchstaben beginnt. Selten sinnvoll außer z.B. in Formeln.<p>\n";
		print "<a name=\"BKL\">BKL = Link zu einer Begriffserklärungsseite. Wikilinks sollten direkt zu der gewünschten Seite zeigen. Dies ist manchmal nicht immer möglich da manche Oberbegriffe in Wikipedia noch keinen Artikel haben, z.B. <a href=\"http://de.wikipedia.org/w/index.php?title=Disteln&oldid=30266650\">Disteln</a>. Siehe auch <a href=\"http://de.wikipedia.org/wiki/WP:VL#Gut_zielen\">WP:VL#Gut_zielen</a>.<p>\n";
		print "<a name=\"MAYBEBKL\">MAYBEBKL = Eventuell Link zu einer Begriffserklärungsseite, bitte prüfen. Wikilinks sollten direkt zu der gewünschten Seite zeigen. Dies ist manchmal nicht immer möglich da manche Oberbegriffe in Wikipedia noch keinen Artikel haben, z.B. <a href=\"http://de.wikipedia.org/w/index.php?title=Disteln&oldid=30266650\">Disteln</a>. Siehe auch <a href=\"http://de.wikipedia.org/wiki/WP:VL#Gut_zielen\">WP:VL#Gut_zielen</a>. (Der Grund, warum manche Links nicht sicher als BKLs identifiziert werden können, ist unterschiedliche Groß-/Kleinschreibung. Beispielsweise ist <a href=\"http://de.wikipedia.org/wiki/ZEUS\">ZEUS</a> eine BKL, würde es <a href=\"http://de.wikipedia.org/wiki/Zeus\">Zeus</a> nicht geben, würde eine Link zu \"Zeus\" zu \"ZEUS\" führen. Da dieser Dienst keine Liste aller Lemma hat, um das wissen zu können, werden diese Links als \"vielleicht BKL\" angezeigt.)<p>\n";
		
		print "<a name=\"ABBREVIATION\">ABBREVIATION = Abkürzungen vermeiden: Statt „z. B.“ kann man so auch „beispielsweise“ schreiben, statt „i. d. R.“ auch „meistens“ oder einfach nur „meist“. Das Wort „beziehungsweise“, abgekürzt „bzw.“, das aus der Kanzleisprache stammt, lässt sich meist besser durch „oder“ ersetzen. Falls tatsächlich ein Bezug auf zwei verschiedene Substantive vorliegt, kann man es manchmal vorteilhafter durch „und im anderen Fall“ oder schlicht durch „und“ ausdrücken siehe <a href=\"http://de.wikipedia.org/wiki/Wikipedia:Wie_schreibe_ich_gute_Artikel#Abk.C3.BCrzungen\">Wikipedia:Wie schreibe ich gute Artikel#Abkürzungen</a>. (<a href=\"$tool_path/$myname?action=show_abbr_de\">Liste der Abkürzungen</a> die hervorgehoben werden.)<p>\n";
		print "<a name=\"NBSP\">NBSP = Zwischen einer Zahl und einer Einheit sollte ein geschütztes Leerzeichen stehen. Dadurch wird ein automatischen Zeilenumbruch zwischen logisch zusammengehörenden Elementen verhindert. Siehe auch <a href=\"http://de.wikipedia.org/wiki/Wikipedia:Textgestaltung\">Wikipedia:Textgestaltung</a>.<p>\n";
		print "<a name=\"ISBN\">ISBN = Falsch formatierte ISBN, durch den Doppelpunkt wird kein Link erzeugt.<p>\n";
		print "<a name=\"TAG\">TAG = &lt;i&gt; oder &lt;b&gt; statt '' oder '''.<p>\n";
		print "<a name=\"TAG2\">TAG2 = Tags die außerhalb von Tabellen nicht verwendet werden sollten: &lt;br \/&gt;, &lt;s&gt;, &lt;u&gt;, &lt;small&gt;, &lt;big&gt;, &lt;div align=\"center\"&gt; oder &lt;div align=\"right\"&gt;. Siehe <a href=\"http://de.wikipedia.org/wiki/Wikipedia:Textgestaltung\">Wikipedia:Textgestaltung</a><p>\n";
		print "<a name=\"FROMTO\">FROMTO = Sollte so formatiert sein: \"von 1971 bis 1986\". Siehe <a href=\"http://de.wikipedia.org/wiki/Wikipedia:Datumskonventionen\">Wikipedia:Datumskonventionen</a><p>\n";
		print "<a name=\"DOTDOTDOT\">DOTDOTDOT =  „...“ (← drei Zeichen) statt „…“.<p>\n";
		print "<a name=\"SELFLINK\">SELFLINK =  Selbstlink ohne Sprung zu Kapitel (eventuell über Redirect)<p>\n";
		print "<a name=\"DOUBLEWORD\">DOUBLEWORD =  Wortdopplung ?<p>\n";
		print "<a name=\"BISSTRICH\">BISSTRICH = Bei Zeitangaben Bis-Strich verwenden, am einfachsten den folgenden per Kopieren und Einfügen: –. Obacht: in diversen Zeichensätzen sind die Unterschiede zwischen den einzelnen Strichen nicht erkennbar. Siehe auch <a href=\"http://de.wikipedia.org/wiki/Wikipedia:Typografie#Bis-Strich\">Wikipedia:Typografie#Bis-Strich</a> und <a href=\"http://de.wikipedia.org/wiki/Bis-Strich#Bis-Strich\">Bis-Strich</a>. <p>\n";
		print "<a name=\"TYPO\">TYPO = Häufige Tippfehler. Tippfehler, die im Wikicode mit &lt;!--sic--&gt; markiert sind, wurden absichtlich so zitiert, siehe auch <a href=\"http://de.wikipedia.org/wiki/Wikipedia:Zitate#Zitate_im_Flie.C3.9Ftext\">Wikipedia:Zitate#Zitate_im_Fließtext</a>. Artikel mit Schweizer Rechtschreibung am Anfang mit &lt;!--schweizbezogen--&gt; markieren, dann findet keine Prüfung statt.  Bei Falschmeldungen bitte auf meiner <a href=\"http://de.wikipedia.org/wiki/Benutzer_Diskussion:Arnomane\">Diskussionsseite</a> Bescheid sagen.<p>\n";
		print "<a name=\"APOSTROPH\">APOSTROPH = Eventuell falsches Apostroph, im Deutschen ' statt ’. Siehe auch <a href=\"http://de.wikipedia.org/wiki/Apostroph#Typografisch_korrekt\">Apostroph#Typografisch_korrekt</a> und <a href=\"http://de.wikipedia.org/wiki/Wikipedia:Typografie#Weitere_Zeichen\">Wikipedia:Typografie#Weitere_Zeichen</a><p>\n";
		print "<a name=\"GS\">GS = Bindestrich (-) statt Gedankenstrich (–). Siehe auch <a href=\"http://de.wikipedia.org/wiki/Wikipedia:Typografie#Gedankenstrich\">Wikipedia:Typografie#Gedankenstrich</a> und <a href=\"http://de.wikipedia.org/wiki/Halbgeviertstrich#Gedankenstrich\">Halbgeviertstrich#Gedankenstrich</a><p>\n";
		print "<a name=\"BRACKET\">BRACKET = Ungleiche Anzahl von Klammern<p>\n";
		print "<a name=\"BRACKET2\">BRACKET2 = Kein Leerzeichen vor einer öffnenden oder nach einer schließenden Klammer.<p>\n";
		print "<a name=\"QUOTATION\">QUOTATION = Einfache Anführungszeichen (\"...\") statt den typografisch korrekten („...“). Siehe auch <a href=\"http://de.wikipedia.org/wiki/Anf%C3%BChrungszeichen#Direkte_Eingabe_per_Tastatur\">Erzeugung von Anführungszeichen</a><p>\n";


	}
	else {
		print "<h3>Explanation:</h3>\n";
		#print "<a name=\"links_to_numbers\">LTN = Links to years and days should usually be avoided.<p>\n";
		print "<a name=\"plenk\">Plenk = blank placed before a punctuation character, see also <a href=\"http://en.wikipedia.org/Plenk\">Plenk<\/a><p>\n";
		print "<a name=\"link_in_section_title\">LiST = Link in section title<p>\n";
		print "<a name=\"colon_minus_section\">CMS = ! ? - : in section title<p>\n";
		print "<a name=\"DL\">DL = Double link, reader can't recognize the border between the two<p>\n";
		print "<a name=\"EM\">EM = Avoid exclamation marks<p>\n";
		print "<a name=\"WORDS\">WORDS = Words to avoid, see <a href=\"http://en.wikipedia.org/wiki/Wikipedia:Words_to_avoid\">WP: Words to avoid</a><p>\n";

	}

	# allow browsers to jump to anchors
	print "<p>&nbsp;<p>&nbsp;<p>&nbsp;<p>&nbsp;<p>&nbsp;<p>&nbsp;<p>&nbsp;<p>&nbsp;<p>&nbsp;<p>&nbsp;<p>&nbsp;<p>&nbsp;<p>&nbsp;<p>&nbsp;<p>&nbsp;<p>&nbsp;<p>&nbsp;<p>&nbsp;<p>&nbsp;<p>&nbsp;<p>&nbsp;<p>&nbsp;<p>&nbsp;<p>&nbsp;<p>&nbsp;<p>&nbsp;<p>&nbsp;<p>&nbsp;\n";

	$dauer = ( time -$start_ts );
	print "it took: $dauer seconds (incl download)<p>\n" if ( $developer );

}


sub show_textfile {
	my ( $file ) = @_;
	print "<pre>\n";
	system "/bin/cat ./$file";
	print "</pre>\n";
}
