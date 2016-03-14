use strict;
use warnings;
use Test::More 0.88;

my @NAMES = ("тест", "bar\000more",
             "тест::plain", "bar\000more::plain",
             "main::тест", "main::bar\000more");
plan tests => scalar @NAMES;

use Sub::Name 'subname';
{
  use utf8;
  no strict 'refs';
  for my $pv (@NAMES) {
    my $cv = subname $pv, sub{42};
    is $cv->(), 42;
  }
}
