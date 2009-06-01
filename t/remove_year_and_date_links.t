#!/usr/bin/perl -w

use Test::More tests => 18;

use strict;
use warnings;

BEGIN { use_ok ('autoreview', 'remove_year_and_date_links'); }
require_ok ('autoreview');

is_deeply ([remove_year_and_date_links ('Kontrollgruppe.', 0)], ['Kontrollgruppe.', 0]);
is_deeply ([remove_year_and_date_links ('Kontrollgruppe.', 1)], ['Kontrollgruppe.', 0]);
is_deeply ([remove_year_and_date_links ('[[1234]] or [[345 v. Chr.]] or [[345 n. Chr.]]', 0)], ['1234 or 345 v. Chr. or 345 n. Chr.', 3]);
is_deeply ([remove_year_and_date_links ('[[1234|34]]', 0)], ['34', 1]);
is_deeply ([remove_year_and_date_links ('[[12. April]]', 0)], ['12. April', 1]);
is_deeply ([remove_year_and_date_links ('[[17. Jahrhundert v. Chr.]] [[17. Jahrhundert]] [[17. Jahrhundert n. Chr.]]', 0)], ['[[17. Jahrhundert v. Chr.]] [[17. Jahrhundert]] [[17. Jahrhundert n. Chr.]]', 0]);
is_deeply ([remove_year_and_date_links ('[[April]]', 0)], ['[[April]]', 0]);
is_deeply ([remove_year_and_date_links ('[[1960er]], [[1960er|60er]]', 0)], ['[[1960er]], [[1960er|60er]]', 0]);
is_deeply ([remove_year_and_date_links ('[[1960er Jahre]]', 0)], ['[[1960er Jahre]]', 0]);
is_deeply ([remove_year_and_date_links ('[[1234]] or [[345 v. Chr.]] or [[345 n. Chr.]]', 1)], ['1234 or 345 v. Chr. or 345 n. Chr.', 3]);
is_deeply ([remove_year_and_date_links ('[[1234|34]]', 1)], ['34', 1]);
is_deeply ([remove_year_and_date_links ('[[12. April]]', 1)], ['12. April', 1]);
is_deeply ([remove_year_and_date_links ('[[17. Jahrhundert v. Chr.]] [[17. Jahrhundert]] [[17. Jahrhundert n. Chr.]]', 1)], ['17. Jahrhundert v. Chr. 17. Jahrhundert 17. Jahrhundert n. Chr.', 3]);
is_deeply ([remove_year_and_date_links ('[[April]]', 1)], ['April', 1]);
is_deeply ([remove_year_and_date_links ('[[1960er]], [[1960er|60er]]', 1)], ['1960er, 1960er', 2]);
is_deeply ([remove_year_and_date_links ('[[1960er Jahre]]', 1)], ['1960er Jahre', 1]);
