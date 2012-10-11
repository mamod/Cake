package Cake::Plugin::I18N;
use Carp;
use Cake 'Plugin';
our $VERSION = "0.001";

my $req = {};

sub loc {
    
    my $self = shift;
    my $string = shift;
    
    my $lang = $self->app->{lang} || 'en';
    my $path = $self->app->{'dir'}.'/I18N/'.$lang;
    my $file;
    
    #croak "I18N Folder Not found in app directory please create one" if (! -e "$path");
    
    if (ref $string eq 'ARRAY'){
        $lang = $lang.'::'.$string->[0];
        $file = $path.'/'.$string->[0].'.po';
        $string = $string->[1];
    }
    
    else {
        $file = $path.'.po';
    }
    
    my $package = $self->app->{'basename'}.'::I18N::'.$lang;

    if (!$req->{$package}){ ##memoize
        
        #eval "require $package";
        $req->{$package} = 1;
        my %hash = &_get_lexi($file || $package);
        
        {
            no strict 'refs';
            
            *{"${package}::Lexi"} = sub {
                shift;
                my $str = shift;
                
                my $hash = \%hash;
                $str = $hash->{$str} || $str;
                
                my @arr = ();
                
                if (@_){
                    @arr =  ('',  @_ > 1 || !ref $_[0] ?  @_ : @{$_[0]} );
                    $str =~ s/%(\d+)/$arr[$1]/g;
                }
                else {$str =~ s/%(\d+)//g;}
                return $str;
            };
        }
    }
    
    return $package->Lexi($string,@_);
}


sub _get_lexi {
    
    my $package = shift;
    my $data;
    
    if ($package =~ /::/){
        no strict 'refs';
        my $DATA = *{"${package}::DATA"};
        $data = do { local $/;  <$DATA> };
    }
    
    else {
        open my $DATA, '<', $package;
        #or croak "Can't open $package for input:\n$!";
        local $/;
        $data = <$DATA>;
        close $DATA;
    }
    
    $data =~ s/\n/#/g;
    
    my @data = split(/##/, $data);
    my %hash = ();
    foreach my $line (@data){
        if ($line =~ /msgid "(.*?)"#msgstr "(.*?)"/){
            $hash{$1} = $2;
        }
    }
    
    return %hash;
}



register();

1;

