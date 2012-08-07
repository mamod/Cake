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
    }
    
    else {
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
        $select = $self->io_select_win();
        
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


sub children {
    
    my $self = shift;
    
    if (!ref $self){
        $self = __PACKAGE__->new();
    }
    
    my %options = @_;
    
    if (exists $options{callback} && ref $options{callback} ne 'CODE'){
        croak 'callback option must be a code ref';
    }
    $self->{fork}->{data} = $options{data};
    $self->{fork}->{callback} = $options{callback};
    $self->{fork}->{max} = $options{max} || 1;
    
    return $self;
}



sub run {

    my $self = shift;
    
    my %options = @_;
    
    my $callback = $self->{fork}->{callback};
    my $maxChilds = $self->{fork}->{max} || 1;
    my $data = $self->{fork}->{data};
    
    open my $io, '>',undef;
    
    $self->{fork}->{manager} = $io;
    
    for (1..$maxChilds){
        my $pid = fork;
        
        if ($pid){
            
            #return $self;
            #1 while wait() != -1;
            
        } else {
            
            &$callback();
            #exit 0;
        }
        exit ($$||0) if $$ != $self->{pid};
    }
    
    return $self;
}





sub manager {

    my $self = shift;
    
    my %options = @_;
    my $childs = {};
    my $callback = $self->{fork}->{callback};
    my $maxChilds = $self->{fork}->{max} || 1;
    my $data = $self->{fork}->{data};
    
    open my $parent_pid,'+>',undef;
    
    $self->{parent_handle} = $parent_pid;
    
    my $cc = 0;
    my $count = 0;
    for (1..$maxChilds){
        
        my $io;
        open $io,'+>',undef;
        
        my $pid = fork;
        if ($pid){
            
            $childs->{$pid} = $io;
            
        } else {
            
            ##start as an idle
            $io->overwrite('idle');
            
            DEBUG and warn "RUNNIG PROCESS $$\n";
            
            my $lp = Cake::Event::Loop->new();
            $lp->io(
                
                fh => $io,
                callback => sub {
                    
                    my $fh = shift;
                    
                    ##read file action tag
                    my $buf = $fh->readTag();
                    if ( $buf ne ("idle" || "running") )  {
                        
                        #local $SIG{CHLD} = \&sig_chld;
                        
                        #continue reading buffer
                        while (sysread($fh,my $more,1024)){
                            $buf .= $more;
                        }
                        
                        ###eval buffer
                        my $shared = eval $buf;
                        
                        $fh->overwrite('running');
                        &$callback($shared);
                        
                        ##once done put it back in idle state
                        $fh->overwrite('idle');
                        
                    }
                    
                }, idle => sub {
                    
                    if ($self->{parent_handle}->readTag eq "close" || $io->readTag eq "close"){
                        croak "Exiting Process $$";
                    }
                    
                }
                
            );
            
            $lp->loop;
            exit 0;
            
        }
        
    }
    
    $self->{childs} = $childs;
    
    return $self;
}

sub sig_chld {
  1 while (waitpid(-1, POSIX::WNOHANG()) > 0);
  $SIG{CHLD} = \&sig_chld;
}

sub kueue {
    
    my $self = shift;
    my $hash = shift;
    
    unless (exists $self->{childs}){
        croak "You need to start a prefork process before calling the invoke method\n";
    }
    
    push @{$self->{kueue}},$hash;
    
    return $self;
    
}

sub add {
    
    my $self = shift;
    my $hash = shift;
    
    my $callback = $self->{fork}->{callback};
    my $maxChilds = $self->{fork}->{max} || 1;
    my $data = $self->{fork}->{data};
    
    
    #$self->{new} ||= Cake::Event::Loop->new();
    my $timer = Cake::Event::Loop->new();
    
    push @{ $self->{kueue} },$hash;
    
    $self->{new} ||= __PACKAGE__->children(
        max => 1,
        callback => sub {
            
            $timer->timer(
                after => 0.1,
                interval => 0.1,
                callback => sub {
                    
                    my $hash = shift @{ $self->{kueue} };
                    &$callback($hash) if $hash;
                    $timer->terminate;
                    
                },
                idle => sub {
                    select(undef,undef,undef,0.1);
                    #print Dumper $$;
                    
                }
            );
            
            $timer->loop;
            
        }
    )->run;
    
    undef @{ $self->{kueue} };
    undef $self->{new};
    return $self;
    
}


sub invoke {
    
    my $self = shift;
    my $hash = shift;
    
    push @{$self->{kueue}},$hash if $hash;
    
    my @kueue = @{$self->{kueue}};
    
    my %childs = %{$self->{childs}};
    my @childs = values %childs;
    
    $self->io(
        
        #WATCH CHILDS FOR STATUS CHANGES
        fh => \@childs,
        callback => sub {
            
            my $fh = shift;
            
            if (@kueue){
                
                my $tag = $fh->readTag;
                
                if ($tag eq "idle"){
                    my $tied = shift @kueue;
                    my $dumper = Data::Dumper->new([ $tied ]);
                    $dumper->Purity(1)->Terse(1)->Indent(0)->Deparse(1);
                    my $data = $dumper->Dump;
                    $fh->overwrite($data);
                }
                
            } else {
                
            }
            
        }, idle => sub {
            $self->terminate() if !@kueue;
        }
        
    );
    
    $self->loop;
    
    ##call DESTROY sub
    #$self->io_select_win->unwatch;
    undef $self;
    
}

sub shared {
    my $shared = shift;
    return shift;
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

sub DESTROY {
    
    my $self = shift;
    return if $$ != $self->{pid};
    $self->killChilds;
    
    if (exists $self->{childs}){
        map {
            delete $self->{childs}->{$_};
        } keys %{$self->{childs}}
    }
    
}

sub killChilds {
    my $self = shift;
    $self->parentHandle->overwrite('close') if $self->{parent_handle};
}

sub parentHandle {
    my $self = shift;
    
    if(@_){
        my $new_handle = shift;
        $self->{parent_handle} = $new_handle;
    }
    
    return $self->{parent_handle};
}

#==============================================================================
# Windows IO::Select fallback = not very reliable
#==============================================================================
package Cake::Event::Loop::IO::Select;
use strict;
use warnings;
use IO::Handle;
use Data::Dumper;
use Carp;


my $handles = {};


sub new {
    return bless({pid=>$$},__PACKAGE__);
}

sub add {
    
    my $self = shift;
    my $fh = shift;
    
    open my $io,'+>',undef;
    
    $self->{handles}->{fileno $fh} = {
        watcher => $io,
        fh => $fh
    };
    
    unless (exists $self->{parent_handle}){
        open my $parent_handle,'+>',undef;
        $self->{parent_handle} = $parent_handle;
    }
    
    my $s = -1;
    my $t = -1;
    
    my $checker = sub {
        
        my $fh = shift;
        
        my $s2 = (stat($fh))[7];
        my $t2 = (stat($fh))[8];
        
        if ($t == $t2){
            if ($s == $s2){
                return 0;
            }
        }
        
        $s = $s2;
        $t = $t2;
        return 1;
        
    };
    
    my $pid = fork();
    
    #child process
    unless ($pid) {
        
        while (1) {
            
            select (undef,undef,undef,0.01);
            
            if ($self->{parent_handle}->readTag eq "close"){
                croak "Ending Process $$";
            }
            
            elsif ($checker->($fh) == 1){
                $io->overwrite('ready');
            }
        }
        
        exit 0;
    }
}


sub can_read {
    
    my ($self,$timeout) = @_;
    select (undef,undef,undef,$timeout);
    
    my @ready = ();
    
    map {
        
        my $watcher = $_->{'watcher'};
        if ($watcher->readTag() eq "ready"){
            push @ready,$_->{'fh'};
            $watcher->overwrite('');
        }
        
    } values %{$self->{handles}};
    
    return @ready;
    
}


sub unwatch {
    my $self = shift;
    
    return if $$ != $self->{pid};
    
    $self->{parent_handle}->overwrite('close');
}


sub DESTROY {
    my $self = shift;
    $self->unwatch();
}






#==============================================================================
# add some functions we use alot to the IO::Handle module
#==============================================================================
package IO::Handle;
sub overwrite {
    my $fh = shift;
    my $text = shift;
    seek $fh,0,1;
    CORE::truncate $fh,0;
    seek $fh,0,0;
    $fh->syswrite($text);
    
    
}

sub readTag {
    my $fh = shift;
    seek $fh,0,0;
    CORE::sysread($fh,my $buf,10);
    return $buf;
}

sub invoke {
    shift->overwrite(shift);
}





1;



__DATA__

