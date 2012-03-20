#!/usr/bin/perl -w

use Test::More tests => 7;

use strict;
use warnings;

BEGIN { use_ok ('Wikilint', 'EscapeSectionTitle'); }
require_ok ('Wikilint');

is (EscapeSectionTitle ('18. Jahrhundert'), 'section-18.%20Jahrhundert');
is (EscapeSectionTitle ('Abgeordnete für Krefeld'), 'section-Abgeordnete%20f%C3%83%C2%BCr%20Krefeld');
is (EscapeSectionTitle ('Allgemeines Krankenhaus „Agios Giorgos“'), 'section-Allgemeines%20Krankenhaus%20%C3%A2%C2%80%C2%9EAgios%20Giorgos%C3%A2%C2%80%C2%9C');
is (EscapeSectionTitle ('Das „Hand-Denkmal“'), 'section-Das%20%C3%A2%C2%80%C2%9EHand-Denkmal%C3%A2%C2%80%C2%9C');
is (EscapeSectionTitle ('Oberstadtdirektoren 1946–1999'), 'section-Oberstadtdirektoren%201946%C3%A2%C2%80%C2%931999');
