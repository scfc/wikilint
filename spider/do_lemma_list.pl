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

# DESCRIPTION: review a list of wikipedia-lemmas


$debug = 8;
#$debugcat = 1;

use CGI qw/:standard/;
use LWP::UserAgent;
use URI::Escape; 

use utf8;
use POSIX qw(locale_h);
setlocale(LC_CTYPE, "german");
setlocale(LC_ALL, "german");

binmode STDOUT, ":utf8";
use open ':utf8';

require "config.pm";
require "autoreview.pm";

$never = "<span class=\"never\">";
$seldom = "<span class=\"seldom\">";
$sometimes = "<span class=\"sometimes\">";


$language="de";

&read_files($language);

my $lolaaa;

while(<>) {

	# ignore ocmments, Spezial:, ...
	if ( !/^#/ && !/Spezial:/ && !/Portal:/ && !/Liste / && !/Wikipedia:/ && !/Hauptseite/ && !/Nekrolog/ && !/Kategorie: / && !/Bild:/ ) {
		chomp;
		my ( $dummy, $dummy2, $dummy3, @rest ) = split(/,/);
		# grmbl, some lemmas contain ,
		my $lemma_list = join(",", @rest );

		$lemma_list = uri_escape($lemma_list);

		my ( $page, $review_level, $num_words, $extra_message );
	
		if ( $debugcat ) {
			$page = `cat test.html`;
		}
		else {
			$page = &download_page("",$lemma_list, $language);
		}
		( $page, $review_level, $num_words, $extra_message, $quotient  ) = &do_review( $page, $language );

		
		print "$quotient - done: $lemma_list: $review_level \n";

		print $extra_message."\n###########\n\n" if ( $debug > 7 );
		sleep 2;
		#die if ( $lolaaa++ > 50 );
	}
}
