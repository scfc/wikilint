#!/usr/bin/perl -w
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

package Wikilint::Config;

use base 'Exporter';

use strict;
use utf8;
use warnings;

our @EXPORT = qw($tool_path $max_words_per_sentence $min_words_per_section $max_words_per_wikilink $min_words_to_recommend_references_section $min_words_to_recommend_references $words_per_reference $max_weblinks $max_see_also $fillwords_per_words $short_quote_length $wait_between_http_retry $http_retry $never_level $seldom_level $sometimes_level $never $seldom $sometimes $proposal %text $table_order %farbe_html %units %units_special $min_length_for_nbsp);

our $tool_path = 'http://toolserver.org/~timl/cgi-bin/wikilint';

our $max_words_per_sentence =   50;
our $min_words_per_section  =   30;
our $max_words_per_wikilink = 1000;


# Threshold to propose literature section.
our $min_words_to_recommend_references_section = 500;

# When to propose "<ref>"s.
our $min_words_to_recommend_references = 1000;
our $words_per_reference               =  500;
our $max_weblinks                      =    5;
our $max_see_also                      =    5;

# Threshold to warn against fill words (average German excellent articles (2007-01—2007-05)).
our $fillwords_per_words = 80;

# Quotes that have more characters than this don't count to complain on looong sentences because they're real quotes.
our $short_quote_length = 120;

# Seconds to wait between HTTP retry.
our $wait_between_http_retry = 10;
# Number of tries.
our $http_retry = 5;

our $never_level     = 4;
our $seldom_level    = 2;
our $sometimes_level = 1;

# Shortcuts.
our $never     = '<span class="never">';
our $seldom    = '<span class="seldom">';
our $sometimes = '<span class="sometimes">';
our $proposal  = '<span class="proposal">';

# Explanations of all problems found and stored in $review_letters.
# Format: $text {$language . '|' . $review_letter} = '$LEVEL|$SUMMARY|$TEXT';
# $SUMMARY can be "S" (sum), "C" (count) or "X" (maximum).
our %text;
$text {'de|A'} = "2|S|Lange Sätze (mehr als $max_words_per_sentence Wörter)";
$text {'de|B'} = '1|S|Wörter, die in Wikipedia nicht stehen sollten';
$text {'de|C'} = '1|S|Potentielle Füllwörter';
$text {'de|D'} = '1|S|Abkürzung';
$text {'de|E'} = '3|S|Doppel-Wikilink ohne erkennbaren Übergang';
$text {'de|F'} = '2|S|Fettschrift im Text (außerhalb der Lemma-Definition und Tabellen)';
$text {'de|G'} = '3|S|Ausrufezeichen außerhalb von Zitaten';
$text {'de|H'} = '1|C|Wenige Einzelnachweise, aber Abschnitt "== Literatur =="';
$text {'de|I'} = '1|S|Sehr kurzer Abschnitt';
$text {'de|J'} = '3|S|Weblink in Text (außerhalb von "&lt;ref&gt;" und "== Weblinks =="';
$text {'de|K'} = '2|S|Wikilinks zu Jahren (außer Geburts- und Sterbedaten in Biografien)';
$text {'de|L'} = '2|S|Wikilinks zu Tagen (außer Geburts- und Sterbedaten in Biografien)';
$text {'de|M'} = '3|S|Plenk';
$text {'de|N'} = '3|S|Weblink in Abschnitts-Titel';
$text {'de|O'} = '3|S|Wikilink in Abschnitts-Titel';
$text {'de|P'} = '3|S|Doppelpunkt, Ausrufe- oder Fragezeichen in Abschnitts-Titel';
$text {'de|Q'} = '1|S|Zu viele Wikilinks zum gleichen Lemma';
$text {'de|R'} = '2|C|Wenige Einzelnachweise';
$text {'de|S'} = '2|C|Zu viele Weblinks';
$text {'de|T'} = '2|S|Kein geschütztes Leerzeichen vor Einheit';
$text {'de|U'} = '2|S|Wikilinks zu Jahrhunderten';
$text {'de|V'} = '2|S|Wikilinks zu Jahrzehnten';
$text {'de|W'} = '2|S|Wikilinks zu Monaten';
$text {'de|X'} = '2|S|Unformatierte Weblinks';
$text {'de|Y'} = '1|C|Zu viele Links bei "== Siehe auch =="';
$text {'de|Z'} = '3|S|Link bei "== Siehe auch ==", der vorher schon gesetzt ist';
$text {'de|a'} = '3|S|Satz, der klein geschrieben beginnt';
$text {'de|b'} = '3|S|Abschnitts-Titel, der klein geschrieben beginnt';
$text {'de|c'} = '3|S|Klemp';
$text {'de|d'} = '2|S|Link zu Begriffsklärungs-Seite';
$text {'de|e'} = '1|S|Fettschrift als Abschnittsersatz';
$text {'de|f'} = '0|C|Vorschlag: Kein Wiktionary-Link';
$text {'de|g'} = '0|C|Vorschlag: Kein Wikimedia-Commons-Link';
$text {'de|h'} = '0|C|Vorschlag: Kein Bild im Artikel';
$text {'de|i'} = '3|S|Falsch formatierte ISBN';
$text {'de|j'} = "3|S|\"&lt;i&gt;\" oder \"&lt;b&gt;\" statt \"''\" oder \"'''\"";
$text {'de|k'} = '2|S|Tags, die nicht verwendet werden sollten: "&lt;s&gt;", "&lt;u&gt;", "&lt;small&gt;" oder "&lt;big&gt;"';
$text {'de|l'} = '2|S|"..." (drei Zeichen) statt "…"';
$text {'de|m'} = '3|S|Selbstlink ohne Sprung zu Kapitel (eventuell über Redirect)';
$text {'de|n'} = '3|S|Wortdopplung';
$text {'de|o'} = '2|S|Häufige Tippfehler';
$text {'de|p'} = '1|S|Minus statt Bis-Strich';
$text {'de|q'} = '2|S|Klammer falsch bei Vorlage oder Wikilink';
$text {'de|r'} = '2|X|Anzahl der Wörter im längsten Satz';
$text {'de|s'} = "1|S|Falsches Apostroph, \"'\" statt \"’\"";
$text {'de|t'} = '1|S|Bindestrich ("-") statt Gedankenstrich ("–") verwendet';
$text {'de|u'} = "1|S|Normale Anführungszeichen '\"\"' statt \"„\" und \"“\"";
$text {'de|v'} = '2|S|Kein Leerzeichen vor einer öffnenden oder nach einer schließenden Klammer.';

# Order of rows in review table.
our $table_order = 'nMcENGJOPZabijdlmopstuqvkXArBCDFeQHRSTKLUVWYhfg';

our %farbe_html;
$farbe_html {1} = '#b9ffc5';
$farbe_html {2} = '#ffebad';
$farbe_html {3} = '#ffcbcb';

# Units where a &nbsp; is mandatory (case-sensitive!).
our (%units, %units_special);
$units {'de'} = 'kg;cm;m;km;mm;l;dl;qm;Prozent;s;h;Nm;N;W;°C;Watt;Pf;Pfennig;Mark;RM;GBP;Pfund;SFr;m³;MW;EUR;EURO;Euro;Minuten;Stunden;Sekunden;Tage;Wochen;Monate;Jahre;Volt;Ampere;Watt;Ohm';
$units_special {'de'} = '°C;€;\$;£';
# Ignore missing &nbsp; in short lines.
our $min_length_for_nbsp = 100;

1;