package ordo::License;
use Mojo::Base -base, -signatures;
use Crypt::JWT qw(decode_jwt);
use Crypt::PK::RSA;

use constant PUBLIC_KEY_PEM => <<'END';
-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAtG5j5lmVX23bLyh/l6td
i4bmnvNs8rN5rB2GXwtBuuxZvrN9tlg492Vbvsn60dADjcFXZyOCn2LeH4LeEDI/
OO850FDX4lUy+y2PqQHrY6DVHVoFE1maiKnrMilcMoUAGTJH58mAROttGyUokVrh
FMyl05z+++gg9R+FWXcy3SV2yYxut4sn7+Nftrbh8vxMT9bAJoROXn4Voz3p3ao4
2UhCJst2VrfR3j3DnD07eI6wHdh0Um5ZhKnQ+lVUkd1Ye7r8kpEnNo9tPYF2Vfvq
/wFfmZZWmCxkaESf1YKna5x+vvptKF58qWnKdQJ7c1QBut0yovn9xn2r17oqreW9
CQIDAQAB
-----END PUBLIC KEY-----
END

sub verify ($token) {
    return undef unless $token && length($token) > 40;

    my $pk = Crypt::PK::RSA->new(\PUBLIC_KEY_PEM);

    my $payload = eval {
        decode_jwt(
            token        => $token,
            key          => $pk,
            accepted_alg => 'RS256',
        );
    };

    return undef if $@ || ref($payload) ne 'HASH';
    return $payload;
}

sub require_valid_license () {
    my $key = $ENV{ORDO_LICENSE_KEY} // '';

    unless ($key) {
        die "ERROR: ORDO_LICENSE_KEY environment variable is required.\n"
          . "Create a .env file containing:\n\n"
          . "ORDO_LICENSE_KEY=your-license-key-here\n";
    }

    my $payload = verify($key);
    unless ($payload) {
        die "ERROR: Invalid or expired Ordo license key.\n";
    }

    return $payload;
}

1;
