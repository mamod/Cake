package App;
use Test::More;
use Data::Dumper;
use Cake;
use FindBin qw($Bin);

get qr{^/mmm/(.*)} => sub {
    my $self = shift;
    my $c = shift;
    ok(ref $c->capture eq 'ARRAY');
    is($c->capture(0),'anything');
    is($c->capture(1),'here');
    $c->body('From Regex');
};

## simple route
get '/test' => sub {
    
};

##test params

#local $ENV{PLACK_TEST_IMPL} = 'Server';
#local $ENV{PLACK_SERVER} = 'HTTP::Server::PSGI';

App->bake()->serve(sub{
    my $c = shift;
    is($Bin,$c->app->{dir}, $c->app->{dir} . ' == ' . $Bin);
    ok(ref $c eq 'Cake','$c instance of Cake');
    my $dispatch = $c->dispatcher;
    ok(ref $dispatch eq 'Cake::Controllers',"dispatch instance of Cake::Controllers");
    ok($dispatch->{'/test'},"dispatch has /test");
});

done_testing();

1;
