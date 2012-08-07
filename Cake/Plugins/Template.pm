package Cake::Plugins::Template;
use Cake 'Plugin';
use Cake::View::TT;
use Carp;

my $template;
my $settings;

sub _template {
    
    return $template if $template;
    #if (!$settings){
        $settings = settings;
    #}
    
    $template = new Cake::View::TT(
        path => $settings->{path},
        layout => $settings->{layout},
        Debug => $settings->{Debug}
    );
    
    return $template;
}


sub render {
    my $self = $_[0];
    my $temp = &_render_template(@_);
    $self->body($temp);
}


sub get_template {
    my $temp = &_render_template(@_);
    return $temp;
}


sub layout {
    my $self = shift;
    my $layout = shift;
    _template->{layout} = $layout;
    return $self;
}

sub template_path {
    my $self = shift;
    my $path = shift;
    _template->{path} = $path;
    return $self;
}



sub _render_template {
    
    my $self = shift;
    my $file = shift;
    my $vars = shift;
    
    $vars = {} if !$vars;
    
    
    ###stash pass as default with Cake object as c
    $vars = {%{$vars},%{$self->stash},c=>$self};
    my $temp;
    eval {
        $temp = _template->render(
            $file,
            $vars
        );
    };
    
    if ($@){
        croak($@);
    }
    
    return $temp;
    
}


register();






1;









