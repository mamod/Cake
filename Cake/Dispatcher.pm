package Cake::Dispatcher;
use strict;
use warnings;
use Carp;

our $VERSION = '0.004';

#============================================================================
# setup
#============================================================================
sub setup {
    
    
    my $self = shift;
    
    #match current route
    $self->match();
    
    if (defined $self->controller and $self->controller->can('begin')){
        $self->controller->begin($self);
    }
    
    
    ##dispatch & excute
    $self->dispatch();
    
    
    if (defined $self->controller and $self->controller->can('end')){
        $self->controller->end($self);
    }
    
}


#============================================================================
# dispatch: sending to the match route and execute
#============================================================================
sub dispatch {
    
    my $self = shift;
    my $args = shift;
    
    
    my $actionclass = $self->ActionClass;
    my $controller = $self->controller;
    my $code = $self->code;
    $args ||= $self->action->{args};
    
    ##running actions
    if ($actionclass){
        $actionclass->execute($controller,$self,$code,$args);
    }
    
    ##running auto blocks
    if (my $auto = $self->auto_chain->{ref $controller}){
        my $line = $self->action->{line};
        map { __PACKAGE__->execute($controller,$self,$_->{code},$args) if $_->{line} < $line } @{$auto};
    }
    
    __PACKAGE__->execute($controller,$self,$code,$args);
    
}


#============================================================================
# match : match current request path with routes
#============================================================================
##match sequence
## 1) direct paths - 2) paths with defined arguments - 3) chained - 4) regex
sub match {
    
    my $self = shift;
    my $path = shift || $self->path;
    
    my $method = $self->method;
    my $dispatch = $self->dispatcher;
    
    my $match;
    my @captures;
    
    if ($dispatch->{$path} && ($match = $dispatch->{$path}->{$method})){
        $self->addAction($match);
        return;
    }
    
    
    ## nothing found in direct paths, lets try with args
    (my $tpath = $path) =~ s/^\///;
    my @args = split(/\//,$tpath);
    my $i = $#args+1;
    
    ####get sequence of path - arg ...   /first/second(1)   /first(2)   /(3)
    my $t;
    my @t = reverse (map { --$i; $t .= '/'.$_;  $t.'('.$i.')' } @args);
    push(@t,'/'.'('.($#args+1).')');
    
    foreach my $this (@t){
        
        if ($dispatch->{$this} && ($match = $dispatch->{$this}->{$method})){
            ##capture
            @captures = splice(@args,-$i,$i);
            $self->addAction($match,@captures);
            return;
        }
        
        $i++;
    }
    
    ##lets try chains
    ####start with chain indexes and search for best match
    if ( my $indexes = $dispatch->{chains_index} ){
        
        local $self->{chain_action};
        local $self->{chain_sequence};
        
        for my $index (@{$indexes}){
            
            #die Dumper $chain->{$index_path};
            my $return = $self->_loop_chains($path,$index,1);
            $return && $return == 1 ? next : last;
            
        }
        
        if ($self->{chain_action}){
            
            #die Dumper $self->{chain_action};
            my @chain = @{$self->{chain_action}};
            
            my $lastaction = pop @chain;
            
            for my $action (@chain){
                $self->addAction($action);
                $self->dispatch();
            }
           
            $self->addAction($lastaction);
            return;
            
        }
    }
    
    
    ##TODO: use tie to match regex in hash keys??!
    if ($dispatch->{regex}){
        
        my $oldstrength = '';
        my $match;
        
        foreach my $this (@{$dispatch->{regex}}){
            
            if ($path =~ m/$this->{regex}/){
                
                next if (!grep(/$method/,@{$this->{methods}}));
                
                ###select the strongest
                my $localpath = $path; $localpath =~ s/$this->{regex}//;
                my $strength = length $localpath;
                
                if ($oldstrength eq '' || $strength < $oldstrength){
                    $match = $this;
                }
                
                $oldstrength = $strength;
                #return;
            }
            
        }
        
        if ($match){
            ##capture it
            @captures = ($path =~ m/$match->{regex}$/);
            @{$self->{capture}} = map { split('/',$_) } @captures;
            $self->addAction($match->{action},@{$self->{capture}});
        }
        
    }
    
    
}


sub _loop_chains {
    
    my $self = shift;
    my $path = shift;
    my $dir = shift;
    my $add_namespace = shift;
    
    
    my $regex;
    my $dispatch = $self->dispatcher;
    my $chain = $dispatch->{chains};
    my $thisChain = $chain->{$dir};
    
    
    my $route;$route = $add_namespace ?
    $dir :
    $thisChain->{dir};
    
    
    my $args = $thisChain->{args};
    
    if ($args){
        $regex = qr{^$route/(.*?)$};
    }
    
    else {
        $regex = qr{^$route(.*?)$};
    }
    
    
    if (my ($newpath) = $path =~ m#$regex#){
        
        my $match = $dispatch->{$thisChain->{path}}->{$self->method}
        or return 1;
        
        my @captures;
        if ($args){
            
            @captures = split '/',$newpath;
            my @args = splice @captures,0,$args;
            
            ##re construct path
            $newpath = '/'.join '/',@captures;
            $match->{captures} = \@args;
            
        }
        
        my $next_chain = $thisChain->{chained_by};
        
        return 1 if !$next_chain && $newpath && (!$args || $args && @captures);
        
        push @{$self->{action_sequence}},$match;
        
        ###last action in the chain
        $self->{chain_action} = $self->{action_sequence} and return
        if !$next_chain;
        
        for my $next (@{$next_chain}){
            
            my $nextnamespace = $chain->{$next}->{namespace};
            
            my $return = $self->_loop_chains($newpath,$next,$nextnamespace ne $thisChain->{namespace} ? 1 : 0);
            
            
            if ($return && $return == 1){
                next;
            }
            
            return;
            
        }
        
        @{$self->{action_sequence}} = splice @{$self->{action_sequence}},0,-1;
       
    }
    
    
    return 1;
    
}



sub addAction {
    
    my $self = shift;
    my $match = shift;
    
    my @captures;
    
    if (@_) {
        @captures = @_;}
    elsif ($match->{captures}){
        @captures = @{$match->{captures}};
    }
    
    
    $self->action({
        ActionClass => $match->{ActionClass},
        controller => bless($self->config->{$match->{class}} || {},$match->{class}),
        code => _get_code($match->{class},$match->{code}),
        line => $match->{line},
        namespace => $match->{namespace},
        args => \@captures
    });
    
    if (@captures && ref $match->{args} eq 'ARRAY'){
        my $count = -1;
        my %capture = map {  ++$count; $_ => $captures[$count] } @{$match->{args}};
        $self->action->{args} = \%capture;
    }
    
    
    if ($self->debug){
        carp "running $match->{script} $match->{line}" if ($match->{script} && $match->{line});
    }
    
    return;
    
}

#============================================================================
# excute : execute current action
#============================================================================
sub execute {
    shift;
    my ($controller,$c,$method,$args) = @_;
    if (ref $method eq 'CODE'){
        my @args = ref $args eq 'HASH' ? values %{$args} : @{$args};
        return $method->($controller,$c,@args);
    }
}


#============================================================================
# private methods
#============================================================================
sub _get_code {
    
    
    my $controller = shift;
    my $method = shift;
    
    ###convert method to CODE ref
    if (ref $method ne 'CODE'){
        $method = $controller.'::'.$method;
        $method = \&$method;
    }
    
    return $method;
    
}


1;

__END__


