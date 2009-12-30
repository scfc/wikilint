#!/usr/bin/perl -w

use Test::More tests => 6;

use strict;
use warnings;

BEGIN { use_ok ('Wikilint', 'remove_stuff_to_ignore'); }
require_ok ('Wikilint');

undef %Wikilint::replaced_stuff;
is_deeply ([remove_stuff_to_ignore ('Kontrollgruppe.')], ['Kontrollgruppe.', 0]);
ok (!defined (%Wikilint::replaced_stuff));
is_deeply ([remove_stuff_to_ignore ('Das <math>ist</math> <code>ein</code> <blockquote>Test</blockquote>. <poem>Und ein {{Lückenhaft}} Gedicht.</poem> {{Quelle}} <!-- Kommentar --> <!--sic-->')], ['Das -R-R1-R- -R-R2-R- -R-R3-R-. -R-R4-R- -R-R5-R- -R-R6-R- -R-R-SIC0-R-', 7]);
is_deeply (\%Wikilint::replaced_stuff, {'0' => '<!--sic-->', '3' => '<blockquote>Test</blockquote>', '2' => '<code>ein</code>', '4' => '<poem>Und ein {{Lückenhaft}} Gedicht.</poem>', '1' => '<math>ist</math>', '5' => '{{Quelle}}', '6' => '<!-- Kommentar -->'});
