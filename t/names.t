use strict;
use warnings;

use Test::More;
use B 'svref_2object';

sub caller3_ok {
    my ( $cref, $expected, $ord, $type ) = @_;

    local $Test::Builder::Level = $Test::Builder::Level + 1;

    my $for_what = sprintf "when it contains \\x%s ( %s )", (
        ( ($ord > 255)
            ? sprintf "{%X}", $ord
            : sprintf "%02X", $ord
        ),
        (
            $ord > 255                    ? unpack('H*', pack 'C0U', $ord )
            : ($ord > 0x1f and $ord < 0x7f) ? sprintf "%c", $ord
            :                                 sprintf '\%o', $ord
        ),
    );

    # this is apparently how things worked before 5.16
    utf8::encode($expected) if $] < 5.016 and $ord > 255;

    my $fullname   = svref_2object($cref)->GV->STASH->NAME . "::" . svref_2object($cref)->GV->NAME;

    is $fullname, $expected, "stash name for $type is correct $for_what";
    is $cref->(), $expected, "caller() in $type returns correct name $for_what";
}

#######################################################################

use Sub::Name 'subname';

my @test_ordinals = ( 1 .. 255 );

# 5.14 is the first perl to start properly handling \0 in identifiers
push @test_ordinals, 0
    unless $] < 5.014;

# This is a mess. Yes, the stash supposedly can handle unicode, yet
# on < 5.16 the behavior is literally undefined (with crashes beyond
# the basic plane), and is still unclear post 5.16 with eval_bytes/eval_utf8
# In any case - Sub::Name needs to *somehow* work with this, so try to
# do the a heuristic with plain eval (grep for `5.016` below)
push @test_ordinals,
    0x100,    # LATIN CAPITAL LETTER A WITH MACRON
    0x498,    # CYRILLIC CAPITAL LETTER ZE WITH DESCENDER
    0x2122,   # TRADE MARK SIGN
    0x1f4a9,  # PILE OF POO
    unless $] < 5.008;

plan tests => @test_ordinals * 2 * 2;

for my $ord (@test_ordinals) {
    my $sub;
    my $pkg       = sprintf 'test::SOME_%c_STASH', $ord;
    my $subname   = sprintf 'SOME_%c_NAME', $ord;
    my $full_name = $pkg . '::' . $subname;
    if ($ord == 0x27) {
        $full_name = "test::SOME_::_STASH::SOME_::_NAME";
    }

    $sub = subname $full_name => sub { (caller(0))[3] };
    caller3_ok $sub, $full_name, $ord, 'renamed closure';

    # test that we can *always* compile at least within the correct package
    my $expected;
    if ( chr($ord) =~ /^[A-Z_a-z0-9']$/ ) { # legal identifier char, compile directly
        $expected = $full_name;
        if ( chr($ord) eq "'" ) {  # special-case ' == ::
            $expected =~ s/'/::/g; # gv.c:S_parse_gv_stash_name
            $pkg     .=  "::SOME_";
        }
        $sub = eval( "
            package $pkg;
            sub $full_name { (caller(0))[3] };
            no strict 'refs';
            \\&{\$full_name}
        " ) || die $@;
    }
    else { # not a legal identifier but at least test the package name
        $expected = "${pkg}::foo";
        { no strict 'refs'; *palatable:: = *{"${pkg}::"} }
        $sub = eval( "
            package palatable;
            sub foo { (caller(0))[3] };
            \\&foo;
        " ) || die $@;
    }
    caller3_ok $sub, $expected, $ord, 'natively compiled sub';
}
