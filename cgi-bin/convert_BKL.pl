#!/usr/bin/perl

# convert catscan BKL-list into a lowercase list of just the words

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

$redirs_file ="redirs.txt";
$bkl_file ="BKL_neu.txt";

#############################################################
# i don't get all this utf8-stuff but it kind of works now
#use utf8;
#use POSIX qw(locale_h);

#setlocale(LC_CTYPE, "german");
#setlocale(LC_ALL, "german");

binmode STDOUT, ":utf8";
use open ':utf8';
#############################################################

# read #REDIRECTS to also be able to complain on redirects to BKLs
open (REDIRS, "< $redirs_file") || die "cant open $redirs_file\n";
while(<REDIRS>) {

	utf8::decode($_);
	$_ =~ /\[\[(.+?)\]\]...\[\[(.+?)\]\]/;
	$to{"$2"} .= "$1\t";
#print "$1 -> $2\n";
}
close(REDIRS);

open (BKLS, "< $bkl_file") || die "cant open $bkl_file\n";

while(<BKLS>) {
	($d, $bkl, @rest ) = split(/\t/);
	$bkl =~ s/_/ /g;
	utf8::decode($bkl);

	# grmbl, case matters, [[USA]] vs. [[Usa]]
	#$bkl = lc($bkl);
	#utf8::encode($bkl);
	print "$bkl\n";

	if ( $to{"$bkl"} ) {
		chop($to{"$bkl"});
		my ( @redirs_from ) = split(/\t/, $to{"$bkl"} );
		foreach $redir_from ( @redirs_from ) {
			print "$redir_from\n";
		}
	}
}
