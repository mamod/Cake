package Cake::Controllers;
use warnings;
use strict;
use base 'Exporter';

our @EXPORT = qw(
    dispatcher
    auto_chain
);

our $VERSION = '0.003';
my $dispatch = bless ({},__PACKAGE__);
my $auto_chain = {};
my @methods = ('get','post','delete','put');

sub dispatcher {$dispatch}
sub auto_chain {$auto_chain}
##returns last added controller action
sub Action { return shift->{lastAction}; }
sub Path { return shift->{path}; }
#----------------------------------------------------------------------------
# FIXME::::: just fix me no need to explain :)
#----------------------------------------------------------------------------
sub dispatch {
    
    my $self = shift;
    my $type = shift;
    my $path = shift;
    
    my @types = ($type);
    
    if (ref $path eq 'ARRAY'){
        @types = @{$path};
        $path = shift;
    }
    
    elsif ($type eq 'any'){
        @types = @methods;
    }
    
    #code is last
    my $code = pop @_;
    my ($caller, $script, $line) = caller(1);
    my ($abs_path,$namespace);
    
    ##redifine whole sub
    if ($type eq 'route'){
        
        my $hash = $code;
        my $controller = $hash->{controller} || '+'.$caller;
        $code = $hash->{action};
        
        @types = ref $hash->{method} eq 'ARRAY' ? @{$hash->{method}} : $hash->{method};
        @types = @methods if !$hash->{method} || $hash->{method} eq 'any';
        
        if ($controller =~ s/^\+//g){
            #nothing !!
        }
        
        else {$controller = $caller.'::Controllers::'.$controller;}
        
        ##require if not in controller folder
        if ($controller !~ /(Controllers::|Plugins::)/i){            
            my $req = $controller.'.pm';
            $req =~ s/::/\//g;
            eval "require '$req'";
        }
        
        $caller = $controller;
        
    }
    
    
    if (ref $path eq 'Regexp'){
        $abs_path = qr{$path};
    }
    
    #for absolute paths
    elsif ($path =~ m/^\//){
        $abs_path = lc($path);
    }
    
    else {
        
        ($namespace) = $caller =~ m/Controllers(::.*)$/;
        
        if ($namespace){
            $namespace =~ s/::/\//g;
            $abs_path = lc($namespace.'/');
        }
        
        $abs_path .= lc($path);
        $abs_path =~ s/\/$//;
    }
    
    
    local $dispatch->{lastAction} = {
        code => $code,
        line => $line,
        script => $script,
        class => $caller,
        namespace => $namespace || '',
        path => $abs_path
    };
    
    ###if there is another rules left, process them
    ### accept ref code
    foreach my $rule (@_) {
        if (ref $rule eq 'CODE'){
            $rule->($dispatch);
        }
    }
    
    ##new path ref
    my $nPath = $dispatch->{lastAction}->{path};
    
    if (ref $nPath eq 'Regexp' || ref $path eq 'Regexp') {
        push(@{$dispatch->{regex}},{
            regex => qr{$nPath},
            methods => \@types,
            action => $dispatch->{lastAction}
        });
    }
    
    else {
        
        my $actions;
        my $first_method = '';
        
        #one reference for all methods
        foreach my $method (@types){
            
            if ($actions->{$first_method}){
                $actions->{$method} = $actions->{$first_method};
            }
            
            else {
                $actions->{$method} = $dispatch->{lastAction};
                $first_method = $method;
            }
        }
        
        if ($dispatch->{$nPath}){
            $dispatch->{$nPath} = {%{$dispatch->{$nPath}},%{$actions}};
        }
        
        else {
            $dispatch->{$nPath} = $actions;
        }
    }
    
}



sub auto {
    
    my $self = shift;
    my $code = pop(@_);
    my ($caller, $script, $line) = caller(1);
    
    push @{$auto_chain->{$caller}},{
        code => $code,
        line => $line
    };
    
}



sub clear {
    $dispatch = {};
}

1;


__END__



