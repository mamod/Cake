package Cake::Plugins::I18N;
use Carp;
use Cake 'Plugin';
my $req = {};
my $settings = {};

sub loc {
    my $self = shift;
    my $string = shift;
    $settings ||= settings();
    my $dir = $settings->{path} || $self->app->{'dir'}.'/I18N';
    my $lang = $settings->{lang} || 'en';
    my $path = $dir.'/'.$lang;
    my $file;
    
    #croak "I18N Folder Not found in $path app directory please create one" if (! -e "$path");
    if (ref $string eq 'ARRAY'){
        $lang = $lang.'::'.$string->[0];
        $file = $path.'/'.$string->[0].'.po';
        $string = $string->[1];
    } else {
        $file = $path.'.po';
    }
    
    my $package = $self->app->{'basename'}.'::I18N::'.$lang;
    if (!$req->{$package}){ ##memoize
        #eval "require $package";
        $req->{$package} = 1;
        my %hash = Cake::Plugins::I18N::Lexi::_get_lexi($file || $package);
        {
            no strict 'refs';
            no warnings;
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

sub set_lang {
    my $self = shift;
    my $lang = shift;
    $settings ||= settings();
    $settings->{lang} = $lang if $lang;
}

sub get_lang {
    my $self = shift;
    return $settings->{lang} || 'en';
}

register();

package Cake::Plugins::I18N::Lexi;
sub _get_lexi {
    
    my $package = shift;
    my $data;
    
    if ($package =~ /::/){
        no strict 'refs';
        my $DATA = *{"${package}::DATA"};
        $data = do { local $/;  <$DATA> };
    } else {
        open my $DATA, '<', $package;
        #or croak "Can't open $package for input:\n$!";
        binmode $DATA,":utf8";
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

1;

__END__

=head1 NAME

Cake::Plugin::I18N

=head1 SYNOPSIS
    
    ##in your settings.json
    {
        "plugins" : [
            "I18N" : {
                "path" : "/full/path/to/your/language/files",
                "lang" : "en"
            },
            ....
        ]
    }
    
    ##or in your App.pm
    plugins [
        'I18N' => {
            path => '/full/path/to/your/language/files',
            lang => 'en' #default language
        },
        ....
    ];
    
    ###now create your language files inside language folder
    ###you set above {lang}.po
    
    ##-- en.po
    msgid "test"
    msgstr "test Hello from english file"
    
    ##-- ar.po
    msgid "test"
    msgstr "مرحبا بك"
    
    ##this plugin will export set_lang() & loc() functions to your application by default
    
    use Cake 'Controller';
    
    get '/lang' => sub {
        my $self = shift;
        my $c = shift;
        
        my $text = $c->loc('test');
        $c->body($text);
    };
    
    ###to change language
    $c->set_lang('ar');
    
    
=head1 Description

I18N Cake Plugin is a simple pure Perl translation plugin

=head1 Methods

=head2 loc(%args)

    $c->loc('Hello %1 %2',['mamod','mehyar']);
    
    ##or
    $c->loc('Hello',['mamod','mehyar']);
    
    ##and in your po file
    ##please make sure msgid match the first argument in loc() method
    
    ##-- en.po
    msgid "Hello %1 %2"
    msgstr "Hello %1 %2"
    
    ##-- ar.po
    msgid "Hello %1 %2"
    msgstr "%2 %1 مرحبا بك"
    
=head2 set_lang()

accepts a single string argument which defines the current language

    $c->set_lang('ar');
    

=head1 Sub translations

Sometimes your translation files are huge and better with distributing them across multiple files,
to do that you can create a sub folder under your original language path with the same name as the language
so for english files for example create a sub folder "en" then put .po files inside with different name like
"forms.po"

To call that file instead of the default translation file "en.po" you need to pass an array ref as the first argument to your loc
method for fisrt index is the file to be called.
    
    $c->loc(['form','Hello %1 %2'],['Mamod','Mehyar']);
    ##this will call "Hello %1 %2" msgid from
    ##/path/to/translation/en/form.po
    
