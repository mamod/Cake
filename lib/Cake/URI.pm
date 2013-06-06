package Cake::URI;
use strict;
use warnings;

use base 'Exporter';
our @EXPORT = qw(
    uri_for
    uri_with
    subdomain
    subdomains
);

sub uri_encode {
    return '' if !$_[0];
    $_[0] =~ s/([^A-Za-z0-9])/sprintf("%%%02X", ord($1))/seg;
    return $_[0];
}

sub uri_decode {
    $_[0] =~ tr/+/ /;
    $_[0] =~ s/\%([A-Fa-f0-9]{2})/pack('C', hex($1))/seg;
    return $_[0];
}

#============================================================================
# url functions
#============================================================================
sub uri_for {   
    my $self = shift;
    return get_full_url($self,@_);
}
#=============================================================================
# return current url with path & parameters
# we can add new params to the requested URL $c->get_full_url({param=> value ...});
#=============================================================================
sub uri_with {
    
    my $self = shift;
    
    ##localize params
    local $self->{params};
    for (@_){
        if (ref $_ eq 'HASH'){
            $_ = $self->param($_);
            last;
        }
    }
    
    return get_full_url($self,@_);
}

#=============================================================================
# get current full url
#=============================================================================
sub get_full_url {
    
    my $self = shift;
    
    my $path = '';
    my $params = {};
    my $url = $self->base;
    
    if (!ref $_[0]){
        
        $path = shift;
        
        ##if request url has script name keep it
        my $script = $self->env->{SCRIPT_NAME};
        if ($self->env->{REQUEST_URI} =~ m/^$script/){
            $url = $self->base.$script;
        }
        
        if ($path =~ /^http/){
            $url = $path;
        } elsif ($path =~ /^\//){
            $url .= $path;
        } else {
            $url .= lc $self->action->{namespace}
            .'/'.$path;
        }
        
    } else {
        $url = $self->env->{'REQUEST_URI'};
    }
    
    if (ref $_[0] eq 'ARRAY') {
        my $args = shift;
        foreach my $arg (@{$args}){
            $url .= '/'.$arg;
        }
    } elsif (ref $_[0] eq 'HASH') {
        $params = shift;
    }
    
    if (keys %{$params}){
        my @params;
        while (my ($key,$value) = each(%{$params})) {
            push(@params,$key.'='.uri_encode($value));
        }
        
        $params = join('&',@params);   
        $url .= '?'.$params;
    }
    
    return $url;
}


sub subdomain {
    my $self = shift;
    return $self->{'subdomain'} if $self->{'subdomain'};
    
    ###parse sub domains
    my $host = $self->host;
    
    #remove port
    $host =~ s/:\d+//;
    
    $host =~ s/^(([^\/]+?\.)*)([^\.]{2,})((\.[a-z]{1,4}))$/$1/;
    $host =~ s/\.$//;
    $self->{'subdomain'} = $host;
    return $host;
}

sub subdomains {
    my $self = shift;
    return $self->{'subdomains'} if $self->{'subdomains'};
    ###parse sub domains
    my $host = $self->subdomain;
    my @subs = split(/\./,$host);
    $self->{'subdomains'} = \@subs;
    return \@subs;
}

1;

__END__

