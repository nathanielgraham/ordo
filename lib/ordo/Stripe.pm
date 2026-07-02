package ordo::Stripe;

use Mojo::Base -base;
use Mojo::UserAgent;
use Mojo::JSON qw(decode_json encode_json);
use Data::Dumper;

has 'config';
has ua => sub { Mojo::UserAgent->new };

sub stripe_url {
    my $self = shift;
    return 'https://api.stripe.com/v1';
}

sub headers {
    my $self = shift;
    return {
        Authorization => 'Bearer ' . $self->config->{stripe}{secret_key},
        'Content-Type' => 'application/x-www-form-urlencoded',
    };
}

# Create Checkout Session
sub create_checkout_session {
    my ($self, %args) = @_;

    # Required parameters check
    unless ($args{success_url} && $args{cancel_url} && $args{price_id}) {
        die "Missing required args: success_url, cancel_url, or price_id";
    }

    my $form = {
        mode                => 'subscription',
        customer_email      => $args{customer_email},
        'line_items[0][price]'     => $args{price_id},
        'line_items[0][quantity]'  => 1,
        success_url         => $args{success_url},
        cancel_url          => $args{cancel_url},
        'metadata[org_id]'  => $args{org_id} // '',
    };

    print "=== STRIPE REQUEST ===\n";
    print Dumper($form);

    my $tx = $self->ua->post(
        $self->stripe_url . '/checkout/sessions' => 
        $self->headers => 
        form => $form
    );

    my $res = $tx->result;

    print "=== STRIPE RESPONSE ===\n";
    if ($res->error) {
        print "Error: " . Dumper($res->error);
    }
    print "Status: " . $res->code . "\n";
    print $res->body . "\n";

    return decode_json($res->body) if $res->is_success;

    die "Stripe error: " . $res->body;
}

# Create Customer Portal Session
sub create_customer_portal {
    my ($self, %args) = @_;

    my $form = {
        customer   => $args{customer_id},
        return_url => $args{return_url},
    };

    my $tx = $self->ua->post(
        $self->stripe_url . '/billing_portal/sessions' =>
        $self->headers =>
        form => $form
    );

    my $res = $tx->result;

    die "Portal error: " . $res->body unless $res->is_success;

    return decode_json($res->body);
}

# Verify Stripe Webhook Signature
sub verify_webhook {
    my ($self, $payload, $sig_header) = @_;

    my $secret = $self->config->{stripe}{webhook_secret}
        or die "Missing webhook_secret in config";

    # Using Stripe's official way (requires Crypt::JWT or similar, or simple timestamp check)
    # For simplicity, we'll use a basic version first. You can upgrade later.

    require Digest::SHA;
    require Time::HiRes;

    # Basic signature verification (recommended minimum)
    if (!$sig_header) {
        die "Missing Stripe-Signature header";
    }

    # For full verification, it's better to use the official method.
    # Here's a working version using raw parsing:

    my $timestamp;
    my $signature;

    if ($sig_header =~ /t=(\d+),v1=([a-f0-9]+)/) {
        $timestamp = $1;
        $signature = $2;
    } else {
        die "Invalid signature format";
    }

    my $signed_payload = $timestamp . '.' . $payload;
    my $expected_sig = Digest::SHA::hmac_sha256_hex($signed_payload, $secret);

    unless ($expected_sig eq $signature) {
        die "Invalid signature";
    }

    # Optional: check timestamp (replay attack protection)
    my $now = time();
    if (abs($now - $timestamp) > 300) {  # 5 minutes
        die "Timestamp too old";
    }

    return decode_json($payload);
}

1;
