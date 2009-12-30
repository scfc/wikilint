#!/usr/bin/perl -w

use Test::More tests => 12;

use strict;
use warnings;

BEGIN { use_ok ('Wikilint', 'tag_dates_rest_line'); }
require_ok ('Wikilint');

is (tag_dates_rest_line ('Kontrollgruppe.'), 'Kontrollgruppe.');
is (tag_dates_rest_line ('[[2005]]'), '<span class="seldom">[[2005]]</span><sup class="reference"><a href="#links_to_numbers">[LTN?]</a></sup>');
is (tag_dates_rest_line ('[[1878|78]]'), '<span class="seldom">[[1878|78]]</span><sup class="reference"><a href="#links_to_numbers">[LTN?]</a></sup>');
is (tag_dates_rest_line ('[[17. Jahrhundert]] or [[17. Jahrhundert|whatever]]'), '<span class="sometimes">[[17. Jahrhundert]]</span><sup class="reference"><a href="#links_to_numbers">[LTN?]</a></sup> or <span class="sometimes">[[17. Jahrhundert|</span><sup class="reference"><a href="#links_to_numbers">[LTN?]</a></sup>whatever]]');
is (tag_dates_rest_line ('[[1960er]] or [[1960er|60er]]'), '<span class="sometimes">[[1960er]]</span><sup class="reference"><a href="#links_to_numbers">[LTN?]</a></sup> or <span class="sometimes">[[1960er|</span><sup class="reference"><a href="#links_to_numbers">[LTN?]</a></sup>60er]]');
is (tag_dates_rest_line ('[[1960er Jahre]]'), '<span class="sometimes">[[1960er Jahre]]</span><sup class="reference"><a href="#links_to_numbers">[LTN?]</a></sup>');
is (tag_dates_rest_line ('[[12. Mai]] or [[12. Mai|...]]'), '<span class="seldom">[[12. Mai]]</span><sup class="reference"><a href="#links_to_numbers">[LTN?]</a></sup> or <span class="seldom">[[12. Mai|</span><sup class="reference"><a href="#links_to_numbers">[LTN?]</a></sup>...]]');
is (tag_dates_rest_line ('[[Mai]] or [[Mai|...]]'), '<span class="sometimes">[[Mai]]</span><sup class="reference"><a href="#links_to_numbers">[LTN?]</a></sup> or <span class="sometimes">[[Mai|</span><sup class="reference"><a href="#links_to_numbers">[LTN?]</a></sup>...]]');
is ($Wikilint::review_level, 15);
is_deeply (\%Wikilint::count_letters, {'K' => 2, 'U' => 2, 'V' => 3, 'L' => 2, 'W' => 2});
