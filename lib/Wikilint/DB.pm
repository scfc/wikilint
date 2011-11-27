#!/usr/bin/perl -w

package Wikilint::DB;

use base 'Exporter';
use strict;
use utf8;
use warnings;

use Wikilint::DB::Language;

=head1 NAME

Wikilint::DB - Object interface to Wikipedia data

=head1 SYNOPSIS

    use Wikilint::DB;

    $DB = new Wikilint::DB ();
    @fw = $DB->GetAvoidWords ('en');
    $i = $DB->IsDisambiguation ('de', 'A46');

=head1 DESCRIPTION

C<Wikilint::DB> provides an object interface to Wikipedia
data for wikilint. It is used primarily by L<Wikilint>.

=head1 CONSTRUCTOR

=over 4

=item new ()

Creates a new object.

=back

=cut

sub new
{
  my $class = shift;
  my $self  = {};

  $self->{'Languages'} = {};

  return bless ($self, $class);
}

=head1 METHODS

=over 4

=item GetAbbreviations (LANGUAGE)

Returns the list of abbreviations for LANGUAGE.

=cut

sub GetAbbreviations ($)
{
  my $self = shift;
  my ($Language) = @_;

  $self->{'Languages'}->{$Language} = new Wikilint::DB::Language ($Language) unless (defined ($self->{'Languages'}->{$Language}));

  return $self->{'Languages'}->{$Language}->GetAbbreviations ();
}

=item GetAvoidWords (LANGUAGE)

Returns the list of words to avoid for LANGUAGE.

=cut

sub GetAvoidWords ($)
{
  my $self = shift;
  my ($Language) = @_;

  $self->{'Languages'}->{$Language} = new Wikilint::DB::Language ($Language) unless (defined ($self->{'Languages'}->{$Language}));

  return $self->{'Languages'}->{$Language}->GetAvoidWords ();
}

=item GetFillWords (LANGUAGE)

Returns the list of filler words for LANGUAGE.

=cut

sub GetFillWords ($)
{
  my $self = shift;
  my ($Language) = @_;

  $self->{'Languages'}->{$Language} = new Wikilint::DB::Language ($Language) unless (defined ($self->{'Languages'}->{$Language}));

  return $self->{'Languages'}->{$Language}->GetFillWords ();
}

=item GetRedirects (LANGUAGE, TITLE)

Returns the list of redirects for LANGUAGE that point to
TITLE.

=cut

sub GetRedirects
{
  my $self = shift;
  my ($Language, $Title) = @_;

  $self->{'Languages'}->{$Language} = new Wikilint::DB::Language ($Language) unless (defined ($self->{'Languages'}->{$Language}));

  return $self->{'Languages'}->{$Language}->GetRedirects ($Title);
}

=item GetTypos (LANGUAGE)

Returns the list of typos for LANGUAGE.

=cut

sub GetTypos ($)
{
  my $self = shift;
  my ($Language) = @_;

  $self->{'Languages'}->{$Language} = new Wikilint::DB::Language ($Language) unless (defined ($self->{'Languages'}->{$Language}));

  return $self->{'Languages'}->{$Language}->GetTypos ();
}

=item IsDisambiguation (LANGUAGE, TITLE)

Checks whether TITLE refers to a disambiguation page in
LANGUAGE.

=back

=cut

sub IsDisambiguation ($$)
{
  my $self = shift;
  my ($Language, $Title) = @_;

  $self->{'Languages'}->{$Language} = new Wikilint::DB::Language ($Language) unless (defined ($self->{'Languages'}->{$Language}));

  return $self->{'Languages'}->{$Language}->IsDisambiguation ($Title);
}

=head1 SEE ALSO

L<Wikilint>

=head1 AUTHOR

Tim Landscheidt E<lt>tim@tim-landscheidt.deE<gt>

=cut

1;