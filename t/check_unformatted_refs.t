#!/usr/bin/perl -w

use Test::More tests => 7;

use strict;
use warnings;
use utf8;

BEGIN { use_ok ('autoreview', 'check_unformatted_refs'); }
require_ok ('autoreview');

our ($language) = 'de';

my ($extra_message);

$extra_message = '';
check_unformatted_refs ('1. Line
abc www.tim-landscheidt.de def
3. Line', $extra_message);
is ($extra_message, '');
$extra_message = '';
check_unformatted_refs ('1. Line
abc http://www.tim-landscheidt.de/ def
3. Line', $extra_message);
is ($extra_message, '<span class="seldom">Unformatierter Weblink: </span>http://www.tim-landscheidt.de/ – Siehe <a href="http://de.wikipedia.org/wiki/WP:WEB#Formatierung">WP:WEB#Formatierung</a><br />
');
$extra_message = '';
check_unformatted_refs ('1. Line
abc [http://www.tim-landscheidt.de/] def
3. Line', $extra_message);
is ($extra_message, '<span class="seldom">Unformatierter Weblink: </span>[http://www.tim-landscheidt.de/] – Siehe <a href="http://de.wikipedia.org/wiki/WP:WEB#Formatierung">WP:WEB#Formatierung</a><br />
');
$extra_message = '';
check_unformatted_refs ('1. Line
{{abc|url=http://www.tim-landscheidt.de/}}
3. Line', $extra_message);
is ($extra_message, '');
$extra_message = '';
check_unformatted_refs ('1. Line
{{def|url= http://www.tim-landscheidt.de/}}
3. Line', $extra_message);
is ($extra_message, '');
