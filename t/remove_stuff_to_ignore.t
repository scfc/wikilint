#!/usr/bin/perl -w

use Test::More tests => 6;

use strict;
use warnings;

BEGIN { use_ok ('autoreview', 'remove_stuff_to_ignore'); }
require_ok ('autoreview');

undef %autoreview::replaced_stuff;
is_deeply ([remove_stuff_to_ignore ('Kontrollgruppe.')], ['Kontrollgruppe.', 0]);
ok (!defined (%autoreview::replaced_stuff));
is_deeply ([remove_stuff_to_ignore ('Das <math>ist</math> <code>ein</code> <blockquote>Test</blockquote>. <poem>Und ein {{Lückenhaft}} Gedicht.</poem> {{Quelle}} <!-- Kommentar --> <!--sic-->')], ['Das -R-R0-R- -R-R1-R- -R-R4-R-. -R-R3-R- -R-R2-R- -R-R5-R- -R-R-SIC6-R-', 7]);
is_deeply (\%autoreview::replaced_stuff, {'6' => '<!--sic-->', '4' => '<blockquote>Test</blockquote>', '1' => '<code>ein</code>', '3' => '<poem>Und ein {{Lückenhaft}} Gedicht.</poem>', '0' => '<math>ist</math>', '2' => '{{Quelle}}', '5' => '<!-- Kommentar -->'});
