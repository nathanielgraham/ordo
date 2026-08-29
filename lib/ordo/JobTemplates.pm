package ordo::JobTemplates;
use Mojo::Base -base, -signatures;
use Mojo::File;
use Mojo::JSON qw(encode_json);

# Categories shown as optgroups, in this order.
our @CATEGORIES = qw(languages handlers triggers);
our %CATEGORY_LABEL = (
  languages => 'Languages',
  handlers  => 'Handlers',
  triggers  => 'Triggers',
);

sub root ($app) {
  return $app->home->child( 'examples', 'job-templates' );
}

# Scan examples/job-templates once per process.
sub catalog ($app) {
  state $cached;
  return $cached if $cached;

  my $root = root($app);
  my @items;
  my %by_id;

  for my $cat (@CATEGORIES) {
    my $dir = $root->child($cat);
    next unless -d $dir;
    for my $file ( sort { $a->basename cmp $b->basename } $dir->list->each ) {
      next unless -f $file && -s $file;
      my $item = _parse_file( $cat, $file );
      next unless $item;
      push @items, $item;
      $by_id{ $item->{id} } = $item;
    }
  }

  $cached = {
    categories => [
      map { { id => $_, label => $CATEGORY_LABEL{$_} // ucfirst($_) } }
        @CATEGORIES
    ],
    items => \@items,
    by_id => \%by_id,
  };
  return $cached;
}

sub json ($app) {
  my $c = catalog($app);
  return encode_json(
    {
      categories => $c->{categories},
      items      => [
        map {
          {
            id       => $_->{id},
            label    => $_->{label},
            category => $_->{category},
            desc     => $_->{desc},
            script   => $_->{script},
          }
        } @{ $c->{items} }
      ],
    }
  );
}

sub _parse_file ( $cat, $file ) {
  my $text = eval { $file->slurp } // return;
  $text =~ s/\r\n/\n/g;
  my $stem = $file->basename;
  $stem =~ s/\.[^.]+$//;

  my ( $id, $label, $desc );
  for my $line ( split /\n/, $text ) {
    last if $line =~ /\S/ && $line !~ /^\s*#/ && $line !~ /^#!/;
    if ( $line =~ /^\s*#\s*\@id\s+(\S+)/ ) {
      $id = $1;
    }
    elsif ( $line =~ /^\s*#\s*\@label\s+(.+?)\s*$/ ) {
      $label = $1;
    }
    elsif ( $line =~ /^\s*#\s*\@desc\s+(.+?)\s*$/ ) {
      $desc = $1;
    }
  }

  $id    ||= $stem;
  $label ||= join( ' ', map { ucfirst $_ } split /[-_]/, $id );

  return {
    id       => $id,
    label    => $label,
    desc     => $desc // '',
    category => $cat,
    path     => "$file",
    script   => $text,
  };
}

1;
