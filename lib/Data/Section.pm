use strict;
use warnings;
package Data::Section;
# ABSTRACT: read multiple hunks of data out of your DATA section

use Class::ISA;
use Sub::Exporter 0.979 -setup => {
  groups     => { setup => \'_mk_reader_group' },
  collectors => { INIT => sub { $_[0] = { into => $_[1]->{into} } } },
};

=head1 SYNOPSIS

  package Letter::Resignation;
  use Data::Section -setup;

  sub quit {
    my ($class, $angry, %arg) = @_;

    my $template = $self->section_data(
      ($angry ? "angry_" : "professional_") . "letter"
    );

    return fill_in($$template, \%arg);
  }

  __DATA__
  __[ angry_letter ]__
  Dear jerks,

    I quit!

  -- 
  {{ $name }}
  __[ professional_letter ]__
  Dear {{ $boss }},

    I quit, jerks!


  -- 
  {{ $name }}

=head1 DESCRIPTION

Data::Section provides an easy way to access multiple named chunks of
line-oriented data in your module's DATA section.  It was written to allow
modules to store their own templates, but probably has other uses.

=head1 WARNING

You will need to use C<__DATA__> sections and not C<__END__> sections.  Yes, it
matters.  Who knew!

=head1 EXPORTS

To get the methods exported by Data::Section, you must import like this:

  use Data::Section -setup;

Optional arguments may be given to Data::Section like this:

  use Data::Section -setup => { ... };

Valid arguments are:

  inherit - if true, allow packages to inherit the data of the packages
            from which they inherit; default: true

  header_re - if given, changes the regex used to find section headers
              in the data section; it should leave the section name in $1

Three methods are exported by Data::Section:

=head2 section_data

  my $string_ref = $pkg->section_data($name); 

This method returns a reference to a string containing the data from the name
section, either in the invocant's C<DATA> section or in that of one of its
ancestors.  (The ancestor must also derive from the class that imported
Data::Section.)

By default, named sections are delimited by lines that look like this:

  __[ name ]__

You can use as many underscores as you want, and the space around the name is
optional.  This pattern can be configured with the C<header_re> option (see
above).

=head2 merged_section_data

  my $data = $pkg->merged_section_data;

This method returns a hashref containing all the data extracted from the
package data for all the classes from which the invocant inherits -- as long as
those classes also inherit from the package into which Data::Section was
imported.

In other words, given this inheritence tree:

  A
   \
    B   C
     \ /
      D

...if Data::Section was imported by A, then when D's C<merged_section_data> is
invoked, C's data section will not be considered.  (This prevents the read
position of C's data handle from being altered unexpectedly.)

The keys in the returned hashref are the section names, and the values are
B<references to> the strings extracted from the data sections.

=head2 local_section_data

  my $data = $pkg->local_section_data;

This method returns a hashref containing all the data extracted from the
package on which the method was invoked.  If called on an object, it will
operate on the package into which the object was blessed.

This method needs to be used carefull, because it's weird.  It returns only the
data for the package on which it was invoked.  If the package on which it was
invoked has no data sections, it returns an empty hashref.

=cut

sub _mk_reader_group {
  my ($mixin, $name, $arg, $col) = @_;
  my $base = $col->{INIT}{into};
  my $header_re = $arg->{header_re} || qr/\A_+\[\s*([^\]]+?)\s*\]_+\Z/;
  $arg->{inherit} = 1 unless exists $arg->{inherit};

  my %export;
  my %stash = ();

  $export{local_section_data} = sub {
    my ($self) = @_;

    my $pkg = ref $self ? ref $self : $self;

    return $stash{ $pkg } if $stash{ $pkg };

    my $template = $stash{ $pkg } = { };

    my $dh = do { no strict 'refs'; \*{"$pkg\::DATA"} }; ## no critic Strict
    return $stash{ $pkg} unless defined fileno *$dh;

    my $current;
    LINE: while (my $line = <$dh>) {
      if ($line =~ $header_re) {
        $current = $1;
        $template->{ $current } = \(my $blank = q{});
        next LINE;
      }

      Carp::confess("bogus data section: text outside of named section")
        unless defined $current;

      $line =~ s/\A\\//;

      ${$template->{$current}} .= $line;
    }

    return $stash{ $pkg };
  };

  $export{merged_section_data} =
    !$arg->{inherit} ? $export{local_section_data} : sub {

    my ($self) = @_;
    my $pkg = ref $self ? ref $self : $self;

    my $lsd = $export{local_section_data};

    my %merged;
    for my $class (Class::ISA::self_and_super_path($pkg)) {
      # in case of c3 + non-$base item showing up
      next unless $class->isa($base);
      my $sec_data = $class->$lsd;

      # checking for truth is okay, since things must be undef or a ref
      # -- rjbs, 2008-06-06
      $merged{ $_ } ||= $sec_data->{$_} for keys %$sec_data;
    }

    return \%merged;
  };

  $export{section_data} = sub {
    my ($self, $name) = @_;
    my $pkg = ref $self ? ref $self : $self;

    my @to_check = $arg->{inherit}
                 ? Class::ISA::self_and_super_path($pkg) 
                 : $pkg;

    my $lsd = $export{local_section_data}; # in case they use another name

    for my $class (@to_check) {
      # in case of c3 + non-$base item showing up
      next unless $class->isa($base);

      return $class->$lsd->{$name}
        if exists $class->$lsd->{$name};
    }

    return undef; ## no critic Undef
  };

  return \%export;
}

=head1 SEE ALSO

L<Inline::Files|Inline::Files> does something that is at first look similar,
but it works with source filters, and contains the warning:

  It is possible that this module may overwrite the source code in files that
  use it. To protect yourself against this possibility, you are strongly
  advised to use the -backup option described in "Safety first".

Enough said.

=cut

1;
