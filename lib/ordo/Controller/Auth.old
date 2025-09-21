package ordo::Controller::Auth;

use Mojo::Base 'Mojolicious::Controller';

sub index {
  my $c = shift;
  $c->render('confirmed') if $c->session('email');
}

sub logout {
  my $c = shift;
  $c->session(expires => 1)->to_index;
}

sub sign_up {
  my $c = shift;

  my $email = $c->param('email');
  return $c->to_index('Email cannot be blank') unless $email;

  # Validate email address
  require Email::Valid;
  my $valid = Email::Valid->new;
  # Uncomment the next line to enable MX record checking (requires network access)
  # $valid->mxcheck(1);
  unless ($valid->address($email)) {
    return $c->to_index('Invalid email address');
  }

  return $c->to_index("Email $email is already registered")
    if $c->app->emails->{$email};

  $c->app->emails->{$email} = { confirmed => 0 };
  my $jwt = $c->jwt->claims({email => $email})->encode;
  my $url = $c->url_for('confirm')->to_abs->query(jwt => $jwt);
  $c->email($email, 'Confirm Your Email', "Please click the following link to confirm your email: $url");
  $c->to_index('Registration complete, please check your email to confirm');
}

sub confirm {
  my $c = shift;
  my $email = $c->jwt->decode($c->param('jwt'))->{email};
  return $c->to_index("Email $email not found") unless $c->app->emails->{$email};
  $c->app->emails->{$email}{confirmed} = 1;
  $c->session(email => $email);
  $c->to_index('Email confirmed, you are now logged in');
}

1;
