package App;
use Test::More;
use Cake;
use HTTP::Request::Common;
use Plack::Test;

use FindBin qw($Bin);

plugins [
    
    'Static' => {
        dir => $Bin . '/static'
    },
    
    'Simple::Cache' => {
        cache_root => $Bin . '/cache',
        expire_time => '1h',
        depth => '2'
    },
    
    'Simple::Session' => {
        cookie_name => 'SESSION',
        session_expire_time => '1d'
    },
    
    'View' => {
        path => $Bin . '/tmp',
        layout => 'layout.tt'
    },
    
    'I18N' => {
        path => $Bin . '/I18N',
        lang => 'en'
    }
];

get 'cache' => sub {
    my $self = shift;
    my $c = shift;
    ##set cache
    $c->cache('person',{
        name => 'Jack',
        age => 32
    });
    
    $c->forward(\&forward,{a => 'b'});
};

sub forward {
    my $self = shift;
    my $c = shift;
    my $args = shift;
    is($args->{a},'b');
    
    my $cc = $c->cache('person');
    is($cc->{name},'Jack');
    is($cc->{age},32);
}

sub testCache {
    my $cb = shift;
    my $req = HTTP::Request->new(GET => "/cache");
    my $res = $cb->($req);
}

my @tests = (
    \&testCache,
);

##initiate app
my $app = sub {
    my $env = shift;
    App->bake($env)->serve('psgi');
};

##run tests
test_psgi $app, sub {
    my $cb  = shift;
    
    foreach my $test (@tests){
        $test->($cb);
    }
};

done_testing();
