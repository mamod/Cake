package App;
use Test::More;
use Cake;

settings {
    'url' => 'http://localhost33',
};

plugins [
    '+Plugins::Test' => {
        ##plugin settings
        url => 'http://localhost'
    }
];

App->bake()->serve(sub{
    my $c = shift;
    ##got this from Plugin::Test
    is($c->getArgs,1);
});

done_testing();

1;
