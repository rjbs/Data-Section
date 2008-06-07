use strict;
use warnings;
package Data::Section;
# ABSTRACT: read multiple hunks of data out of your DATA section

use MRO::Compat;
use Sub::Exporter 0.979 -setup => {
  groups     => { setup => \'_mk_reader_group' },
  collectors => { INIT => sub { $_[0] = { into => $_[1]->{into} } } },
};

sub _mk_reader_group {
  my ($mixin, $name, $arg, $col) = @_;
  my $base = $col->{INIT}{into};
  my $header_re = $arg->{header_re} || qr/\A_+\[\s*([^\]]+)\s*\]_+\Z/;
  $arg->{inherit} = 1 unless exists $arg->{inherit};

  my %export;
  my %stash = ();

  $export{local_section_data} = sub {
    my ($self) = @_;
    my $pkg = ref $self ? ref $self : $self;

    return $stash{ $pkg } if $stash{ $pkg };

    my $template = $stash{ $pkg } = { };

    my $dh = do { no strict 'refs'; \*{"$pkg\::DATA"} };

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
    for my $class (@{ mro::get_linear_isa($pkg) }) {
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

    my $to_check = $arg->{inherit} ? mro::get_linear_isa($pkg) : [ $pkg ];

    my $lsd = $export{local_section_data}; # in case they use another name

    for my $class (@$to_check) {
      # in case of c3 + non-$base item showing up
      next unless $class->isa($base);

      return $class->$lsd->{$name}
        if exists $class->$lsd->{$name};
    }

    return undef;
  };

  return \%export;
}

1;
