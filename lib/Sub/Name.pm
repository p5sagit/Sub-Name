package Sub::Name;
# ABSTRACT: (re)name a sub

=pod

=head1 SYNOPSIS

    use Sub::Name;

    subname $name, $subref;

    $subref = subname foo => sub { ... };

=head1 DESCRIPTION

This module has only one function, which is also exported by default:

=for stopwords subname

=head2 subname NAME, CODEREF

Assigns a new name to referenced sub.  If package specification is omitted in
the name, then the current package is used.  The return value is the sub.

The name is only used for informative routines (caller, Carp, etc).  You won't
be able to actually invoke the sub by the given name.  To allow that, you need
to do glob-assignment yourself.

Note that for anonymous closures (subs that reference lexicals declared outside
the sub itself) you can name each instance of the closure differently, which
can be very useful for debugging.

=head1 SEE ALSO

=for :list
* L<Sub::Identify> - for getting information about subs
* L<Sub::Util> - set_subname is another implementation of C<subname>

=for stopwords cPanel

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2004, 2008 by Matthijs van Duin, all rights reserved;
copyright (c) 2014, 2015 cPanel Inc., all rights reserved.

This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

use 5.006;

use strict;
use warnings;

our $VERSION = '0.15';

use Exporter 5.57 'import';

our @EXPORT = qw(subname);
our @EXPORT_OK = @EXPORT;

use XSLoader;
XSLoader::load(
    __PACKAGE__,
    $VERSION,
);

1;
