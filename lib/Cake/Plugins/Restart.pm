package Cake::Plugins::Restart;
use Cake 'Plugin';
use File::Find;
use Carp;
my $files = {};
my $settings;

##DO NOT USE

sub init {
    
    my $self = shift;
    $settings ||= settings();
    $self->NEXT::init();
    
    ##nothing to watch for CGI and only watch when debugging
    return if $self->run_once() || !$self->debug();
    
    if (!$settings->{dir}){
        croak('You must set at least one folder to watch');
    }
    
    my @folders_to_watch = !ref $settings->{dir} ? ($settings->{dir}) : @{$settings->{dir}};
    my $found_some_change;
    
    find(sub {
        
        if ($_ =~ m/\.pm$/){
            my $file = $File::Find::name;
            
            my $time = (stat $file)[9];
            if (!$found_some_change && $files->{$file} && $time != $files->{$file}){
                $found_some_change = 1;
            }
            
            $files->{$file} = $time;
        }
        
    }, @folders_to_watch);
    
    
    return if !$found_some_change;
    
    Cake::Controllers::clear();
    Cake::clear_counter();
    
    ##save previos ISA
    my @isa = @Cake::ISA;
    
    @Cake::ISA = ('Exporter','Cake::Engine::Default','Cake::Dispatcher');
    
    my %seen;
    while (my ($key,$value) = each (%INC) ){
        if ($key =~ /^$self->{'app.basename'}/ || $key =~ /^$self->{'app.dir'}/ || $key =~ /^Cake\/Plugins/){
            $seen{$key} = $value;
            delete $INC{$key};
        }
    }
    
    {
        no warnings "redefine";
        map {    
            eval "require $_";
        } keys %seen;
        
        @Cake::ISA = @isa;
    }
    
    
}

register();

1;