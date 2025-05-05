package ordo::Controller::Pet;
use Mojo::Base 'Mojolicious::Controller', -signatures;
use JSON;
use Data::Dumper;

sub list ($self) {
  # Do not continue on invalid input and render a default 400
  # error document.
  my $c = $self->openapi->valid_input or return;

  # You might want to introspect the specification for the current route
  my $spec = $c->openapi->spec;
  print Dumper($spec);
  #unless ($spec->{'x-opening-hour'} == (localtime)[2]) {
  #  return $c->render(openapi => [], status => 498);
  #}
  #my $age  = $c->param("age");
  #my $body = decode_json($c->req->json);
  #my $body = $c->req->json;
  #print Dumper($body);
  #my @errors = $schema->validate( $body );
  #die $errors[0] if @errors;

  
  # $output will be validated by the OpenAPI spec before rendered
  my $output = {pets => [{name => "kit-e-cat"}]};
  $c->render(openapi => $output);
}
1;

