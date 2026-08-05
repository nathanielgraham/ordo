package OrdoAgent;
use strict;
use warnings;
use Exporter 'import';
use JSON::PP qw(encode_json decode_json);
use IPC::Open3 ();
use Symbol     ();

our @EXPORT_OK = qw(ordo_post);
our $VERSION   = '1.0';

# ---------------------------------------------------------------------------
# ordo_post($url, \%data, %opts) -> Str | HashRef | undef
#
# POST JSON to the Ordo API using system curl (HTTPS without Perl SSL modules).
#
# Options:
#   timeout         => N     whole-operation timeout seconds (default 10)
#   retries         => N     extra attempts after the first (default 0)
#   soft_fail       => 1     return undef on failure instead of die
#   decode          => 1     return decoded hashref instead of raw body
#   require_success => 1     after decode, die unless { success => true }
#                            (implies decode => 1)
#   on_error        => CODEREF($message)  optional logger (e.g. print to job log)
# ---------------------------------------------------------------------------
sub ordo_post {
    my ( $url, $data, %opts ) = @_;

    _fail( $opts{on_error}, 'ordo_post: url required',  %opts )
      unless defined $url && length $url;
    _fail( $opts{on_error}, 'ordo_post: data hash required', %opts )
      unless ref($data) eq 'HASH';

    my $timeout = $opts{timeout} // 10;
    my $retries = $opts{retries} // 0;
    $opts{decode} = 1 if $opts{require_success};

    my $body = eval { encode_json($data) };
    _fail( $opts{on_error}, "ordo_post: JSON encode failed: $@", %opts )
      if $@ || !defined $body;

    my ( $resp, $rc, $stderr );
    my $attempts = $retries + 1;

    while ( $attempts-- > 0 ) {
        ( $resp, $rc, $stderr ) = _curl_post( $url, $body, $timeout );

        if ( defined $rc && $rc == 0 ) {
            return _maybe_decode( $resp, %opts );
        }

        my $msg = _error_message( $rc, $stderr, $resp );
        if ( $attempts > 0 ) {
            _log( $opts{on_error}, "$msg - retrying..." );
            sleep 1;
            next;
        }

        return _fail( $opts{on_error}, $msg, %opts );
    }

    return _fail( $opts{on_error}, 'ordo_post: exhausted retries', %opts );
}

# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------
sub _curl_post {
    my ( $url, $body, $timeout ) = @_;

    my $err = Symbol::gensym();
    my ( $in, $out, $pid );

    $pid = eval {
        IPC::Open3::open3(
            $in, $out, $err,
            'curl',
            '-sS',
            '-f',
            '-m', "$timeout",
            '-H', 'Content-Type: application/json',
            '--data-binary', '@-',
            $url
        );
    };

    if ( $@ || !defined $pid ) {
        return ( '', -1, "cannot run curl: $@$!" );
    }

    print {$in} $body;
    close $in;

    local $/;
    my $resp   = readline($out) // '';
    my $stderr = readline($err) // '';
    close $out;
    close $err;
    waitpid $pid, 0;

    return ( $resp, ( $? >> 8 ), $stderr );
}

sub _maybe_decode {
    my ( $resp, %opts ) = @_;
    return $resp unless $opts{decode};

    my $args = eval { decode_json( $resp || '{}' ) };
    if ($@) {
        return _fail(
            $opts{on_error},
            "ordo_post: invalid JSON response: $@",
            %opts
        );
    }

    if ( $opts{require_success}
        && ( $args->{exit} || !$args->{success} ) )
    {
        return _fail(
            $opts{on_error},
            'ordo_post: scheduler error: ' . encode_json($args),
            %opts
        );
    }

    return $args;
}

sub _error_message {
    my ( $rc, $stderr, $resp ) = @_;
    my $detail =
        ( defined $stderr && length $stderr ) ? $stderr
      : ( defined $resp   && length $resp )   ? $resp
      :                                         '(no detail)';
    $rc = '?' unless defined $rc;
    return "ordo_post failed (curl exit $rc): $detail";
}

sub _log {
    my ( $cb, $msg ) = @_;
    if ( $cb && ref($cb) eq 'CODE' ) {
        $cb->($msg);
    }
    else {
        warn "$msg\n";
    }
}

sub _fail {
    my ( $cb, $msg, %opts ) = @_;
    _log( $cb, $msg );
    return if $opts{soft_fail};
    die "$msg\n";
}

1;

__END__

=head1 NAME

OrdoAgent - minimal HTTP helper for Ordo node scripts

=head1 SYNOPSIS

  use lib "$Bin/../modules";
  use OrdoAgent qw(ordo_post);

  # launcher: best-effort state update
  ordo_post(
      $api,
      { command => 'update_job_state', token => $token, id => $id, ... },
      soft_fail => 1,
      on_error  => sub { print STDOUT "$_[0]\n" },
  );

  # update_stats: must succeed and return structure
  my $args = ordo_post(
      $api,
      { token => $token, id => $id, command => 'update_sysinfo', %$sysinfo },
      retries         => 3,
      decode          => 1,
      require_success => 1,
  );

=head1 DEPENDENCIES

Core Perl only, plus the system C<curl> binary. No LWP, no IO::Socket::SSL.

=cut
