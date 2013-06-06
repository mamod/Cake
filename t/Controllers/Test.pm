package App::Controllers::Test;
use Cake;
use Test::More;
use Data::Dumper;
sub begin {
    my $self = shift;
    my $c = shift;
    $c->content_type('application/javascript');
    is(1,1);
}

get 'controller' => sub {
    my $self = shift;
    my $c = shift;
    is(1,1);
    $c->body('From Controller');
};



1;
