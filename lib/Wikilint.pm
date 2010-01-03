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

package Wikilint;

use base 'Exporter';
use feature qw(state);
use strict;
use utf8;
use warnings;

use CGI qw(:standard);
use DBI;
use HTML::Entities;
use LWP::UserAgent;
use URI::Escape qw(uri_escape_utf8);
use Wikilint::Config;

our @EXPORT = qw(create_ar_link create_edit_link create_review_summary_html do_review download_page find_random_page read_files selftest EscapeSectionTitle);
our @EXPORT_OK = qw(check_unformatted_refs remove_stuff_to_ignore remove_year_and_date_links tag_dates_rest_line);   # Public only for tests.

my @months = ('Januar', 'Jänner', 'Februar', 'März', 'April', 'Mai', 'Juni', 'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember');
my (@abbreviations, @avoid_words, $count_ref, $DB, @fill_words, $global_removed_count, @is_typo, $last_word, $line, $lola, %remove_refs_and_images_array, %remove_stuff_for_typo_check_array);
our (%replaced_stuff, %count_letters, $review_level);   # Public only for tests.

sub EscapeSectionTitle ($)
{
  my ($SectionTitle) = @_;

  return uri_escape_utf8 ('section-' . $SectionTitle);
}

sub IsDisambiguation ($)
{
  my ($Title) = @_;
  state $s = $DB->prepare ('SELECT 1 FROM DisambiguationPages WHERE Title = ?;') or die ($DB->errstr ());

  $s->execute ($Title) or die ($DB->errstr ());

  return $s->fetch ();
}

sub download_page ($$$$;$$);
sub download_page ($$$$;$$)   # Create URL to download from and call http_download ().
{
  # This function gets called recursively on Wikipedia #REDIRECT[[]]s.
  my ($url, $lemma, $language, $oldid, $ignore_error, $recursion_depth) = @_;

  if ($url)
    {
      $lemma =  $url;
      $lemma =~ s/^http:\/\/\w\w\.wikipedia\.org\/w(iki)?\///;
    }
  elsif ($lemma)
    { $lemma =~ tr/ /_/; }
  else
    { die ("Neither URL nor lemma\n"); }

  $oldid = $2 if ($lemma =~ s/index\.php\?title=(.+?)&oldid=(\d+)/$1/);

  my $downlemma = $lemma;
  $downlemma =~ tr/ /_/;

  # uri_escape can't be used because some characters are already escaped except &.
  $downlemma =~ s/&amp;/%26/g;
  $downlemma =~ s/&/%26/g;
  $downlemma =~ s/’/%E2%80%99/g;

  $::lemma_org =  $lemma;
  $lemma       =~ s/%([0-9A-Fa-f]{2})/chr (hex ($1))/eg;

  utf8::decode ($lemma);

  $::search_lemma =  $lemma;
  $::search_lemma =~ tr/_/ /;

  # Security check.
  die if (length ($language) != 2);

  my $down_url = new URI ('http://' . $language . '.wikipedia.org/w/index.php');
  $down_url->query_form ({'title' => $downlemma, 'action' => 'raw', defined ($oldid) && $oldid =~ /^\d+$/ ? ('oldid' => $oldid) : ()});

  my $page = http_download ($down_url->as_string (), $ignore_error);

  if ($page =~ /#REDIRECT *\[\[(.+?)\]\]/i && $recursion_depth < 2)   # Don't get infinite loop on two redirects which point to each other.
    {
      my $redir_to;

      $redir_to =  $1;
      $redir_to =~ s/#.*$//;
      $redir_to =  uri_escape_utf8 ($redir_to);
      $page     =  download_page ('', $redir_to, $language, $oldid, $ignore_error, $recursion_depth + 1);
    }

  return $page;
}

sub http_download ($$)
{
  my ($down_url, $ignore_error) = @_;

  die ("URL too long\n") if (length ($down_url) > 300);

  # Create a user agent object with timeout set to 10 s.
  my $ua = LWP::UserAgent->new (agent => 'toolserver.org/~timl/cgi-bin/wikilint', timeout => 10);

  for (my $tries = 0; $tries < $http_retry; $tries++)
    {
      my $res = $ua->get ($down_url);
      if ($res->is_success ())
        { return $res->decoded_content (); }
      print "Problem beim Runterladen der Seite \"" . $down_url . "\" von Wikipedia, bitte später nochmal probieren: ";
      print b ($res->status_line ()), p ();
      print 'Problem downloading the page from Wikipedia, please try again later: ';
      print b ($res->status_line ()), p ();

      exit unless ($ignore_error);

      sleep ($wait_between_http_retry);
    }

  return undef;
}

sub find_random_page ($)
{
  my ($language) = @_;

  die ("Only de or en random page so far\n") unless ($language eq 'de' || $language eq 'en');

  # Create a user agent object with timeout set to 10 s.
  my $ua = LWP::UserAgent->new (agent => 'toolserver.org/~timl/cgi-bin/wikilint', timeout => 10, max_redirect => 0);

  # Create a request
  my $req = HTTP::Request->new (GET => $language eq 'de' ? 'http://de.wikipedia.org/wiki/Spezial:Zufällige_Seite' :
                                       $language eq 'en' ? 'http://en.wikipedia.org/wiki/Special:Random' :
                                       '');

  # Pass request to the user agent and get a response back
  my $res = $ua->simple_request ($req);

  return $res->header ('Location');
}

sub do_review ($$$$$)
{
  my ($page, $language, $remove_century, $self_lemma, $do_typo_check) = @_;
  my ($dont_look_for_apostroph, $times, $section_title, $section_level, $count_words, $inside_weblinks, $inside_ref, $num_words, $count_ref, $inside_template, $new_page, $new_page_org, $words_in_section, $dont_count_words_in_section_title, $removed_links, $last_replaced_num, $inside_ref_word, $inside_comment_word, $inside_comment, $inside_literatur, $open_ended_sentence, $gallery_in_section, $section_sources, %count_linkto, $dont_look_for_klemp, $literatur_section_level, $year_article);
  my $count_weblinks         = 0;
  my $count_fillwords        = 0;
  my $count_see_also         = 0;
  my $extra_message          = '';
  my $longest_sentence       = 0;
  my $weblinks_section_level = 0;

  $global_removed_count = 0;
  $last_word            = '';
  %count_letters        = ();
  $review_level         = 0;

  my $self_lemma_tmp = $self_lemma;
  $self_lemma_tmp =~ s/%([0-9A-Fa-f]{2})/chr (hex ($1))/eg;

  # If the lemma contains a klemp, ignore it in the article, e. g. "[[Skulptur.Projekte]]".
  if ($dont_look_for_klemp = $self_lemma_tmp =~ /[[:alpha:]][[:lower:]]{2,}[,.][[:alpha:]]{3,}/)
    { $extra_message .= b ('Klemp in Lemma') . ': Klemp-Suche deaktiviert.' . br () . "\n"; }

  # If the lemma contains an apostroph, ignore it in the article, e. g. "[[Mi'kmaq]]".
  my $bad_search_apostroph = qr/(?<!['´=\d])(['´][[:lower:]]+)/;
  if ($dont_look_for_apostroph = $self_lemma_tmp =~ /$bad_search_apostroph/)
    { $extra_message .= b ('Apostroph in Lemma') . ': Apostroph-Suche deaktiviert.' . br () . "\n"; }

  my $schweizbezogen = $page =~ /<!--\s*schweizbezogen\s*-->/i;

  if ($year_article = $page =~ /{{Artikel Jahr.*?}}/ || $page =~ /{{Kalender Jahrestage.*?}}/)
    { $extra_message .= b ('Jahres- oder Tages-Artikel') . ': Links zu Jahren ignoriert.' . br () . "\n"; }

  # For later use …
  my @units;
  push (@units, qr/((?:\d+?[,.])?\d+? ?$_)\b/) foreach (split (/;/, $units {$language}));
  # Now special-character units like "€", "%".
  push (@units, qr/((?:\d+?[,.])?\d+? $_)/) foreach (split (/;/, $units_special {$language}));

  # Store original lines for building "modified wikisource for cut & paste".
  my (@lines_org_wiki) = split (/\n/, $page);

  # Remove "<math>", "<code>", "<!-- -->", "<poem>" (any stuff to ignore completetly).
  ($page, $last_replaced_num) = remove_stuff_to_ignore ($page);

  # Check for at least one image.
  if ($page !~ /\[\[(Bild|Datei|File|Image):/i              &&
      $page !~ /<gallery>/i                                 &&
      $page !~ /\|(.+?)=.+?\.(jpg|png|gif|bmp|tiff|svg)\b/i ||   # Picture in template.
      $1    =~ /(karte|wappen)/i)                                # Don't count wappen/heraldics or maps as pictures.
    {
      $count_letters {'h'}++;

      if ($language eq 'de')
        {
          my $eng_message = $page =~ /^\[\[en:(.+?)\]\]/m ? '(' . a ({href => 'http://commons.wikimedia.org/wiki/Special:Search?search=' . $1 . '&go=Seite'}, $1) . ') ' : '';

          $extra_message .= $proposal . 'Vorschlag</span> (der nur bei manchen Lemmas sinnvoll ist): Dieser Artikel enthält kein einziges Bild. Um zu schauen, ob es auf den Commons entsprechendes Material gibt, kann man einfach schauen, ob es in den anderssprachigen Versionen dieses Artikels ein Bild gibt, oder selbst auf den Commons nach ' . a ({href => 'http://commons.wikimedia.org/wiki/Special:Search?search=' . $::search_lemma . '&go=Seite'}, $::search_lemma) . ' suchen (eventuell unter dem englischen Begriff ' . $eng_message . " oder dem lateinischen bei Tieren und Pflanzen).\n";
        }
      else
        { $extra_message .= "Proposal: include link to wikimedia commons\n"; }
    }

  # Check for unformatted weblinks in "<ref></ref>".
  check_unformatted_refs ($page, \$extra_message);

  # Remove "<ref></ref>".
  ($page, $last_replaced_num, $count_ref) = remove_refs_and_images ($page, $last_replaced_num);

  # Avoid marking comments "<!--" as evil exclamation mark.
  $page =~ s/<!/&lt;&iexcl;/g;

  # "!"s in wikilinks are ok.
  while ($page =~ s/(\[\[[^!\]]+)!([^\]]+?\]\])/$1&iexcl;$2/g)
    { }

  # No tagging above this line!
  # Convert all original "<tags>".
  $page =~ s/</&lt;/g;
  $page =~ s/>/&gt;/g;

  # Find common typos from list.
  # Do only if checked in form because it takes ages.
  if ($do_typo_check)
    {
      if ($schweizbezogen)
        { $extra_message .= b ('Hinweis') . ': Tippfehler-Prüfung entfällt, weil schweizbezogener Artikel' . br () . "\n"; }
      else   # This is early because it takes long and now the page has less tagging from myself.
        {
          # Remove lines with "<!--sic-->" and "{{Zitat…}}".
          ($page) = remove_stuff_for_typo_check ($page);

          if ($language eq 'de')
            {
              foreach my $typo (@is_typo)
                {
                  my $times;

                  # "(?<!-)" to avoid strange words in German double-names like "meier-pabst".
                  # @is_typo is an array of regular expressions!
                  $times                = $page =~ s/$typo/$seldom$1<\/span><sup class="reference"><a href="#TYPO">[TYPO?]<\/a><\/sup>/g;
                  $review_level        += $times * $seldom_level;
                  $count_letters {'o'} += $times;
                }
            }
          $page = restore_stuff_quote ($page);
        }
    }

  my $lola = 0;

  # 1. Too much wiki-links to the same page.
  # 2. HTTP-links except "<ref>" or in "== Weblinks ==".
  foreach my $line (split (/\n/, $page))
    {
      my $line_org_wiki = shift (@lines_org_wiki);

      my $line_org = $line;

      # Simple '"' instead of "„“".
      if ($line !~ /^({\||\|)/ &&
          $line !~ /^{{/       &&
          $line !~ /style=/)
        {
          my $times;

          # Remove all quotation marks in "<tags>".
          while ($line =~ s/(<[^>]*?)"([^>]*?>)/$1QM-ERS$2/g)
            {}
          while ($line =~ s/(&lt;[^>&]*?)"([^>]*?&gt;)/$1QM-ERS$2/g)
            {}
          while ($line =~ s/="/=QM-ERS/g)
            {}
          while ($line =~ s/(\d)"/$1QM-ERS/g)
            {}
          while ($line =~ s/%"/%QM-ERS/g)
            {}

          $times                = $line =~ s/("([^";]{3,}?)")/$sometimes$1<\/span><sup class="reference"><a href="#QUOTATION">[QUOTATION?]<\/a><\/sup>/g;
          $review_level        += $times * $sometimes_level;
          $count_letters {'u'} += $times;

          # "(?<!['\d\w])" to avoid "''", "'''" and coordinates "4'5"".
          # "\w" to avoid "d'Agoult".
          $times                = $line =~ s/(?<!['\d\w])('([^';]{3,}?)')(?!')/$sometimes$1<\/span><sup class="reference"><a href="#QUOTATION">[QUOTATION?]<\/a><\/sup>/g;
          $review_level        += $times * $sometimes_level;
          $count_letters {'u'} += $times;

          $line =~ s/QM-ERS/"/g;
        }

      my $last_section_title = $section_title;

      # Section title.
      if ($line =~ /^(={2,9})\s*(.+?)\s*={2,9}/)
        {
          $section_level = length ($1);
          $section_title = $2;

          # Just to be sure reset some things which normally don't strech over section titles.
          $inside_ref = $inside_template = $inside_comment = $inside_comment_word = 0;

          $dont_count_words_in_section_title = 1;

          if ($words_in_section                          &&
              # Avoid complaining on short "definition":
              defined ($last_section_title)              &&
              !$gallery_in_section                       &&
              $words_in_section < $min_words_per_section &&
              $last_section_title !~ /weblink/i          &&
              $last_section_title !~ /literatur/i        &&
              $last_section_title !~ /quelle/i           &&
              $last_section_title !~ /einzelnachweis/i   &&
              $last_section_title !~ /siehe auch/i       &&
              $last_section_title !~ /fußnote/i          &&
              $last_section_title !~ /referenz/i)
            {
              if ($language eq 'de')
                { $extra_message .= $sometimes . 'Kurzer Abschnitt: ' . a ({href => '#' . EscapeSectionTitle ($last_section_title)}, '== ' . $last_section_title . ' ==') . ' (' . $words_in_section . ' Wörter)</span> Siehe ' . a ({href => 'http://de.wikipedia.org/wiki/WP:WSIGA#.C3.9Cberschriften_und_Abs.C3.A4tze'}, 'WP:WSIGA#Überschriften_und_Absätze') . ' und ' . a ({href => 'http://de.wikipedia.org/wiki/Wikipedia:Typografie#Grundregeln'}, 'Wikipedia:Typografie#Grundregeln') . '.' . br () . "\n"; }
              else
                { $extra_message .= $sometimes . 'Very short section: == ' . $last_section_title . ' == (' . $words_in_section . ' words)</span>' . br () . "\n"; }
              $review_level += $sometimes_level;
              $count_letters {'I'}++;
            }

          $words_in_section = $gallery_in_section = 0;

          # Check if we're in section "weblinks" or in a subsection of it.
          if ($section_title =~ /weblink/i || $section_title =~ /external link/i)
            {
              $inside_weblinks        = 1;
              $inside_literatur       = 0;
              $weblinks_section_level = $section_level;
            }
          elsif ($inside_weblinks && $section_level > $weblinks_section_level)   # Keep status.
            { }
          else
            { $inside_weblinks = 0; }

          # Check if we're in section "literatur" or in a subsection of it.
          # Beware of "== Heilquellen ==".
          if ($section_title =~ /Quellen/ || $section_title =~ /literatur/i)
            {
              $inside_literatur        = 1;
              $literatur_section_level = $section_level;

              # Only this case is still "$inside_weblinks".
              # "== Weblinks ==
              #  === Quellen ===".
              $inside_weblinks = 0 if ($section_level <= $weblinks_section_level);
            }
          elsif ($inside_literatur && $section_level > $literatur_section_level)   # Keep status.
            { }
          else
            { $inside_literatur = 0; }

          # Strip whitespace from beginning and end.
          $section_title =~ s/^\s+//;
          $section_title =~ s/\s+$//;

          # Just to know later if there's a literature section at all.
          if ($section_title =~ /(.*?Literatur.*?)/i ||
              $section_title =~ /(Quelle.*?)/        ||
              $section_title =~ /(Referenzen.*?)/    ||
              $section_title =~ /(Nachweise.*?)/     ||
              $section_title =~ /(References.*?)/    ||
              $section_title =~ /(Source.*?)/)
            { $section_sources = $1; }
        }
      else
        { $dont_count_words_in_section_title = 0; }

      if (!$year_article     &&
          !$inside_literatur &&
          !$inside_weblinks  &&
          !$inside_comment   &&
          !$inside_template  &&
          $line !~ /\|/      &&
          $line !~ /ISBN/)
        {
          my $times;

          # "von 1420 bis 1462" instead of "von 12-13" (this has to be applied before LTN).
          $times                = $line =~ s/(von (\[\[)?\d{1,4}(\]\])?[–-—](\[\[)?\d{1,4}(\|\d\d)?(\]\])?)/$never$1<\/span><sup class="reference"><a href="#FROMTO">[FROMTO?]<\/a><\/sup>/g;
          $review_level        += $times * $never_level;
          $count_letters {'l'} += $times;

          # Usage of en-dashes at ranges: "1974–1977" (not "1974-1977"), etc.
          # Caution: The different dashes aren't recognizable in terminal fonts!
          my $line_tmp = $line;
          my $undo = 0;
          my $times_total = 0;
          while (my $times = $line =~ s/( |\[\[)(\d{1,4})((\]\]| )?\-( ||\[\[)?)(\d{1,4})(\]\])?( +[nv]\. Chr\.)?/$1$sometimes$2$3$6<\/span><sup class="reference"><a href="#BISSTRICH">[BISSTRICH?]<\/a><\/sup>$7$8/)   # Do "1980-1990" and "[[1980]]-[[1990]]".
            {
              my $from = $2;
              my $to   = $6;

              if ($8)   # "v. Chr." included, must be a date so leave as is.
                { $times_total += $times; }
              elsif ((length ($from) <= length ($to) && $from > $to) ||   # "747-200" good.
                     (length ($from) == 4 && length ($to) == 2 && substr ($from, 2, 2) > $to))   # 1971-30 good
                { $undo = 1; }
              else
                { $times_total += $times; }
            }

          # Undo if one substitution was wrong.
          if ($undo)
            { $line = $line_tmp; }
          else
            {
              $review_level        += $times_total * $sometimes_level;
              $count_letters {'p'} += $times_total;
            }
        }

      # Check for bold text after some lines, should be only in the definition.
      # Links to dates are also okay in first line.
      if ($lola > 0 && $line)
        {
          # Bold everywhere is okay in English Wikipedia,
          # and only German Wikipedia doesn't like links to years and dates.
          if ($language eq 'de')
            {
              # Ignore bold in comments and tables (which is quite useless anyway ;).
              if ($line !~ /&lt;&iexcl;--.*?'''.*?--&gt;/         &&
                  $line !~ /&lt;div.+?'''.+?'''.*?&lt;\/div&gt;/i &&
                  !$inside_template                               &&
                  !$inside_comment                                &&
                  $line !~ /^\|/                                  &&   # Not in table.
                  $line !~ /^{\|/                                 &&
                  $line !~ /^\|}/)
                {
                  # Ignore "'''BOLD'''" in less than four character words, also in "[[wikilinks]]".
                  # The strange character in front of STARTBOLD is some strange UTF8-character.
                  # I copied from a webpage to have something to exclude in "[^￼]".
                  $line =~ s/'''''(.+?)'''''/''￼STARTBOLD$1￼ENDBOLD''/g;
                  $line =~ s/'''''(.+?)'''/''￼STARTBOLD$1￼ENDBOLD/g;
                  $line =~ s/'''(.+?)'''/￼STARTBOLD$1￼ENDBOLD/g;

                  # First, see if somebody used bold-text to replace a section-title.
                  # "*" for "'''''bold+italic'''''".
                  if ($line =~ /^'*￼STARTBOLD[^￼]+?￼ENDBOLD'*\s*(&lt;br( ?\/)?&gt;)?:?$/)
                    {
                      my $times;

                      $times                = $line =~ s/(￼STARTBOLD)([^￼]+?)(￼ENDBOLD)(:?)/$sometimes'''$2'''<\/span><sup class="reference"><a href="#BOLD-INSTEAD-OF-SECTION">[BOLD-INSTEAD-OF-SECTION?]<\/a><\/sup>$4/g;
                      $review_level        += $times * $sometimes_level;
                      $count_letters {'e'} += $times;
                    }
                  else
                    {
                      my $times;

                      # Okay: "'''[[Wasserstoff|H]]'''".
                      # Regular expression uses alternation for three cases: "/('''[[Wasserstoff]]'''|'''[[Wasserstoff|H2O]]'''| '''Wasserstoff''')/".
                      # This part is for "'''baum [[Wasserstoff|H]]'''": "[^￼\[\n]*?".
                      $times                = $line =~ s/(￼STARTBOLD)(([^￼\[\n]*?\[\[[^￼\]\|]{4,}?\]\])[^￼\[\n]*?|([^￼\[\n]*?\[\[[^￼]+?\|[^￼\]]{4,}?\]\][^￼\[\n]*?)|([^￼\[]{4,}?))(￼ENDBOLD)/$seldom'''$2'''<\/span><sup class="reference"><a href="#BOLD">[BOLD]<\/a><\/sup>/g;
                      $review_level        += $times * $seldom_level;
                      $count_letters {'F'} += $times;
                    }
                  $line =~ s/￼STARTBOLD(.+?)￼ENDBOLD/'''$1'''/g;

                  # "<big>", "<small>", "<s>", "<u>", "<br />", "<div align="center">", "<div align="right">".
                  my $times;

                  $times                = $line =~ s/(&lt;(br ?(\/)?|center|big|small|s|u|div align="?center"?|div align="?right"?)&gt;)/$seldom$1<\/span><sup class="reference"><a href="#TAG2">[TAG2]<\/a><\/sup>/g;
                  $review_level        += $times * $seldom_level;
                  $count_letters {'k'} += $times;
                }

              if (!$year_article          &&
                  $line !~ /GEBURTSDATUM/ &&
                  $line !~ /DATUM/        &&
                  $line !~ /STERBEDATUM/)
                {
                  my $times;

                  $line                     = tag_dates_rest_line ($line);
                  ($line_org_wiki, $times)  = remove_year_and_date_links ($line_org_wiki, $remove_century);
                  $removed_links           += $times;
                }
            }
        }
      else   # Here we might be in the first line of article (except templates, comments, …).
        {
          # Don't replace date links in infoboxes.
          if ($line !~ /^(\||\{\{|\{\|)/ && !$year_article)
            {
              # Tag date links.
              $line = tag_dates_first_line ($line);

              # Remove date links for copy/paste wikisource ($line_org_wiki).
              $removed_links += $line_org_wiki =~ s/(?<!(?:\w\]\]| \(\*|. †) )\[\[(\d{1,4}(?: [nv]\. Chr\.)?)\]\]/$1/g;

              # Remove day and month links.
              $removed_links += $line_org_wiki =~ s/(?<!(\*|†) )\[\[((?:\d{1,2}\. )?$_)\]\]/$1/g foreach (@months);
            }
        }

      $inside_template++ if ($line =~ /{{/ || $line =~ /{\|/);   # Might be nested tables so not false/true, but ++/--.

      $inside_comment = 1 if ($line =~ /^\s*&lt;&iexcl;--/ || $line =~ /&lt;div/i);

      # Don't count short lines, textbox lines, templates, …
      $lola++ if (length ($line) > 5                       &&
                  $line !~ /^{/                            &&
                  $line !~ /^--&gt;/                       &&
                  $line !~ /^[!\|]/                        &&
                  $line !~ /\|$/                           &&
                  $line !~ /^__/                           &&
                  !$inside_template                        &&
                  !$inside_comment                         &&
                  $line !~ /^\[\[(Bild|Datei|File|Image):/ &&
                  $line !~ /^-R-I\d+-R--R-$/               &&
                  $line !~ /^-R-R\d+-R-$/);

      # Plenk and klemp.
      if (!$inside_ref && !$inside_comment && !$inside_template &&
          $line =~ /[,.]/)   # Only look for plenk and klemp if line contains "," or ".".
        {
          # Avoid complaining on dots in URLs by replacing "." with "PUNKTERSATZ".
          while ($line =~ s/(https?:\/\/.+?)\./$1PUNKTERSATZ/gi                    ||
                 $line =~ s/((?:Bild|Datei|File|Image):[^\]]+?)\./$1PUNKTERSATZ/gi ||
                 $line =~ s/({{.+?)\./$1PUNKTERSATZ/g                              ||
                 $line =~ s/(https?:\/\/.+?),/$1KOMMAERSATZ/gi)
            { }

          # Avoid complaining on company names like "web.de" in the text.
          # Any two-letter domain:
          $line =~ s/\.(\w\w\b)/PUNKTERSATZ$1/gi;
          $line =~ s/\.((com|org|net|biz|int|info|edu|gov)\b)/PUNKTERSATZ$1/gi;
          $line =~ s/([^\/]www)\.(\w)/$1PUNKTERSATZ$2/gi;
          $line =~ s/\.(html|doc|exe|htm|pdf)/PUNKTERSATZ$1/gi;

          # Do "baum .baum" (cf. <URI:http://de.wikipedia.org/wiki/Plenk>).
          my $line_copyy = $line;
          my $times;
          $times = $line_copyy =~ s/( [[:alpha:]]{2,}?)( [,.])([[:alpha:]]+? )/$1$never$2<\/span><sup class="reference"><a href="#plenk">[plenk?]<\/a><\/sup>$3/g;
          if ($times == 1)
            {
              $line                 = $line_copyy;
              $review_level        += $times * $never_level;
              $count_letters {'M'} += $times;
            }

          # Do "baum . baum".
          $line_copyy = $line;
          $times      = $line_copyy =~ s/( [[:alpha:]]{2,}?)( [,.]) ([[:alpha:]]{2,}? )/$1$never$2<\/span><sup class="reference"><a href="#plenk">[plenk?]<\/a><\/sup>$3/g;
          # If it happens more than once in one line, assume it's intentional.
          if ($times == 1)
            {
              $line                 = $line_copyy;
              $review_level        += $times * $never_level;
              $count_letters {'M'} += $times;
            }

          # Cf. <URI:http://de.wikipedia.org/wiki/Klempen>.
          # Use "{2}" to avoid hitting abbreviations like "i.d.r.".
          # Domains like "www.yahoo.com" are already dealt with above.
          if (!$dont_look_for_klemp)
            {
              my $times;

              $times                = $line =~ s/( [[:alpha:]][[:lower:]]{2,})([,.])([[:alpha:]][[:lower:]]{2,} )/$1$never$2<\/span><sup class="reference"><a href="#klemp">[klemp?]<\/a><\/sup>$3/g;
              $review_level        += $times * $never_level;
              $count_letters {'c'} += $times;
            }

          # Do "blub.blub.Blub".
          $times                = $line =~ s/([.,][[:alpha:]][[:lower:]]{2,})([,.])([[:upper:]][[:alpha:]]{2,}( |))/$1$never$2<\/span><sup class="reference"><a href="#klemp">[klemp?]<\/a><\/sup>$3$4/g;
          $review_level        += $times * $never_level;
          $count_letters {'c'} += $times;

          # Do "blub.Blub.blub".
          $times                = $line =~ s/([.,][A-ZÖÄÜ][[:lower:]]{2,})([,.])([[:alpha:]][[:lower:]]{2,}( |))/$1$never$2<\/span><sup class="reference"><a href="#klemp">[klemp?]<\/a><\/sup>$3$4/g;
          $review_level        += $times * $never_level;
          $count_letters {'c'} += $times;

          # Change "PUNKTERSATZ" back.
          $line =~ s/PUNKTERSATZ/./g;
          $line =~ s/KOMMAERSATZ/,/g;
        }

      # Check for words to avoid and fill words except in "weblinks" and "literatur".
      if ((!defined ($section_title) || $section_title !~ /weblink/i && $section_title !~ /literatur/i) && !$inside_ref)
        {
          # Check for too long sentences. Lots of cases have to be considered which dots are sentence
          # endings or not. Order is important in these checks!
          my $line_copy = $line;

          # Remove HTML-comments "<!--".
          $line_copy =~ s/&lt;&iexcl;--.+?--&gt;//g;

          # Remove "<ref>…</ref>" and "<ref name=>…</ref>".
          $line_copy =~ s/&lt;ref(&gt;| name=).+?&lt;\/ref&gt;//g;
          # Remove "<ref name="test">".
          $line_copy =~ s/&lt;ref [^&]+?&gt;//g;

          # Avoid using dot in "9. armee" as sentence-splitter,
          # but this should be two sentences: "… in the year 1990. Next sentence"
          $line_copy =~ s/(\D\d{1,2})\./$1&#46;/g;

          # Avoid using dot in "Monster Inc." as sentence-splitter.
          $line_copy =~ s/\b(Inc|Ltd|usw|bzw|jährl|monatl|tägl|mtl|Chr)\./$1&#46;/g;

          # Avoid using dot in "Burder (türk. Döner)" as sentence-splitter.
          $line_copy =~ s/( \(\w{2,10})\. ([^\)]{2,160}\) )/$1&#46; $2/g;

          # Avoid using dot in "Burder türk.: Döner" as sentence-splitter.
          $line_copy =~ s/\.:/&#46;:/g;

          # "255.255.255.224".
          $line_copy =~ s/(\d)\.(\d)/$1&#46;$2/g;

          # "A.2".
          $line_copy =~ s/(\w)\.(\d)/$1&#46;$2/g;

          # "2.A".
          $line_copy =~ s/(\d)\.(\w)/$1&#46;$2/g;

          # Avoid splitting on "a..b".
          $line_copy =~ s/\.\.\./&#46;&#46;&#46;/g;
          $line_copy =~ s/\.\./&#46;&#46;/g;

          # Avoid splitting on "Sigismund I. II. III. IV. VI.".
          $line_copy =~ s/(\w X?V?I{1,3}X?V?)\./$1&#46;/g;

          # "." followed by a small letter probably isn't a sentence end, rather abbreviation.
          # ";" for "z.&nbsp;B.".
          $line_copy =~ s/([\w;])\.( [[:lower:]])/$1&#46;$2/g;
          # Avoid using dot in "z.B.", "z. B." or "z.&nbsp;B." as sentence-splitter but split on "zwei [[Banane]]n. Neue Satz".
          $line_copy =~ s/(\w\.( |&nbsp;)?\w)\./$1&#46;/g;

          # Do last dot of "z.B." or "i.d.R.".
          $line_copy =~ s/(\.|&#46;)(\w)\./$1$2&#46;/;

          # Avoid splitting on "[[Henry W. Bessemer|H. Bessemer]]".
          $line_copy =~ s/(\[\[[^\]]*?)\.([^\]]*?\]\])/$1&#46;$2/;
          $line_copy =~ s/(\[\[[^\]]*?)\.([^\]]*?\]\])/$1&#46;$2/;
          $line_copy =~ s/(\[\[[^\]]*?)\.([^\]]*?\]\])/$1&#46;$2/;

          # Avoid splitting on "www.yahoo.com" or middle dot of "z.B.".
          $line_copy =~ s/(\w)\.(\w)/$1&#46;$2/g;

          # Avoid splitting on my own question marks in "[LTN?]".
          $line_copy =~ s/\?\]/FRAGERS]/g;

          # A sure sign of a sentence ending dot "mit der Nummer 22. Im Folgejahr".
          $line_copy =~ s/&#46;( {1,2})(Dies|Diese|Dieses|Der|Die|Das|Ein|Eine|Einem|Eines|Vor|Im|Er|Sie|Es|Doch|Aber|Doch|Allerdings|Da|Im|Am|Auf|Wegen|Für|Noch|Eben|Um|Auch|Sein|Seine|Seinem|So|Als|Man|Sogar)( {1,2})/.$1$2$3/g;
          # A sure sign of a non-sentence ending dot "mit der Nummer 22. im Folgejahr".
          $line_copy =~ s/\.( {1,2})(dies|diese|dieses|der|die|das|ein|eine|einem|eines|vor|im|er|sie|es|doch|aber|doch|allerdings|da|im|am|auf|wegen|für|noch|eben|um|auch|sein|seine|seinem|so|als|man|sogar)( {1,2})/&#46;$1$2$3/g;

          # Next block is to avoid splitting in quotes.

          # Substitute quote-signs for better searching.
          # "(''…'')" has no defined start-end so hard to find the quote in "''quote''no-quote''quote''".
          # The "￼" is some utf8 char randomly picked from the web.
          $line_copy =~ s/''([^']*?)''/￼QSSINGLE%$1￼QESINGLE%/g;
          $line_copy =~ s/"([^"]*?)"/￼QSDOUBLE%$1￼QEDOUBLE%/g;
          $line_copy =~ s/&lt;i&gt;(.*?)&lt;\/i&gt;/￼QSTAG%$1￼QETAG%/gi;
          $line_copy =~ s/„([^“]*?)“/￼QSLOW%$1￼QELOW%/g;
          $line_copy =~ s/«([^»]*?)»/￼QSFF%$1￼QEFF%/g;
          $line_copy =~ s/‚([^‘]*?)‘/￼QSLS%$1￼QELS%/g;
          $line_copy =~ s/&lt;sic&gt;(.*?)&lt;\/sic&gt;/￼QSSIC%$1￼QESIC%/gi;

          # Avoid splitting on dot in "{{Zitat|Dies ist Satz eins. Dies ist Satz zwei. Dies ist.}}".
          while ($line_copy =~ s/({{Zitat(-\w\w)?\|[^\}]*?)\.([^\}]*?}})/$1&#46;$2/)
            { }
          while ($line_copy =~ s/({{Zitat(-\w\w)?\|[^\}]*?):([^\}]*?}})/$1DPLPERS$2/)
            { }
          while ($line_copy =~ s/({{Zitat(-\w\w)?\|[^\}]*?)!([^\}]*?}})/$1EXCLERS$2/)
            { }
          while ($line_copy =~ s/({{Zitat(-\w\w)?\|[^\}]*?)\?([^\}]*?}})/$1FRAGERS$2/)
            { }
          while ($line_copy =~ s/({{Zitat(-\w\w)?\|[^\}]*?);([^\}]*?}})/$1SEMIERS$2/)
            { }

          # "QUOTESTART" …
          while ($line_copy =~ s/(￼QS[^￼]*?)\.([^￼]*?￼QE)/$1&#46;$2/)
            { }
          while ($line_copy =~ s/(￼QS[^￼]*?):([^￼]*?￼QE)/$1DPLPERS$2/)
            { }
          while ($line_copy =~ s/(￼QS[^￼]*?)!([^￼]*?￼QE)/$1EXCLERS$2/)
            { }
          while ($line_copy =~ s/(￼QS[^￼]*?)\?([^￼]*?￼QE)/$1FRAGERS$2/)
            { }
          while ($line_copy =~ s/(￼QS[^￼]*?);([^￼]*?￼QE)/$1SEMIERS$2/)
            { }

          $line_copy =~ s/￼QSSINGLE%(.*?)￼QESINGLE%/''$1''/g;
          $line_copy =~ s/￼QSDOUBLE%(.*?)￼QEDOUBLE%/"$1"/g;
          $line_copy =~ s/￼QSTAG%(.*?)￼QETAG%/&lt;i&gt;$1&lt\/i&gt;/gi;
          $line_copy =~ s/￼QSLOW%(.*?)￼QELOW%/„$1“/g;
          $line_copy =~ s/￼QSFF%(.*?)￼QEFF%/«$1»/g;
          $line_copy =~ s/￼QSLS%(.*?)￼QELS%/‚$1‘/g;
          $line_copy =~ s/￼QSSIC(.*?)￼QESIC%/&lt;sic&gt;$1&lt;\/sic&gt;/gi;

          # No mangling $line_copy below here.
          # To avoid splitting on the ";" of "&gt;".
          $line_copy =~ s/(&.{2,6});/$1SEMIERS/g;

          # To avoid splitting on "dieser Satz (türk.: sütz) ist zuende".
          while ($line_copy =~ s/(\([^\)]{0,80}?):([^\)]{0,160}?\))/$1DPLPERS$2/)
            { }

          # Don't split on "[[:tr:Yıldırım Orduları]]".
          while ($line_copy =~ s/(\[\[[^\]]{0,80}?):([^\]]{0,160}?\]\])/$1DPLPERS$2/)
            { }

          foreach my $sentence (split (/[:.!?;]/, $line_copy))
            {
              # Put dots back in, see above.
              $sentence =~ s/&#46;/./g;
              $sentence =~ s/SEMIERS/;/g;
              $sentence =~ s/DPLPERS/:/g;
              $sentence =~ s/EXCLERS/!/g;
              $sentence =~ s/FRAGERS/?/g;
              my $sentence_tmp = $sentence;

              # To count as only one word: "[[Religious conversion|converts]]".
              $sentence_tmp =~ s/\[\[[^\]\|]+?\|//g;
              # Remove my own tags to avoid counting them as words.
              $sentence_tmp =~ s/<.+?>//g;

              if (!$dont_count_words_in_section_title)
                {
                  my $count_words = 0;
                  foreach my $word (split (/ +/, $sentence_tmp))
                    {
                      $count_words++ if (length ($word) > 2 &&
                                         $word !~ /^&.+;$/);   # Don't count special HTML characters, e. g. "&nbsp;".
                    }

                  # To find too short sections, see above.
                  $words_in_section += $count_words;

                  $gallery_in_section = 1 if ($sentence_tmp =~ /-R-I-G/i);

                  $sentence_tmp =~ s/'''/BLDERS/g;

                  # Avoid considering "''short italic''" as complete quote-sentence.
                  $sentence_tmp =~ s/''([^']{0,$short_quote_length})''/SHORTQUOTEERSATZ$1SHORTQUOTEERSATZ/g;
                  $sentence_tmp =~ s/&lt;i&gt;([^']{0,$short_quote_length})&lt;\/i&gt;/SHORTIERSATZ$1SHORTIERSATZ/g;
                  $sentence_tmp =~ s/"([^"]{0,$short_quote_length})"/SHORTGANSERSATZ$1SHORTGANSERSATZ/g;

                  # Don't complain on looong sentences with mainly quotes.
                  if ($count_words > $max_words_per_sentence                           &&
                      $sentence_tmp !~ /''.{$short_quote_length,}?''/                  &&
                      # This is because some people do "''quote.''" where the "''" gets split off.
                      $sentence_tmp !~ /''.{$short_quote_length,}?$/                   &&
                      # "(?<!<)" to avoid also ignoring sentences with "<a name="HTML tags">".
                      $sentence_tmp !~ /(?<!<)"[^ ]{$short_quote_length,}?"(?!>)/      &&
                      $sentence_tmp !~ /(?<!<)".{$short_quote_length,}?$/              &&
                      $sentence_tmp !~ /&lt;i&gt;.{$short_quote_length,}?&lt;\/i&gt;/  &&
                      # This is because some people do "<i>quote.</i>" where the "</i>" gets split off.
                      $sentence_tmp !~ /&lt;i&gt;.{$short_quote_length,}?$/            &&
                      $sentence_tmp !~ /{{Zitat(-\w\w)?\|.{$short_quote_length,}?}}/   &&
                      $sentence_tmp !~ /{{Zitat(-\w\w)?\|[^}]{$short_quote_length,}?$/ &&
                      $sentence_tmp !~ /„.{$short_quote_length,}?“/                    &&
                      $sentence_tmp !~ /„.{$short_quote_length,}?$/                    &&
                      $sentence_tmp !~ /«.{$short_quote_length,}?»/                    &&
                      $sentence_tmp !~ /«.{$short_quote_length,}?$/)
                    {
                      my $sentence_tmp_restored;

                      $review_level += $never_level;
                      $count_letters {'A'}++;

                      $longest_sentence = $count_words if ($count_words > $longest_sentence);

                      # Restore removed HTML comments and the like.
                      $sentence_tmp_restored = restore_stuff_to_ignore ($sentence, 1);

                      # Remove "<ref>" in beginning of sentence because of no relevance.
                      $sentence_tmp_restored =~ s/^\s*&lt;ref(&gt;| name=[^&]+?&gt;)[^&]+?&lt;\/ref&gt;//i;

                      if ($language eq 'de')
                        { $extra_message .= $sometimes . 'Langer Satz (eventuell als Zitat markieren?) (' . $count_words . ' Wörter)</span> Siehe ' . a ({href => 'http://de.wikipedia.org/wiki/WP:WSIGA#Schreibe_in_ganzen_S.C3.A4tzen'}, 'WP:WSIGA#Schreibe_in_ganzen_Sätzen') . ': '. i ($sentence_tmp_restored . '.') . br () . "\n"; }
                      else
                        { $extra_message .= $sometimes . 'Very long sentence (' . $count_words . ' words)</span>: ' . $sentence_tmp_restored . '. See ' . a ({href => 'http://en.wikipedia.org/wiki/Wikipedia:Avoid_trite_expressions#Use_short_sentences_and_lists'}, 'here') . br () . "\n"; }
                    }
                }
            }

          # Substitute quote-signs for better searching.
          # "(''…'')" has no defined start-end so hard to find the quote in "''quote''no-quote''quote''".
          # The "￼" is some utf8 char randomly picked from the web.
          $line =~ s/'''''([^']*?)'''''/'''￼QSSA%$1￼QESA%'''/g;
          # Do "'''''bold&italic''' end bold'' end italic" (yes, I've seen it ;).
          $line =~ s/'''''([^']+?'''[^']+?)(?<!')''(?!')/'''￼QSSB%$1￼QESB%/g;

          $line =~ s/(?<!')''([^']*?)''(?!')/￼QSSC%$1￼QESC%/g;
          $line =~ s/"([^"]*?)"/￼QSD%$1￼QED%/g;
          $line =~ s/&lt;i&gt;(.*?)&lt;\/i&gt;/￼QST%$1￼QET%/gi;
          $line =~ s/„([^“]*?)“/￼QSL%$1￼QEL%/g;
          $line =~ s/«([^»]*?)»/￼QSF%$1￼QEF%/g;
          $line =~ s/‚([^‘]*?)‘/￼QSX%$1￼QEX%/g;
          $line =~ s/&lt;sic&gt;(.*?)&lt;\/sic&gt;/￼QSC%$1￼QEC%/gi;

          # Avoid "!" always except in tables (= beginning of a line, "." matches anything except newline) and in "<ref>" and in quotes.
          if ($inside_comment                                                                             ||
              $inside_template                                                                            ||
              (defined ($last_section_title) && $last_section_title =~ /literatur/i && $line =~ /^\s?\*/) ||
              $line =~ /￼QSS.*?!.*?￼QES/i                                                                 ||
              $line =~ /￼QSL.*?!.*?￼QEL/i                                                                 ||
              $line =~ /￼QSD.*?!.*?￼QED/i                                                                 ||
              $line =~ /￼QST.*?!.*?￼QET/i                                                                 ||
              $line =~ /￼QSF.*?!.*?￼QEF/i                                                                 ||
              $line =~ /￼QSX.*?!.*?￼QEX/i                                                                 ||
              $line =~ /￼QSC.*?!.*?￼QEC/i                                                                 ||
              $line =~ /(?<!')''[^']*?![^']*?$/i                                                          ||
              $line =~ /^:/                                                                               ||
              # Avoid grammar-articles.
              $line =~ /imperativ/i)
            {
              # Do nothing.
            }
          elsif ($line !~ /&lt;ref&gt;.+?!.+?&lt;\/ref&gt;/i &&
                 $line !~ /&lt;&iexcl;--.+?!.+?&gt;/         &&
                 $line !~ /!\]\]/                            &&
                 # Avoid tagging lists of boo/movie titles.
                 $line !~ /^\*/                              &&
                 $line !~ /!!/)
            {
              my $times;

              do
                {
                  # Avoid "!" in wikilinks and HTML tags, "$!" and "26!" (factorial) and chess ("e2e4!").
                  $times                = $line =~ s/([^\[<\$]+?[^\d\[<\$])!([^\]&>]*?$)/$1$seldom!<\/span><sup class="reference"><a href="#EM">[EM1]<\/a><\/sup>$2/g;
                  $review_level        += $times * $seldom_level;
                  $count_letters {'G'} += $times;
                }
              until (!$times);
            }
          else
            {
              my $times;

              # Match "!" before "<ref>" and after "</ref>".
              $times                = $line =~ s/(.[^\[<]*?)!([^\]&>]*?&lt;ref&gt;)/$1$seldom!<\/span><sup class="reference"><a href="#EM">[EM2]<\/a><\/sup>$2/g;
              $review_level        += $times * $seldom_level;
              $count_letters {'G'} += $times;
              $times                = $line =~ s/(&lt;\/ref&gt;.[^\[<]*?)!([^\]&>]*?)/$1$seldom!<\/span><sup class="reference"><a href="#EM">[EM3]<\/a><\/sup>$2/g;
              $review_level        += $times * $seldom_level;
              $count_letters {'G'} += $times;
            }

          foreach my $avoid_word (@avoid_words)
            {
              # Check if that word is used in "<ref>" or in quote (buggy because doesn't show same word outside "<ref>" in same line)
              # or in "{{Zitat …}}".

              # Performance: Don't make all the following checks if there's no word to avoid anyway.
              if ($line =~ /$avoid_word/i)
                {
                  if ($line !~ /^(!|\|)/                                    &&   # Don't complain in tables.
                      $line !~ /￼QSS.*?$avoid_word.*?￼QES/i                 &&   # Don't complain in quotes.
                      $line !~ /￼QSL.*?$avoid_word.*?￼QEL/i                 &&
                      $line !~ /￼QSD.*?$avoid_word.*?￼QED/i                 &&
                      $line !~ /￼QST.*?$avoid_word.*?￼QET/i                 &&
                      $line !~ /￼QSF.*?$avoid_word.*?￼QEF/i                 &&
                      $line !~ /￼QSX.*?$avoid_word.*?￼QEX/i                 &&
                      $line !~ /￼QSC.*?$avoid_word.*?￼QEC/i                 &&
                      $line !~ /[\[\|[^\[\]].*?$avoid_word[^\[\]]*?[\]\|]/i &&   # Don't complain in wikilinks.
                      $line !~ /{{[\w\-]+\|[^}]*?$avoid_word[^}]*?}}/i)          # Don't complain in templates.
                    {
                      my $times;

                      $times                = $line =~ s/$avoid_word/$sometimes$1<\/span><sup class="reference"><a href="#WORDS">[WORDS?]<\/a><\/sup>/gi;
                      $review_level        += $times * $sometimes_level;
                      $count_letters {'B'} += $times;
                    }
                }
            }

          # Fill words.
          foreach my $fill_word (@fill_words)
            {
              # Performance: Don't make all the following checks if there's no fill word anyway.
              if ($line =~ /$fill_word/)
                {
                  if ($line !~ /￼QSS.*?$fill_word.*?￼QES/                 &&   # Check if that word is used in quote ("…").
                      $line !~ /￼QSL.*?$fill_word.*?￼QEL/                 &&
                      $line !~ /￼QSD.*?$fill_word.*?￼QED/                 &&
                      $line !~ /￼QST.*?$fill_word.*?￼QET/                 &&
                      $line !~ /￼QSF.*?$fill_word.*?￼QEF/                 &&
                      $line !~ /￼QSX.*?$fill_word.*?￼QEX/                 &&
                      $line !~ /￼QSC.*?$fill_word.*?￼QEC/                 &&
                      $line !~ /{{[\w\-]+\|[^}]*?$fill_word[^}]*?}}/      &&   # Check if that word is used in templates.
                      $line !~ /[\[\|[^\[\]].*?$fill_word[^\[\]]*?[\]\|]/)     # Check if that word is used in wikilinks.
                    {
                      # Ignore "ein Hut (auch Mütze genannt)".
                      if (('auch' =~ /$fill_word/ && ($line =~ /\(\s?auch/i  ||
                                                      $line =~ /siehe auch/i ||
                                                      $line =~ /als auch/i   ||
                                                      $line =~ /aber auch/i)) ||
                          ('aber' =~ /$fill_word/ && ($line =~ /aber auch/i)))
                        {
                          # Do nothing.
                        }
                      else
                        {
                          my $times;

                          # Fill words are not /i because:
                          # 1. In the beginning of a line they're mostly useful.
                          # 2. To avoid e. g. tagging "zum Wohl des Reiches" (wohl).
                          $times = $line =~ s/$fill_word/$sometimes$1<\/span><sup class="reference"><a href="#FILLWORD">[FILLWORD?]<\/a><\/sup>/g;
                          # This $review_level is counted separately because a certain number of fill words is ok.
                          $count_letters {'C'} += $times;
                          $count_fillwords     += $times;
                        }
                    }
                }
            }

          # Abbreviations.
          foreach my $abbreviation (@abbreviations)
            {
              # Performance: Don't make all the following checks if there's no abbreviation anyway.
              if ($line =~ /$abbreviation/i)
                {
                  # Check if that word is used in "<ref>" (buggy because doesn't show same word outside "<ref>" in same line).
                  if ($line !~ /￼QSS[^￼]*?$abbreviation[^￼]*?￼QES/i      &&
                      $line !~ /￼QSD[^￼]*?$abbreviation[^￼]*?￼QED/i      &&
                      $line !~ /￼QST[^￼]*?$abbreviation[^￼]*?￼QET/i      &&
                      $line !~ /￼QSL[^￼]*?$abbreviation[^￼]*?￼QEL/i      &&
                      $line !~ /￼QSF[^￼]*?$abbreviation[^￼]*?￼QEF/i      &&
                      $line !~ /￼QSX[^￼]*?$abbreviation[^￼]*?￼QEX/i      &&
                      $line !~ /￼QSC[^￼]*?$abbreviation[^￼]*?￼QEC/i      &&
                      $line !~ /{{[\w\-]+\|[^}]*?$abbreviation[^}]*?}}/i)
                    {
                      my $times;

                      $times                = $line =~ s/$abbreviation/$sometimes$1<\/span><sup class="reference"><a href="#ABBREVIATION">[ABBREVIATION]<\/a><\/sup>/gi;
                      $review_level        += $times * $sometimes_level;
                      $count_letters {'D'} += $times;
                    }
                }
            }

          $line = restore_quotes ($line);

          # Evil: "[[Automobil|Auto]][[bahn]]".
          # Okay: "[[Bild:MIA index.jpg|thumb|Grafik der Startseite]][[Bild:CreativeCommond_logo_trademark.svg|right|120px|Logo der Creative Commons]]".
          if ($line !~ /\[\[(?:Bild|Datei|File|Image):/i)
            {
              my $times;

              # "[[^\[\]]" instead of "." is neccesarry to avoid marking all of "[[a]] blub [[s]][[u]]".
              $times                = $line =~ s/(\[\[[^\[\]]+?\]\]\[\[[^\[\]]+?\]\])/$never$1<\/span><sup class="reference"><a href="#DL">[DL]<\/a><\/sup>/g;
              $review_level        += $times * $never_level;
              $count_letters {'E'} += $times;
            }
        }

      # Lower-case beginning of sentence.
      # The blank in the search-string is to avoid e. g. "bild:image.jpg" inside a "<gallery>".
      if (!$open_ended_sentence)
        {
          my $times;

          $times                = $line =~ s/^([[:lower:]][[:lower:]]+? )/$seldom$1<\/span><sup class="reference"><a href="#LC">[LC?]<\/a><\/sup>/g;
          $review_level        += $times * $seldom_level;
          $count_letters {'a'} += $times;
        }

      # Open ended if ends in "," or indented.
      if ($line =~ /,(&lt;br \/&gt;)?$/ || $line =~ /^:/)
        { $open_ended_sentence = 1; }
      elsif ($line =~ /[\.!\?](\s*)?(&lt;.+?&gt;)?$/ ||   # Not open end if sentecene ends with ".!?".
             $line =~ /[\.!\?](\s*)?(-R-.+?-R-)?$/   ||   # … or is REPLACED-stuff.
             $line =~/^(={2,9})(.+?)={2,9}/)              # … or is section title.
        { $open_ended_sentence = 0; }   # … then next sentence must begin upper-case.
      elsif ($line =~ /;(\s*)?(&lt;.+?&gt;)?$/)
        { $open_ended_sentence = 1; }
      else   # Default to open end.
        { $open_ended_sentence = 1; }

      # Small section title.
      my $times;
      $times                = $line =~ s/^(={2,9} ?\b?)([[:lower:]].+?)( ?={2,9})/$1$seldom$2<\/span><sup class="reference"><a href="#LC">[LC?]<\/a><\/sup>$3/g;
      $review_level        += $times * $seldom_level;
      $count_letters {'b'} += $times;

      if ($inside_weblinks && !$inside_literatur && $line =~ /https?:\/\//i)
        { $count_weblinks += $line =~ s/(https?:\/\/)/$1/gi; }   # Just count, replace with same (for more than one weblink per line).

      # Check for link in "== See also ==" already linked to above.
      if (defined ($section_title)                   &&
          $section_title =~ /(siehe auch|see also)/i &&
          $line !~ /\[\[\w\w:[^\]]+?\]\]/            &&
          $line !~ /\[\[Kategorie:[^\]]+?\]\]/i      &&
          $line !~ /\[\[category:[^\]]+?\]\]/i       &&
          $line =~ /\[\[(.+?)\]\]/)
        {
          my $wikilink = '';
          while ($line =~ /\[\[(.+?)\]\]/g)
            {
              $wikilink = $1;
              $count_see_also++;

              # Check if see-also-link previously used.
              my $see_also_link = $1;
              if ($count_linkto {lc ($see_also_link)})
                {
                  $review_level += $sometimes_level;
                  $count_letters {'Z'}++;

                  if ($language eq 'de')
                    { $extra_message .= $sometimes . 'Links in "Siehe auch", der vorher schon gesetzt wurde</span>: [[' . $see_also_link . ']] - Siehe ' . a ({href => 'http://de.wikipedia.org/wiki/Wikipedia:Assoziative_Verweise'}, 'WP:ASV') . br () . "\n"; }
                  else
                    { $extra_message .= $sometimes . 'Link in "see also" which was used before:</span> [[' . $see_also_link . ']].' . br () . "\n"; }
                }
            }
        }

      # Check line word by word.
      my $line_org_tmp = $line_org;
      # Ignore "<ref name="Jahresrueckblick"/>".
      $line_org_tmp =~ s/&lt;ref name=.+?\/&gt;//g;

      # Do "[[wiki link hurray]]" -> "[[wiki_link_hurray]]" to keep them as one word.
      while ($line_org_tmp =~ s/(\[\[[^\]]+?) ([^\]]+?[|\]])/$1_$2/)
        { }

      my (@words) = split (/\s/, $line_org_tmp);

      my $words_in_this_line = 0;
      foreach my $word (@words)
        { $words_in_this_line++ if (length ($word) > 3); }

      my $inside_comment_word = 0;
      my $inside_ref_word     = 0;
      my $inside_quote_word   = 0;

      foreach my $word (@words)
        {
          if (!$inside_weblinks     &&
              !$inside_literatur    &&
              !$inside_comment_word &&
              !$inside_comment)
            { $num_words++; }

          # Do "[[wiki_link_hurray]]" -> "[[wiki_link_hurray]]" to restore original version.
          while ($word =~ s/(\[\[[^\]]+?)_([^\]]+?[|\]])/$1 $2/)
            { }

          if ($word =~ /&lt;ref(&gt;| name=)/i)
            {
              $inside_ref_word = 1;
              $count_ref++;
            }

          $inside_comment_word = 1 if ($word =~ /&lt;&iexcl;--/);

          if ($word =~ /\[\[(.+?)[|\]]/ &&   # This is a wikilink.
              !$inside_template         &&
              !$inside_comment_word)
            { $count_linkto {lc ($1)}++; }
          elsif ($word =~ /\[?https?:\/\//                              &&
                 $word !~ /&lt;&iexcl;--/                               &&
                 $word !~ /{{\w+?\|[^}]*https?:\/\//                    &&   # Avoid templates like "{{SEP|http://plato.stanford.edu/entries/aristotle-ethics/index.html#7".
                 $line_org !~ /(\[\[)?Webse?ite(\]\])?[\s\|=:]+?[\[h]/i &&   # Next three for template infoboxes, e. g. "| Website = http://www.stadt.de".
                 $line_org !~ /(\[\[)?Webseite(\]\])? ?=/i              &&
                 $line_org !~ /(\[\[)?Weblink(\]\])? ?=/i               &&
                 !$inside_weblinks                                      &&
                 !$inside_literatur                                     &&
                 !$inside_ref_word                                      &&
                 !$inside_comment_word                                  &&
                 !$inside_comment                                       &&
                 $word !~ /\[?https?:\/\/.+?&lt;\/ref&gt;/)                  # Avoid "http://www.db.de</ref>".
            {
              $extra_message .= $seldom . 'Weblink außerhalb von "== Weblinks ==" und "&lt;ref&gt;:…&lt;/ref&gt;":</span> ' . encode_entities ($word) . ' (Siehe ' . a ({href => 'http://de.wikipedia.org/wiki/WP:WEB#Allgemeines'}, 'Wikipedia:Weblinks') . ')' . p () . "\n";
              $review_level  += $never_level;
              $count_letters {'J'}++;
            }

          # Check for disambiguation pages.
          if ($word =~ /\[\[(.+?)[|\]]/)
            {
              my $linkto_org = $1;

              if (IsDisambiguation ($linkto_org))
                {
                  my ($linkto_tmp, $times);

                  # Remove "_" already, otherwise links to Wikipedia with blank *and* wrong case don't work.
                  $linkto_tmp =  $linkto_org;
                  $linkto_tmp =~ tr/_/ /;
                  $line       =~ s/$linkto_org/$linkto_tmp/g;

                  $times                = $line =~ s/(\[\[)($linkto_tmp)([|\]])/$1$seldom<a href="http:\/\/de.wikipedia.org\/wiki\/Spezial:Suche?search=$2&go=Artikel">$2<\/a><\/span><sup class="reference"><a href="#BKL">[BKL]<\/a><\/sup>$3/gi;
                  $review_level        += $times * $seldom_level;
                  $count_letters {'d'} += $times;
                }
            }

          $inside_quote_word++ if ($word =~ /(?<!')''(?!')\w/ || $word =~ /„/);

          # Find double words, only longer than three chars to avoid "die die".
          if ($word eq $last_word                                                         &&
              !$inside_quote_word                                                         &&
              length ($word) > 3                                                          &&
              $word =~ /^\w+$/                                                            &&
              $words_in_this_line > 4                                                     &&   # Avoid hitting those lists of latin "homo sapiens sapiens".
              !($word =~ /^[a-z]/ && ($word =~ /(um|us|i|a|ens)$/) && length ($word) > 4) &&   # More latin avoiding (small first letter and "…um").
              $word !~ /\-\d/)
            {
              my $times;

              # This regular expression won't hit "tree.tree" but that's not wanted anyway.
              $times                = $line =~ s/($word $word)/$never$1<\/span><sup class="reference"><a href="#DOUBLEWORD">[DOUBLEWORD?]<\/a><\/sup>/i;
              $review_level        += $times * $never_level;
              $count_letters {'n'} += $times;
            }

          $inside_quote_word   = 0 if ($word =~ /(?<!')''(?!').?$/ || $word =~ /“/);

          $inside_comment_word = 0 if ($word =~ /--&gt;/);

          $inside_ref_word = 0 if ($word =~ /&lt;\/ref&gt;/        &&
                                   $word !~ /&lt;\/ref&gt;&lt;ref/);    # Avoid "/ref><ref".

          $last_word = $word;
        }

      if ($line !~ /^\|/ && !$inside_template && length ($line) > $min_length_for_nbsp)
        {
          my $times;

          # Use "&nbsp;" between "50 kg" -> "50&nbsp;kg".
          foreach my $unit (@units)
            {
              my $times;

              # "[\.,]" is for decimal divider.
              $times                = $line =~ s/$unit/$sometimes$1<\/span><sup class="reference"><a href="#NBSP">[NBSP]<\/a><\/sup>/g;
              $review_level        += $times * $sometimes_level;
              $count_letters {'T'} += $times;
            }

          # Good: "[[Dr. phil.]]".
          $times                = $line =~ s/(?<!\[)(Dr\. )(\w)/$sometimes$1<\/span><sup class="reference"><a href="#NBSP">[NBSP]<\/a><\/sup>$2/g;
          $review_level        += $times * $sometimes_level;
          $count_letters {'T'} += $times;
        }

      # Apostroph.
      # Don't complain on "'" in wikilinks.
      if (!$dont_look_for_apostroph &&
          $line !~ /\[\[[^\]]*?$bad_search_apostroph[^\]]*?\]\]/o &&   # Wikilink.
          $line !~ /Achs(formel|folge)/)                               # Don't complain on "Achsfolge Co'Co".
        {
          my $times;

          # Avoid complaining on "''italic''" with "(?<!')".
          $times                = $line =~ s/(\w+)?$bad_search_apostroph/$sometimes$1$2<\/span><sup class="reference"><a href="#APOSTROPH">[APOSTROPH?]<\/a><\/sup>/go;
          $review_level        += $times * $sometimes_level / 3;
          $count_letters {'s'} += $times;
        }

      # Gedankenstrich -----
      my $bad_search = qr/([[:alpha:]]+)( - )([[:alpha:]]+)/;
      if ($line !~ /\[\[[^\]]*?$bad_search[^\]]*?\]\]/o && $line !~ /^\|/)
        {
          my $times;

          $times                = $line =~ s/$bad_search/$1$sometimes$2<\/span><sup class="reference"><a href="#GS">[GS?]<\/a><\/sup>$3/g;
          $review_level        += $times * $sometimes_level;
          $count_letters {'t'} += $times;
        }

      # Do missing spaces before brackets.
      $times                = $line =~ s/([[:alpha:]]{3,}?\()([[:alpha:]]{3,})/$seldom$1<\/span><sup class="reference"><a href="#BRACKET2">[BRACKET2?]<\/a><\/sup>$2/g;
      $review_level        += $times * $seldom_level;
      $count_letters {'v'} += $times;

      # … missing spaces after brackets.
      $times                = $line =~ s/([[:alpha:]]{3,})(\)[[:alpha:]]{3,}?)/$1$seldom$2<\/span><sup class="reference"><a href="#BRACKET2">[BRACKET2?]<\/a><\/sup>/g;
      $review_level        += $times * $seldom_level;
      $count_letters {'v'} += $times;

      $new_page     .= $line          . "\n";
      $new_page_org .= $line_org_wiki . "\n";

      if ($line =~ /}}/ || $line =~ /\|}/)
        { $inside_template-- if ($inside_template); }   # "if" to avoid going below zero with wrong wikisource.
      $inside_comment = 0 if ($line =~ /^--&gt;/ || $line =~ /--&gt;$/ || $line =~ /&lt;\/div&gt;/i);
    }

  $page = $new_page;

  # No weblinks in section titles.
  # … except "de.wikipedia" to avoid tagging BKL tag as weblink in section.
  $times                = $page =~ s/(={2,9}.*?)(http:\/\/(?!de\.wikipedia).+?)( .*?)(={2,9})/$1$never$2<\/span><sup class="reference"><a href="#link_in_section_title">[LiST-Web]<\/a><\/sup>$3$4/g;
  $review_level        += $times * $never_level;
  $count_letters {'N'} += $times;

  # No wikilinks in section titles.
  $times                = $page =~ s/(={2,9}.*?)(\[\[.+?\]\])(.*?={2,9})/$1$never$2<\/span><sup class="reference"><a href="#link_in_section_title">[LiST]<\/a><\/sup>$3$4/g;
  $review_level        += $times * $never_level;
  $count_letters {'O'} += $times;

  # No ":!?" in section titles.
  $times                = $page =~ s/(={2,9}.*?)([:\?!])( .*?)(={2,9})/$1$sometimes$2<\/span><sup class="reference"><a href="#colon_minus_section">[CMS]<\/a><\/sup>$3$4/g;
  $review_level        += $times * $sometimes_level;
  $count_letters {'P'} += $times;

  # No "-" except "== Haus- und Hofnarr ==".
  $times                = $page =~ s/(={2,9}.*?)( - )(.*?)(={2,9})/$1$sometimes$2<\/span><sup class="reference"><a href="#colon_minus_section">[CMS]<\/a><\/sup>$3$4/g;
  $review_level        += $times * $sometimes_level;
  $count_letters {'P'} += $times;

  # Do "ISBN: 3-540-42849-6".
  $times                = $page =~ s/(ISBN: \d[\d\- ]{11,15}\d)/$never$1<\/span><sup class="reference"><a href="#ISBN">[ISBN]<\/a><\/sup>/g;
  $review_level        += $times * $never_level;
  $count_letters {'i'} += $times;

  # Bracket errors on templates, e. g. "{ISSN|0097-8507}}".
  # Expect template name to be not longer than 20 characters.
  $times                = $page =~ s/(?<!{)({[^{}]{1,20}?\|[^{}]+?}})/$seldom$1<\/span><sup class="reference"><a href="#BRACKET">[BRACKET?]<\/a><\/sup>/g;
  $review_level        += $times * $seldom_level;
  $count_letters {'q'} += $times;
  # "{{ISSN|0097-8507}".
  $times                = $page =~ s/({{[^{}]{1,20}?\|[^{}]+?}(?!}))/$seldom$1<\/span><sup class="reference"><a href="#BRACKET">[BRACKET?]<\/a><\/sup>/g;
  $review_level        += $times * $seldom_level;
  $count_letters {'q'} += $times;

  # "[Baum]]".
  # Expect wikilink to be not longer than 80 characters.
  # Good: "[[#a|[a]]".
  # "\D" to avoid "[1  + [3+4]]".
  $times                = $page =~ s/(?<![\[\|])(\[[^\[\]\d][^\[\]]{1,80}?\]\])/$seldom$1<\/span><sup class="reference"><a href="#BRACKET">[BRACKET?]<\/a><\/sup>/g;
  $review_level        += $times * $seldom_level;
  $count_letters {'q'} += $times;

  # "[[Baum]".
  # Expect wikilink to be not longer than 80 characters.
  $times                = $page =~ s/(?<!\[)(\[\[[^\[\]]{1,80}?\](?!\]))/$seldom$1<\/span><sup class="reference"><a href="#BRACKET">[BRACKET?]<\/a><\/sup>/g;
  $review_level        += $times * $seldom_level;
  $count_letters {'q'} += $times;

  # "[[[Baum]]".
  # Expect wikilink to be not longer than 80 characters.
  $times                = $page =~ s/(\[\[\[[^\[\]]{1,80}?\]\](?!\]))/$seldom$1<\/span><sup class="reference"><a href="#BRACKET">[BRACKET?]<\/a><\/sup>/g;
  $review_level        += $times * $seldom_level;
  $count_letters {'q'} += $times;

  # "[[Baum]]]".
  # Expect wikilink to be not longer than 80 characters.
  # Good: "[[Image:Baum.jpg [[Baum]]]]".
  $times                = $page =~ s/(\[\[[^\[\]]{1,80}?\]\]\](?!\]))/$seldom$1<\/span><sup class="reference"><a href="#BRACKET">[BRACKET?]<\/a><\/sup>/g;
  $review_level        += $times * $seldom_level;
  $count_letters {'q'} += $times;

  # "<i>" and "<b>" instead of "''" and "'''".
  $times                = $page =~ s/(&lt;[ib]&gt;)/$never$1<\/span><sup class="reference"><a href="#TAG">[TAG]<\/a><\/sup>/g;
  $review_level        += $times * $never_level;
  $count_letters {'j'} += $times;

  # „...“ (= three dots) instead of „…“.
  $times                = $page =~ s/(\.\.\.)/$sometimes$1<\/span><sup class="reference"><a href="#DOTDOTDOT">[DOTDOTDOT]<\/a><\/sup>/g;
  $review_level        += $times * $sometimes_level;
  $count_letters {'l'} += $times;

  # Do self-wikilinks.
  $self_lemma =~ s/%([0-9A-Fa-f]{2})/chr (hex ($1))/eg;
  utf8::decode ($self_lemma);
  my $self_linkle       = 'http://de.wikipedia.org/wiki/' . $self_lemma;
  $times                = $page =~ s/(\[\[)$self_lemma(\]\]|\|.+?\]\])/$never$1<a href="$self_linkle">$self_lemma<\/a>$2<\/span><sup class="reference"><a href="#SELFLINK">[SELFLINK]<\/a><\/sup>/g;
  $review_level        += $times * $never_level;
  $count_letters {'m'} += $times;

  my $RedirectFrom;
  my $s = $DB->prepare ('SELECT FromTitle FROM Redirects WHERE ToTitle = ?') or die ($DB->errstr ());
  $s->execute ($self_lemma) or die ($DB->errstr ());
  $s->bind_columns (\($RedirectFrom)) or die ($DB->errstr ());
  while ($s->fetch ())
    {
      my $self_linkle = 'http://de.wikipedia.org/wiki/' . $RedirectFrom;
      # Avoid regular expression grouping by "()" in $RedirectFrom (e. g. "A3 (Autobahn)") with "\Q…\E".
      my $times             = $page =~ s/(\[\[)\Q$RedirectFrom\E(\]\]|\|.+?\]\])/$never$1<a href="$self_linkle">$RedirectFrom<\/a>$2<\/span><sup class="reference"><a href="#SELFLINK">[SELFLINK]<\/a><\/sup>/g;
      $review_level        += $times * $never_level;
      $count_letters {'m'} += $times;
    }

  # One wikilink to one lemma per $max_words_per_wikilink words is okay (number made up by me ;).
  my $too_much_links = $num_words / $max_words_per_wikilink + 1;
  foreach my $linkto (keys %count_linkto)
    {
      if ($count_linkto {$linkto} > $too_much_links)
        {
          $review_level += ($count_linkto {$linkto} - $too_much_links) / 2;
          $count_letters {'Q'}++;

          if ($language eq 'de')
            {
              my ($linkto_tmp, $linkto_tmp_ahrefname);

              $linkto_tmp            = ucfirst ($linkto);
              $linkto_tmp_ahrefname  = $linkto_tmp;
              $linkto_tmp_ahrefname  =~ tr/ /_/;
              $extra_message        .= a ({name => 'TML-' . $linkto_tmp_ahrefname}) . $seldom . 'Zu viele Links zu [[' . $linkto_tmp . ']] (' . $count_linkto {$linkto} . ' Stück)</span>, siehe ' . a ({href => 'http://de.wikipedia.org/wiki/WP:VL#H.C3.A4ufigkeit_der_Verweise'}, 'WP:VL#Häufigkeit_der_Verweise') . br () . "\n";

              # This one "(?<!\| )" to avoid tagging links in tables (which isn't perfect but perl doesn't do variable length look behind).
              $page =~ s/(?<!\| )(\[\[$linkto_tmp\b)/$seldom$1<\/span><sup class="reference"><a href="#TML-$linkto_tmp_ahrefname">[TML:$count_linkto{$linkto}x]<\/a><\/sup>/gi;
            }
          else
            { $extra_message .= $seldom . 'Too many links to [[' . $linkto . ']] (' . $count_linkto {$linkto} . ')</span>' . br () . "\n"; }
        }
    }

  # Number made up by me: One reference per $words_per_reference words or a literature chapter in an article < $words_per_reference words.
  $count_ref ||= '0';

  # Don't complain on …
  if ($num_words < $min_words_to_recommend_references_section               ||   # 1. … less than $min_words_to_recommend_references_section.
      ($count_ref / $num_words > 1 / $words_per_reference)                  ||   # 2. … enough "<ref>"s.
      ($section_sources && $num_words < $min_words_to_recommend_references))     # 3. … section "sources" and less than $min_words_to_recommend_references.
    {
      # Okay.
    }
  else   # Complain.
    {
      $review_level += $seldom_level;
      my $tmp_text = '';
      if ($language eq 'de')
        {
          if ($section_sources)
            {
              $tmp_text = ', aber Abschnitt ' . a ({href => '#' . EscapeSectionTitle ($section_sources)}, '== ' . $section_sources . ' ==');
              $count_letters {'H'}++;
            }
          else
            { $count_letters {'R'}++; }
          $extra_message .= $sometimes . 'Wenige Einzelnachweise</span> (Quellen: ' . $count_ref . '/Wörter: ' . $num_words . $tmp_text . ') siehe ' . a ({href => 'http://de.wikipedia.org/wiki/Wikipedia:Quellenangaben'}, 'WP:QA') . ' und ' . a ({href => 'http://de.wikipedia.org/wiki/Wikipedia:Kriterien_f%C3%BCr_lesenswerte_Artikel'}, 'WP:KrLA') . br () . "\n";
        }
      else
        { $extra_message .= $sometimes . 'Very few references (References: ' . $count_ref . '/words: ' . $num_words . ')</span>' . br () . "\n"; }
    }

  if ($count_weblinks > $max_weblinks)
    {
      $review_level        += ($count_weblinks - $max_weblinks);
      $count_letters {'S'} += $count_weblinks;
      if ($language eq 'de')
        {
          $extra_message .= $sometimes . 'Mehr als ' . $max_weblinks . ' Weblinks (' . $count_weblinks . ' Stück)</span>, siehe ' . a ({href => 'http://de.wikipedia.org/wiki/Wikipedia:Weblinks#Allgemeines'}, 'WP:WEB#Allgemeines') . br () . "\n"; }
      else
        { $extra_message .= $sometimes . 'More than ' . $max_weblinks . ' weblinks</span> (' . $count_weblinks . ')' . br () . "\n"; }
    }

  if ($count_see_also > $max_see_also)
    {
      $review_level        += ($count_see_also - $max_see_also);
      $count_letters {'Y'} += $count_see_also;

      if ($language eq 'de')
        {
          $extra_message .= $sometimes . 'Mehr als ' . $max_see_also . ' Links bei "Siehe auch" (' . $count_see_also . ' Stück)</span>. Wichtige Begriffe sollten schon innerhalb des Artikels vorkommen und dort verlinkt werden. Bitte nicht einfach löschen, sondern besser in den Artikel einarbeiten. Siehe ' . a ({href => 'http://de.wikipedia.org/wiki/Wikipedia:Assoziative_Verweise'}, 'WP:ASV') . br () . "\n"; }
      else
        { $extra_message .= $sometimes . 'More than ' . $max_see_also . ' weblinks</span> (' . $count_weblinks . ')' . br () . "\n"; }
    }

  # Check for "{{Wiktionary|".
  if ($page !~ /\{\{wiktionary\|/i)
    {
      $count_letters {'f'}++;
      if ($language eq 'de')
        {
          $extra_message .= $proposal . 'Vorschlag</span> (der nur bei manchen Lemmas sinnvoll ist): Dieser Artikel enthält keinen Link zum Wiktionary, siehe beispielsweise ' . a ({href => 'http://de.wikipedia.org/wiki/Kunst#Weblinks'}, 'Kunst#Weblinks') . '. ' . a ({href => 'http://de.wiktionary.org/wiki/Spezial:Suche?search=' . $::search_lemma . '&go=Seite'}, 'Prüfen, ob es einen Wiktionaryeintrag zu ' . $::search_lemma . ' gibt') . ".\n"; }
    }
  # Check for "{{commons".
  if ($page !~ /(\{\{commons(cat)?(\|)?)|({{commons}})/i)
    {
      $count_letters {'g'}++;

      if ($language eq 'de')
        {
          my $eng_message = $page =~ /^\[\[en:(.+?)\]\]/m ? '(' . a ({href => 'http://commons.wikimedia.org/wiki/Special:Search?search=' . $1 . '&go=Seite'}, $1) . ') ' : '';

          $extra_message .= $proposal . 'Vorschlag</span> (der nur bei manchen Lemmas sinnvoll ist): Dieser Artikel enthält keinen Link zu den Wikimedia Commons, bei manchen Artikeln ist dies informativ (beispielsweise Künstler, Pflanzen, Tiere und Orte), siehe beispielsweise ' . a ({href => 'http://de.wikipedia.org/wiki/Wespe#Weblinks'}, 'Wespe#Weblinks') . '. Um zu schauen, ob es auf den Commons entsprechendes Material gibt, kann man einfach schauen, ob es in den anderssprachigen Versionen dieses Artikels einen Link gibt, oder selbst auf den Commons nach ' . a ({href => 'http://commons.wikimedia.org/wiki/Special:Search?search=' . $::search_lemma . '&go=Seite'}, $::search_lemma) . ' suchen (eventuell unter dem englischen Begriff ' . $eng_message . ' oder dem lateinischen bei Tieren und Pflanzen). Siehe auch ' . a ({href => 'http://de.wikipedia.org/wiki/Wikipedia:Wikimedia_Commons#In_Artikeln_auf_Bildergalerien_hinweisen'}, 'Wikimedia_Commons#In_Artikeln_auf_Bildergalerien_hinweisen') . "\n";
        }
      else
        { $extra_message .= "Proposal: include link to wikimedia commons\n"; }
    }

  # Always propose "whatredirectshere".
  $extra_message .= $proposal . 'Vorschlag</span>: Weiterleitungen/#REDIRECTS zu [[' . $::search_lemma . ']] ' . a ({href => 'http://toolserver.org/~tangotango/whatredirectshere.php?lang=' . $language . '&title=' . $::search_lemma . '&subdom=' . $language . '&domain=.wikipedia.org'}, 'prüfen') . ' mit ' . a ({href => 'http://toolserver.org/~tangotango/whatredirectshere.php'}, 'Whatredirectshere') . "\n";

  # to do
  # -----

  # - List of units.
  # - Quotient 5 for [[Martin Parry]]?
  # - <URI:http://de.wikipedia.org/wiki/Benutzer:Revvar/RT>.
  # - [[Die Weltbühne]].
  # - review_letters sqrt ().
  # - "BRACKET2" not in quotes.
  # - "“Die Philosophie“".
  # - Look at physics and biology.
  # - JavaScript guru for:
  #   - Jump by click to the correct position, and back:
  #     - TML,
  #     - > 5 weblinks,
  #     - EM,
  #     - LiST,
  #     - WORD,
  #     - FILLWORD,
  #     - ABBR,
  #     - LC,
  #     - plenk/klemp,
  #     - CMS,
  #     - unformatted weblink,
  #     - weblink outside of "== Weblinks ==",
  #     - short paragraph and
  #     - long sentence.
  #   - Adjust by checkbox:
  #     - LTN on/off,
  #     - BOLD section title and
  #     - NBSP.
  #   - Per dropdown:
  #     - Choose disambiguation pages and
  #     - BOLD -> italic off (or jump there).
  # - Icing on the cake:
  #   - Use better parser (cf. <URI:http://www.mediawiki.org/wiki/Alternative_parsers>),
  #   - EM, WORDS, AVOID, ABBR after remove_stuff_for_typo_check (),
  #   - "25€" separate and "&nbsp;" in between,
  #   - "§12 §§12 §12 ff." separate and "&nbsp;" in between,
  #   - enumerations not as long sentences (cf. [[Systematik der Schlangen]]),
  #   - treat "list" and "systematik" differently,
  #   - bark at second bold text at [[DBAG Baureihe 226]],
  #   - if a text in brackets is marked up as a whole, the brackets are marked up the same way: "''(und nicht anders!).''" The same goes for punctuation marks. If they are contained in or follow immediately italic or bold set text, they are marked up italic or bold as well: "Es ist ''heiß!''".
  #   - "&nbsp;" in abbreviations,
  #   - spaces preceding "<ref>" are bad (cf. [[Hilfe:Einzelnachweise#Gebrauch von Leerzeichen]]),
  #   - rename section titles like "Links", "Webseiten", "Websites", etc. to "Weblinks" for a uniform style of all articles,
  #   - anchor every line ("<a name=…"),
  #   - show configuration,
  #   - bookmarklet,
  #   - propose format for "§"s,
  #   - bark at wrong date formats,
  #   - dispose of all "<ref>" code, is no longer needed due to remove_refs () and
  #   - "z.B." -> "z.&nbsp;B.".

  # Featured articles in German Wikipedia have one fillword per 146 words, so I consider 1/$fillwords_per_words okay and only raise the review-level above this.
  my $fillwords_ok = $num_words / $fillwords_per_words;

  if ($count_fillwords > $fillwords_ok)
    { $review_level += ($count_fillwords - $fillwords_ok) / 2; }
  $count_letters {'r'} += $longest_sentence;

  # Round $review_level.
  my $review_level = int (($review_level + 0.5) * 100) / 100;
  # Calculate quotient and round.
  my $quotient = int (($review_level / $num_words * 1000 + 0.5) * 100) / 100 - 0.5;

  # Restore exclamation marks.
  $page =~ s/&iexcl;/!/g;

  $page         = restore_stuff_to_ignore ($page,         1);
  $new_page_org = restore_stuff_to_ignore ($new_page_org, 0);

  use Data::Dumper;

  return ($page, $review_level, $num_words, $extra_message, $quotient, join ('', map { $_ x $count_letters {$_}; } (sort (keys (%count_letters)))), $new_page_org, $removed_links, $count_ref, $count_fillwords);
}

sub read_files ($)
{
  my ($language) = @_;

  die "Language missing\n" unless (defined ($language));

  my $LangDataDir = $ENV {'HOME'} . '/share/langdata';

  if ($language eq 'de')
    {
      # Open database.
      $DB = DBI->connect ('dbi:SQLite:dbname=' . $LangDataDir . '/de/cache.db', '', '') or die (DBI->errstr ());
      $DB->{PrintError} = 0;
      $DB->{unicode}    = 1;

      # Words to avoid.
      open (WORDS, '<:encoding(UTF-8)', $LangDataDir . '/de/avoid_words.txt') || die ("Can't open de/avoid_words.txt: $!\n");
      while (<WORDS>)
        {
          chomp ();
          push (@avoid_words, qr/(\b$_\b)/);
        }
      close (WORDS);

      # Fill words ("aber", "auch", "nun", "dann", "doch", "wohl", "allerdings", "eigentlich", "jeweils").
      open (FILLWORDS, '<:encoding(UTF-8)', $LangDataDir . '/de/fill_words.txt') || die ("Can't open de/fill_words.txt: $!\n");
      while (<FILLWORDS>)
        {
          chomp ();
          push (@fill_words, qr/(\b$_\b)/);
        }
      close (FILLWORDS);

      # Abbreviations.
      open (ABBR, '<:encoding(UTF-8)', $LangDataDir . '/de/abbreviations.txt') || die ("Can't open de/abbreviations.txt: $!\n");
      while (<ABBR>)
        {
          chomp ();
          s/\./\\\./g;
          push (@abbreviations, qr/(\b$_)/);
        }
      close (ABBR);

      # Typos.
      open (TYPO, '<:encoding(UTF-8)', $LangDataDir . '/de/typos.txt') || die ("Can't open de/typos.txt: $!\n");
      while (<TYPO>)
        {
          chomp ();

          # It's far faster to search for /tree/ and /Tree/ than /tree/i so …
          my $typo = lc ($_);

          # Ignore case only in first letter to speed up search (that's factor 5 to complete /i!).
          $typo =~ s/^(.)/\(?i\)$1\(?-i\)/;
          push (@is_typo, qr/(?<![-\*])\b($typo)\b/);
        }
      close(TYPO);
    }
  elsif ($language eq 'en')
    {
      # Words to avoid.
      open (WORDS, '<:encoding(UTF-8)', $LangDataDir . '/en/avoid_words.txt') || die ("Can't open en/avoid_words.txt: $!\n");
      while (<WORDS>)
        {
          chomp ();
          push (@avoid_words, qr/(\b$_\b)/);
        }
      close (WORDS);
    }
}

sub remove_year_and_date_links ($$)
{
  my ($line, $remove_century) = @_;
  my ($count_removed);

  # [[1234]] or [[345 v. Chr.]].
  $count_removed += $line =~ s/\[\[(\d{3,4}( [nv]\. Chr\.)?)\]\]/$1/go;

  # [[1234|34]].
  $count_removed += $line =~ s/\[\[(\d{3,4}( [nv]\. Chr\.)?\|)(\d\d)(\]\])/$3/go;

  # Links to days [[12. April]].
  $count_removed += $line =~ s/\[\[(\d{1,2}\. $_)\]\]/$1/g foreach (@months);

  if ($remove_century)
    {
      $count_removed += $line =~ s/\[\[(\d{1,2}\. Jahrhundert( [nv]\. Chr\.)?)\]\]/$1/go;

      # Links to months [[April]].
      $count_removed += $line =~ s/\[\[($_)\]\]/$1/g foreach (@months);

      # Do [[1960er]] or [[1960er|60er]].
      $count_removed += $line =~ s/\[\[(\d{1,4}er)(\|[^\]]*?)?]\]\]?/$1/go;

      # Do [[1960er Jahre]].
      $count_removed += $line =~ s/\[\[(\d{1,4}er Jahre)[\]\|]\]?/$1/go;
    }

  return ($line, $count_removed);
}

sub tag_dates_first_line ($)   # This function is for the first line only!
{
  my ($line) = @_;
  my ($times);

  # This subroutine is buggy, this works:
  # "Larry Wall (* [[27. September]] [[1954]] ; † [[30. April]] [[2145]] ) blub [[3. Mai]] blub [[1977]]",
  # this doesn't work:
  # "Larry Wall (* [[27. September]] [[1954]] ; † [[30. April]] [[2145]] ) blub [[3. Mai]] [[1977]]".

  # Replace years except birth and death = "r]] [[1234]]" or "* [[1971]]" or " † [[2012]]".
  $times                = $line =~ s/(?<!(\w\]\]| \(\*|. †|; \*) )(\[\[[1-9]\d{0,3}( [nv]\. Chr\.)?\]\])/$seldom$2<\/span><sup class="reference"><a href="#links_to_numbers">[LTN?]<\/a><\/sup>/g;
  $review_level        += $times * $seldom_level;
  $count_letters {'K'} += $times;

  # "[[1878|78]]".
  $times                = $line =~ s/(\[\[[1-9]\d{0,3}( [nv]\. Chr\.)?\|)(\d\d)(\]\])/$seldom$3<\/span><sup class="reference"><a href="#links_to_numbers">[LTN?]<\/a><\/sup>/g;
  $review_level        += $times * $seldom_level;
  $count_letters {'K'} += $times;

  # Replace days ("[[3. April]]") except birth and death.
  foreach my $month (@months)
    {
      $times                = $line =~ s/(?<!(\*|†) )(\[\[(\d{1,2}\. )?$month\]\])/$seldom$2<\/span><sup class="reference"><a href="#links_to_numbers">[LTN?]<\/a><\/sup>/g;
      $review_level        += $times * $seldom_level;
      $count_letters {'L'} += $times;
    }

  return $line;
}

sub tag_dates_rest_line ($)
{
  my ($line) = @_;
  my $times;

  # Links to dates.
  # Do [[2005]].
  $times                = $line =~ s/(\[\[[1-9]\d{0,3}(?: [nv]\. Chr\.)?\]\])/$seldom$1<\/span><sup class="reference"><a href="#links_to_numbers">[LTN?]<\/a><\/sup>/g;
  $review_level        += $times * $seldom_level;
  $count_letters {'K'} += $times;

  # [[1878|78]].
  $times                = $line =~ s/(\[\[[1-9]\d{0,3}(?: [nv]\. Chr\.)?\|\d\d\]\])/$seldom$1<\/span><sup class="reference"><a href="#links_to_numbers">[LTN?]<\/a><\/sup>/g;
  $review_level        += $times * $seldom_level;
  $count_letters {'K'} += $times;

  # Do [[17. Jahrhundert]] or [[17. Jahrhundert|whatever]].
  $times                = $line =~ s/(\[\[\d{1,2}\. Jahrhundert( [nv]\. Chr\.)?[\]\|]\]?)/$sometimes$1<\/span><sup class="reference"><a href="#links_to_numbers">[LTN?]<\/a><\/sup>/g;
  $review_level        += $times * $sometimes_level;
  $count_letters {'U'} += $times;

  # Do [[1960er]] or [[1960er|60er]].
  $times                = $line =~ s/(\[\[\d{1,4}er[\]\|]\]?)/$sometimes$1<\/span><sup class="reference"><a href="#links_to_numbers">[LTN?]<\/a><\/sup>/g;
  $review_level        += $times * $sometimes_level;
  $count_letters {'V'} += $times;

  # Do [[1960er Jahre]].
  $times                = $line =~ s/(\[\[\d{1,4}er Jahre[\]\|]\]?)/$sometimes$1<\/span><sup class="reference"><a href="#links_to_numbers">[LTN?]<\/a><\/sup>/g;
  $review_level        += $times * $sometimes_level;
  $count_letters {'V'} += $times;

  # Links to days.
  foreach my $month (@months)
    {
      # Do [[12. Mai]] or [[12. Mai|…]].
      $times                = $line =~ s/(\[\[\d{1,2}\. $month[\]\|]\]?)/$seldom$1<\/span><sup class="reference"><a href="#links_to_numbers">[LTN?]<\/a><\/sup>/g;
      $review_level        += $times * $seldom_level;
      $count_letters {'L'} += $times;

      # Do [[Mai]] or [[Mai|…]].
      $times                = $line =~ s/(\[\[$month[\]\|]\]?)/$sometimes$1<\/span><sup class="reference"><a href="#links_to_numbers">[LTN?]<\/a><\/sup>/g;
      $review_level        += $times * $sometimes_level;
      $count_letters {'W'} += $times;
    }

  return $line;
}

sub create_edit_link ($$)
{
  my ($lemma, $lang) = @_;

  my $u = new URI ('http://' . $lang . '.wikipedia.org/w/index.php') or die ('Cannot construct Wikipedia link.');;
  $u->query_form ({'title' => $lemma, 'action' => 'edit'});

  return $u->canonical ()->as_string ();
}

sub create_ar_link ($$$$)
{
  my ($lemma, $lang, $oldid, $do_typo_check) = @_;

  my $u = new URI ($tool_path) or die ('Cannot construct wikilint link.');
  $u->query_form ({'lemma' => $lemma, 'l' => $lang, defined ($oldid) ? ('oldid' => $oldid) : (), $do_typo_check ? ('do_typo_check' => 'ON') : ()});

  return $u->canonical ()->as_string ();
}

# Inside "<math>", "<code>", etc. everything can be removed
# before review and restored afterwards.
sub remove_stuff_to_ignore ($)
{
  my ($page) = @_;
  my $lola = 0;

  undef %replaced_stuff;

  # Mark lines containing "<!--sic-->" for ignoring typos later.
  while ($page =~ s/(<!--\s*sic\s*-->)/-R-R-SIC$lola-R-/is)
    { $replaced_stuff {$lola++} = $1; }

  # "<!-- -->", "<blockquote>", "<code>", "<math>", "<nowiki>", "poem", "{{Lückenhaft}}" and "{{Quelle}}".
  while ($page =~ s/(<!--.+?-->|<(blockquote|code|math|nowiki|poem)>.*?<\/\2>|\{\{(?:Lückenhaft|Quelle)[^}]*?\}\})/-R-R$lola-R-/is)
    { $replaced_stuff {$lola++} = $1; }

  return ($page, $lola);
}

sub restore_stuff_to_ignore ($$)
{
  my ($page, $substitute_tags) = @_;
  my %replaced_stuff_tmp = %replaced_stuff;

  while (%replaced_stuff_tmp)
    {
      foreach my $lola (keys (%replaced_stuff_tmp))
        {
          # Before restoring the text, replace the "<>".
          my $restore = $replaced_stuff_tmp {$lola};
          if ($substitute_tags)
            {
              $restore =~ s/</&lt;/go;
              $restore =~ s/>/&gt;/go;
            }

          delete ($replaced_stuff_tmp {$lola}) unless ($page =~ s/-R-R(-SIC|-G)?$lola-R-/$restore/);
        }
    }

  my $times2 = 0;
  my $total  = 0;
  my $todo   = keys (%remove_stuff_for_typo_check_array);

  do
    {
      $times2  = $page =~ s/-R-I(-G)?(\d+)-R-.*?-R-/restore_one_item ($2, \%remove_refs_and_images_array, $substitute_tags)/egs;
      $total  += $times2;
    }
  until (!$times2 || $total == $todo);

  return $page;
}

sub restore_stuff_quote ($)
{
  # Restoring is a bit tricky because the removed stuff might be nested, e. g.
  # a removed comment inside a quote, so it has to be repeated until everything is restored.
  my ($page) = @_;
  my $times2;
  my $total = 0;
  my $todo = keys (%remove_stuff_for_typo_check_array);

  do
    {
      $times2  = $page =~ s/-R-N(\d+)-R-.*?-R-/restore_one_item ($1, \%remove_stuff_for_typo_check_array, 0)/egs;
      $total  += $times2;
    }
  until (!$times2 || $total == $todo);

  $page =~ s/Q-REP/'/g;

  return $page;
}

sub check_unformatted_refs ($\$)
{
  my ($page, $extra_message) = @_;
  my $last_word = '';

  foreach my $word (split (/\s/, $page))
    {
      if ($last_word !~ /^URL:/i &&
          $word      !~ /{{\w+?\|[^}]*https?:\/\// &&
          $last_word !~ /url=/i &&
          $word      !~ /url=/i &&
          # Unformatted weblink: "http://rupp.de".
          ($word =~ /(https?:\/\/.+)/ && $word !~ /(\[https?:\/\/.+)/) ||
          # Unformatted weblink: "[http://rupp.de]".
          $word  =~ /(\[https?:\/\/[^\s]+?\])/)
        {
          my $weblink = $1;
  
          if ($::language eq 'de')
            { ${$extra_message} .= $seldom . 'Unformatierter Weblink: </span>' . $weblink . ' – Siehe ' . a ({href => 'http://de.wikipedia.org/wiki/WP:WEB#Formatierung'}, 'WP:WEB#Formatierung') . br () . "\n"; }
          $review_level += $seldom_level;
          $count_letters {'X'}++;
        }
      $last_word = $word;
    }
}

sub remove_stuff_for_typo_check ($)
{
  # Remove lines with "<!--sic-->" and "{{templates…}}" and quotes, web and wikilinks.
  my ($page) = @_;

  $lola = 0;

  # Remove complete_line with "<!--sic-->" marked earlier in remove_stuff ()
  $page =~ s/^(.*-R-R-SIC\d+-R-.*)$/remove_one_item ($1, '-R-N', \%remove_stuff_for_typo_check_array)/egim;

  # Any template like "{{Zitat}}".
  $page =~ s/({{\w.{4,}?}})/remove_one_item ($1, '-R-N', \%remove_stuff_for_typo_check_array)/egis;

  # Quotes.
  my $page_new = '';

  foreach my $line_copy (split (/\n/, $page))
    {
      # Only replace quotes with three or more letters.
      # Remove single ' to be able to use [^'] in next line.
      $line_copy =~ s/(?<!')'(?!')/Q-REP/g;
      $line_copy =~ s/((?<!')''([^']{3,}?)''(?!'))/remove_one_item ($1, '-R-N', \%remove_stuff_for_typo_check_array)/eg;
      $line_copy =~ s/Q-REP/'/g;

      # Also does ''quote 'blub' quote on''?
      $line_copy =~ s/(\"([^"]{3,}?)\")/remove_one_item ($1, '-R-N', \%remove_stuff_for_typo_check_array)/eg;
      $line_copy =~ s/(&lt;i&gt;(.{3,}?)&lt;\/i&gt;)/remove_one_item ($1, '-R-N', \%remove_stuff_for_typo_check_array)/eg;
      $line_copy =~ s/(„([^“]{3,}?)“)/remove_one_item ($1, '-R-N', \%remove_stuff_for_typo_check_array)/eg;
      $line_copy =~ s/(«([^»]{3,}?)»)/remove_one_item ($1, '-R-N', \%remove_stuff_for_typo_check_array)/eg;
      $line_copy =~ s/(‚([^‘]{3,}?)‘)/remove_one_item ($1, '-R-N', \%remove_stuff_for_typo_check_array)/eg;
      $line_copy =~ s/(&lt;sic&gt;(.{3,}?)&lt;\/sic&gt;)/remove_one_item ($1, '-R-N', \%remove_stuff_for_typo_check_array)/egi;

      $page_new .= $line_copy . "\n";
    }
  $page = $page_new;

  # Any "[[]]" wikilink.
  $page =~ s/(\[\[[^\]]{1,150}?\]\])/remove_one_item ($1, '-R-N', \%remove_stuff_for_typo_check_array)/eg;

  # Any "[]" weblink.
  $page =~ s/(\[http.+?\])/remove_one_item ($1, '-R-N', \%remove_stuff_for_typo_check_array)/eg;

  return ($page, $lola);
}

sub remove_refs_and_images ($$)
{
  my ($page, $lola) = @_;
  my ($count_ref_backup, $count_ref_return, $times);
  my ($global_removed_count_backup, $global_removed_count_return);

  $global_removed_count_backup = $global_removed_count;
  $global_removed_count        = 0;
  $count_ref_backup            = $count_ref;
  undef $count_ref;

  # Lines with leading blank.
  # "(?!\|)" to avoid removing lines in table with leading blank like " | blub = blab".
  $page =~ s/^( (?!\|).+)$/remove_one_item ($1, '-R-I', \%remove_refs_and_images_array, 1)/egim;

  # "<ref></ref>".
  # This one isn't perfect: "[^<]" because it prevents "<ref> haha <- like this </ref>" but still
  # better than expanding an open "<ref name=cc>" over the whole page.
  $page =~ s/(<ref(>| +name ?= ?)[^<]+?<\/ref>)/remove_one_item ($1, '-R-I', \%remove_refs_and_images_array, 1)/egis;

  # The "(…)*" is for links inside the picture description,
  # like "[[Image:bild.jpg|This is a [[tree]] genau]]", the
  # "([^][]*?)" is for images with links in it.
  $page =~ s/(\[\[(Bild:|Datei:|File:|Image:)[^][]+(?:\[\[[^][]*\]\][^][]*)*[^][]*\]\])/remove_one_item ($1, '-R-I', \%remove_refs_and_images_array, 1)/egis;

  # "<gallery> … </gallery>".
  # "<gallery widths="200" heights =…></gallery>".
  $page =~ s/(<gallery.*?>.+?<\/gallery>)/remove_one_item ($1, '-R-I-G', \%remove_refs_and_images_array, 1)/egis;

  $count_ref_return            = $count_ref;
  $count_ref                   = $count_ref_backup;
  $global_removed_count_return = $global_removed_count;
  $global_removed_count        = $global_removed_count_backup;

  return ($page, $global_removed_count_return, $count_ref_return);
}

sub create_review_summary_html ($$)
{
  my ($review_letters, $language) = @_;
  my $table = '';

  my %count_letters;
  foreach my $letter (split (//, $review_letters))
    { $count_letters {$letter}++; }

  foreach my $letter (split (//, $table_order))
    {
      my ($level, $summary, $message) = split(/\|/, $text {$language . '|' . $letter});

      # Treat fill words differently.
      if ($letter eq 'C')
        { $table .= Tr (td ({bgcolor => $farbe_html {$level}}, $message) . td ('Siehe' . br () . 'unten')); }
      else
        {
          my $secondcell;
          if ($count_letters {$letter} && $level eq '0')
            { $secondcell = td ({bgcolor => 'yellow'}, $count_letters {$letter}); }
          elsif ($count_letters {$letter})
            { $secondcell = td ($count_letters {$letter}); }
          else
            { $secondcell = td ({bgcolor => 'lime'}, 'OK'); }
          $table .= Tr (td ($level ? {bgcolor => $farbe_html {$level}} : {}, $message) . $secondcell);
        }
    }

  print h3 ('Zusammenfassung');
  print table ({border => 1}, Tr (th ('Prüfung') . th ('Ergebnis')) . $table);
}

sub selftest ($$)   # Check if reviewing test.html gave the right results indicated by GOOD vs. BAD vs. EVIL (= bad in comments).
{
  my ($page, $extra_messages) = @_;
  my (%found_evil_messages, %found_evil_text);

  foreach my $line (split (/\n/, $page))
    {
      print 'MISSED REPLACEMENT: ' . $line . br () . "\n" if ($line =~ /-R-.+?\d+-R-/);

      if ($line =~ /bad/i || $line =~ /mixed/i)
        {
          if ($line !~ /</)
            { print 'MISSING TAG: ', $line, br (); }
        }
      elsif ($line =~ /good/i)
        {
          if ($line =~ /</)
            { print 'FALSE POSITIVE: ', $line, br (); }
        }
      elsif ($line =~ /evil/i)
        { print 'COMMENT: ', $line, br (); }
      else   # Don't care.
        { }

      $found_evil_text {$1}++ if ($line =~ /evil(\d+)/i)   # Count to check all were found.
    }

  foreach my $line (split (/\n/, $extra_messages))
    {
      if ($line =~ /saint/i)
        { print 'MESG FALSE POSITIVE: ', $line, br (); }
      elsif ($line =~ /evil(\d+)/i)   # Count to check all were found.
        { $found_evil_messages {$1}++; }
      else
        {
          if ($line !~ /Mehr als 5 Weblinks/ &&
              $line !~ /Mehr als 5 Links bei "Siehe auch/ &&
              $line !~ /keinen Link zum Wiktionary/ &&
              $line !~ / #REDIRECTS zu/)
            { print 'MESG FALSE POSITIVE: ', $line, br (); }
        }
    }

  foreach my $evil (keys %found_evil_text)
    { print 'MISSING MESG: ', $evil, "\n" unless ($found_evil_messages {$evil}); }
}

sub restore_quotes ($)
{
  my ($line) = @_;

  $line =~ s/￼QSS.?%(.*?)￼QES.?%/''$1''/go;
  $line =~ s/￼QSD%(.*?)￼QED%/\"$1\"/go;
  $line =~ s/￼QST%(.*?)￼QET%/&lt;i&gt;$1&lt\/i&gt;/go;
  $line =~ s/￼QSL%(.*?)￼QEL%/„$1“/go;
  $line =~ s/￼QSF%(.*?)￼QEF%/«$1»/go;
  $line =~ s/￼QSX%(.*?)￼QEX%/‚$1‘/go;
  $line =~ s/￼QSC%(.*?)￼QEC%/&lt;sic&gt;$1&lt\/sic&gt;/go;

  return $line;
}

sub remove_one_item ($$\%;$)
{
  my ($item, $prefix, $ref_to_replaced_stuff_quote, $do_count_ref) = @_;

  $global_removed_count++;

  ${$ref_to_replaced_stuff_quote} {$global_removed_count} = $item;

  $count_ref++ if ($do_count_ref && $item =~ /<\/ref>/i);

  # This is to keep $line and $line_org_wiki in do_review () in sync, not allowed to remove lines from page!
  my $append_newlines = "\n" x ($item =~ tr/\n//);

  return $prefix . $global_removed_count . '-R-' . $append_newlines . '-R-';
}

sub restore_one_item ($\%$)
{
  my ($lola, $ref_to_replaced_stuff_quote, $substitute_tags) = @_;

  my $return = ${$ref_to_replaced_stuff_quote} {$lola};
  if ($substitute_tags)
    {
      $return =~ s/</&lt;/g;
      $return =~ s/>/&gt;/g;
    }

  return $return;
}

1;
