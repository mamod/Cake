package Cake::Utils::Accessor;
use strict;
use warnings;
use base qw/Exporter/;

our @EXPORT = qw(
    Accessor
);

###quick simple accessor
sub Accessor {
    my $class;
    if (caller eq $_[0]){
        $class = shift;
    } else {
        $class = caller;
    }
    
    foreach my $method (@_){
        my $code = $class.'::'.$method;
        {
            no strict 'refs';
            *$code = sub {
                my $self = shift;
                $self->{$method} ||= {};
                if(@_ == 1) {
                    return $self->{$method} = $_[0];
                } elsif (@_ > 1) {
                    return $self->{$method} = [@_];
                } else {
                    return $self->{$method};
                }
            };
        }
    }
}

1;

__END__

