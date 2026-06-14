package ordo::Controller::Pages;
use Mojo::Base 'Mojolicious::Controller', -signatures;

sub terms ($self) {
    $self->render(template => 'terms');
}

sub privacy ($self) {
    $self->render(template => 'privacy');
}

1;
