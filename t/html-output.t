#!/usr/bin/perl -w

use strict;
use Test::More;
use warnings;

my @filenames = <t/testcases/de/*.html>;

plan tests => scalar (@filenames);

foreach my $filename (@filenames)
  {
    $filename =~ /^t\/testcases\/de\/(.*)\.html$/ || die;
    my $lemma = $1;
    my @got = `cd cgi-bin && perl wikilint "url=http://de.wikipedia.org/wiki/$lemma&do_typo_check=ON&l=de&Go\!=Go\!&.cgifields=rnd&.cgifields=testpage&.cgifields=remove_century&.cgifields=do_typo_check&testhtml=$lemma"`;
    my @expected = `cat $filename`;
    is_deeply (\@got, \@expected, $lemma . '.html');
  }
