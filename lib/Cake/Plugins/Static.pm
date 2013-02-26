package Cake::Plugins::Static;
use Cake 'Plugin';
use Carp;

my $map = {
    'js' => 'text/javascript',
    'css' => 'text/css',
    'png' => 'image/png',
    'jpg' => 'image/jpeg',
    'gif' => 'image/gif',
    'html' => 'text/html',
    'htm' => 'text/html',
    'xml' => 'text/xml'
};

my $time = time();

sub setup {
    
    my $self = shift;
    my $settings = settings();
    
    ####static path
    my $dir = $settings->{dir};
    if (!$dir){
        $self->warn("***Please specify a static path when using Cake::Plugins::Static");
        $self->warn("***Ex: 'Static'=>{dir=>'/path/to/static/folder'}");
        return $self->NEXT::setup();
    }
    
    
    ##get last folder
    $dir =~ s/(.*)\/(.*?)$/$1/;
    my $ma_path = '/'.$2;
    
    if ($self->path =~ /^$ma_path/i){
        
        my $path = $self->path;
        my ($ext) = $path =~ m/.*\.(.*?)$/;
        my $content_type = $map->{$ext} || 'text/plain';
        my $file = $dir.$path;
        
        ##simple Etag caching
        my $hex = $time.$file;
        $hex =~ s/(.)/sprintf("%x",ord($1))/eg;
        #if ($self->request_header('IF_NONE_MATCH') && $self->request_header('IF_NONE_MATCH') eq $hex){
        #    $self->status_code('304');
        #    $self->body('');
        #    return 1;
        #}
        
        my $data = '';
        
        #open file
        if (open(my $fh,'<',$file)){
            if ($ext =~ /png|gif|jpg/i){
                binmode $fh;
            }
            $data = do { local $/; <$fh> };
            close($fh);
        }
        
        if ($@){
            $self->content_type('text/plain');
            $self->status_code('404');
            $self->body('File Doesn\'t Exists');
            $self->log("Static File $path not found");
            return 1;
        }
        
        $self->log("Serving Static File $path");
        $self->content_type($content_type);
        $self->push_header("Etag: $hex");
        $self->body($data);
        return 1;
        
    } else {
        $self->NEXT::setup();
    }
}


register();


1;


__END__

head1 NAME

Cake::Plugins::Static

head1 DESCRIPTION

Serve static files from cake apps - this is very basic static file plugin

head1 SYNOPSIS

    #myapp.pm
    use Cake
    
    plugins [
        
        'Static' => {
            dir => '/path/to/static/folder'
        },
        
        ....
    ]







