package App;
use Test::More;
use Data::Dumper;
use Cake;
use HTTP::Request::Common;
use Plack::Test;

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
    my $self = shift;
    my $c = shift;
    $c->body("Hello");
};

##test params
post '/test/params' => sub {
    my $self = shift;
    my $c = shift;
    my $hi = $c->param('hi');
    
    is $hi, "There";
    is $c->method, "post";
    my $ret = $c->param('ret');
    $c->body($ret);
};


get '/args' => args(['name','age']) => sub {
    my $self = shift;
    my $c = shift;
    my $args = $c->capture;
    
    ok(ref $args eq 'HASH','captured args as hash ref');
    
    my $name = $args->{name};
    my $age = $args->{age};
    $c->body($name . ' ' . $age);
};


get '/args' => args(3) => sub {
    my $self = shift;
    my $c = shift;
    my $args = $c->capture;
    
    ok(ref $args eq 'ARRAY','captured args as array ref');
    
    my $name = $args->[0];
    my $age = $args->[1];
    my $age2 = $args->[2];
    $c->body($name . ' ' . $age . ' ' . $age2);
};

#local $ENV{PLACK_TEST_IMPL} = 'Server';
#local $ENV{PLACK_SERVER} = 'HTTP::Server::PSGI';

##initiate app
my $app = sub {
    my $env = shift;
    App->bake($env)->serve('psgi');
};

sub testSimpeRoute {
    my $cb = shift;
    my $req = HTTP::Request->new(GET => "/test");
    my $res = $cb->($req);
    is $res->content, "Hello";
}

sub testPostParams {
    my $cb = shift;
    my $req = HTTP::Request::Common::POST('/test/params',
        Content => {
            hi => 'There',
            ret => 'Hello'
        }
    );
    
    my $res = $cb->($req);
    is $res->content, "Hello";
    is $res->content_type, "text/html";
}


sub testArgs {
    my $cb = shift;
    my $req = HTTP::Request::Common::GET('/args/mamod/33');
    my $res = $cb->($req);
    is $res->content, "mamod 33","returned body with captured args";
    #is $res->content_type, "text/html";
}


sub testArgs2 {
    my $cb = shift;
    my $req = HTTP::Request::Common::GET('/args/mamod/33/99');
    my $res = $cb->($req);
    is $res->content, "mamod 33 99","returned body with captured args2";
}

sub testController {
    my $cb = shift;
    my $req = HTTP::Request->new(GET => "/test/controller");
    my $res = $cb->($req);
    is $res->content, "From Controller";
    is $res->content_type, 'application/javascript','application/javascript';
}

sub testFromRegex {
    my $cb = shift;
    my $req = HTTP::Request->new(GET => "/mmm/anything/here");
    my $res = $cb->($req);
    is $res->content, "From Regex","From Regex";
}


my @tests = (
    \&testSimpeRoute,
    \&testPostParams,
    \&testController,
    \&testFromRegex,
    \&testArgs,
    \&testArgs2
);

##run tests
test_psgi $app, sub {
    my $cb  = shift;
    
    foreach my $test (@tests){
        $test->($cb);
    }
};

done_testing();

1;
