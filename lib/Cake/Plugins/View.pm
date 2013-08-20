package Cake::Plugins::View;
use Cake 'Plugin';
use Cake::View::TT;
use Carp;

my $template;
my $settings;

sub template {
    return $template if $template;
    $settings ||= $_[1] || settings;
    
    $template = new Cake::View::TT({
        path => $settings->{path},
        layout => $settings->{layout},
        DEBUG => $settings->{Debug}
    });
    
    return $template;
}

sub render {
    my $self = $_[0];
    my $temp = &_render_template(@_);
    $self->body(Encode::encode('UTF-8',$temp));
}

sub _render_template {
    
    my $self = shift;
    my $file = shift;
    my $vars = shift;
    $vars = {} if !$vars;
    
    ###stash pass as default with Cake object as c
    $vars = {%{$self->stash},%{$vars},c=>$self};
    my $temp;
    eval {
        $temp = template->render(
            $file,
            $vars
        );
    };
    
    if ($@){
        my $error = $@;
        ##get message & line number
        my ($msg,$l) = ($error->{message} =~ /(.*?) at .*? line (\d+)/);
        
        open my $fh, '<', $error->{file};
        read $fh, my $buf, $error->{pos}+1;
        close $fh;
        
        #count number of lines
        my @lines = split /\n/,$buf;
        my $line = scalar @lines + ($l-1);
        die {
            caller => [
                __PACKAGE__,
                $error->{file},
                $line
            ],
            file => $error->{file},
            pos => $error->{pos},
            message => $msg
        }
    }
    return $temp;
}

sub layout {
    my $self = shift;
    my $layout = shift;
    template->{layout} = $layout;
    return $self;
}

register();

1;

__END__

head1 NAME

Cake::Plugins::View

head1 DESCRIPTION

Cake Template View Plugin

head1 SYNOPSIS

    ##App.pm
    
    use Cake;
    
    plugins [
        
        'View' => {
            path => '/full/path/to/template/folder',
            layout => 'layout.tt',
            Debug => 1
        },
        
        ...
        
    ];
    
    
    #controller.pm
    
    ##cake stash will be passed to the template file
    
    $c->stash({
        first_name => 'Mamod'
    });
    
    get 'home' => sub {
        my ($self,$c) = @_;
        $c->render('home',{
            last_name => 'Mehyar'
        });  
    };
    
    #home.tmp
    Welcome Home [% first_name %] [% last_name %]
    
head1 ALSO SEE

For more information about template rendering please see <L>Cake::View::TT</L>;

