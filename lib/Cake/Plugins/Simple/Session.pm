package Cake::Plugins::Simple::Session;
use Cake 'Plugin';
use Carp;

my $utils_class = 'Cake::Plugins::Simple::Session::Utils';

sub setup {
    my $self = shift;
    ##only works with Cake::Plugins::Simple::Cache plugin
    if (!settings('Cake::Plugins::Simple::Cache')){
        $self->error('You need to load Cake::Plugins::Simple::Cache plugin in order to use Simple Session plugin');
    }
    $self->NEXT::setup(@_);
}


sub session {
    my $self = shift;
    ##set/get cookie
    my ($cookie_name,$expire) = (!ref $_[0] ? shift : undef, !ref $_[1] ? $_[1] : undef);
    my $options = $utils_class->get_options($self);
    $cookie_name ||= $options->{cookie_name};
    $expire ||= $options->{session_expire_time};
    
    my $cookieValue = $utils_class->get_cookie($self, $cookie_name, $expire);
    
    #get from cache
    my $session = $utils_class->get_session($self, $cookieValue,$cookie_name);
    if (@_) {
        my $newsession = $_[0];
        croak('session takes a hash or hashref') unless ref $newsession;
        for my $key (keys %$newsession) {
            $session->{$key} = $newsession->{$key};
        }
        ##set in cache
        $self->cache($cookieValue,$session,$expire,'SESSIONS/'.$cookie_name);
    }
    return $session;
}



sub flash {
    
    my $self = shift;
    
    $self->{'app.flash'} ||= {}; 
    
    if (@_){
        
        ##only get requested
        if (@_ == 1 and !ref $_[0]){
            my $value = $self->session->{'app.flash'};
            
            my $return = $value->{$_[0]};
            delete $value->{$_[0]};
            $self->session({
                'app.flash' => $value
            });
            
            return $return;
        }
        
        my $hash = @_ > 1 ? { @_ } : $_[0];
        #croak('flash takes a hash or hashref') unless ref $hash;
        $self->{'app.flash'} = Cake::Plugins::Simple::Session::Utils::combine_hashes($self->{'app.flash'},$hash);
        
        $self->session({
            'app.flash' => $self->{'app.flash'}
        });
    }
    
    else {
        if (my $flash = $self->session->{'app.flash'}){
            $self->session({
                'app.flash' => undef
            });
            return $flash;
        }
        
        else {
            return $self->{'app.flash'};
        }
    }
}


register();


package #hide from cake and cpan :)
Cake::Plugins::Simple::Session::Utils;
use strict;
use warnings;

my $options_singleton;
my $session;
my $cookie_jar = {};

sub get_options {
    shift;
    $options_singleton ||= shift->config('Cake::Plugins::Simple::Session');
    return $options_singleton;
}


sub get_cookie {
    
    shift;
    my $c = shift; ##$c
    my $cookie_name = shift;
    my $expire = shift;
    
    my $cookie = $c->cookie($cookie_name) || delete $cookie_jar->{$cookie_name};
    if (!$cookie){
        ###create random name for this cookie
        $cookie = Cake::Utils::random_string();
        my $result = $c->cookie({
            name => $cookie_name,
            value => $cookie,
            path => '/',
            length => $expire
        });
        $cookie_jar->{$cookie_name} = $cookie;
    }
    return $cookie;
}

sub get_session {
    shift;
    my ($c,$cookie,$cookie_name) = @_;
    $session = $c->cache($cookie,'SESSIONS/'.$cookie_name);
    return $session || {};
}


sub combine_hashes {
    my ($hash1,$hash2) = @_;
    while (my($key,$value) = each(%{$hash2})) {
        $hash1->{$key} = $value;
    }
    return $hash1;
}


1;



__END__

A very simple session handler



