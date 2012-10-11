package Cake::Event::Loop;
use strict;
use warnings;
no warnings 'recursion';
no warnings 'redefine';
use IO::Handle;
use IO::Select;
use Data::Dumper;
use Carp;
use Time::HiRes qw (time);
use Socket;
use POSIX ":sys_wait_h";
use constant DEBUG => 1;
#use diagnostics;

sub new {
    bless({pid=>$$},__PACKAGE__);
}

sub timer {
    
    my $self = shift;
    
    ###construct a new instance if called directly
    if (!ref $self){
        $self = __PACKAGE__->new();
    }
    
    my %options = @_;
    
    if (exists $options{callback} && ref $options{callback} ne 'CODE'){
        croak 'callback option must be a code ref';
    }
    
    if (exists $options{idle} && ref $options{idle} ne 'CODE'){
        croak 'idle option must be a code ref';
    }
    
    $self->{timer} = {
        callback => $options{callback} || sub{},
        idle => $options{idle} || sub{},
        after => $options{after} || 0,
        interval => $options{interval}
    } if @_ > 0;
    
    return $self;
}


sub loop {
    
    my $self = shift;
    
    return if $self->{stop};
    return $self->loop_io if $self->{loop_io};
    
    if ($self->{timer}->{after} == 0){
        $self->_run_loop(1);
    } else {
        $self->_run_loop();
    }
}


sub _run_loop {
    
    my $self = shift;
    my $run_once = shift || 0;
    
    my $idle = $self->{timer}->{'idle'};
    my $interval = $self->{timer}->{'interval'};
    my $callback = $self->{timer}->{'callback'};
    my $time = time();
    my $after = $self->{timer}->{after};
    
    while (1){
        
        if ($self->{terminate}){
            $interval = 0;
            last;
        }
        
        else {
            my $run = $run_once || (time() - $time) >= $after;
            if ($run){
                last;
            }
            else {
                &$idle;
            }
        }
    }
    
    &$callback if !$self->{terminate};
    
    if ($interval){
        local $self->{timer}->{after} = $interval;
        $self->timer();
        $self->loop;
    }
    
    return $self;
    
}

my @ready;
sub io {
    
    my $self = shift;
    
    $self->{loop_io} = 1;
    
    ###construct a new instance if called directly
    if (!ref $self){
        $self = __PACKAGE__->new();
    }
    
    my %options = @_;
    
    if (exists $options{callback} && ref $options{callback} ne 'CODE'){
        croak 'callback option must be a code ref';
    }
    
    my $fh = $options{fh};
    
    $self->{io} = {
        callback => $options{callback} || sub {},
        idle => $options{idle} || sub {},
        poll => $options{poll} || 'read',
        fh => $fh
    } if @_ > 0;
    
    return $self;
    
}



sub loop_io {
    
    my $self = shift;
    my $fh = $self->{io}->{fh};
    
    my $bless = ref $fh;
    my $s = -S $fh || 0;
    
    my $select;
    
    if ($^O eq "MSWin32" && ($bless !~ /IO::Socket::INET/ || $s)){
        ##sending to some workaround, not very good though!!?
        #$select = $self->io_select_win();
        croak "windows IO select is not supported yet";
        
    } else {
        $select = $self->io_select();
    }
    
    my $idle = $self->{io}->{idle};
    my $callback = $self->{io}->{callback};
    my $poll = $self->{io}->{poll};
    
    if (ref $fh eq 'ARRAY'){
        foreach my $fd (@{$fh}){
            $select->add($fd);
        }
    }
    
    else {
        $select->add($fh);
    }
    
    $self->timer(
        after => 0,
        interval => 0.01,
        callback => sub {
            @ready = $poll eq 'read' ? $select->can_read(0.01) : $select->can_write(0.01);
            foreach my $_fh (@ready) {
                &$callback($_fh);
            }
        },
        idle => sub {
            select(undef,undef,undef,0.01);
            &$idle;
        }
    );
    
    local $self->{loop_io} = 0;
    $self->loop();
    
    return $self;
}

sub stop {
    shift->{stop} = 1;
}


sub terminate {
    my $self = shift;
    $self->{terminate} = 1;
}

sub io_select {
    my $self = shift;
    return $self->{io_select} ||= IO::Select->new();
}

sub io_select_win {
    my $self = shift;
    return $self->{io_select} ||= Cake::Event::Loop::IO::Select->new();
}

sub uSleep {
    select(undef,undef,undef,$_[1]);
}

1;

__DATA__

