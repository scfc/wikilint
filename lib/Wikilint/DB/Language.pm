#!/usr/bin/perl -w

package Wikilint::DB::Language;

use base 'Exporter';
use strict;
use utf8;
use warnings;

use DBI;

=head1 NAME

Wikilint::DB::Language - Object interface to Wikipedia
language-specific data

=head1 SYNOPSIS

    use Wikilint::DB::Language;

    $l = new Wikilint::DB::Language ('de');

=head1 DESCRIPTION

C<Wikilint::DB::Language> provides an object interface to
Wikipedia language-specific data for wikilint. It is used
primarily by L<Wikilint::DB>.

=head1 CONSTRUCTOR

=over 4

=item new (LANGUAGE)

Creates a new object that reads the language-specific files
and connects to the corresponding database.

=back

=cut

sub new
{
  my $class = shift;
  my $self  = {};
  my $F;

  $self->{'Language'} = shift;
  die ("Language missing\n") unless (defined ($self->{'Language'}));
  die ("Unknown language: " . $self->{'Language'} . "\n") unless ($self->{'Language'} eq 'de' || $self->{'Language'} eq 'en');

  my $LangDataDir = $ENV {'HOME'} . '/share/langdata/' . $self->{'Language'};

  # Open database.
  if (defined ($self->{'DB'} = DBI->connect ('dbi:SQLite:dbname=' . $LangDataDir . '/cache.db', '', '')))
    {
      $self->{'DB'}->{PrintError}        = 0;
      $self->{'DB'}->{unicode}           = 1;
      $self->{'DisambiguationStatement'} = $self->{'DB'}->prepare ('SELECT 1 FROM DisambiguationPages WHERE Title = ?;') or die ($self->{'DB'}->errstr ());
      $self->{'RedirectionsStatement'}   = $self->{'DB'}->prepare ('SELECT FromTitle FROM Redirects WHERE ToTitle = ?;') or die ($self->{'DB'}->errstr ());
    }

  # Words to avoid.
  $self->{'AvoidWords'} = [];
  if (open ($F, '<:encoding(UTF-8)', $LangDataDir . '/avoid_words.txt'))
    {
      while (<$F>)
        {
          chomp ();
          push (@{$self->{'AvoidWords'}}, qr/(\b$_\b)/);
        }
      close ($F);
    }

  # Fill words ("aber", "auch", "nun", "dann", "doch", "wohl", "allerdings", "eigentlich", "jeweils").
  $self->{'FillWords'} = [];
  if (open ($F, '<:encoding(UTF-8)', $LangDataDir . '/fill_words.txt'))
    {
      while (<$F>)
        {
          chomp ();
          push (@{$self->{'FillWords'}}, qr/(\b$_\b)/);
        }
      close ($F);
    }

  # Abbreviations.
  $self->{'Abbreviations'} = [];
  if (open ($F, '<:encoding(UTF-8)', $LangDataDir . '/abbreviations.txt'))
    {
      while (<$F>)
        {
          chomp ();
          s/\./\\\./g;
          push (@{$self->{'Abbreviations'}}, qr/(\b$_)/);
        }
      close ($F);
    }

  # Typos.
  $self->{'Typos'} = [];
  if (open ($F, '<:encoding(UTF-8)', $LangDataDir . '/typos.txt'))
    {
      while (<$F>)
        {
          chomp ();

          # It's far faster to search for /tree/ and /Tree/ than /tree/i so …
          my $typo = lc ($_);

          # Ignore case only in first letter to speed up search (that's factor 5 to complete /i!).
          $typo =~ s/^(.)/\(?i\)$1\(?-i\)/;
          push (@{$self->{'Typos'}}, qr/(?<![-\*])\b($typo)\b/);
        }
      close ($F);
    }

  return bless ($self, $class);
}

=head1 METHODS

=over 4

=item GetAbbreviations ()

Returns the list of abbreviations for this language.

=cut

sub GetAbbreviations
{
  my $self = shift;

  return @{$self->{'Abbreviations'}};
}

=item GetAvoidWords ()

Returns the list of words to avoid for this language.

=cut

sub GetAvoidWords
{
  my $self = shift;

  return @{$self->{'AvoidWords'}};
}

=item GetFillWords ()

Returns the list of filler words for this language.

=cut

sub GetFillWords
{
  my $self = shift;

  return @{$self->{'FillWords'}};
}

=item GetRedirects (TITLE)

Returns the list of redirects for this language that point
to TITLE.

=cut

sub GetRedirects
{
  my $self    = shift;
  my ($Title) = @_;
  my @Result  = ();
  my $FromTitle;

  return @{$self->{'DB'}->selectcol_arrayref ($self->{'RedirectionsStatement'}, {}, $Title)};
}

=item GetTypos ()

Returns the list of typos for this language.

=cut

sub GetTypos
{
  my $self = shift;

  return @{$self->{'Typos'}};
}

=item IsDisambiguation (TITLE)

Checks whether TITLE refers to a disambiguation page in this
language.

=cut

sub IsDisambiguation
{
  my $self    = shift;
  my ($Title) = @_;

  $self->{'DisambiguationStatement'}->execute ($Title) or die ($self->{'DB'}->errstr ());

  return $self->{'DisambiguationStatement'}->fetch ();
}

=item DESTROY

Closes the database connection if it was open.

=back

=cut

sub DESTROY
{
  my $self = shift;

  if (defined ($self->{'DB'}))   # Close database if necessary.
    { $self->{'DB'}->disconnect (); }
}

=head1 SEE ALSO

L<Wikilint::DB>

=head1 AUTHOR

Tim Landscheidt E<lt>tim@tim-landscheidt.deE<gt>

=cut

1;
