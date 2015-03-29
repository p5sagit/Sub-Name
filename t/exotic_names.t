use Test::More;
use warnings;
use strict;

use B 'svref_2object';


my @test_ordinals = ( 1 .. 255 );

# 5.14 is the first perl to start properly handling \0 in identifiers
push @test_ordinals, 0
  unless $] < 5.014;

# This is a mess. Yes, the stash supposedly can handle unicode, yet
# on < 5.16 the behavior is literally undefined (with crashes beyond
# the basic plane), and is still unclear post 5.16 with eval_bytes/eval_utf8
# In any case - Sub::Name needs to *somehow* work with this, so try to
# do the a heuristic with plain eval (grep for `5.016` below)
push @test_ordinals, 0x100, 0x498, 0x2122, 0x1f4a9
  unless $] < 5.008;


plan tests =>
  @test_ordinals * 2
;


for my $ord (@test_ordinals) {

  my $char = chr($ord);

  my $diag_suff = sprintf "when name contains \\x%s ( %s )",
    ( ($ord > 255)
      ? sprintf "{%X}", $ord
      : sprintf "%02X", $ord
    ),
    (
      $ord > 255                    ? unpack('H*', pack 'C0U', $ord )
    : ($ord > 0x1f and $ord < 0x7f) ? sprintf "%c", $ord
    :                                 sprintf '\%o', $ord
    ),
  ;

  my $pkg = sprintf('test::SOME_%c_STASH', $ord);
  my $subname = sprintf('SOME_%c_NAME', $ord);
  my $initial_full_name = $pkg . '::' . $subname;

  my $expected_full_name;

  # special handling of ' == ::
  if ( $char eq "'" ) {
    $pkg = "test::SOME_'_STASH::SOME_";
    $expected_full_name = "test::SOME_::_STASH::SOME_::_NAME"
  }

  my (%tests, $me_via_caller);

  # we can *always* compile at least within the correct package
  $tests{"natively compiled"} = do {
    my $exp = $expected_full_name;

    my $code;

    # compile-able directly
    if ( $char =~ /^[A-Z_a-z0-9']$/ ) {
      $code = "
        no strict 'refs';
        package $pkg;
        sub $initial_full_name { \$me_via_caller = (caller(0))[3] };
        \\&{\$initial_full_name}
      ";
    }
    # at least test the package name
    else {
      no strict 'refs';
      *palatable:: = *{"${pkg}::"};
      $code = "
        package palatable;
        sub foo { \$me_via_caller = (caller(0))[3] };
        \\&foo;
      ";
      $exp = "${pkg}::foo";
    }

    {
      expected_full_name => $exp,
      cref => eval($code) || die $@,
    }
  };


  for my $type (keys %tests) {
    my $t = $tests{$type};

    my $expected = $t->{expected_full_name} || $initial_full_name;

    # this is apparently how things worked before 5.16
    utf8::encode($expected) if $] < 5.016 and $ord > 255;

    my $gv = svref_2object($t->{cref})->GV;

    is (
      $gv->STASH->NAME . '::' . $gv->NAME,
      $expected,
      "$type sub named properly $diag_suff",
    );

    $t->{cref}->();

    is (
      $me_via_caller,
      $expected,
      "caller() works within $type sub $diag_suff",
    );
  }
}
