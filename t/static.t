package App;
use Test::More;
use Data::Dumper;
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

sub testStaticHTML {
    my $cb = shift;
    my $req = HTTP::Request->new(GET => "/static/hello.html");
    my $res = $cb->($req);
    is $res->content, "Hello From HTML";
    is $res->content_type, "text/html";
}

sub testStaticTxt {
    my $cb = shift;
    my $req = HTTP::Request->new(GET => "/static/hello.txt");
    my $res = $cb->($req);
    is $res->content, "Hello From TXT";
}

sub testStaticJS {
    my $cb = shift;
    my $req = HTTP::Request->new(GET => "/static/hello.js");
    my $res = $cb->($req);
    is $res->content, "hello from javascript";
    is $res->content_type, "application/javascript";
}

my @tests = (
    \&testStaticHTML,
    \&testStaticTxt,
    \&testStaticJS
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
