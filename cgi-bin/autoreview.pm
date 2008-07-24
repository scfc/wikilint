#
#    Program: Lint for Wikipedia articles
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

@months = ("Januar", ,"Jänner", "Februar", "März", "April", "Mai", "Juni", "Juli", "August", "September", "Oktober", "November", "Dezember" );

1;

use utf8;

sub download_page {
	
	# create URL to download_from and call &http_download()
	# this sub get's called recusivly on wikipedia-#REDIRECTS[[]]
	my ( $url, $lemma, $language, $oldid, $ignore_error, $recursion_depth ) = @_;

	$recursion_depth++;

	if ( $url ) {
		$lemma = $url;
		$lemma =~ s/^http:\/\/\w\w.wikipedia.org\/w(iki)?\///;
	}
	elsif ( $lemma ) {
		$lemma =~ s/ /_/g;
	}
	else {
		die "neither url nor lemma<p>\n";;
	}

	if ( $lemma =~ s/index.php\?title=(.+?)&oldid=(\d+)/$1/ ) {
		$oldid = $2;
	}

	$downlemma = $lemma;
	$downlemma =~ s/ /_/g;

	# uri_escape can't be used because some characters are already escape ...
	#$downlemma = uri_escape($downlemma);
	# ... except &
	$downlemma =~ s/&amp;/%26/g;
	$downlemma =~ s/&/%26/g;
	$downlemma =~ s/’/%E2%80%99/g;


	$lemma_org = $lemma;
	$lemma =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;

	utf8::decode($lemma);

	$search_lemma = $lemma;
	$search_lemma =~ s/_/ /g;


	if ( $oldid =~ /^\d+$/ ) {
		$down_url= "http:\/\/$language.wikipedia.org\/w\/index.php?title=$downlemma&action=raw&oldid=$oldid";
	}
	else {
		$down_url= "http:\/\/$language.wikipedia.org\/w\/index.php?title=$downlemma&action=raw";
	}

	# some more security checks
	die if (length($language) != 2 );
	die "evil url" if ($down_url =~ /[ ;]/ || $down_url =~ /\.\./ );

	print "oldid: $oldid<p>\n" if ( $debug && $developer);
	print "URL: $url<p>\n" if ( $debug && $developer);
	print "Lemma: $lemma<p>\n" if ( $debug && $developer);
	print "search Lemma: $search_lemma<p>\n" if ( $debug && $developer);
	print "down-URL: $down_url<p>\n" if ( $debug && $developer);

	#$down_url =~ s/’/%E2%80%99/g;



	my ($page ) = &http_download($down_url, $ignore_error );

	# why [^'] ?
	#if ( $page =~ /#REDIRECT *\[\[([^']+?)\]\]/i && 
	if ( $page =~ /#REDIRECT *\[\[(.+?)\]\]/i && 
		# don't get infinite loop on 2 redirects which point to each other
		$recursion_depth < 3 ) 
	{
			$redir_to = $1;
			$redir_to =~ s/#.*//;
			$redir_to = uri_escape_utf8($redir_to);
print "IS REDIR: recursion_depth: $recursion_depth - $page - $redir_to <br>\n" if ( $developer && $debug ); 
			$page = &download_page( "", $redir_to, $language, $oldid, $ignore_error, $recursion_depth );
        }
	else {
#print "NO REDIR: recursion_depth: $recursion_depth - $page\n" if ( $developer ); 
	}

	($page );
}

sub http_download {

	my ( $down_url, $ignore_error ) = @_;

	# Create a user agent object
	my $ua = LWP::UserAgent->new;

	# no proxy, Arnomane
	# $ua->proxy(['http'], $proxy);
	# set timeout to 10 sec
	$ua->timeout(10);

	die "URL zu lang\n" if ( length( $down_url ) > 300 );

	$ua->agent('tools.wikimedia.de/~timl/cgi-bin/wikilint');

	# Create a request
	my $req = HTTP::Request->new(GET => $down_url);

	my $tries = 0;
	my $is_ok = 0;

	my $res;

	do {

		# Pass request to the user agent and get a response back
		$res = $ua->request($req);

		# Check the outcome of the response
		if ($res->is_success) {
			#print $res->content;
			$is_ok = 1;
		} else {
			print "Problem beim Runterladen der Seite \"$down_url\" von Wikipedia, bitte später nochmal probieren: ";
			$message =  $res->status_line;
			print '<b>'.$message.'</b><p>';
			print 'Problem downloading the page from Wikipedia, please try again later: ';
			$message =  $res->status_line;
			print '<b>'.$message.'</b><p>';

			if ( !$ignore_error ) {
				exit;
			}

			sleep $wait_between_http_retry;
		}
		$tries++;
	} until ( $tries > $http_retry || $is_ok );

	# i don't have a clue why i have to "decode" the utf8-page delivered from wikipedia but it doesn't
	# work otherwise
	my $page = $res->content ;
	utf8::decode($page) ;
	( $page );
}

sub find_random_page {
	
	my ( $language ) = @_;

	my ( $down_url);

	if ( $language eq "de") {
		$down_url = "http://de.wikipedia.org/wiki/Spezial:Zuf%C3%A4llige_Seite";
	}
	elsif ( $language eq "en") {
		$down_url = "http://en.wikipedia.org/wiki/Special:Random";
	}
	else {
		die "only de or en randmon page so far\n";
	}

	# Create a user agent object
	my $ua = LWP::UserAgent->new(max_redirect => 0);
	# $ua->proxy(['http'], $proxy);
	$ua->agent('tools.wikimedia.de/~timl/cgi-bin/wikilint');
	# set timeout to 10 sec
	$ua->timeout(10);

	# Create a request
	my $req = HTTP::Request->new(GET => $down_url);

	# Pass request to the user agent and get a response back
	#my $res = $ua->request($req);
	my $res = $ua->simple_request($req);

	# Check the outcome of the response
	my $answer = $res->as_string;
	$answer=~/Location: (http:.+)/;
	$random_url=$1;

	( $random_url );

}

sub do_review {
	my ( $page, $language, $remove_century, $self_lemma, $do_typo_check ) = @_;

	my ( $times, $section_title, $last_section_level, $section_level, $count_words, $inside_weblinks, $count_weblinks, $inside_ref, $num_words, $count_ref, $count_see_also, $linkto, $inside_template, $new_page, $new_page_org, $words_in_section, $last_section_title, $dont_count_words_in_section_title, $removed_links, $last_replaced_num, $inside_ref_word, $inside_comment_word, $inside_comment, $inside_literatur, $count_fillwords, $open_ended_sentence, $schweizbezogen, $longest_sentence, $gallery_in_section, $year_article, $dont_look_for_klemp, $dont_look_for_apostroph );

	my ( $weblinks_section_level, $section_sources);
	my (  %count_linkto );
	local ($review_letters )="";
	local ($extra_message )="";
	local ($review_level )=0;
	local (%remove_stuff_for_typo_check_array );
	local ($global_removed_count )=0;

	$self_lemma_tmp = $self_lemma;
	$self_lemma_tmp =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;

	# if the lemma contains a klemp, ignore it in the article, e.g. [[Skulptur.Projekte]]
print "SELF_LEMMA: $self_lemma  - $self_lemma_tmp <br>\n" if ( $developer  && $debug );
	if ( $self_lemma_tmp =~ /[[:alpha:]][[:lower:]]{2,}[,.][[:alpha:]]{3,}/ ) {
		$dont_look_for_klemp = 1;
		$extra_message .= "<b>Klemp im Lemma</b>: Klemp-Suche deaktiviert.<br>\n";
	}

	# if the lemma contains a apostroph, ignore it in the article, e.g. [[Mi'kmaq]]
	my $bad_search_apostroph = qr/(?<!['´=\d])(['´][[:lower:]]+)/;
	if ( $self_lemma_tmp =~ /$bad_search_apostroph/ ) {
		$dont_look_for_apostroph = 1;
		$extra_message .= "<b>Apostroph in Lemma</b>: Apostroph-Suche deaktiviert.<br>\n";
	}

	if ( $page =~ /<!--\s*schweizbezogen\s*-->/i ) {
		$schweizbezogen = 1;
	}

	if ( $page =~ /{{Artikel Jahr.*?}}/ ||
		$page =~ /{{Kalender Jahrestage.*?}}/ 
	) {
		$year_article = 1;
		$extra_message .= "<b>Jahres- oder Tages-Artikel</b>: Links zu Jahren ignoriert.<br>\n";
	}

	# for later use ...
	my ( @units );
	my ( @units_tmp ) = split(/;/, $units{ $language });
	foreach my $unit ( @units_tmp ) {
		# not working to match on 20kg despite " ?" ???? (mabybe not \b anymore ???
		push @units, qr/((\d+?[,\.])?\d+? ?$unit)(\b|\Z)/;
		#push @units2, qr/((\d+?[,\.])?\d+?$unit)(\b|\Z)/;
	}

	# now special character-units like €, %
	my ( @units_tmp ) = split(/;/, $units_special{ $language });
	foreach my $unit ( @units_tmp ) {
		push @units, qr/((\d+?[,\.])?\d+? $unit)(\B|)/;
		#push @units, qr/((\d+?[,\.])?\d+?$unit)(\B|)/;
	}


	# store original lines for building "modified wikisource for cut&paste"
	my ( @lines_org_wiki ) = split(/\n/, $page);

	# remove <math>, <code>, <!-- -->, <poem> (any stuff to completetly ignore )
#print "seite0: <pre>$page</pre>" if ( $developer);
	( $page, $last_replaced_num ) = &remove_stuff_to_ignore( $page );

#print "seite1: <pre>$page</pre>" if ( $developer);


	# check for at least one image
	$nopic=0;

	if ( 
		$page !~ /\[\[(Image|Bild):/i && 
		$page !~ /<gallery>/i && 
		# pic in template
		$page !~ /\|(.+?)=.+?\.(jpg|png|gif|bmp|tiff|svg)\b/i
	) {
#print "PAGE: $page<p>\n" if ( $developer );
#|Wappen            = Wappen Hattersheim.jpg
#|Bild=Friedrich-Ebert-Anlage 2, Frankfurt.jpg
		$nopic =1;

	}
	else {
		# don't count wappen/heraldics or maps as pic
		if ( $1 =~ /(wappen|karte)/i ) {
			$nopic=1;
		}
	}


	if ( $nopic ) {
		$review_letters .="h";

		if ( $language eq "de" ) {

			my ( $en_lemma, $eng_message );
			$times = $page =~ /^\[\[en:(.+?)\]\]/m;
#print "XXXXXXXXXX $ page XXXXX<p>\n";
			if ( $times ) {
				$en_lemma = $1;
				print "ENG: $en_lemma<p>\n" if ( $developer && $debug );
				$eng_message ="(<a href=\"http://commons.wikimedia.org/wiki/Special:Search?search=$en_lemma&go=Seite\">$en_lemma</a>) ";
			}
			$extra_message .= "${proposal}Vorschlag<\/span> (der nur bei manchen Lemmas sinnvoll ist): Dieser Artikel enthält kein einziges Bild. Um zu schauen, ob es auf den Commons entsprechendes Material gibt, kann man einfach schauen, ob es in den anderssprachigen Versionen dieses Artikels ein Bild gibt oder selbst auf den Commons nach <a href=\"http://commons.wikimedia.org/wiki/Special:Search?search=$search_lemma&go=Seite\">$search_lemma</a> suchen (eventuell unter dem englischen Begriff $eng_message oder dem lateinischen bei Tieren & Pflanzen).\n"; 
		}
		else {
			$extra_message .= "Proposal: include link to wikimedia commons\n";
		}
		
	}

	# check for unformated weblinks in <ref></ref>
	&check_unformated_refs( $page );

	# remove <ref></ref>
	( $page, $last_replaced_num, $count_ref ) = &remove_refs_and_images( $page, $last_replaced_num );

#print "seite2: <pre>$page</pre>" if ( $developer);


	# avoid marking comments <!-- as evil exclamation mark
	$page =~ s/<!/&lt;&iexcl;/g; 

	# ! in wikilinks are ok
	do {
		$times = $page =~ s/(\[\[[^!\]]+)!([^\]]+?\]\])/$1&iexcl;$2/g;
	} until ( !$times );

	# NO TAGGING ABOVE THIS LINE !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
	# convert all original <tags>
	$page =~ s/</&lt;/g;
	$page =~ s/>/&gt;/g;

	##########################################################
	# find common TYPOS from list

	# do only if checked in form because it takes ages
	if ( $do_typo_check ) {
		if ( $schweizbezogen ) {
			$extra_message .= "<b>Hinweis</b>: Tippfehler-Prüfung entfällt weil schweizbezogener Artikel<br>\n";
		}
		else {
			# this is early because it takes long and now the page has less tagging from myself
			# list used from http://tools.wikimedia.de/~apper/sc/check.php?list=1
			# other list: http://de.wikipedia.org/wiki/Wikipedia:Liste_von_Tippfehlern
			# other list: http://de.wikipedia.org/wiki/Benutzer:BWBot

			# remove lines with <!--sic--> and {{Zitat...}}
			( $page ) = &remove_stuff_for_typo_check( $page );

			if ( $language eq "de" ) {
				foreach my $typo ( @is_typo ) {
					# this one (?<!-) to avoid strange words i german double-names like "meier-pabst"
					# typos saved as qr// !!!
					$times = $page =~ s/$typo/$seldom$1<\/span><sup class=reference><a href=#TYPO>[TYPO ?]<\/a><\/sup>/g;
					$review_level += $times * $seldom_level;
					$review_letters .="o" x $times;
					print "lemma: $self_lemma - TYPO: $typo \n" if ( $times && $developer && $debug );
				}
			}
			( $page ) = &restore_stuff_quote( $page );
		}
	}
	##########################################################


	print "search_lemma: $search_lemma<p>\n" if ( $developer && $debug > 10 );


	my $lola=0;

	my ( @lines ) = split(/\n/, $page);

#print "SSS: $page<p>\n" if ( $developer );



	# 1. too much wiki-links to same page
	# 2. http-links except <ref> or in ==weblinks==
	foreach my $line ( @lines ) {

#print "XX: $review_letters<br>\n" if ($developer);
		$line_org_wiki = shift ( @lines_org_wiki );
#print "DDD1: $line_org_wiki<br>\n" if ( $developer );
#print "DDD2: $line<br>\n" if ( $developer );

		my $line_org = $line;

		# normale " statt „“
		if ( $line !~ /^({\||\|)/ &&
			$line !~ /^{{/ &&
			$line !~ /style=/ 
		) {
			# remove all quotation marks in <TAGs>
			while ( $line =~ s/(<[^>]*?)"([^>]*?>)/$1QM-ERS$2/g ) {}
			while ( $line =~ s/(&lt;[^>&]*?)"([^>]*?&gt;)/$1QM-ERS$2/g ) {}
			while ( $line =~ s/="/=QM-ERS/g ) {}
			while ( $line =~ s/(\d)"/$1QM-ERS/g ) {}
			while ( $line =~ s/%"/%QM-ERS/g ) {}
			
			$times = $line =~ s/("([^";]{3,}?)")/$sometimes$1<\/span><sup class=reference><a href=#QUOTATION>[QUOTATION ?]<\/a><\/sup>/g;
			$review_level += $times * $sometimes_level;
			$review_letters .="u" x $times;

			# (?<!['\d\w]) to avoid '', ''' and GPS coordinates 4'5"
			# \w to avoid d'Agoult
			$times = $line =~ s/(?<!['\d\w])('([^';]{3,}?)')(?!')/$sometimes$1<\/span><sup class=reference><a href=#QUOTATION>[QUOTATION ?]<\/a><\/sup>/g;
			$review_level += $times * $sometimes_level;
			$review_letters .="u" x $times;

			$line =~ s/QM-ERS/"/g;
	#print "XX: $line\n" if ( $developer );
		}

		$last_section_level = $section_level;
		$last_section_title = $section_title;
		
		# section title
		if ( $line =~/^(={2,9})(.+?)={2,9}/ ) {
			$section_level = length($1);
			$section_title = $2;

			# just to be sure reset some things which normaly don't strech over section titles
			$inside_ref = 0;
			$inside_template=0;
			$inside_comment=0;
			$inside_comment_word=0;

			$dont_count_words_in_section_title = 1;

			if ( $words_in_section && 
				# avoid complaining on short "definition":
				$last_section_title &&
				!$gallery_in_section &&
				$words_in_section < $min_words_per_section && 
				$last_section_title !~ /weblink/i && 
				$last_section_title !~ /literatur/i &&
				$last_section_title !~ /quelle/i &&
				$last_section_title !~ /einzelnachweis/i &&
				$last_section_title !~ /siehe auch/i &&
				$last_section_title !~ /fußnote/i &&
				$last_section_title !~ /referenz/ 
			) {
				if ( $language eq "de" ) {
					$extra_message .= $sometimes."Kurzer Abschnitt: <a href=\"#$last_section_title\">==$last_section_title==</a> ($words_in_section Wörter)</span> Siehe <a href=\"http://de.wikipedia.org/wiki/WP:WSIGA#.C3.9Cberschriften_und_Abs.C3.A4tze\">WP:WSIGA#Überschriften_und_Absätze</a> und <a href=\"http://de.wikipedia.org/wiki/Wikipedia:Typografie#Grundregeln\">Wikipedia:Typografie#Grundregeln</a>.<br>\n";
				}
				else {
					$extra_message .= $sometimes."Very short section: ==$last_section_title== ($words_in_section words)</span><br>\n";
				}

				$review_level += $sometimes_level;
				$review_letters .="I";
			}

			$words_in_section = 0;
			$gallery_in_section = 0;

			# check if we're in section "weblinks" or in a subsection of it
			if (  $section_title =~ /weblink/i ||
				$section_title =~ /external link/i ) 
			{
				$inside_weblinks = 1;
				$inside_literatur = 0;
				$weblinks_section_level = $section_level;
			}
			elsif ( $inside_weblinks && $section_level > $weblinks_section_level ) {
				# keep status
			}
			else {
				$inside_weblinks = 0;
			}
			
			# check if we're in section "literatur" or in a subsection of it
			# beware of ==Heilquellen==
			if (	$section_title =~ /Quellen/ ||
				$section_title =~ /literatur/i )
			{
				$inside_literatur = 1;
				$literatur_section_level = $section_level;

				# only this case is still "inside_weblinks"
				# ==Weblinks==
				# ===Quellen===
				if ( !$inside_weblinks || $section_level <= $weblinks_section_level ) {
					$inside_weblinks = 0;
				}
			}
			elsif ( $inside_literatur && $section_level > $literatur_section_level ) {
				# keep status
			}
			else {
				$inside_literatur = 0;
			}

			# strip whitespace from begining and end
			$section_title =~ s/^\s+//;
			$section_title =~ s/\s+$//;

			# just to know later if there's a literature-section at all
			if ( $section_title =~ /(.*?Literatur.*?)/i || 
				$section_title =~ /(Quelle.*?)/  ||  
				$section_title =~ /(Referenzen.*?)/  ||  
				$section_title =~ /(Nachweise.*?)/  ||  
				$section_title =~ /(References.*?)/ ||
				$section_title =~ /(Source.*?)/ 
			) {
				$section_sources=$1;
			}
		}
		else {
			$dont_count_words_in_section_title = 0;
		}

#print "lit: $inside_literatur web: $inside_weblinks  com: $inside_comment tmp: $inside_template: $line <br>\n" if ( $developer );
		if ( 
			!$year_article &&
			!$inside_literatur &&
			!$inside_weblinks && 
			!$inside_comment &&
			!$inside_template &&
			$line !~ /\|/ &&
			$line !~ /ISBN/
		) { 
			# "von 1420 bis 1462" statt "von 12-13" (this has to be applied before LTN
			$times = $line =~ s/(von (\[\[)?\d{1,4}(\]\])?[–-—](\[\[)?\d{1,4}(\|\d\d)?(\]\])?)/$never$1<\/span><sup class=reference><a href=#FROMTO>[FROMTO ?]<\/a><\/sup>/g;
			$review_level += $times * $never_level;
			$review_letters .="l" x $times;

			# Verwendung des Bis-Strichs bei „Bis-Angaben“: 1974–1977 (nicht 1974-1977) usw.
			# beware, the different dashes aren't recognizable in terminal-fonts!
			my $line_tmp = $line;
			my $undo=0;
			my $times_total=0;
			do {
				# do 19080-1990 and [[1980]]-[[1990]]
				$times = $line =~ s/( |\[\[)(\d{1,4})((\]\]| )?\-( ||\[\[)?)(\d{1,4})(\]\])?( +v\. Chr\.)?/$1$sometimes$2$3$6<\/span><sup class=reference><a href=#BISSTRICH>[BISSTRICH ?]<\/a><\/sup>$7$8/;
				if ( $times ) {
					my $from=$2;
					my $to=$6;

					if ( $8 ) {
						# v. Chr. included, must be a date so leave as it is
						$times_total += $times;
#print "BISS: $times - $line <br>\n";
					}
					elsif ( 
						# 747-200 good
						( length( $from ) <= length($to)  && $from > $to ) ||
						# 1971-30 good
						( length( $from ) == 4 && length( $to ) == 2 && substr ($from,2,2) > $to )
					) {
#print "undo: $line ".substr ($from,2,2)." to: $to\n" if ($developer  );
						$undo = 1;
					}
					else {
						$times_total += $times;
#print "BISS2: $times - $line <br>\n";
					}
				}
			} until ( !$times );

			# undo if one substitution was wrong
			if ( $undo ) {
				$line = $line_tmp ;
			}
			else {
				$review_level += $times_total * $sometimes_level;
				$review_letters .="p" x $times_total;
			}
			
		}

		# check for bold text after some lines, should be only in the definition
		# links to dates are also OK in 1st line
		if ( $lola > 0 && $line ) {
			# bold everywhere is ok in english WP
			# and only german WP doesn't like links to years & dates
			if ( $language eq "de" ) {

				# ignore bold in comments, tables (which is quite useless anyway ;)
				if ( $line !~ /&lt;&iexcl;--.*?'''.*?--&gt;/ &&	
					$line !~ /&lt;div.+?'''.+?'''.*?&lt;\/div&gt;/i &&
					!$inside_template &&
					!$inside_comment &&
					# not in table
					$line !~ /^\|/ &&
					$line !~ /^{\|/ &&
					$line !~ /^\|}/ 
				) {
					# ignore '''BOLD''' in less than 4 character words, also in [[wikilinks]]
					# the strange character in front of STARTBOLD is some strange UTF8-character
					# i copied from a webpage to have something to exclude in [^￼]
					$times = $line =~ s/'''''(.+?)'''''/''￼STARTBOLD$1￼ENDBOLD''/g;
#print "111: $line<br>\n" if ( $times && $developer );
					$times = $line =~ s/'''''(.+?)'''/''￼STARTBOLD$1￼ENDBOLD/g;
#print "222: $line<br>\n" if ( $times && $developer );
					$times = $line =~ s/'''(.+?)'''/￼STARTBOLD$1￼ENDBOLD/g;
#print "333: $line<br>\n" if ( $times && $developer );
					
					# 1st see if somebody used bold-text to replace a section-title
					# '* for '''''bold+italic'''''
					if ( $line =~ /^'*￼STARTBOLD[^￼]+?￼ENDBOLD'*\s*(&lt;br( ?\/)?&gt;)?:?$/ ) {
						$times = $line =~ s/(￼STARTBOLD)([^￼]+?)(￼ENDBOLD)(:?)/$sometimes'''$2'''<\/span><sup class=reference><a href=#BOLD-INSTEAD-OF-SECTION>[BOLD-INSTEAD-OF-SECTION ?]<\/a><\/sup>$4/g;
						$review_level += $times * $sometimes_level;
						$review_letters .="e" x $times;
					}
					else {
						#$times = $line =~ s/(￼STARTBOLD'{0,2})([^￼]{3,})('{0,2}￼ENDBOLD)/$seldom'''$2'''<\/span><sup class=reference><a href=#BOLD>[BOLD]<\/a><\/sup>/g;
						# OK: '''[[Wasserstoff|H]]'''
						# regexp uses alternation for 3 cases: /('''[[Wasserstoff]]'''|'''[[Wasserstoff|H2O]]'''| '''Wasserstoff''')/
						# this part is for '''baum [[Wasserstoff|H]]''': [^￼\[\n]*?
						
						$times = $line =~ s/(￼STARTBOLD)(([^￼\[\n]*?\[\[[^￼\]\|]{4,}?\]\])[^￼\[\n]*?|([^￼\[\n]*?\[\[[^￼]+?\|[^￼\]]{4,}?\]\][^￼\[\n]*?)|([^￼\[]{4,}?))(￼ENDBOLD)/$seldom'''$2'''<\/span><sup class=reference><a href=#BOLD>[BOLD]<\/a><\/sup>/g;
						$review_level += $times * $seldom_level;
						$review_letters .="F" x $times;

					}
					$line =~ s/￼STARTBOLD(.+?)￼ENDBOLD/'''$1'''/g;

					# <big>, <small>, <s>, <u>, <br /> <div align="center">, <div align="right">
					$times = $line =~ s/(&lt;(br ?(\/)?|center|big|small|s|u|div align="?center"?|div align="?right"?)&gt;)/$seldom$1<\/span><sup class=reference><a href=#TAG2>[TAG2]<\/a><\/sup>/g;
					$review_level += $times * $seldom_level;
					$review_letters .="k" x $times;

					
				}

				if ( 	
					!$year_article &&
					$line !~ /GEBURTSDATUM/ && 
					$line !~ /DATUM/ && 
					$line !~ /STERBEDATUM/ 
				) {
					$line = &tag_dates_rest_line( $line );
					( $line_org_wiki, $times ) = &remove_year_and_date_links( $line_org_wiki , $remove_century);
					$removed_links += $times;
				}

			}
		}
		else {
			# here we might be in 1st line of article (except templates, comments, ... )

			# don't replace date-links in info-boxes 
			if ( $line !~ /^(\||\{\{|\{\|)/ &&
				!$year_article 
			) {
				# tag date-links
				$line = &tag_dates_first_line( $line );

				# remove date-links for copy/paste wikisource ( $line_org_wiki )
				$times = $line_org_wiki =~ s/(?<!(\w\]\]| \(\*|. †) )\[\[(\d{1,4}( v. Chr.)?)\]\]/$1$2/g;
				$removed_links += $times;

				# remove day- and month-links
				foreach my $month ( @months ) {
					$times = $line_org_wiki =~ s/(?<!(\*|†) )\[\[((\d{1,2}\. )?$month)\]\]/$1$2/g;
					$removed_links += $times;
				}
			}

		}
	
		if ( $line =~ /{{/ ||
			$line =~ /{\|/ 
		) {
			# might be nested tables so not 0/1 but ++/--
			$inside_template++;
#print "INSIDE_TEMPL: $line<br>\n" if ( $developer );
		}

		if ( $line =~ /^\s*&lt;&iexcl;--/ ||
			$line =~ /&lt;div/i
		) {
			$inside_comment=1;
		}


	#print "XXX:		inside_template: $inside_template  - inside_comment:  $inside_comment  <br>\n";
		# dont count short lines, textbox-lines, templates, ...
		if ( length( $line ) > 5 && 
			$line !~ /^{/ && 
			$line !~ /^--&gt;/ && 
			$line !~ /^[!\|]/ && 
			$line !~ /\|$/ && 
			$line !~ /^__/ && 
			!$inside_template && 
			!$inside_comment && 
			$line !~ /^\[\[Bild:/ && 
			$line !~ /^\[\[Image:/ &&
			$line !~ /^-R-I\d+-R--R-$/ &&
			$line !~ /^-R-R\d+-R-$/
		) {
			$lola++;
print "LOLA: #$line#<br>\n" if ($developer && $debug > 8 );
		}


		# PLENK & KLEMP

		if ( !$inside_ref &&
			!$inside_comment &&
			!$inside_template &&
			# only look for plenk & klemp if line conains , or .
			$line =~ /[,.]/
		) {

			# avoid complaining on dots in URLs by replacing . with PUNKTERSATZ
			do {
				$replaced = 0;
				$replaced += $line =~ s/(https?:\/\/.+?)(\.)/$1PUNKTERSATZ$4/gi;
				$replaced += $line =~ s/(Bild:[^\]]+?)(\.)/$1PUNKTERSATZ/gi;
				$replaced += $line =~ s/(Image:[^\]]+?)(\.)/$1PUNKTERSATZ/gi;
				$replaced += $line =~ s/({{.+?)(\.)/$1PUNKTERSATZ/gi;
				$replaced += $line =~ s/(https?:\/\/.+?)(\,)/$1KOMMAERSATZ/gi;
				$replaced += $line =~ s/({{.+?)(\.)/$1PUNKTERSATZ/gi;
			} until ( !$replaced );

			# avoid complaining on company names like "web.de" in the text
			# any 2 letter domain:
			$line =~ s/\.(\w\w\b)/PUNKTERSATZ$1/gi;
			$line =~ s/\.((com|org|net|biz|int|info|edu|gov)\b)/PUNKTERSATZ$1/gi;
			$line =~ s/([^\/]www)\.(\w)/$1PUNKTERSATZ$2/gi;
			$line =~ s/\.(html|doc|exe|htm|pdf)/PUNKTERSATZ$2/gi;

			# http://de.wikipedia.org/wiki/Plenk
			# do "baum .baum"
			my $line_copyy = $line;
			$times = $line_copyy =~ s/( [[:alpha:]]{2,}?)( [,.])([[:alpha:]]{1,}? )/$1$never$2<\/span><sup class=reference><a href=#plenk>[plenk ?]<\/a><\/sup>$3/g;
			if ( $times == 1 ) { 
				$line = $line_copyy;
				$review_level += $times * $never_level;
				$review_letters .="M" x $times;
			}

			# do "baum . baum"
			my $line_copyy = $line;
			$times = $line_copyy =~ s/( [[:alpha:]]{2,}?)( [,.]) ([[:alpha:]]{2,}? )/$1$never$2<\/span><sup class=reference><a href=#plenk>[plenk ?]<\/a><\/sup>$3/g;
			# if it happens more than once in one line, assume it's intetion
			if ( $times == 1 ) { 
				$line = $line_copyy;
				$review_level += $times * $never_level;
				$review_letters .="M" x $times;
			}

			# http://de.wikipedia.org/wiki/Klempen
			# use {2} to avoid hitting abbriviations i.d.r.
			# domains like www.yahoo.com are already dealt with above
			if ( !$dont_look_for_klemp ) {
				$times = $line =~ s/( [[:alpha:]][[:lower:]]{2,})([,.])([[:alpha:]][[:lower:]]{2,} )/$1$never$2<\/span><sup class=reference><a href=#klemp>[klemp ?]<\/a><\/sup>$3/g;
				$review_level += $times * $never_level;
				$review_letters .="c" x $times;
			}

			# do blub.blub.Blub
			$times = $line =~ s/([.,][[:alpha:]][[:lower:]]{2,})([,.])([[:upper:]][[:alpha:]]{2,}( |))/$1$never$2<\/span><sup class=reference><a href=#klemp>[klemp ?]<\/a><\/sup>$3$4/g;
			$review_level += $times * $never_level;
			$review_letters .="c" x $times;

			# do blub.Blub.blub
			$times = $line =~ s/([.,][A-ZÖÄÜ][[:lower:]]{2,})([,.])([[:alpha:]][[:lower:]]{2,}( |))/$1$never$2<\/span><sup class=reference><a href=#klemp>[klemp ?]<\/a><\/sup>$3$4/g;
			$review_level += $times * $never_level;
			$review_letters .="c" x $times;

			# change PUNKTERSATZ back
			$line =~ s/PUNKTERSATZ/./g;
			$line =~ s/KOMMAERSATZ/,/g;
		}

		# check for avoid_words and fill_words except in weblinks and literatur
		if (    
			$section_title !~ /weblink/i &&
			$section_title !~ /literatur/i &&
			!$inside_ref 
		) {

			# check for too long sentences. lot's of cases have to be considered which dots are sentence
			# endings or not. order is important in these checks!

			my $line_copy = $line;
			# remove HTML-comments <!--
			$line_copy =~ s/&lt;&iexcl;--.+?--&gt;//g;
			# remove <ref>...</ref>
			# remove <ref name=>...</ref>
			$line_copy =~ s/&lt;ref(&gt;| name=).+?&lt;\/ref&gt;//g;
			# remove <ref name="test">
			$line_copy =~ s/&lt;ref [^&]+?&gt;//g;


			# avoid using dot in "9. armee" as sentence-splitter
			# but this should be 2 sentences: "... in the year 1990. Next sentence"
			$line_copy =~ s/(\D\d{1,2})\./$1&#46;/g;

			# avoid using dot in "Monster Inc." as sentence-splitter
			$line_copy =~ s/\b(Inc|Ltd|usw|bzw|jährl|monatl|tägl|mtl|Chr)\./$1&#46;/g;

			# avoid using dot in "Burder (türk. Döner)"  as sentence-splitter
			$line_copy =~ s/( \(\w{2,10})\. ([^\)]{2,160}\) )/$1&#46; $2/g;

			# avoid using dot in "Burder türk.: Döner"  as sentence-splitter
			$line_copy =~ s/\.:/&#46;:/g;

			# 255.255.255.224
			$line_copy =~ s/(\d)\.(\d)/$1&#46;$2/g;

			# A.2
			$line_copy =~ s/(\w)\.(\d)/$1&#46;$2/g;

			# 2.A
			$line_copy =~ s/(\d)\.(\w)/$1&#46;$2/g;

			# avoid splitting on a..b
			$line_copy =~ s/\.\.\./&#46;&#46;&#46;/g;
			$line_copy =~ s/\.\./&#46;&#46;/g;

			# avoid splitting on Sigismund I. II. III. IV. VI.
			$line_copy =~ s/(\w X?V?I{1,3}X?V?)\./$1&#46;/g;

			# . followed by a small letter probably isn't a sentence end, rather abbreviation
			# ; for z.&nbsp;B.
			$line_copy =~ s/([\w;])\.( [[:lower:]])/$1&#46;$2/g;
			# avoid using dot in "z.B.", "z. B." or "z.&nbsp;B." as sentence-splitter but split on "zwei [[Banane]]n. Neue Satz"
			$line_copy =~ s/(\w\.( |&nbsp;)?\w)\./$1&#46;/g;
			# old versions:
			#$line_copy =~ s/([^\]\w]\w)\./$1&#46;/g;
			#$line_copy =~ s/(\b\w)\./$1&#46;/g;

			# do last dot of z.B. or i.d.R.
			$line_copy =~ s/(\.|&#46;)(\w)\./$1$2&#46;/;
			
			# avoid splitting on [[Henry W. Bessemer|H. Bessemer]]
			$line_copy =~ s/(\[\[[^\]]*?)\.([^\]]*?\]\])/$1&#46;$2/;
			$line_copy =~ s/(\[\[[^\]]*?)\.([^\]]*?\]\])/$1&#46;$2/;
			$line_copy =~ s/(\[\[[^\]]*?)\.([^\]]*?\]\])/$1&#46;$2/;

			# avoid splitting on www.yahoo.com or middle dot of z.B.
			$line_copy =~ s/(\w)\.(\w)/$1&#46;$2/g;

			# avoid splitting on my own question marks in [LTN ?]
			$line_copy =~ s/\?\]/FRAGERS]/g;

			# a sure sign of a sentence ending dot "mit der Nummer 22. Im Folgejahr"
			$line_copy =~ s/&#46;( {1,2})(Dies|Diese|Dieses|Der|Die|Das|Ein|Eine|Einem|Eines|Vor|Im|Er|Sie|Es|Doch|Aber|Doch|Allerdings|Da|Im|Am|Auf|Wegen|Für|Noch|Eben|Um|Auch|Sein|Seine|Seinem|So|Als|Man|Sogar)( {1,2})/.$1$2$3/g;
			# a sure sign of a non-sentence ending dot "mit der Nummer 22. im Folgejahr"
			$line_copy =~ s/\.( {1,2})(dies|diese|dieses|der|die|das|ein|eine|einem|eines|vor|im|er|sie|es|doch|aber|doch|allerdings|da|im|am|auf|wegen|für|noch|eben|um|auch|sein|seine|seinem|so|als|man|sogar)( {1,2})/&#46;$1$2$3/g;

			# next block is to avoid splitting in quotes

			# substitute quote-signs for better searching 
			# (''..'') has no defined start-end so hard to find the quote in ''quote''no-quote''quote''
			# the ￼ is some utf8 char randomly picked from the web
			$line_copy =~ s/\'\'([^']*?)\'\'/￼QSSINGLE%$1￼QESINGLE%/g;
			$line_copy =~ s/\"([^"]*?)\"/￼QSDOUBLE%$1￼QEDOUBLE%/g;
			$line_copy =~ s/&lt;i&gt;(.*?)&lt;\/i&gt;/￼QSTAG%$1￼QETAG%/gi;
			$line_copy =~ s/„([^“]*?)“/￼QSLOW%$1￼QELOW%/g;
			$line_copy =~ s/«([^»]*?)»/￼QSFF%$1￼QEFF%/g;
			$line_copy =~ s/‚([^‘]*?)‘/￼QSLS%$1￼QELS%/g;
			$line_copy =~ s/&lt;sic&gt;(.*?)&lt;\/sic&gt;/￼QSSIC%$1￼QESIC%/gi;


			# avoid splitting on dot in {{Zitat|Dies ist Satz eins. Dies ist Satz zwei. Dies ist.}}
			do {
				$times = $line_copy =~ s/({{Zitat(-\w\w)?\|[^\}]*?)\.([^\}]*?}})/$1&#46;$2/;
			} until ( !$times );
			do {
				$times = $line_copy =~ s/({{Zitat(-\w\w)?\|[^\}]*?):([^\}]*?}})/$1DPLPERS$2/;
			} until ( !$times );
			do {
				$times = $line_copy =~ s/({{Zitat(-\w\w)?\|[^\}]*?)!([^\}]*?}})/$1EXCLERS$2/;
			} until ( !$times );
			do {
				$times = $line_copy =~ s/({{Zitat(-\w\w)?\|[^\}]*?)\?([^\}]*?}})/$1FRAGERS$2/;
			} until ( !$times );
			do {
				$times = $line_copy =~ s/({{Zitat(-\w\w)?\|[^\}]*?);([^\}]*?}})/$1SEMIERS$2/;
			} until ( !$times );

			####### QUOTESTART...
			do {
				$times = $line_copy =~ s/(￼QS[^￼]*?)\.([^￼]*?￼QE)/$1&#46;$2/;
			} until ( !$times );
			do {
				$times = $line_copy =~ s/(￼QS[^￼]*?):([^￼]*?￼QE)/$1DPLPERS$2/;
			} until ( !$times );
			do {
				$times = $line_copy =~ s/(￼QS[^￼]*?)!([^￼]*?￼QE)/$1EXCLERS$2/;
			} until ( !$times );
			do {
				$times = $line_copy =~ s/(￼QS[^￼]*?)\?([^￼]*?￼QE)/$1FRAGERS$2/;
			} until ( !$times );
			do {
				$times = $line_copy =~ s/(￼QS[^￼]*?);([^￼]*?￼QE)/$1SEMIERS$2/;
			} until ( !$times );

			$line_copy =~ s/￼QSSINGLE%(.*?)￼QESINGLE%/''$1''/g;
			$line_copy =~ s/￼QSDOUBLE%(.*?)￼QEDOUBLE%/\"$1\"/g;
			$line_copy =~ s/￼QSTAG%(.*?)￼QETAG%/&lt;i&gt;$1&lt\/i&gt;/gi;
			$line_copy =~ s/￼QSLOW%(.*?)￼QELOW%/„$1“/g;
			$line_copy =~ s/￼QSFF%(.*?)￼QEFF%/«$1»/g;
			$line_copy =~ s/￼QSLS%(.*?)￼QELS%/‚$1‘/g;
			$line_copy =~ s/￼QSSIC(.*?)￼QESIC%/&lt;sic&gt;$1&lt;\/sic&gt;/gi;

################################################################ no mangling $line_copy below here
			# to avoid splitting on the ; of &gt;
			$line_copy =~ s/(&.{2,6});/$1SEMIERS/g;
			
			# to avoid splitting on "dieser Satz (türk.: sütz) ist zuende"
			do {
				$times = $line_copy =~ s/(\([^\)]{0,80}?):([^\)]{0,160}?\))/$1DPLPERS$2/;
			} until ( !$times );

			# don't split on [[:tr:Yıldırım Orduları]] 
			do {
				$times = $line_copy =~ s/(\[\[[^\]]{0,80}?):([^\]]{0,160}?\]\])/$1DPLPERS$2/;
			} until ( !$times );
			
if ( $debug > 8 && $developer ) {
my $line_copy_tmp = $line_copy;
$line_copy_tmp =~ s/&/&amp;/g;
print "TOSPLIT: $line_copy_tmp<p>\n" 
}

			my ( @sentences ) = split(/[\:.!\?;]/, $line_copy );

			foreach my $sentence ( @sentences ) {

				# put dots back in, see above
				$sentence =~ s/&#46;/\./g;
				$sentence =~ s/SEMIERS/;/g;
				$sentence =~ s/DPLPERS/:/g;
				$sentence =~ s/EXCLERS/!/g;
				$sentence =~ s/FRAGERS/?/g;
				my $sentence_tmp = $sentence;

				# to count as only one word: [[Religious conversion|converts]],
				$sentence_tmp =~ s/\[\[[^\]\|]+?\|//g;
				# remove my own tags to avoid counting them as words
				$sentence_tmp =~ s/<.+?>//g;
print "SENTENCE TO COUNT: $dont_count_words_in_section_title: $sentence_tmp<br>\n" if ( $developer && $debug > 9 );

				if ( !$dont_count_words_in_section_title ) {

					my ( @words ) = split(/ +/, $sentence_tmp);
					my $count_words=0;
					foreach my $word ( @words ) {
						if ( length($word) > 2 &&
							# don't count special HTML-character e.g. &nbsp;
							$word !~ /^&.+;$/ 
						) {
							$count_words++
						}
					}

					# to find too short sections, see above
					$words_in_section += $count_words;

					if ( $sentence_tmp =~ /-R-I-G/i ) {
						$gallery_in_section = 1;
					}

					$sentence_tmp =~ s/\'\'\'/BLDERS/g;

					# avoid considering ''short italic'' as complete quote-sentence
					$sentence_tmp =~ s/\'\'([^\']{0,$short_quote_length})\'\'/SHORTQUOTEERSATZ$1SHORTQUOTEERSATZ/g;
					$sentence_tmp =~ s/&lt;i&gt;([^\']{0,$short_quote_length})&lt;\/i&gt;/SHORTIERSATZ$1SHORTIERSATZ/g;
					$sentence_tmp =~ s/"([^"]{0,$short_quote_length})"/SHORTGANSERSATZ$1SHORTGANSERSATZ/g;

					# don't complain on loooong sentences with mainly quotes
					if ( $count_words > $max_words_per_sentence && 
						$sentence_tmp !~ /\'\'.{$short_quote_length,}?\'\'/  &&
						# this is because some people do ''quote.'' where the '' gets splitted off
						$sentence_tmp !~ /\'\'.{$short_quote_length,}?$/  &&
						# (?<!<) to avoid also ignoring sentences with <a name=\"HTML tags\">
						$sentence_tmp !~ /(?<!<)\"[^ ]{$short_quote_length,}?\"(?!>)/ &&
						$sentence_tmp !~ /(?<!<)\".{$short_quote_length,}?$/ &&
						$sentence_tmp !~ /&lt;i&gt;.{$short_quote_length,}?&lt;\/i&gt;/ &&
						# this is because some people do <i>quote.</i> where the </i> gets splitted off
						$sentence_tmp !~ /&lt;i&gt;.{$short_quote_length,}?$/ &&
						$sentence_tmp !~ /{{Zitat(-\w\w)?\|.{$short_quote_length,}?}}/ &&
						$sentence_tmp !~ /{{Zitat(-\w\w)?\|[^}]{$short_quote_length,}?$/ &&
						$sentence_tmp !~ /„.{$short_quote_length,}?“/ &&
						$sentence_tmp !~ /„.{$short_quote_length,}?$/ &&
						$sentence_tmp !~ /«.{$short_quote_length,}?»/ &&
						$sentence_tmp !~ /«.{$short_quote_length,}?$/
					) {
						$review_level += $never_level;
						$review_letters .="A";

						if ( $count_words > $longest_sentence ) {
							$longest_sentence = $count_words;
						}

						print "LONG SENTENCE: $count_words<br>\n" if ( $developer && $debug >8 );

						# restore removed HTML-comments and the like:
						$sentence_tmp_restored = &restore_stuff_to_ignore( $sentence, "substitue_tags" );

						# remove <ref> in beginning of sentence because of no relevance
						$sentence_tmp_restored =~ s/^\s*&lt;ref(&gt;| name=[^&]+?&gt;)[^&]+?&lt;\/ref&gt;//i;

						if ( $language eq "de" ) {
							$extra_message .= $sometimes."Langer Satz (eventuell als Zitat markieren ?) ($count_words Wörter)</span> Siehe <a href=\"http://de.wikipedia.org/wiki/WP:WSIGA#Schreibe_in_ganzen_S.C3.A4tzen\">WP:WSIGA#Schreibe_in_ganzen_Sätzen</a>: <i>$sentence_tmp_restored.</i><br>\n";

						}
						else {
							$extra_message .= $sometimes."Very long sentence ($count_words words)</span>: $sentence_tmp_restored. See <a href=\"http://en.wikipedia.org/wiki/Wikipedia:Avoid_trite_expressions#Use_short_sentences_and_lists\">here</a><br>\n";
						}
					}
				}
			}

			# substitute quote-signs for better searching 
			# (''..'') has no defined start-end so hard to find the quote in ''quote''no-quote''quote''
			# the ￼ is some utf8 char randomly picked from the web
			$line =~ s/'''''([^']*?)'''''/'''￼QSSA%$1￼QESA%'''/g;
			# do '''''bold&italic''' end bold'' end italic (yes, i've seen it ;)
			$line =~ s/'''''([^']+?'''[^']+?)(?<!')''(?!')/'''￼QSSB%$1￼QESB%/g;
#print "XXX: $line <br>\n" if ($developer );
			$line =~ s/(?<!')''([^']*?)''(?!')/￼QSSC%$1￼QESC%/g;
			$line =~ s/\"([^"]*?)\"/￼QSD%$1￼QED%/g;
			$line =~ s/&lt;i&gt;(.*?)&lt;\/i&gt;/￼QST%$1￼QET%/gi;
			$line =~ s/„([^“]*?)“/￼QSL%$1￼QEL%/g;
			$line =~ s/«([^»]*?)»/￼QSF%$1￼QEF%/g;
			$line =~ s/‚([^‘]*?)‘/￼QSX%$1￼QEX%/g;
			$line =~ s/&lt;sic&gt;(.*?)&lt;\/sic&gt;/￼QSC%$1￼QEC%/gi;
#print "XXX: $line <br>\n" if ($developer );

			# avoid ! always except in tables (=beginning of a line, . matches anything except newline) and in <ref> and in quotes
			if ( $inside_comment ||
				$inside_template ||
				( $last_section_title =~ /literatur/i && $line =~ /^\s?\*/ ) ||
				$line =~ /￼QSS.*?!.*?￼QES/i ||
				$line =~ /￼QSL.*?!.*?￼QEL/i ||
				$line =~ /￼QSD.*?!.*?￼QED/i ||
				$line =~ /￼QST.*?!.*?￼QET/i ||
				$line =~ /￼QSF.*?!.*?￼QEF/i ||
				$line =~ /￼QSX.*?!.*?￼QEX/i ||
				$line =~ /￼QSC.*?!.*?￼QEC/i ||
				$line =~ /(?<!')''[^']*?![^']*?$/i ||
				$line =~ /^:/ ||
				# avoid grammar-articles
				$line =~ /imperativ/i 
			) {
	#print "EMMM: $line <br> inside_comment: $inside_comment - inside_template: $inside_template <br>\n" if ( $developer);
				# do nothing
			}
			elsif ( $line !~ /&lt;ref&gt;.+?!.+?&lt;\/ref&gt;/i && 
				$line !~ /&lt;&iexcl;--.+?!.+?&gt;/ &&
				$line !~ /!\]\]/ &&
				# avoid tagging lists of boo/movie titles
				$line !~ /^\*/ &&
				$line !~ /!!/ 
			) {
				
				do { 
					# avoid ! in wikilinks and HTML-tags, $! and 26! (fakultät) and chess e2e4!
					$times = $line =~ s/([^\[<\$]+?[^\d\[<\$])!([^\]&>]*?$)/$1$seldom!<\/span><sup class=reference><a href=#EM>[EM1]<\/a><\/sup>$2/g;
	#print "EM: $line <br>\n" if ( $developer );
					$review_level += $times * $seldom_level;
					$review_letters .="G" x $times ;
				} until ( !$times );
			}
			else {
				# match ! before <ref> and after </ref>
				$times = $line =~ s/(.[^\[<]*?)!([^\]&>]*?&lt;ref&gt;)/$1$seldom!<\/span><sup class=reference><a href=#EM>[EM2]<\/a><\/sup>$2/g;
				$review_level += $times * $seldom_level;
				$review_letters .="G" x $times;
				$times = $line =~ s/(&lt;\/ref&gt;.[^\[<]*?)!([^\]&>]*?)/$1$seldom!<\/span><sup class=reference><a href=#EM>[EM3]<\/a><\/sup>$2/g;
				$review_level += $times * $seldom_level;
				$review_letters .="G" x $times;
	#print "EM2: -$line-<p>\n";
			}

			foreach my $avoid_word ( @avoid_words ) {
				# check if that word is used in <ref> or in quote(buggy because doesn't show same word outside <ref> in same line)
				# or in {{Zitat ...}}

				# performance-thing: don't make all the following checks if there's no avoid_word anyway
				if ( $line =~ /$avoid_word/i) {
#print "AVOID: $avoid_word - BEG: $line :END<br>\n" if ( $developer );
					if ( 
						# dont complain in tables
						$line !~ /^(!|\|)/ &&
						# dont complain in quotes
						$line !~ /￼QSS.*?$avoid_word.*?￼QES/i &&
						$line !~ /￼QSL.*?$avoid_word.*?￼QEL/i &&
						$line !~ /￼QSD.*?$avoid_word.*?￼QED/i &&
						$line !~ /￼QST.*?$avoid_word.*?￼QET/i &&
						$line !~ /￼QSF.*?$avoid_word.*?￼QEF/i &&
						$line !~ /￼QSX.*?$avoid_word.*?￼QEX/i &&
						$line !~ /￼QSC.*?$avoid_word.*?￼QEC/i &&
						# wikilinks
						$line !~ /[\[\|[^\[\]].*?$avoid_word[^\[\]]*?[\]\|]/i && 
						# templates
						$line !~ /{{[\w\-]+\|[^}]*?$avoid_word[^}]*?}}/i
					) {
						$times = $line =~ s/$avoid_word/$sometimes$1<\/span><sup class=reference><a href=#WORDS>[WORDS ?]<\/a><\/sup>/gi;
						$review_level += $times * $sometimes_level;
						$review_letters .="B" x $times;
#print "AVOID: $avoid_word - BEG: $line :END<br>\n" if ( $developer );

					}
				}
			}

#print "FFF: $page\n" if ( $developer );

			# fill words
			foreach my $fill_word ( @fill_words ) {
				# performance-thing: don't make all the following checks if there's no fill_word anyway
				if ( $line =~ /$fill_word/) {
					# check if that word is used in quote ("..")
					if ( 
						$line !~ /￼QSS.*?$fill_word.*?￼QES/ &&
						$line !~ /￼QSL.*?$fill_word.*?￼QEL/ &&
						$line !~ /￼QSD.*?$fill_word.*?￼QED/ &&
						$line !~ /￼QST.*?$fill_word.*?￼QET/ &&
						$line !~ /￼QSF.*?$fill_word.*?￼QEF/ &&
						$line !~ /￼QSX.*?$fill_word.*?￼QEX/ &&
						$line !~ /￼QSC.*?$fill_word.*?￼QEC/ &&
						# templates
						$line !~ /{{[\w\-]+\|[^}]*?$fill_word[^}]*?}}/ &&
						# wikilinks
						$line !~ /[\[\|[^\[\]].*?$fill_word[^\[\]]*?[\]\|]/ 
					) {
						# ignore "ein Hut (auch Mütze genannt)"
						if ( 
							(
								"auch" =~ /$fill_word/ && 
								( 
									$line =~ /\(\s?auch/i ||
									$line =~ /siehe auch/i ||
									$line =~ /als auch/i ||
									$line =~ /aber auch/i
								)
							) || (
								"aber" =~ /$fill_word/ && 
								(
									$line =~ /aber auch/i
								)
							)
							
						) {
							# do nothing
						}
						else {
#print "FW: $line\n" if ( $developer );
							# fillwords are not /i because:
							# 1. in the beginning of a line they're mostly useful
							# 2. to avoid e.g. tagging "zum Wohl des Reiches" (wohl)
							$times = $line =~ s/$fill_word/$sometimes$1<\/span><sup class=reference><a href=#FILLWORD>[FILLWORD ?]<\/a><\/sup>/g;
							# this review_level counted sepratly because a certain amount of fillwords is ok
							#####$review_level += $times * $sometimes_level;

							$review_letters .="C" x $times;
							$count_fillwords += $times;
						}

					}
				}
			}

			# abbreviation
			foreach my $abbreviation ( @abbreviations ) {
				# performance-thing: don't make all the following checks if there's no abbreviation anyway
				if ( $line =~ /$abbreviation/i ) {
					# check if that word is used in <ref> (buggy because doesn't show same word outside <ref> in same line)
					if ( 
						$line !~ /￼QSS[^￼]*?$abbreviation[^￼]*?￼QES/i &&
						$line !~ /￼QSD[^￼]*?$abbreviation[^￼]*?￼QED/i &&
						$line !~ /￼QST[^￼]*?$abbreviation[^￼]*?￼QET/i &&
						$line !~ /￼QSL[^￼]*?$abbreviation[^￼]*?￼QEL/i &&
						$line !~ /￼QSF[^￼]*?$abbreviation[^￼]*?￼QEF/i &&
						$line !~ /￼QSX[^￼]*?$abbreviation[^￼]*?￼QEX/i &&
						$line !~ /￼QSC[^￼]*?$abbreviation[^￼]*?￼QEC/i &&
						$line !~ /{{[\w\-]+\|[^}]*?$abbreviation[^}]*?}}/i 
					) {
						$times = $line =~ s/$abbreviation/$sometimes$1<\/span><sup class=reference><a href=#ABBREVIATION>[ABBREVIATION]<\/a><\/sup>/gi;
						$review_level += $times * $sometimes_level;
						$review_letters .="D" x $times;


					}
				}
			}

			$line = &restore_quotes($line);

			# evil: [[Automobil|Auto]][[bahn]] 
			# ok: [[Bild:MIA index.jpg|thumb|Grafik der Startseite]][[Bild:CreativeCommond_logo_trademark.svg|right|120px|Logo der Creative Commons]]
			if ( $line !~ /\[\[Bild:/i &&
				$line !~ /\[\[Image:/i 
			) {
				# [[^\[\]] instead of . is neccesarry ! to avoid marking  all of "[[a]] blub [[s]][[u]]"
				$times = $line =~ s/(\[\[[^\[\]]+?\]\]\[\[[^\[\]]+?\]\])/$never$1<\/span><sup class=reference><a href=#DL>[DL]<\/a><\/sup>/g;
				$review_level += $times * $never_level;
				$review_letters .="E" x $times;


			}
		}
else {
if ( $debug > 10  && $developer ) {
my $line_copy_tmp = $line_copy;
$line_copy_tmp =~ s/&/&amp;/g;
print "NOT AT ALL TOSPLIT: $line_copy_tmp<p>\n" 
}
}

		# lower-case beginning of sentence
		# the blank in the searchstring is to avoid e.g. "bild:image.jpg" inside a <gallery>
		if ( !$open_ended_sentence ) {
			$times = $line =~ s/^([[:lower:]][[:lower:]]+? )/$seldom$1<\/span><sup class=reference><a href=#LC>[LC ?]<\/a><\/sup>/g;
print "LC: $line \n" if ( $developer && $debug > 8 );
			$review_level += $times * $seldom_level;
			$review_letters .="a" x $times;
		}

		# open ended if ends in , or eingerueckt
		if ( $line =~ /,(&lt;br \/&gt;)?$/ ||
			$line =~ /^:/ 
		) {
			$open_ended_sentence = 1;
		}
		elsif ( 
			# not poen ende if sentecene ends with .!? 
			$line =~ /[\.!\?](\s*)?(&lt;.+?&gt;)?$/ ||
			# ... or is REPLACED-stuff
			$line =~ /[\.!\?](\s*)?(-R-.+?-R-)?$/ ||
			# .. or is section-title 
			$line =~/^(={2,9})(.+?)={2,9}/ 
		) {

			# ... then next sentence must begin uppercase
			$open_ended_sentence = 0;
		}
		elsif ( $line =~ /;(\s*)?(&lt;.+?&gt;)?$/ ) {
			$open_ended_sentence = 1;
#print "XXX: $line <br>\n" if ( $developer && $debug );
		}
		# default to open end
		else {
			$open_ended_sentence = 1;
		}

		# small section title
		$times = $line =~ s/^(={2,9} ?\b?)([[:lower:]].+?)( ?={2,9})/$1$seldom$2<\/span><sup class=reference><a href=#LC>[LC ?]<\/a><\/sup>$3/g;
		$review_level += $times * $seldom_level;
		$review_letters .="b" x $times;

		if ( 
			$inside_weblinks && 
			!$inside_literatur && 
			$line =~ /https?:\/\//i 
		) {
			# just count, replace with same (for more than one weblink per line)
			my $times = $line =~ s/(https?:\/\/)/$1/gi;
			$count_weblinks += $times;
		}

		# check for link in ==see also== already linked to above
		if (
			$section_title =~ /(siehe auch|see also)/i &&
			$line !~ /\[\[\w\w:[^\]]+?\]\]/  &&
			$line !~ /\[\[Kategorie:[^\]]+?\]\]/i  &&
			$line !~ /\[\[category:[^\]]+?\]\]/i  &&
			$line =~ /\[\[(.+?)\]\]/ 
		) {

				my $wikilink = "";
			while ( $line =~ /\[\[(.+?)\]\]/g ) {
				$wikilink = $1;
				$count_see_also++;	

				# check if see-also-link previously used 
				my $see_also_link = $1;
				if ( $count_linkto{ lc($see_also_link) } ) {
					$review_level += $sometimes_level;
					$review_letters .="Z";

					if ( $language eq "de" ) {
						$extra_message .= $sometimes."Links in \"Siehe auch\", der vorher schon gesetzt wurde</span>: [[$see_also_link]] - Siehe <a href=\"http://de.wikipedia.org/wiki/Wikipedia:Assoziative_Verweise\">WP:ASV</a><br>\n";
					}
					else {
						$extra_message .= $sometimes."Link in \"see also\" which was used before:</span> [[$see_also_link]].<br>\n";
					}
				}
			}

		}
#print "111: $line<br>\n" if ( $developer );

		# check line word by word
		$line_org_tmp = $line_org;
		# ignore <ref name="Jahresrueckblick"/>
		$line_org_tmp =~ s/&lt;ref name=.+?\/&gt;//g;

		# do [[wiki link hurray]] -> [[wiki_link_hurray]] to keep them as one word
		my $replaced=0;
		do {
			$replaced = $line_org_tmp =~ s/(\[\[[^\]]+?) ([^\]]+?[|\]])/$1_$2/;
		} until ( !$replaced );

		my ( @words ) = split(/\s/, $line_org_tmp );

		my $words_in_this_line = 0;
		foreach my $word ( @words ) {
			$words_in_this_line++ if (length( $word ) > 3 );
		}

		my $inside_comment_word = 0;
		my $inside_ref_word=0;
		my $inside_qoute_word=0;

		foreach my $word ( @words ) {

			if ( 
				!$inside_weblinks &&
				!$inside_literatur &&
				!$inside_comment_word &&
				!$inside_comment 
			) {
				$num_words++;
			}


			# do [[wiki_link_hurray]] -> [[wiki_link_hurray]] to restore original version
			my $replaced=0;
			do {
				$replaced = $word =~ s/(\[\[[^\]]+?)_([^\]]+?[|\]])/$1 $2/;
			} until ( !$replaced );

			if ( $word =~ /&lt;ref(&gt;| name=)/i ){
				$inside_ref_word = 1;
				$count_ref++;
#print "REF: $word<br>\n" if ( $developer );
			}

			if ( $word =~ /&lt;&iexcl;--/ ){
				$inside_comment_word = 1;
			}

			if ( $word =~ /\[\[(.+?)[|\]]/ &&
				# don't remember why i wouldn't want to count links in 1st line, uncomment:
				#$lola > 1 &&
				!$inside_template &&
				!$inside_comment_word 
			) {
				# this is a wikilink
				$linkto_org = $1;
				$linkto = lc($linkto_org);
				$count_linkto{ $linkto }++;
				print "X:$linkto ---- $word<br>\n" if ( $debug > 8 && $developer );

			}
			elsif ( 
				$word =~ /\[{0,1}https{0,1}:\/\// && 
				$word !~ /&lt;&iexcl;--/ && 
				# avoid templates like {{SEP|http://plato.stanford.edu/entries/aristotle-ethics/index.html#7
				$word !~ /{{\w+?\|[^}]*https?:\/\// && 
				# next 3 for templates infoboxes, e.g. "| Website = http://www.stadt.de"
				$line_org !~ /(\[\[)?Webse?ite(\]\])?[\s\|=:]+?[\[h]/i &&
				$line_org !~ /(\[\[)?Webseite(\]\])? ?=/i &&
				$line_org !~ /(\[\[)?Weblink(\]\])? ?=/i &&
				!$inside_weblinks &&
				!$inside_literatur &&
				!$inside_ref_word  && 
				!$inside_comment_word  && 
				!$inside_comment  && 
				# avoid: http://www.db.de</ref>
				$word !~ /\[{0,1}https{0,1}:\/\/.+?&lt;\/ref&gt;/ 
			) {
					$extra_message .= $seldom."Weblink außerhalb von ==Weblinks== und &lt;ref&gt;:...&lt;\/ref&gt;:<\/span> $word (Siehe <a href=\"http://de.wikipedia.org/wiki/WP:WEB#Allgemeines\">Wikipedia:Weblinks</a>)<p>\n";
					$review_level += $never_level;
					$review_letters .="J";

print "JJJ: $word<br>\n$line_org<br>\n" if ( $developer && $debug > 8 );
			}

			# check for WP:BKL
			if ( $word =~ /\[\[(.+?)[|\]]/ ) {
		                 $linkto_org = $1;

				# 1st 100% case-sensitive match, bec of [[USA]] vs. [[Usa]]
				if ( $is_bkl{ "$linkto_org" } ) {
					print "BKL:$linkto_org ---- $word<br>\n" if ( $debug > 8 && $developer );

					# remove _ already otherwise links to WP with blank AND wrong casing don't work
					$linkto_tmp = $linkto_org;
					$linkto_tmp =~ s/_/ /g;
					$line =~ s/$linkto_org/$linkto_tmp/g;

					$times = $line =~ s/(\[\[)($linkto_tmp)([|\]])/$1$seldom<a href=\"http:\/\/de.wikipedia.org\/wiki\/Spezial:Suche?search=$2&go=Artikel\">$2<\/a><\/span><sup class=reference><a href=#BKL>[BKL]<\/a><\/sup>$3/gi;
					$review_level += $times * $seldom_level;
					$review_letters .="d" x $times;
					
					
				}
				# 2nd case-insensitive bec we just know there's [[Usa]] in the list, 
				# and [[usa]] in the article might also be evil
				# anyway, exlcude USA because that happens to often and is just false postive
				elsif ( $is_bkl_lc{ "$linkto" } && 
						lc($linkto) ne "usa" &&
						lc($linkto) ne "gen" &&
						lc($linkto) ne "gas" 
				) {
					print "BKL:$linkto ---- $word<br>\n" if ( $debug > 8 && $developer );

					# remove _ already otherwise links to WP with blank AND wrong casing don't work
					$linkto_tmp = $linkto;
					$linkto_tmp =~ s/_/ /g;
					$line =~ s/$linkto/$linkto_tmp/g;

					$times = $line =~ s/(\[\[)($linkto_tmp)(\||\]\])/$1$sometimes<a href=\"http:\/\/de.wikipedia.org\/wiki\/Spezial:Suche?search=$2&go=Artikel\">$2<\/a><\/span><sup class=reference><a href=#MAYBEBKL>[MAYBEBKL ?]<\/a><\/sup>$3/gi;
					$review_level += $times * $sometimes_level;
					$review_letters .="d" x $times;
					
					
				}
			}


			if ( $word =~ /(?<!')''(?!')\w/ ||
				$word =~ /„/ 
			){
				$inside_qoute_word++;
			}

			# find double words, only > 3 chars to avoid "die die"
			if ( $word eq $last_word && 
				!$inside_qoute_word &&
				length( $word ) > 3 &&
				$word =~ /^\w+$/ &&
				# avoid hitting those lists of latin "homo sapiens sapiens"
				$words_in_this_line > 4 &&
				# more latin avoiding (small 1st letter and ...um
				!($word =~ /^[a-z]/ && ( $word =~ /(um|us|i|a|ens)$/ ) && length( $word ) > 4 ) &&
				$word !~ /\-\d/ 
			) {
				# this regexp wont hit "tree.tree" but that's not wanted anyway
				$times = $line =~ s/($word $word)/$never$1<\/span><sup class=reference><a href=#DOUBLEWORD>[DOUBLEWORD ?]<\/a><\/sup>/i;
				$review_level += $times * $never_level;
				$review_letters .="n" x $times;
			}

			if ( $word =~ /(?<!')''(?!').?$/ ||
				$word =~ /“/ 
			){
				$inside_qoute_word = 0;
			}

			if ( $word =~ /--&gt;/ ){
				$inside_comment_word = 0;
			}

			if ( $word =~ /&lt;\/ref&gt;/ &&
				# avoid /ref><ref
				     $word !~ /&lt;\/ref&gt;&lt;ref/ 
			){
				$inside_ref_word = 0;
			}


			$last_word = $word;
		}

		if ( $line !~ /^\|/ &&
			!$inside_template &&
			length( $line ) > $min_length_for_nbsp 
		) {
			# use &nbsp; between 50 kg -> 50&nbsp;kg
			foreach my $unit ( @units ) {
				# [\.,] is for decimal-divider
				$times = $line =~ s/$unit/$sometimes$1<\/span><sup class=reference><a href=#NBSP>[NBSP]<\/a><\/sup>$3/g;
				$review_level += $times * $sometimes_level;
				$review_letters .="T" x $times;
#print "NBSP: $unit<p>\n" if ( $developer );
			}

			# good: [[Dr. phil.]]
			$times = $line =~ s/(?<!\[)(Dr\. )(\w)/$sometimes$1<\/span><sup class=reference><a href=#NBSP>[NBSP]<\/a><\/sup>$2/g;
			$review_level += $times * $sometimes_level;
			$review_letters .="T" x $times;
		}
		
		# Apostroph
		# don't complain on ' in wikilinks
		if ( 
			!$dont_look_for_apostroph &&
			# wikilink
			$line !~ /\[\[[^\]]*?$bad_search_apostroph[^\]]*?\]\]/o &&
			# dont complain on "Achsfolge Co'Co"
			$line !~ /Achs(formel|folge)/ 
		) {
			# avoid complaining on ''italic'' with (?<!')
			$times = $line =~ s/(\w+)?$bad_search_apostroph/$sometimes$1$2<\/span><sup class=reference><a href=#APOSTROPH>[APOSTROPH ?]<\/a><\/sup>/go;
			$review_level += $times * $sometimes_level /3;
			$review_letters .="s" x $times;
#print "APO: $line<br>\n\n" if ( $times && $developer );
		}

		# Gedankenstrich -----
		my $bad_search = qr/([[:alpha:]]+)( - )([[:alpha:]]+)/;
		if ( $line !~ /\[\[[^\]]*?$bad_search[^\]]*?\]\]/o &&
			$line !~ /^\|/ 
		) {
			$times = $line =~ s/$bad_search/$1$sometimes$2<\/span><sup class=reference><a href=#GS>[GS ?]<\/a><\/sup>$3/g;
			$review_level += $times * $sometimes_level;
			$review_letters .="t" x $times;
#print "GS: $line<br>\n\n" if ( $times && $developer );
		}

		# do(missing spaces(before brackts
		$times = $line =~ s/([[:alpha:]]{3,}?\()([[:alpha:]]{3,})/$seldom$1<\/span><sup class=reference><a href=#BRACKET2>[BRACKET2 ?]<\/a><\/sup>$2/g;
		$review_level += $times * $seldom_level;
		$review_letters .="v" x $times;
		# ... missing space after brackets 
		$times = $line =~ s/([[:alpha:]]{3,})(\)[[:alpha:]]{3,}?)/$1$seldom$2<\/span><sup class=reference><a href=#BRACKET2>[BRACKET2 ?]<\/a><\/sup>/g;
		$review_level += $times * $seldom_level;
		$review_letters .="v" x $times;

		$new_page .= "$line\n";
		$new_page_org .= "$line_org_wiki\n";

		if ( $line =~ /}}/ ||
			$line =~ /\|}/ 
		) {
			# "if" to avoid going below zero with wrong wikisource
			$inside_template-- if ( $inside_template);
		}
		if ( $line =~ /^--&gt;/ ||
		 $line =~ /--&gt;$/  ||
		 $line =~ /&lt;\/div&gt;/i
		) {
			$inside_comment=0;
		}
	}

	$page = $new_page;

	##############################################################

	#	no weblinks in section titles
	# ... except de.wikipedia to avoid tagging BKL-tag as weblink in section
	$times = $page =~ s/(={2,9}.*?)(http:\/\/(?!de\.wikipedia).+?)( .*?)(={2,9})/$1$never$2<\/span><sup class=reference><a href=#link_in_section_title>[LiST-Web]<\/a><\/sup>$3$4/g;
	$review_level += $times * $never_level;
	$review_letters .="N" x $times;

	# no wikilinks in section titles
	$times = $page =~ s/(={2,9}.*?)(\[\[.+?\]\])(.*?={2,9})/$1$never$2<\/span><sup class=reference><a href=#link_in_section_title>[LiST]<\/a><\/sup>$3$4/g;
	$review_level += $times * $never_level;
	$review_letters .="O" x $times;

	# 	no :!?  in section titles
	$times = $page =~ s/(={2,9}.*?)([:\?!])( .*?)(={2,9})/$1$sometimes$2<\/span><sup class=reference><a href=#colon_minus_section>[CMS]<\/a><\/sup>$3$4/g;
	$review_level += $times * $sometimes_level;
	$review_letters .="P" x $times;

	# no - except ==Haus- und Hofnarr==
	$times = $page =~ s/(={2,9}.*?)( - )(.*?)(={2,9})/$1$sometimes$2<\/span><sup class=reference><a href=#colon_minus_section>[CMS]<\/a><\/sup>$3$4/g;
	$review_level += $times * $sometimes_level;
	$review_letters .="P" x $times;

	# do ISBN: 3-540-42849-6
	$times = $page =~ s/(ISBN: \d[\d\- ]{11,15}\d)/$never$1<\/span><sup class=reference><a href=#ISBN>[ISBN]<\/a><\/sup>/g;
	$review_level += $times * $never_level;
	$review_letters .="i" x $times;


	# bracket errors on templates, e.g. {ISSN|0097-8507}}
	# expect template name to be not longer than 20 chars
	$times = $page =~ s/(?<!{)({[^{}]{1,20}?\|[^{}]+?}})/$seldom$1<\/span><sup class=reference><a href=#BRACKET>[BRACKET ?]<\/a><\/sup>/g;
	$review_level += $times * $seldom_level;
	$review_letters .="q" x $times;
	# {{ISSN|0097-8507}
	$times = $page =~ s/({{[^{}]{1,20}?\|[^{}]+?}(?!}))/$seldom$1<\/span><sup class=reference><a href=#BRACKET>[BRACKET ?]<\/a><\/sup>/g;
	$review_level += $times * $seldom_level;
	$review_letters .="q" x $times;

	# [Baum]]
	# expect wikilink to be not longer than 80 chars
	# GOOD: [[#a|[a]]
	# \D to avoid [1  + [3+4]]
	$times = $page =~ s/(?<![\[\|])(\[[^\[\]\d][^\[\]]{1,80}?\]\])/$seldom$1<\/span><sup class=reference><a href=#BRACKET>[BRACKET ?]<\/a><\/sup>/g;
	$review_level += $times * $seldom_level;
	$review_letters .="q" x $times;

	# [[Baum]
	# expect wikilink to be not longer than 80 chars
	$times = $page =~ s/(?<!\[)(\[\[[^\[\]]{1,80}?\](?!\]))/$seldom$1<\/span><sup class=reference><a href=#BRACKET>[BRACKET ?]<\/a><\/sup>/g;
	$review_level += $times * $seldom_level;
	$review_letters .="q" x $times;

	# [[[Baum]]
	# expect wikilink to be not longer than 80 chars
	$times = $page =~ s/(\[\[\[[^\[\]]{1,80}?\]\](?!\]))/$seldom$1<\/span><sup class=reference><a href=#BRACKET>[BRACKET ?]<\/a><\/sup>/g;
	$review_level += $times * $seldom_level;
	$review_letters .="q" x $times;

	# [[Baum]]]
	# expect wikilink to be not longer than 80 chars
	# good: [[Image:Baum.jpg [[Baum]]]]
	$times = $page =~ s/(\[\[[^\[\]]{1,80}?\]\]\](?!\]))/$seldom$1<\/span><sup class=reference><a href=#BRACKET>[BRACKET ?]<\/a><\/sup>/g;
	$review_level += $times * $seldom_level;
	$review_letters .="q" x $times;

	# <i> und <b> statt '' ''' 
	$times = $page =~ s/(&lt;[ib]&gt;)/$never$1<\/span><sup class=reference><a href=#TAG>[TAG]<\/a><\/sup>/g;
	$review_level += $times * $never_level;
	$review_letters .="j" x $times;

	# „...“ (← drei Zeichen) durch „…“ 
	$times = $page =~ s/(\.\.\.)/$sometimes$1<\/span><sup class=reference><a href=#DOTDOTDOT>[DOTDOTDOT]<\/a><\/sup>/g;
	$review_level += $times * $sometimes_level;
	$review_letters .="l" x $times;


	# do self-wikilinks
	$self_lemma =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;
        utf8::decode($self_lemma);
	print "Selflink: $self_lemma<p>\n" if ( $developer && $debug );
	my $self_linkle = "http://de.wikipedia.org/wiki/$self_lemma";
	$times = $page =~ s/(\[\[)$self_lemma(\]\]|\|.+?\]\])/$never$1<a href=\"$self_linkle\">$self_lemma<\/a><\/span><sup class=reference><a href=#SELFLINK>[SELFLINK]<\/a><\/sup>$2/g;
	$review_level += $times * $never_level;
	$review_letters .="m" x $times;

	#print "doing: /bin/grep -e \"\[\[$self_lemma\]\]\" $redir_file<p>\n" if ( $developer && $debug );
	my $redirs_list = "";
	open(GREP,"-|") || exec "/usr/bin/grep","\\\[\\\[$self_lemma\\\]\\\]", $redir_file;
	while (<GREP>) {
		$redirs_list .= "match: $_";
	}
	close GREP;

        utf8::decode($redirs_list);

	my ( @redirs ) = split(/\n/, $redirs_list );
	foreach my $redir ( @redirs ) {
		# [[∑]] → [[Sigma]]
		$redir =~ /\[\[(.+?)\]\]...\[\[(.+?)\]\]/;
		my $from = $1;
		my $to = $2;
		print "searchgin for redirects from: -$from- <p>\n" if ( $developer && $debug );
		#print "Redir: $redir - from: -$from- to: -$to- <p>\n" if ( $developer && $debug );

		my $self_linkle = "http://de.wikipedia.org/wiki/$from";
		# avoid regexp-grouping by () in $from (e.g. "A3 (Autobahn)" with \Q...\E
		$times = $page =~ s/(\[\[)\Q$from\E(\]\]|\|.+?\]\])/$never$1<a href=\"$self_linkle\">$from<\/a><\/span><sup class=reference><a href=#SELFLINK>[SELFLINK]<\/a><\/sup>$2/g;
		$review_level += $times * $never_level;
		$review_letters .="m" x $times;
	}



	print "number of words: $num_words<p>\n" if ( $developer && $debug > 3 );

	# one wikilink to one lemma per $max_words_per_wikilink words is ok (number made up by me ;)
	my $too_much_links = $num_words/$max_words_per_wikilink +1;
	foreach $linkto ( keys %count_linkto ) {
		if ( $count_linkto{ $linkto } > $too_much_links ) {
			$review_level += ( $count_linkto{ $linkto } - $too_much_links) /2;
			$review_letters .="Q";

			if ( $language eq "de" ) {
				$linkto_tmp = ucfirst( $linkto);
				$linkto_tmp_ahrefname = $linkto_tmp;
				$linkto_tmp_ahrefname =~ s/ /_/g;
				$extra_message .= "<a name=\"TML-$linkto_tmp_ahrefname\"></a>".$seldom."Zu viele Links zu [[$linkto_tmp]] (".$count_linkto{ $linkto }." Stück)</span>, siehe <a href=\"http://de.wikipedia.org/wiki/WP:VL#H.C3.A4ufigkeit_der_Verweise\">WP:VL#Häufigkeit_der_Verweise</a><br>\n";

				# TODO: links in tabellen nicht markieren (mitgezaehlt werden sie schon nicht)
				# this one (?<!\| ) to avoid tagging links in tables (which isn't perfect but perl doesn't to variable length look behind)
				$page =~ s/(?<!\| )(\[\[$linkto_tmp\b)/$seldom$1<\/span><sup class=reference><a href=#TML-$linkto_tmp_ahrefname>[TML:$count_linkto{ $linkto }x]<\/a><\/sup>/gi;
			}
			else {
				$extra_message .= $seldom."Too many links to [[$linkto]] (".$count_linkto{ $linkto }.")</span><br>\n";
			}
		}
	}

	# made up number by me: one references per $words_per_reference words or a litrature-chapter in an article < $words_per_reference words
	$count_ref = $count_ref || "0";
	print "count_ref:  $count_ref / num_words: $num_words < ( 1/  words_per_reference: $words_per_reference ) && ( section_sources: -$section_sources- - min_words_to_recommend_references:  $min_words_to_recommend_references<p>\n" if ( $developer && $debug > 3 );
	# count_ref: 0 / num_words: 3403 < ( 1/ words_per_reference: 500 ) && ( section_sources: 1 - min_words_to_recommend_references: 200

	# don't complain on ... 
		# 1. less than $min_words_to_recommend_references_section
	if ( $num_words < $min_words_to_recommend_references_section || 
		# 2. enough <ref>'s
		($count_ref / $num_words > 1/ $words_per_reference ) || 
		# 3. section "sources" and less than $min_words_to_recommend_references
		( $section_sources && $num_words < $min_words_to_recommend_references )
	) {
		# OK
	}
	else {
		# complain
		$review_level += $seldom_level;
		my $tmp_text;
		if ( $language eq "de" ) {
			if ( $section_sources ) {
				$tmp_text = ", aber Abschnitt <a href=\"#$section_sources\">==$section_sources==</a> " ;
				$review_letters .="H";
			}
			else {
				$review_letters .="R";
			}
			$extra_message .= $sometimes."Wenige Einzelnachweise</span> (Quellen: $count_ref / Wörter: $num_words $tmp_text) siehe <a href=\"http://de.wikipedia.org/wiki/Wikipedia:Quellenangaben\">WP:QA</a> und <a href=\"http://de.wikipedia.org/wiki/Wikipedia:Kriterien_f%C3%BCr_lesenswerte_Artikel\">WP:KrLA</a><br>\n";
		}
		else {
			$extra_message .= $sometimes."Very few references (References: $count_ref / Words: $num_words )</span><br>\n";
		}
	} 

	if ( $count_weblinks > $max_weblinks ) {
			$review_level += ( $count_weblinks - $max_weblinks );
			$review_letters .="S" x $count_weblinks;
			if ( $language eq "de" ) {
				$extra_message .= $sometimes."Mehr als $max_weblinks Weblinks ($count_weblinks Stück)</span>, siehe <a href=\"http://de.wikipedia.org/wiki/Wikipedia:Weblinks#Allgemeines\">WP:WEB#Allgemeines</a><br>\n";
			}
			else {
				$extra_message .= $sometimes."More than $max_weblinks weblinks</span> ($count_weblinks)<br>\n";
			}
		
	}

	if ( $count_see_also > $max_see_also ) {
			$review_level += ( $count_see_also - $max_see_also );
			$review_letters .="Y" x $count_see_also;

			if ( $language eq "de" ) {
				$extra_message .= $sometimes."Mehr als $max_see_also Links bei \"Siehe auch\" ($count_see_also Stück)</span>. Wichtige Begriffe sollten schon innerhalb des Artikels vorkommen und dort verlinkt werden. Bitte nicht einfach löschen sondern besser in den Artikel einarbeiten. Siehe <a href=\"http://de.wikipedia.org/wiki/Wikipedia:Assoziative_Verweise\">WP:ASV</a><br>\n";
			}
			else {
				$extra_message .= $sometimes."More than $max_see_also weblinks</span> ($count_weblinks)<br>\n";
			}
		
	}

	# check for {{Wiktionary|
	if ( $page !~ /\{\{wiktionary\|/i ) {
		$review_letters .="f";
		if ( $language eq "de" ) {

			$extra_message .= "${proposal}Vorschlag<\/span> (der nur bei manchen Lemmas sinnvoll ist): Dieser Artikel enthält keinen Link zum Wiktionary, siehe beispielsweise <a href=\"http://de.wikipedia.org/wiki/Kunst#Weblinks\">Kunst#Weblinks</a>. <a href=\"http://de.wiktionary.org/wiki/Spezial:Suche?search=$search_lemma&go=Seite\">Prüfen ob einen Wiktionaryeintrag zu $search_lemma gibt</a>.\n";
		}
		else {
		}
		
	}
	# check for {{commons
	if ( $page !~ /(\{\{commons(cat)?(\|)?)|({{commons}})/i ) {

			$review_letters .="g";

			if ( $language eq "de" ) {

				my ( $en_lemma, $eng_message );
				$times = $page =~ /^\[\[en:(.+?)\]\]/m;
#print "XXXXXXXXXX $ page XXXXX<p>\n";
				if ( $times ) {
					$en_lemma = $1;
					print "ENG: $en_lemma<p>\n" if ( $developer && $debug );
					$eng_message ="(<a href=\"http://commons.wikimedia.org/wiki/Special:Search?search=$en_lemma&go=Seite\">$en_lemma</a>) ";
				}
				$extra_message .= "${proposal}Vorschlag<\/span> (der nur bei manchen Lemmas sinnvoll ist): Dieser Artikel enthält keinen Link zu den Wikimedia Commons, bei manchen Artikeln ist dies informativ (z.B. Künstler, Pflanzen, Tiere und Orte), siehe beispielsweise <a href=\"http://de.wikipedia.org/wiki/Wespe#Weblinks\">Wespe#Weblinks</a>. Um zu schauen, ob es auf den Commons entsprechendes Material gibt, kann man einfach schauen, ob es in den anderssprachigen Versionen dieses Artikels einen Link gibt oder selbst auf den Commons nach <a href=\"http://commons.wikimedia.org/wiki/Special:Search?search=$search_lemma&go=Seite\">$search_lemma</a> suchen (eventuell unter dem englischen Begriff $eng_message oder dem lateinischen bei Tieren & Pflanzen). Siehe auch <a href=\"http://de.wikipedia.org/wiki/Wikipedia:Wikimedia_Commons#In_Artikeln_auf_Bildergalerien_hinweisen\">Wikimedia_Commons#In_Artikeln_auf_Bildergalerien_hinweisen</a>\n"; 
			}
			else {
				$extra_message .= "Proposal: include link to wikimedia commons\n";
			}
		
	}



	# always propose "whatredirectshere"
	$extra_message .= "${proposal}Vorschlag<\/span>: Weiterleitungen / #REDIRECTS zu [[$search_lemma]] <a href=\"http://tools.wikimedia.de/~tangotango/whatredirectshere.php?lang=$language&title=$search_lemma&subdom=$language&domain=.wikipedia.org\">prüfen</a> mit <a href=\"http://tools.wikimedia.de/~tangotango/whatredirectshere.php\">Whatredirectshere</a>\n";

	# TODO:
	# liste der einheiten
	# quotient 5 bei Martin Parry ???
	# http://de.wikipedia.org/wiki/Benutzer:Revvar/RT
	# http://rupp.de/cgi-bin/WP-autoreview.pl?l=de&lemma=Die%20Weltb%C3%BChne&do_typo_check=ON

	# review_letter sqrt()
	# BRACKET2 nicht in quotes
	# “Die Philosophie“
	# physik und bio schauen

	# bilder-check!
		# durch 8 teilbar gleich unbearbeitet
		# hochformat?
		# anzahl benutzender artikel
		# lizenz
		# kein exif = alt
		# kompressionsgrad

	# rupp.de: 
		#### bot status
		#### http://de.wikipedia.org/wiki/Benutzer_Diskussion:Spongo#Javascript-H.C3.BCpfing (srolling noch)
		# prettytable width

		# bsp: http://rupp.de/cgi-bin/WP-autoreview.pl?l=de&lemma=Deutsche_Milit%C3%A4rmission_im_Osmanischen_Reich
		# test.html auf WP
		# "setting", heute, ist offensichtlich avoidword


	
	# JS-gott suchen:
		# per klick zu richtigen stelle springen, und zurück 
			# TML, 
			# >5 weblinks
			# EM
			# LiST
			# WORD
			# FILLWO
			# ABBR
			# LC
			# plenk, klemp
			# CMS
			# unform weblink
			# weblink ausserhalb
			# kürzer abschnitt
			# langer satz
		# per checkbox ändern
			# LTN rein raus
			# BOLD-section title
			# NBSP
		# per dropdown 
			# BKL auswählen
			# BOLD -> italic, raus (oder hinspringen)
		# siehe auch - vorher wegmachen


	# KÜR:
	# http://meta.wikimedia.org/wiki/Alternative_parsers
	# [EM], [WORDS, [AVOID, [ABBR nach remove_stuff_for_typo_check
	# 25€ auseinander und nbsp dazwischen
	# §12 §§12 §12 ff. auseinander und nbsp dazwischen
	# aufzählungen nicht in lange sätze ? http://de.wikipedia.org/wiki/Systematik_der_Schlangen
	# "liste" und "systematik" anders behandeln??
	# auf "use strict" umstellen
	# zweite fettschrift anmekern: http://rupp.de/cgi-bin/WP-autoreview.pl?l=de&lemma=DBAG%20Baureihe%20226
	# Steht in Klammern der gesamte Text in einer bestimmten Auszeichnung, werden die Klammern identisch formatiert ''(und nicht anders!).'' Dasselbe gilt bei Satzzeichen. Stehen sie in oder direkt nach kursiv bzw. fett formatiertem Text, werden sie auch kursiv bzw. fett ausgezeichnet: Es ist ''heiß!''
	# &nbsp. in abkürzungen
	# leerzeichen vor <ref> böse, [[Hilfe:Einzelnachweise#Gebrauch von Leerzeichen]]
	# Überschriften wie Links, Webseiten, Websites etc. werden in Weblinks umbenannt, um ein einheitliches Erscheinungsbild aller Artikel zu erreichen.
	# vorschlag: georeferenzierung: {{Koordinate Artikel|50_05_41_N_08_39_40_E_type:landmark_region:DE-HE|50° 05' 41" N, 08° 39' 40" O}}
	# jede zeile <a name= </a>
	# config anzeigen
	# bookmarklet
	# auto BKL-downloader
	# maps.google.de URL -> WP, dann [[Grüneburgpark]] [[Philosophisch-Theologische Hochschule Sankt Georgen]]
	# § formatierung vorschlagen
	# fehlender {{Gesundheitshinweis}}, {{Rechtshinweis}}
	# falsche datumsformatierungen
	# konfigurierbar, max_words per sentence, ...
	# ganzen <ref>-code raus, wird nicht mehr gebraucht wegen &remove_refs()
	# http://tools.wikimedia.de/~tangotango/whatredirectshere.php?lang=en&title=Produzent&subdom=de&domain=.wikipedia.org
	# link-checker für weblinks
	# z.B. -> z.&nbsp;B.

	# featured articles in german wikipedia have 1 fillword per 146 words, so i consider 1/$fillwords_per_words ok on only raise the review-level above this.
	my $fillwords_ok = $num_words / $fillwords_per_words ;

	if ( $count_fillwords > $fillwords_ok ) {
		$review_level += ( $count_fillwords - $fillwords_ok ) /2 ;
		print "RRR: ".( $count_fillwords - $fillwords_ok ) /2 ."<br>\n" if ( $developer && $debug );
	}
	print "fillwords_ok: $fillwords_ok - fillwords_this_article: $count_fillwords - longest_sentence: $longest_sentence\n" if ( $developer && $debug );
	$review_letters .= "r" x $longest_sentence;

	if ( $developer && $debug > 7 ) {
		my ( @letters ) = split(//, $review_letters );
		my %count_letters;
		foreach my $letter ( @letters ) {
			$count_letters{ $letter }++;
		}
		foreach my $letter ( sort keys %count_letters ) {
			print "$letter - ".$count_letters{ $letter }."<br>\n";
		}
	}

	# round review_level
	my $review_level= int (( $review_level +0.5)*100)/100;
	# calculate quotient and round 
	my $quotient= int (( $review_level / $num_words *1000 +0.5)*100)/100;

	$quotient -= 0.5;

	print "quote: $quotient - review_level: $review_level / num_words:  $num_words<p>\n" if ( $debug >5  && $developer );

	# restore exclamation marks
	$page =~ s/&iexcl;/!/g; 

	$page = &restore_stuff_to_ignore( $page, "substitute_tags" );
	$new_page_org = &restore_stuff_to_ignore( $new_page_org );

	($page, $review_level, $num_words, $extra_message, $quotient, $review_letters, $new_page_org, $removed_links, $count_ref, $count_fillwords );

}

sub read_files {

	my ( $language) = @_;
	die "language missing\n" if ( !$language );

	if ( $language eq "de" ) {
		# words to avoid
		open(WORDS, "< ./avoid_words_de.txt") || die "cant open avoid_words_de.txt: $!\n";

		while(<WORDS>) {
			if (!/^#/) {
				chomp;
				# i don't have a clue why i have to "decode" the utf8-file but doesn't work otherwise
				utf8::decode($_);
				push @avoid_words, qr/(\b$_\b)/;
			}
		}
		close(WORDS);

		# fill-words
		# aber, auch, nun, dann, doch, wohl, allerdings, eigentlich, jeweils
		open(FILLWORDS, "< ./fill_words_de.txt") || die "cant open fill_words_de.txt\n";
		while(<FILLWORDS>) {
			if (!/^#/) {
				chomp;
				# i don't have a clue why i have to "decode" the utf8-file but doesn't work otherwise
				utf8::decode($_);
				push @fill_words, qr/(\b$_\b)/;
			}
		}
		close(FILLWORDS);

		# abbriviations
		open(ABBR, "< ./abbreviations_de.txt") || die "cant open abbreviations_de.txt\n";
		while(<ABBR>) {
			if (!/^#/ && length($_)> 1 ) {
				chomp;
				s/\./\\\./g;
				# i don't have a clue why i have to "decode" the utf8-file but doesn't work otherwise
				utf8::decode($_);
				push @abbreviations, qr/(\b$_)/;
			}
		}
		close(ABBR);

		# Begriffsklärungsseiten WP:BKL
		open(BKL, "< ./BKL_converted.txt") || die "cant open BKL_converted.txt\n";
		while(<BKL>) {
			if (!/^#/ && length($_)> 1 ) {
				chomp;
				$bkl = $_;
				# i don't have a clue why i have to "decode" the utf8-file but doesn't work otherwise
				utf8::decode($bkl);
				$is_bkl{ $bkl }++;
				$bkl = lc($bkl);
				$is_bkl_lc{ $bkl }++;
			}
		}
		close(BKL);

		# typos
		open(TYPO, "< ./typo.list.de.txt") || die "cant open typo.list.de.txt\n";
		while(<TYPO>) {
			if (!/^#/ && length($_)> 1 ) {
				chomp;
				$typo = $_;
				# i don't have a clue why i have to "decode" the utf8-file but doesn't work otherwise
				utf8::decode($typo);

				# it's far faster to search for /tree/ and /Tree/ than /tree/i so ...
				$typo = lc( $typo );

				# ignore case only in 1st letter to speed up search (that's factor 5* to complete /i !)
				$typo =~ s/^(.)/\(?i\)$1\(?-i\)/;
				push @is_typo, qr/(?<![-\*])\b($typo)\b/;
			}
		}
		close(TYPO);

	}
	elsif ( $language eq "en" ) {
		# words to avoid
		open(WORDS, "< ./avoid_words_en.txt") || die "cant open avoid_words_en.txt\n";

		while(<WORDS>) {
			if (!/^#/) {
				chomp;
				push @avoid_words, qr/\b$_\b/;
			}
		}
		close(WORDS);
	}
}

sub remove_year_and_date_links {
	my ( $line, $remove_century ) = @_;

	my ( $times, $count_removed );


	# [[1234]] or [[3 v. Chr.]]
	$times = $line =~ s/\[\[(\d{3,4}( v\. Chr\.)?)\]\]/$1/g;
	$count_removed += $times;
#print "XXX: $line<br>\n";

	# [[1234|34]]
	$times = $line =~ s/\[\[(\d{3,4}( v\. Chr\.)?\|)(\d\d)(\]\])/$3/g;
	$count_removed += $times;

	# links to days [[12. April]]
	foreach my $month ( @months ) {
		$times = $line =~ s/\[\[(\d{1,2}\. $month)\]\]/$1/g;
		$count_removed += $times;
	}

	if ( $remove_century ) {
		$times = $line =~ s/\[\[(\d{1,2}\. Jahrhundert( v\. Chr\.)?)\]\]/$1/g;
		$count_removed += $times;

		# links to months [[April]]
		foreach my $month ( @months ) {
			$times = $line =~ s/\[\[($month)\]\]/$1/g;
			$count_removed += $times;
		}

		# do [[1960er]] or [[1960er|60er]]
		$times = $line =~ s/\[\[(\d{1,4}er)(\|[^\]]*?)?]\]\]?/$1/g;
		$count_removed += $times;

		# do [[1960er Jahre]]
		$times = $line =~ s/\[\[(\d{1,4}er Jahre)[\]\|]\]?/$1/g;
		$count_removed += $times;
	}


	( $line, $count_removed );
}

sub tag_dates_first_line {
	# this sub is for 1st line only!
	my ( $line ) = @_;

	# this subroutine buggy, this works:
	#  Larry Wall (* [[27. September]] [[1954]] ; † [[30. April]] [[2145]] ) blub [[3. Mai]] blub [[1977]]
	# this doesn't work:
	#  Larry Wall (* [[27. September]] [[1954]] ; † [[30. April]] [[2145]] ) blub [[3. Mai]] [[1977]]

	# replace years except birth & death = "r]] [[1234]]" or "* [[1971]]" or " † [[2012]]"
	$times = $line =~ s/(?<!(\w\]\]| \(\*|. †|; \*) )(\[\[[1-9]\d{0,3}( v. Chr.)?\]\])/$seldom$2<\/span><sup class=reference><a href=#links_to_numbers>[LTN]<\/a><\/sup>/g;
	$review_level += $times * $seldom_level;
	$review_letters .="K" x $times;

	# [[1878|78]]
	$times = $line =~ s/(\[\[[1-9]\d{0,3}( v. Chr.)?\|)(\d\d)(\]\])/$seldom$3<\/span><sup class=reference><a href=#links_to_numbers>[LTN ?]<\/a><\/sup>/g;
	$review_level += $times * $seldom_level;
	$review_letters .="K" x $times;

	# replace days [[3. April]] except birth & death
	foreach my $month ( @months ) {
		$times = $line =~ s/(?<!(\*|†) )(\[\[(\d{1,2}\. )?$month\]\])/$seldom$2<\/span><sup class=reference><a href=#links_to_numbers>[LTN ?]<\/a><\/sup>/g;
		$review_level += $times * $seldom_level;
		$review_letters .="L" x $times;
	}

	( $line );
}

sub tag_dates_rest_line {
#print "OOOOOOOOOOO: $review_letters<br>\n" if ($developer);
	my ( $line ) = @_;
	################### links to dates
	# do [[2005]]
	$times = $line =~ s/(\[\[[1-9]\d{0,3}( v. Chr.)?\]\])/$seldom$1<\/span><sup class=reference><a href=#links_to_numbers>[LTN ?]<\/a><\/sup>/g;
	$review_level += $times * $seldom_level;
	$review_letters .="K" x $times;

	# [[1878|78]]
	$times = $line =~ s/(\[\[[1-9]\d{0,3}( v. Chr.)?\|)(\d\d)(\]\])/$seldom$1$2$3$4<\/span><sup class=reference><a href=#links_to_numbers>[LTN ?]<\/a><\/sup>/g;
	$review_level += $times * $seldom_level;
	$review_letters .="K" x $times;

	# do [[17. Jahrhundert]] or [[17. Jahrhundert|whatever]]
	$times = $line =~ s/(\[\[\d{1,2}\. Jahrhundert( v\. Chr\.)?[\]\|]\]?)/$sometimes$1<\/span><sup class=reference><a href=#links_to_numbers>[LTN ?]<\/a><\/sup>/g;
	$review_level += $times * $sometimes_level;
	$review_letters .="U" x $times;

	# do [[1960er]] or [[1960er|60er]]
	$times = $line =~ s/(\[\[\d{1,4}er[\]\|]\]?)/$sometimes$1<\/span><sup class=reference><a href=#links_to_numbers>[LTN ?]<\/a><\/sup>/g;
	$review_level += $times * $sometimes_level;
	$review_letters .="V" x $times;

	# do [[1960er Jahre]]
	$times = $line =~ s/(\[\[\d{1,4}er Jahre[\]\|]\]?)/$sometimes$1<\/span><sup class=reference><a href=#links_to_numbers>[LTN ?]<\/a><\/sup>/g;
	$review_level += $times * $sometimes_level;
	$review_letters .="V" x $times;


	# links to days
	foreach my $month ( @months ) {
		# do [[12. Mai]] or [[12. Mai|...]]
		$times = $line =~ s/(\[\[\d{1,2}\. $month[\]\|]\]?)/$seldom$1<\/span><sup class=reference><a href=#links_to_numbers>[LTN ?]<\/a><\/sup>/g;
		$review_level += $times * $seldom_level;
		$review_letters .="L" x $times;

		# do [[Mai]] or [[Mai|...]]
		$times = $line =~ s/(\[\[$month[\]\|]\]?)/$sometimes$1<\/span><sup class=reference><a href=#links_to_numbers>[LTN ?]<\/a><\/sup>/g;
		$review_level += $times * $sometimes_level;
		$review_letters .="W" x $times;
	}
	($line );
}
sub create_edit_link {
	my ( $lemma, $lang ) = @_;
	my ( $edit_link );
	if ( $lang eq "de" ) {
		$edit_link ="http://de.wikipedia.org/w/index.php?title=$lemma&action=edit";
	}
	($edit_link);
}

sub create_ar_link {
	my ( $lemma, $lang, $oldid, $do_typo_check ) = @_;

	my ( $oldid_tmp, $ar_link, $typo_tmp );

	if ( $oldid ) {
		$oldid_tmp = "&oldid=$oldid";
	}

	if ( $do_typo_check ) {
		$typo_tmp ="&do_typo_check=ON";
	}
		

	if ( $lang eq "de" ) {
		$ar_link ="http://toolserver.org/~timl/cgi-bin/$arname?l=de&lemma=$lemma$oldid_tmp$typo_tmp";
	}
	($ar_link);
}

sub create_perma_link {
	my ( $lemma, $lang, $oldid ) = @_;
	if ( $lang eq "de" ) {
		$perma_link ="http://de.wikipedia.org/w/index.php?title=$lemma&oldid=$oldid"
	}
	($perma_link);
}


sub remove_stuff_to_ignore {

	# inside <math>, <code> everything is allowed to remove before doing review and restore afterwards
	my ( $page ) = @_;

	undef %replaced_stuff;
# probleme mit sentence-split ? satzulaenge
	my $lola =0;
	my ( $times);

	# <MATH>
	while ( $times = $page =~ s/(<math>.*?<\/math>)/-R-R$lola-R-/si ) {
		$replaced_stuff{ $lola } = $1;
#print "REPLACED: <$1><p>\n" if ( $times && $developer );
		$lola++;
	}

	# <CODE>
	while ( $times = $page =~ s/(<code>.*?<\/code>)/-R-R$lola-R-/si ) {
		$replaced_stuff{ $lola } = $1;
		$lola++;
	}

	# <nowiki>
	while ( $times = $page =~ s/(<nowiki>.*?<\/nowiki>)/-R-R$lola-R-/si ) {
		$replaced_stuff{ $lola } = $1;
		$lola++;
	}

	# {{Lückenhaft } {{Quelle}}
	while ( $times = $page =~ s/({{(Lückenhaft|Quelle)[^}]*?}})/-R-R$lola-R-/si ) {
		$replaced_stuff{ $lola } = $1;
		$lola++;
	}

	# <POEM>
	while ( $times = $page =~ s/(<poem>.*?<\/poem>)/-R-R$lola-R-/si ) {
		$replaced_stuff{ $lola } = $1;
		$lola++;
	}

	# <blockquoe>
	while ( $times = $page =~ s/(<blockquote>.*?<\/blockquote>)/-R-R$lola-R-/si ) {
		$replaced_stuff{ $lola } = $1;
		$lola++;
	}

	# <!-- -->
	while ( $times = $page =~ s/(<!--.+?-->)/-R-R$lola-R-/si ) {
		$replaced_stuff{ $lola } = $1;

		# mark lines containing <!--sic--> for ignoring typos later
		if ( $1 =~ /<!--\s*sic\s*-->/i ) {
			$page =~ s/-R-R$lola-R-/-R-R-SIC$lola-R-/;
		}
		$lola++;
	}

	
	($page, $lola );
}

sub restore_stuff_to_ignore {
	my ( $page, $substitute_tags ) = @_;

	%replaced_stuff_tmp = %replaced_stuff;

	do {
		foreach my $lola ( keys %replaced_stuff_tmp ) {
			my $restore = $replaced_stuff_tmp{ $lola };
			# before restoring the text, replace the <>
			if ( $substitute_tags ) {
				$restore =~ s/</&lt;/g;
				$restore =~ s/>/&gt;/g;
			}
			my $times = $page =~ s/-R-R(-SIC|-G)?$lola-R-/$restore/;

			if ( !$times ) {
				delete( $replaced_stuff_tmp{ $lola });
	#print "NOT RESTORED: $restore<p>\n" if ( $developer );
			}
		}
	} until ( !%replaced_stuff_tmp );

	my ( $times2, $total )=0;
	$todo = keys %remove_stuff_for_typo_check_array;

	do {
		$times2 = $page =~ s/-R-I(-G)?(\d+)-R-.*?-R-/restore_one_item( $2, \%remove_refs_and_images_array, $substitute_tags)/ges;
		$total += $times2;
print "RESTORE REFS $1 $2 <br>\n" if ( $developer && $debug > 8 );
	} until ( !$times2 || $total == $todo );


	
	($page );
}

sub restore_stuff_quote {

	# restoring is a bit tricky because the removed stuff might be inside each other, e.g.
	# a removed comment inside a quote, so it has to be repeated until everything is restored
	my ( $page, $substitute_tags ) = @_;

	my ( $times2, $total )=0;
	$todo = keys remove_stuff_for_typo_check_array;

	do {
		#$times2 = $page =~ s/-R-N(\d+)-R-/$remove_stuff_for_typo_check_array{ $1 }/g;
		$times2 = $page =~ s/-R-N(\d+)-R-.*?-R-/restore_one_item( $1, \%remove_stuff_for_typo_check_array )/ges;
		$total += $times2;
#print "XXXXX<br>\n" if ( $developer );
	} until ( !$times2 || $total == $todo );

	$page =~ s/Q-REP/'/g;
	
	($page );
}

sub check_unformated_refs {
	
	my ( $page ) = @_;

	my ( @lines ) = split(/\n/, $page);

	foreach $line ( @lines ) {

		my ( @words ) = split(/\s/, $line );

		foreach my $word ( @words ) {

			if ( 
				$last_word !~ /^URL:/i &&
				$word !~ /{{\w+?\|[^}]*https?:\/\// && 
				$word !~ /url=/i &&
				# unformated weblink: http://rupp.de
				( $word =~ /(https{0,1}:\/\/.+)/ &&
				$word !~ /(\[https{0,1}:\/\/.+)/ ) ||
				# unformated weblink: [http://rupp.de]
				$word =~ /(\[https{0,1}:\/\/[^\s]+?\])/  
			) {
				my $weblink = $1;

				if ( $language eq "de" ) {
					$extra_message .= $seldom."Unformatierter Weblink: </span>$weblink - Siehe <a href=\"http://de.wikipedia.org/wiki/WP:WEB#Formatierung\">WP:WEB#Formatierung</a><br>\n";
				}
				else {
					#$extra_message .= $never."Link in \"see also\" which was used before:</span> [[$see_also_link]].<br>\n";
				}
				$review_level += $seldom_level;
				$review_letters .="X";
			}
			$last_word = $word;
		}
	}
}
sub remove_stuff_for_typo_check {
	# remove lines with <!--sic--> and {{templates...}} and quotes, web & wikilinks
	

	my ( $page ) = @_;

	undef %replaced_stuff_quote;

	my $ref_to_store_array = \%remove_stuff_for_typo_check_array;

	$lola =0;

	# remove complete_line with <!--sic--> marked earlier in remove_stuff()
	# uses /e execute sub remove_one_item() !
	$page =~ s/^(.*-R-R-SIC\d+-R-.*)$/remove_one_item( $1, "-R-N", \%remove_stuff_for_typo_check_array )/gemi;

	# any template like  {{Zitat }}
	$page =~ s/({{\w.{4,}?}})/remove_one_item( $1, "-R-N", \%remove_stuff_for_typo_check_array )/gesi;

	# quotes
	my ( @lines ) = split(/\n/, $page );
	my $page_new;

	foreach my $line_copy ( @lines ) {
		# only replace quotes with 3 or more letters
		# remove single ' to be able to use [^'] in next line
		$line_copy =~ s/(?<!')'(?!')/Q-REP/g;
		$times = $line_copy =~ s/((?<!')''([^']{3,}?)''(?!'))/remove_one_item( $1, "-R-N", \%remove_stuff_for_typo_check_array )/ge;
		$line_copy =~ s/Q-REP/'/g;

		# also does ''quote 'blub' quote on'' ??
#print "REPLACED QUOTE: $lola : <$1><p>\n" if ( $times && $developer && $debug > 8 );

		$line_copy =~ s/(\"([^"]{3,}?)\")/remove_one_item( $1, "-R-N", \%remove_stuff_for_typo_check_array )/ge;
		$line_copy =~ s/(&lt;i&gt;(.{3,}?)&lt;\/i&gt;)/remove_one_item( $1, "-R-N", \%remove_stuff_for_typo_check_array )/ge;
		$line_copy =~ s/(„([^“]{3,}?)“)/remove_one_item( $1, "-R-N", \%remove_stuff_for_typo_check_array )/ge;
		$line_copy =~ s/(«([^»]{3,}?)»)/remove_one_item( $1, "-R-N", \%remove_stuff_for_typo_check_array )/ge;
		$line_copy =~ s/(‚([^‘]{3,}?)‘)/remove_one_item( $1, "-R-N", \%remove_stuff_for_typo_check_array )/ge;
		$line_copy =~ s/(&lt;sic&gt;(.{3,}?)&lt;\/sic&gt;)/remove_one_item( $1, "-R-N", \%remove_stuff_for_typo_check_array )/gei;

		$page_new .= "$line_copy\n";
	}
	$page = $page_new;

	# any [[]] wikilink
	$page =~ s/(\[\[[^\]]{1,150}?\]\])/remove_one_item( $1, "-R-N", \%remove_stuff_for_typo_check_array )/ge;

	# any [] weblink
	$page =~ s/(\[http.+?\])/remove_one_item( $1, "-R-N", \%remove_stuff_for_typo_check_array )/ge;
#print "XXX:$page:XXX" if ( $developer );

	( $page, $lola );
}

sub remove_refs_and_images {
	my ( $page, $lola ) = @_;

	my ( $times);
	local ( $count_ref);
	local ( $global_removed_count ) = 0;

	# lines with leading blank
	# (?!\|) to avoid removing lines in table with leading blank like " | blub = blab"
	$page =~ s/^( (?!\|).+)$/remove_one_item( $1, "-R-I", \%remove_refs_and_images_array, "count_ref" )/gemi;

	# <ref></ref>
	# this one isn't perfect: [^<] because it prevent <ref> haha <- like this </ref> but still
	# better than expanding an open <ref name=cc> over the whole page
	$page =~ s/(<ref(>| +name ?= ?)[^<]+?<\/ref>)/remove_one_item( $1, "-R-I", \%remove_refs_and_images_array, "count_ref" )/gesi;

print "DDD: $page\n" if ( $developer && $debug > 9 );

	# the (...){0,8} is for links inside the picture description, like [[Image:bild.jpg|This is a [[tree]] genau]]
	# the ([^\]\[]*?) is for images with links in it
	$page =~ s/(\[\[(Image:|Bild:)([^\]\[]*?)([^\]]+?\[\[[^\]]+?\]\][^\]]+?){0,8}\]\])/remove_one_item( $1, "-R-I", \%remove_refs_and_images_array, "count_ref" )/gesi;

	# <gallery> ... </gallery>
	# <gallery widths="200" heights =..></gallery>
	$page =~ s/(<gallery.*?>.+?<\/gallery>)/remove_one_item( $1, "-R-I-G", \%remove_refs_and_images_array, "count_ref" )/gesi;

	( $page, $global_removed_count, $count_ref );
}

sub create_review_summary_html {

        my ( $review_letters, $language ) = @_;
        my ( $result );

	print "<h3>Zusammenfassung</h3><font face=\"arial,helvetica\"><table border=1 >\n";
	print "<tr><th>Prüfung<th>Ergebnis\n";


        my ( @letters ) = split(//, $review_letters );
        my %count_letters;
        foreach my $letter ( @letters ) {
                $count_letters{ $letter }++;
        }

        my ( @order_letters ) = split(//, $table_order );

        foreach my $letter ( @order_letters ) {
		my ( $level, $summary, $message ) = split(/\|/, $text{"$language|$letter"});

		# sonderlocke FILLWORDS
		if ( $letter eq "C" ) {
				#$result = "<td bgcolor=lime>OK\n";
			print "<tr><td bgcolor=\"".$farbe_html{$level}."\">$message<td>Siehe<br>unten\n";
		}
		else {
			print "<tr><td bgcolor=\"".$farbe_html{$level}."\">$message\n";
			if ( $count_letters{ $letter } && $level eq "0" ) {
				$result = "<td bgcolor=yellow>".$count_letters{ $letter }."\n";
			}
			elsif ( $count_letters{ $letter } ) {
				#$result = "<td bgcolor=red>".$count_letters{ $letter }."\n";
				$result = "<td>".$count_letters{ $letter }."\n";
			}
			else {
				$result = "<td bgcolor=lime>OK\n";
			}
			print "$result\n";
		}


        }

	print "</table>\n\n";

}



sub get_pic_parameters {

	# get picture-paramters for wikimedia/wikipedia-picture:
	# - resolution
	# - exif:date taken
	# - exif:camera brand
	# - exif:camera model
	# - date uploaded
	# - date taken
	# - size

	my ( $pic ) = @_;
	my ($width,  $heigth, $size,  $mimetype, $date_info, $date_upload, $exif_maker, $exif_model, $exif_datetimeoriginal );

	my $url = "http://de.wikipedia.org/w/index.php?title=Image:$pic";
	#$url = "http://de.wikipedia.org/w/index.php?title=Image%3AZooLeipzigTigerTeiga.jpg

	#print "url: $url\n";

	my $page = &http_download( $url );

	my ( @lines2 ) = split(/\n/, $page );
	my ( @lines );

	# this one's really stupid but otherwise "while ( $line = shift @lines )" stops at empty lines
	foreach my $line ( @lines2 ) {
		push @lines, "$line\n";
	}

	while ( my $line = shift @lines ) {
	# </ul><div class="fullImageLink" id="file"><a href="http://upload.wikimedia.org/wikipedia/de/b/b4/ZooLeipzigTigerTeiga.jpg"><img border="0" alt="Bild:ZooLeipzigTigerTeiga.jpg" src="http://upload.wikimedia.org/wikipedia/de/b/b4/ZooLeipzigTigerTeiga.jpg" width="610" height="392" /></a><br /><small>Keine höhere Auflösung vorhanden.</small><br /><a href="http://upload.wikimedia.org/wikipedia/de/b/b4/ZooLeipzigTigerTeiga.jpg">ZooLeipzigTigerTeiga.jpg</a> (610 × 392 Pixel, Dateigröße: 42 KB, MIME-Typ: image/jpeg)</div><p>Tiger Taiga im Zoo Leipzig</p>

		chop ( $line );
		#print "line: $line\n";

		if ( $line =~ /<div class="fullImageLink".+?\((\d+) × (\d+) Pixel, Dateigröße: (\d+) KB, MIME-Typ: (.+?)\)/ ) {
			$width = $1;
			$heigth = $2;
			$size = $3;
			$mimetype = $4;
		}
		elsif ( $line =~ /<tr class=exif-make>/i ) {
			$line = shift @lines;
			$line = shift @lines;
			$line =~ /<a href=.+?>(.+?)<\/a>/i;
			$exif_maker = $1;
			#print "exif_maker: $exif_maker\n";
		}
		elsif ( $line =~ /<tr class=exif-model>/i ) {
			$line = shift @lines;
			$line = shift @lines;
			$line =~ /<td>(.+)/i;
			$exif_model = $1;
			#print "exif_model: $exif_model - <$line>\n";
		}
		elsif ( $line =~ /<tr class=exif-datetimeoriginal>/i ) {
			$line = shift @lines;
			$line = shift @lines;
			$line =~ /<td>(.+)/i;
			$exif_datetimeoriginal = $1;
			#print "exif_datetimeoriginal: $exif_datetimeoriginal - <$line>\n";
			#</th><td> 19:30, 19. Mai 2007
		}

		# these two might be in one line:
		if ( $line =~ /{{Information.+?\|Date=(.+?)\|/ ) {
			$date_info = $1;
		}
		if ( $line =~ /\(Löschen\) \(Aktuell\) <a href=.+?>(.+?)<\/a>/ ) {
			$date_upload = $1;
		}

	}

	print "w: $width h: $heigth s: $size m: $mimetype d: $date_info du: $date_upload\n" if ( $developer );
	print "maker: $exif_maker model: $exif_model date: $exif_datetimeoriginal\n" if ( $developer );

	($width,  $heigth, $size,  $mimetype, $date_info, $date_upload, $exif_maker, $exif_model, $exif_datetimeoriginal );
}

sub selftest {
	# check if reviewing test.html gave the right results indicated be GOOD vs. BAD vs. EVIL (=bad in comments)
	my ( $page, $extra_messages ) = @_;
	my ( @lines ) = split(/\n/, $page);

	my ( %found_evil_messages );
	my ( %found_evil_text );

	my ( $br );
	if ( $online ) {
		$br = "<br>";
	}

	foreach my $line ( @lines ) {

		if ( $line =~ /-R-.+?\d+-R-/ ) {
			print "MISSED REPLACEMENT: $line$br\n";
		}

		if ( $line =~ /bad/i || $line =~ /mixed/i ) {
			
			if ( $line !~ /</ ) {
				print "MISSING TAG: $line$br\n";
			}
		}
		elsif ( $line =~ /good/i ) {
			if ( $line =~ /</ ) {
				print "FALSE POSITIVE: $line$br\n";
			}
		}
		elsif ( $line =~ /evil/i ) {
				#print "COMMENT: $line$br\n";
		}
		else {
			# don't care
		}

		if ( $line =~ /evil(\d+)/i ) {
			# ok!
			# count for checking if all where found
			$found_evil_text{ $1 }++;
		}
		
		
	}

	my ( @lines ) = split(/\n/, $extra_messages);
	foreach my $line ( @lines ) {
		if ( $line =~ /saint/i ) {
			print "MESG FALSE POSITIVE: $line$br\n";
		}
		elsif ( $line =~ /evil(\d+)/i ) {
			# ok!
			# count for checking if all where found
			$found_evil_messages{ $1 }++;
		}
		else {
			if ( $line !~ /Mehr als 5 Weblinks/ &&
				$line !~ /Mehr als 5 Links bei "Siehe auch/ &&
				$line !~ /keinen Link zum Wiktionary/ &&
				$line !~ / #REDIRECTS zu/ 
			) {
				print "MESG FALSE POSITIVE: $line$br\n";
			}
		}
	}
	
	foreach my $evil ( keys %found_evil_text ) {
		if ( !$found_evil_messages{ $evil } ) {
			print "MISSING MESG: $evil\n";
		}
	}

}

sub restore_quotes {

	my ( $line ) = @_;
	$line =~ s/￼QSS.?%(.*?)￼QES.?%/''$1''/g;
	$line =~ s/￼QSD%(.*?)￼QED%/\"$1\"/g;
	$line =~ s/￼QST%(.*?)￼QET%/&lt;i&gt;$1&lt\/i&gt;/g;
	$line =~ s/￼QSL%(.*?)￼QEL%/„$1“/g;
	$line =~ s/￼QSF%(.*?)￼QEF%/«$1»/g;
	$line =~ s/￼QSX%(.*?)￼QEX%/‚$1‘/g;
	$line =~ s/￼QSC%(.*?)￼QEC%/&lt;sic&gt;$1&lt\/sic&gt;/g;
	( $line );
}

sub remove_one_item {
	my ( $item, $prefix, $ref_to_replaced_stuff_quote, $do_count_ref ) = @_;
	$global_removed_count++;
	${$ref_to_replaced_stuff_quote}{ $global_removed_count } = $item;

	if ( $do_count_ref && $item =~ /<\/ref>/i ) {
		$count_ref++;
	}
print "removed: $item <br>\n" if ( $developer && $debug > 8 );
	
	# this is to keep $line and $line_org_wiki in &do_review() in sync, not allowed to remove lines from page!
	my $num_of_lines = $item =~ s/\n/\n/g;
	my $append_newlines = "\n" x $num_of_lines;
print "ADD LINES: $num_of_lines - $item <p>\n" if ( $developer && $num_of_lines && $debug > 8 );

	( "$prefix$global_removed_count-R-$append_newlines-R-" );
}

sub restore_one_item {
	my ( $lola, $ref_to_replaced_stuff_quote, $substitute_tags ) = @_;
#$times2 = $page =~ s/-R-N(\d+)-R-/restore_one_item( $1, \%remove_stuff_for_typo_check_array )/g;
	my $return = ${$ref_to_replaced_stuff_quote}{ $lola };
	if ( $substitute_tags ) {
		$return =~ s/</&lt;/g;
		$return =~ s/>/&gt;/g;
	}
print "restore: $return <br>\n" if ( $developer  && $debug > 8 );
	( $return );
}
