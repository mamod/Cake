package App::Plugins::Test;
use Cake 'Plugin';
use Test::More;
sub init {
    is(settings('Plugins::Test')->{url},'http://localhost')
}

sub getArgs {
    
    my $self = shift;
    my $c = shift;
    
    return 1;
    
}


register();

1;
