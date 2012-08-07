package Cake;

use warnings;
use strict;
use Carp;
use NEXT;
use File::Find;
use Encode;
use utf8;
use Data::Dumper;
use Cake::Controllers;
use Cake::Exception;
use Cake::Utils::Accessor;
use Cake::Utils;
use Cake::URI;
use base qw/Exporter Cake::Dispatcher Cake::Engine/;

our $VERSION = '1.005';

my @controller_export = qw(
    get
    post
    any
    args
    chained
    Action
    route
    auto
);

my @plugin_export = qw(
    settings
    register
);

my @extra_export = qw(
    bake
    plugins
    context
);

our @EXPORT = (@controller_export,@plugin_export,@extra_export);

__PACKAGE__->Accessor('env','app','engine','action','stash','uri');

my ($DEBUG,$ENGINE);
my $SELF;
my $SETTINGS = {};
my $COUNTER = 0;

#============================================================================
# Helper functions
#============================================================================
sub context {
    my $caller = shift;
    $ENV{'REQUEST_URI'} = shift || '';
    $ENV{SCRIPT_NAME} = (caller)[0] || '';
    return $caller->bake();
}

sub clear_counter {$COUNTER = 0}
sub counter {$COUNTER}
sub debug {return $DEBUG;}

#============================================================================
# import on app start
#============================================================================
sub import {
    
    my ($class, @options) = @_;
    
    my ($package,$script) = caller;
    my $engine;
    
    ###import these to app by default
    strict->import;
    warnings->import;
    utf8->import;
    
    foreach (@options) {
        if (/^Plugin$/){
            $class->export_to_level(1, $class, @plugin_export);
            return;
        }
        
        elsif (/^Controller$/){
            $class->export_to_level(1, $class, @controller_export);
            return;
        }
        
        # Import engine
        if ( /^:Engine=(\S+)/ && !$ENGINE) {
            $ENGINE = $1;
            $engine = Cake::Utils::Require($ENGINE,'Cake::Engine');
            if ( $@ ) { die qq/can't load engine "$ENGINE", "$@"/ }
            unshift(@Cake::ISA,$engine);
        }
        
        elsif (/^:Debug=(\S+)/){
            $DEBUG = $1;
        }
    }
    
    if (!$SELF){
        $SELF->{'basename'} = $package;
        $package .='.pm';
        ($SELF->{'dir'} = $INC{$package}) =~ s/\.pm//;
        push @INC, $SELF->{'dir'};
    }
    
    $class->export_to_level(1, $class, @EXPORT);
}

#============================================================================
# settings : get/set application Settings
#============================================================================
sub settings {
    
    if (@_ > 1 || ref $_[0]){
        if (!ref $_[0]){
            my $package = shift;
            $SETTINGS->{$package} = {@_};
        }
        
        else {
            $SETTINGS = $_[0];
        }
    }
    
    else {
        my $package = $_[0] || caller;
        $SETTINGS->{$package} ? return $SETTINGS->{$package} : return $SETTINGS;
    }
    
    return $SETTINGS;
}


sub config {
    
    my $self = shift;
    if ($_[0]){
        return $self->{settings}->{$_[0]};
    }
    return $self->{settings};
}


#============================================================================
# load plugins
#============================================================================
sub plugins {
    
    my @plugins = @{$_[0]};
    my @pluginsRequire;
    return if !@plugins;
    
    my $withOptions;
    for (my $i= 0; $i < @plugins; $i++) {
        if (!ref $plugins[$i]){
            my $module = Cake::Utils::noRequire($plugins[$i],'Cake::Plugins');
            push(@pluginsRequire,$plugins[$i]);
            if (ref ( my $next = $plugins[$i+1] )){
                $withOptions->{$module} =  $next;
                splice(@plugins, $i+1, 1);
            }
        }
    }
    
    map {Cake::Utils::Require($_,'Cake::Plugins')} @pluginsRequire;
    $SETTINGS = {%{$SETTINGS},%{$withOptions}};
}


#============================================================================
# bakery: bake the cake
#============================================================================
sub bake {
    
    my $class = shift;
    my $self = bless({}, __PACKAGE__);
    ###FIXME: internal use of some global captured things!!!?
    $self->app(bless($SELF, $class));
    $self->{pid} = $$;
    $self->env(bless($_[0] || \%ENV, 'Cake::ENV'));
    $self->{COUNT} = $COUNTER;
    $self->{response}->{headers} = ["X-Framework: PerlCake"];
    $self->{settings} = $SETTINGS;
    $self->loadControllers();
    return $self->_runner();
}






#============================================================================
# run app
#============================================================================
sub _runner {
    
    my $self = shift;
    
    local $SIG{__DIE__};
    
    eval {
        
        $self->init();
        
        if ($self->app->can('begin')){
            $self->app->begin($self);
        }
        
        ++$self->{_count};
        croak('Infinte Loop Detected') if $self->{_count} > '20';
        $self->setup();
        
        if ($self->app->can('end')){
            $self->app->end($self);
        }
        
        $self->finalize();
    };
    
    if ($@){
        $self->error($@);
    }
    
    $COUNTER++;
    return $self;
}


#============================================================================
# Run code on destruction ??!
#============================================================================
sub DESTROY {
    my $self = shift;
    return if $$ != $self->{pid};
    if ( exists $self->{on_destroy} ){
        map {
            $_->($self) if ref $_ eq "CODE";
        } @{$self->{on_destroy}};
        
        $self->{on_destroy} = [];
    }
}

#============================================================================
# load controllers
#============================================================================
sub loadControllers {
    return if $COUNTER;
    my $self = shift;
    my $dir = $self->app->{'dir'}.'/Controllers';
    
    find(sub {
        if ($_ =~ m/\.pm$/){
            my $file = $File::Find::name;
            
            eval "require '$file'";
            
            if ($@) {
                die("can't load controller $file");
            }
        }
    }, $dir);
}

#============================================================================
# load app model
#============================================================================
sub model {
    
    my $self = shift;
    my $model = shift;

    my $module = $self->app->{'dir'}."::Model::".$model;
    $module =~ s/::/\//g;
    $module .= '.pm';
    
    require "$module";
    $model = $self->app->{'basename'}."::Model::".$model;
    return bless({
        c => $self
    },$model);
}

#============================================================================
# load Plugins
#============================================================================
sub loadPlugins {
    
    my $self = shift;
    my $dir = shift;
    
    foreach my $module (@{$SELF->{plugins}}) {
        Cake::Utils::Require($module,'Cake::Plugins');
        ####maybe we should register plugins internally, but let's first test
        #$self->register($module);
    }
}

#============================================================================
# register plugins
#============================================================================
sub register {
    
    my @attr = @_;
    my $caller = caller(0);
    
    unshift (@Cake::ISA,$caller);
    return;
}

#============================================================================
# server - get server name if set
#============================================================================
sub server {
    return shift->env->{'cake.server'};
}

#============================================================================
# controllers routing
#============================================================================
sub get { Cake::Controllers->dispatch('get',@_); }
sub post { Cake::Controllers->dispatch('post',@_); }
sub any { Cake::Controllers->dispatch('any',@_); }
sub after { Cake::Controllers->dispatch('after',@_); }
sub before { Cake::Controllers->dispatch('before',@_); }
sub route { Cake::Controllers->dispatch('route',@_); }
sub auto { Cake::Controllers->auto(@_); }

#============================================================================
# Custom Action Class Loader
#============================================================================
sub Action {
    
    my $class = shift;
    my $caller = (caller)[0];
    
    $class = Cake::Utils::Require($class,'Cake::Actions');
    
    my $self = {};
    
    if (@_ == 1){
        $self = $_[0];
    }
    
    elsif (@_){
        $self = \@_;
    }
    
    ##bless action class
    $class = bless($self,$class);
    
    return sub {
        my $dispatch = shift;
        $dispatch->Action->{ActionClass} = $class;
    };
}

#============================================================================
# args
#============================================================================
sub args {
    
    #return ('args',$_[0]);
    my $args = $_[0];
    my $num = $args;
    
    if (ref $args eq 'ARRAY'){
        $num = @{$args};
    }
    
    return sub {
        
        my $dispatch = shift;
        
        my $path = $dispatch->Action->{path};
        
        if (my $chain = $dispatch->{chains}->{$path}){
            $dispatch->{chains}->{$path}->{path} = $path.'('.$num.')';
            $dispatch->{chains}->{$path}->{args} = $num;
        }
        
        if (ref $path eq 'Regexp'){
            $dispatch->Action->{path} = qr{$path(/.*?)(/.*?)$};
        }
        else {
            $dispatch->Action->{path} .= '('.$num.')';
        }
        
        $dispatch->Action->{args} = $args;
    };
    
}

#============================================================================
# chained controllers
#============================================================================
sub chained {
    
    #return ('args',$_[0]);
    my $chain_path = $_[0];
    
    return sub {
        
        my $dispatch = shift;
        my $path = $dispatch->Action->{path};
        
        my $class;
        my $namespace;
        my $abs_path = $chain_path;
        
        
        $class  = $dispatch->Action->{class};
        
        
        ($class) = $class =~ m/Controllers(::.*)$/;
        ($class = lc $class) =~ s/::/\//g;
        
        $namespace = $dispatch->Action->{namespace};
        
        my $to_chain = $chain_path;
        unless ($chain_path =~ m/^\// ){
            $to_chain = lc $class.'/'.$chain_path;
        }
        
        if (!$abs_path){
            push @{$dispatch->{chains_index}},$path;
        }
        
        my ($dir) = $path =~ m/^$namespace(.*?)$/;
        $dispatch->{chains}->{$path}->{dir} = $dir;
        $dispatch->{chains}->{$path}->{path} = $path;
        $dispatch->{chains}->{$path}->{namespace} = $namespace;
        push @{$dispatch->{chains}->{$to_chain}->{chained_by}},$path;
        
    };
    
}

#============================================================================
# some short cuts
#============================================================================
sub capture {return $_[0]->action->{args}}



sub ActionClass {
    return shift->action->{ActionClass};
}

#============================================================================
# return controller class object
#============================================================================
sub controller {
    return shift->action->{controller};
}

#============================================================================
# return current action code
#============================================================================
sub code {
    return shift->action->{code};
}


#============================================================================
# set body content
#============================================================================
sub body {
    
    my ($self,$content) = @_;
    
    if (@_ == 2){
        
        my $body;
        
        if (ref $content eq ('CODE' || 'ARRAY')){
            $body = $content;
        }
        
        elsif (ref $content eq 'GLOB'){
            $body = $content;
        }
        
        #save as file handle
        else {
            #truncates and open for reading and writing
            open($body, "+>", undef);
            $body->write($content);
        }
        
        $self->{response}->{'body'} = $body;
        return $self;
    }
    
    my $body = $self->{response}->{'body'};
    return $body;
}


##append content to the body
sub write {
    my ($self,$chunk) = @_;
    my $fh = $self->body();
    
    if ($fh && ref $fh eq 'GLOB'){
        $fh->write($chunk);
    } else {
        $self->body($chunk);
    }
}
#============================================================================
# dump data
#============================================================================
sub dumper {
    
    my $self = shift;
    my $data = shift;
    $self->body(Dumper $data);
    
}

sub json {
    my $self = shift;
    my $data = shift;
    $self->body($self->serialize($data)->to_json);
}

#============================================================================
# stash
#============================================================================
#sub stash {
#    
#    my $self = shift;
#    
#    $self->{'app.stash'} ||= {};
#    
#    
#    if (@_){
#        my $hash = @_ > 1 ? { @_ } : $_[0];
#        croak('stash takes a hash or hashref') unless ref $hash;
#        $self->{'app.stash'} = $hash;
#        return $self;
#    }
#    
#    
#    return $self->{'app.stash'};
#    
#}


sub detach {
    my $self = shift;
    $self->finalize();
    Cake::Exception::Mercy_Killing($self);
}

#============================================================================
# param : set/get param
# copied form catalyst param method :P that's why it looks sophisticated :))
#============================================================================
sub param {
    my $self = shift;

    if ( @_ == 0 ) {
        return keys %{ $self->parameters };
    }
    
    if (ref($_[0]) eq 'HASH'){
        my $hash = shift;
        while (my ($key,$value) = each(%{$hash})){
            $self->parameters->{$key} = $value;
        }
    }

    elsif ( @_ == 1 ) {
        
        my $param = shift;
        
        unless ( exists $self->parameters->{$param} ) {
            return wantarray ? () : undef;
        }
        
        if ( ref $self->parameters->{$param} eq 'ARRAY' ) {
            return (wantarray)
              ? @{ $self->parameters->{$param} }
              : $self->parameters->{$param}->[0];
        }
        else {
            return (wantarray)
              ? ( $self->parameters->{$param} )
              : $self->parameters->{$param};
        }
    }
    
    elsif ( @_ > 1 ) {
        my $field = shift;
        $self->parameters->{$field} =  @_ >= 2 ? [@_] : $_[0] ;
    }
    
    return $self->parameters();
}


#============================================================================
# params : alias for parameters
#============================================================================
#============================================================================
# parameters : Implemented in Cake::Engine
#============================================================================
sub params {
    return shift->parameters(@_);
}

#============================================================================
# push_header : add header
#============================================================================
sub push_header {
    
    my $self = shift;
    my ($header) = @_;
    
    if (ref $header eq 'HASH'){
        foreach my $key (keys %{$header}){
            my $head = $key.': '.$header->{$key};
            $self->push_header($head);
        }
        
        return;
        
    }
    
    elsif (ref $header eq 'ARRAY'){
        map { $self->push_header($_) } @{$header};
        return;
    }
    
    if (@_ > 1){
        $header = $_[0].': '.$_[1];
    }
    
    croak 'Headers accept a Hash ref, Array of Hash refs or scalar'
    if ref $header || $header !~ /(.*?):(.*?)/;
    
    if ($header =~ s/^content-type:\s*//i){
        $self->content_type($header);
    }
    
    elsif ($header =~ s/^status:\s*//i){
        $self->status_code($header);
    }
    
    else {
        push(@{$self->{response}->{headers}}, $header);
    }
    
    return $self;
}

#============================================================================
# add multiple headers / get all headers
#============================================================================
sub headers {
    my $self = shift;
    
    if (@_){
        foreach my $header (@_){
            $self->push_header($header);
        }
        
        return $self;
    }
    
    return wantarray ? @{$self->{response}->{headers}} : $self->{response}->{headers};
}

#============================================================================
# get/set content type header
#============================================================================
sub content_type {
    my ($self,$type) = @_;
    if ($type){
        $self->{response}->{content_type} = $type;
    }
    return $self->{response}->{content_type} || 'text/html';
}

#============================================================================
# get/set response status code header
#============================================================================
sub status_code {
    my ($self,$code) = @_;
    if ($code){
        $self->{response}->{status_code} = $code;
    }
    return $self->{response}->{status_code} || '200';
}

#============================================================================
# redirect
#============================================================================
sub redirect {
    
    my $self = shift;
    my $url = shift;
    my $status   = shift || 302;
    
    $url = $self->uri_for($url);
    
    $self->status_code($status);
    
    $self->push_header("Location: $url");
    
    ##just in case ?? inject this HTNL/javascript redirect
    my $html = qq~<html><head><script type="text/javascript">
    window.location.href='$url';</script></head><body>
    This page has moved to <a href="$url">$url</a></body></html>~;
    $self->body($html);
    $self->finalize();
}

#============================================================================
# forward
# to stop after forward use
# return $c->forward();
#============================================================================
sub forward {
    
    my $self = shift;
    my $forward_to = shift;
    my $args = shift;
    
    if (ref $forward_to eq 'CODE'){
        $forward_to->($self->controller,$self,$args);
    }
    
    elsif ($forward_to !~ /^\//){
        $self->controller()->$forward_to($self,$args);
    }
    
    else {
        ####alter reguest path
        $self->path($forward_to);
        $self->run($args);
    }
}





#package UNIVERSAL;
#use strict;
    sub methods {
        my ($class, $types) = @_;
        $class = ref $class || $class;
        $types ||= '';
        my %classes_seen;
        my %methods;
        my @class = ($class);
        
        no strict 'refs';
        while ($class = shift @class) {
            next if $classes_seen{$class}++;
            unshift @class, @{"${class}::ISA"} if $types eq 'all';
            # Based on methods_via() in perl5db.pl
            for my $method (grep {not /^[(_]/ and 
                                  defined &{${"${class}::"}{$_}}} 
                            keys %{"${class}::"}) {
                $methods{$method} = wantarray ? undef : $class->can($method); 
            }
        }
      
        wantarray ? keys %methods : \%methods;
    }



package Cake::ENV;
our $AUTOLOAD;

sub ip {
    return shift->{SERVER_ADDR};
}

sub host {
    return shift->{HTTP_HOST};
}

sub referrer {
    return shift->{HTTP_REFERER};
}

sub AUTOLOAD {
    my $self = shift;
    my $sub = $AUTOLOAD;
    $sub =~ s/.*:://;
    while (my ($key,$val) = each %{$self} ){
        if ($key =~ m/$sub/i){
            return $val;
        }
    }
    
    return '';
}

1;

__END__


=head1 NAME

Cake - A simple perl web framework

=head1 SYNOPSIS

    use Cake;
    
    get '/hello' => sub {
        
        my $self = shift;
        my $c = shift;
        
        my $name = $c->param('name');
        $c->body("Hello ".$name);
        
    };
    
    ##bake and serve the cake
    bake->server();


=head1 DESCRIPTION

Cake is a mix between Dancer simplicity and Catalyst MVC way, I wanted to name
it Cancer but since that was a really bad name I went with Cake :)

Cake has zero dependency -- yes -- it requires nothing more than the core modules
that come with Perl itself, and this was my design decesion from day one, so I had
to reinvent some wheels and steel some others :)

=head1 Features

Cake apps can be written in one single file, or the catalyst MVC way

Cake apps Can run on any server with standard Perl installation

It comes with a simple template system, something like TT, but we call it Cake-TT

It comes with a simple Database abstraction layer

Cake is also PSGI/Plack friendly by default, no need to change anything to enable
your app to run under any of the available Plack webservers


    
    
    
    
    
    
    
    
    



