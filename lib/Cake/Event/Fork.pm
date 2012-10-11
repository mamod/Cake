package Cake::Event::Fork;

use strict;
use warnings;
use Carp;
use Data::Dumper;
use IO::Handle;
use constant DEBUG => 1;
use POSIX ":sys_wait_h";
our $VERSION = '0.001';

##TODO

sub new {
    my $class= shift;
    my $processes = shift;
    bless({
        childs_count => 0,
        parent_pid => $$,
        max => $processes || 1
    },__PACKAGE__);
    
}

sub on_finish {
    my $self = shift;
    my $code = shift;
    $self->{on_finish} = $code;
}

sub start {
    
    my $self = shift;
    croak "[$$] can't fork inside child process" unless $self->is_parent;
    
    local $SIG{CHLD} = 'IGNORE';
    my $pid = fork();
    
    if ($pid){
        
        $self->{childs}->{$pid} = 1;
        $self->{childs_count}++;
        
    } else {
        $self->{child_pid} = $$;
    }
    
    if ($self->is_parent){
        return 1;
    } else {
        return 0;
    }
}

sub finish {
    
    my $self = shift;
    my $data = shift;
    
    unless ($self->is_parent){
        exit $$;
    }
}

sub count {
    return shift->{childs_count};
}

sub is_child {
    my $self = shift;
    exists $self->{child_pid} ? 1 : 0;
}


sub child {
    my $self = shift;
    return $self->{child_pid} || undef;
}


sub is_parent {
    my $self = shift;
    $$ == $self->{parent_pid} ? 1 : 0;
}


sub wait_all {
    my $self = shift;
    my $max = shift;
    
    local $self->{max} = $max if $max;
    
    #return if $self->{childs_count} < $self->{max};
    return $self if $self->{max} && $self->{max} > $self->count;
    
    while ($self->count){
        $self->wait_one;
    }
}

sub wait_one {
    my $self = shift;
    my $kid = waitpid(-1, 0);
    $self->{childs_count}--;
    DEBUG && warn "[$kid] Terminated\n";
}


sub DESTROY {
    
}


1;



__END__
=head1 NAME

Cake::Event::Fork

=head1 DESCRIPTION

Simple fork Manager

=head1 SYNOPSIS
    
    use Cake::Event::Fork;
    my $fork = Cake::Event::Fork->new(3);
    
    for (1..30) {
        $fork->start();
        unless ($fork->is_parent){
            ##do something in forked processes
        }
        $fork->finish();
        $fork->wait_all();
    }
    
    ##continue your code

=cut