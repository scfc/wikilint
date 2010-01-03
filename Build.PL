#!/usr/bin/perl -w

use strict;
use utf8;
use warnings;

use App::Build;

# lib/langdata/de/disambs.txt:
#   mysql -e "SELECT REPLACE(page_title, '_', ' ') FROM categorylinks JOIN page ON cl_from = page_id WHERE cl_to = 'Begriffsklärung' AND page_namespace = 0 UNION SELECT REPLACE(p2.page_title, '_', ' ') FROM categorylinks JOIN page AS p1 ON cl_from = p1.page_id JOIN redirect ON rd_namespace = p1.page_namespace AND rd_title = p1.page_title JOIN page AS p2 ON rd_from = p2.page_id WHERE cl_to = 'Begriffsklärung';" dewiki_p | tail -n +2 | sort > lib/langdata/de/disambs.txt
# lib/langdata/de/redirs.txt:
#   mysql -e "SELECT REPLACE(page_title, '_', ' '), REPLACE(rd_title, '_', ' ') FROM page JOIN redirect ON page_id = rd_from WHERE page_namespace = 0 AND rd_namespace = 0;" dewiki_p | tail -n +2 | sort > lib/langdata/de/redirs.txt

my $class = App::Build->subclass (code => 'sub process_langdata_files
{
  my $self = shift;

  use DBI;

  foreach my $f (@{$self->rscan_dir ("share/langdata", qr/\.txt$/)})
    { $self->copy_if_modified ("from" => $f, "to" => "blib/" . $f) unless ($f =~ /\/(?:disambs|redirs)\.txt$/); }

  if (!$self->up_to_date (["share/langdata/de/disambs.txt", "share/langdata/de/redirs.txt"], ["blib/share/langdata/de/cache.db"]))
    {
      # Set up database.
      my $DB = DBI->connect ("dbi:SQLite:dbname=blib/share/langdata/de/cache.db", "", "", {AutoCommit => 0, PrintError => 0, unicode => 1}) or die (DBI->errstr ());

      # $DB->begin_work () or die ($DB->errstr ());

      if (!defined ($DB->do ("DELETE FROM DisambiguationPages;"))                                   &&
          !defined ($DB->do ("CREATE TABLE DisambiguationPages (Title VARCHAR(255) PRIMARY KEY);")))
        { die ($DB->errstr ()); }

      if (!defined ($DB->do ("DELETE FROM Redirects;"))                                                                        &&
          !(defined ($DB->do ("CREATE TABLE Redirects (FromTitle VARCHAR(255) PRIMARY KEY, ToTitle VARCHAR(255) NOT NULL);")) &&
            defined ($DB->do ("CREATE INDEX Redirects_ToTitle_Index ON Redirects (ToTitle);"))))
        { die ($DB->errstr ()); }

      # Disambiguation pages.
      open (DISAMBS, "<:encoding(UTF-8)", "share/langdata/de/disambs.txt") or die ($!);
      my $s = $DB->prepare ("INSERT INTO DisambiguationPages (Title) VALUES (?);") or die ($DB->errstr ());
      $s->execute ("#" . (stat (DISAMBS)) [9]) or die ($DB->errstr ());
      while (<DISAMBS>)
        {
          chomp ();
          $s->execute ($_) or die ($DB->errstr ());
        }
      close (DISAMBS);

      # Redirects.
      open (REDIRECTS, "<:encoding(UTF-8)", "share/langdata/de/redirs.txt") or die ($!);
      $s = $DB->prepare ("INSERT INTO Redirects (FromTitle, ToTitle) VALUES (?, ?);") or die ($DB->errstr ());
      $s->execute ("#", (stat (REDIRECTS)) [9]) or die ($DB->errstr ());
      while (<REDIRECTS>)
        {
          /^([^\t]+)\t([^\t]+)\n/ or die;
          $s->execute ($1, $2) or die ($DB->errstr ());
        }
      close (REDIRECTS);

      # Close database.
      $DB->commit () or die ($DB->errstr ());
      $DB->disconnect ();
    }
}');

my $build = $class->new (dist_name         => 'wikilint',
                         dist_version_from => 'cgi-bin/wikilint',
                         dist_author       => 'Tim Landscheidt <tim@tim-landscheidt.de>',
                         dist_abstract     => 'A web based service to find errors (like typos and wrong formatting) ' .
                                              'in Wikipedia articles and make proposals how to improve them.',
                         license           => 'gpl',
                         requires          => {'CGI' => 0,
                                               'DBD::SQLite' => 0,
                                               'DBI' => 0,
                                               'HTML::Entities' => 0,
                                               'LWP::UserAgent' => 0,
                                               'URI::Escape' => 0},
                         build_requires    => {'App::Build'     => 0,    # Needed for installing the software.
                                               'DBD::SQLite'    => 0},   # Needed for compiling the cache.
                         extra_dirs        => {'cgi-bin' => {dest_dir => $ENV {'HOME'} . '/public_html/cgi-bin'},
                                               'htdocs'  => {dest_dir => $ENV {'HOME'} . '/public_html/wikilint'}},
                         install_path      => {'lib'     => $ENV {'HOME'} . '/lib',
                                               'libdoc'  => $ENV {'HOME'} . '/man/man3',
                                               'share'   => $ENV {'HOME'} . '/share'},
                         dynamic_config    => 1,
                         create_packlist   => 0);

$build->add_build_element ('langdata');
$build->create_build_script ();

exit;
