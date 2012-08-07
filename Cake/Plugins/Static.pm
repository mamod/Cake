package Cake::Plugins::Static;
use Cake 'Plugin';
use Carp;


###Proof of concept

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
    
    ##get last folder
    $dir =~ s/(.*)\/(.*?)$/$1/;
    my $ma_path = '/'.$2;
    
    if ($self->path =~ /^$ma_path/i){
        
        
        my $path = $self->path;
        
        my ($ext) = $path =~ m/\.(.*?)$/;
        my $content_type = $map->{$ext} || 'text/plain';
        
        #$path =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;
        
        my $file = $dir.$path;
        
        
        
        ##simple Etag caching
        my $hex = $time.$file;
        $hex =~ s/(.)/sprintf("%x",ord($1))/eg;
        if ($self->request_header('IF_NONE_MATCH') && $self->request_header('IF_NONE_MATCH') eq $hex){
            $self->status_code('304');
            #$self->push_header("Etag: $hex");
            $self->body('');
            return 1;
        }
        
        
        my ($data);
        
        #open file
        if (open(my $fh,'<',$file)){
            
            if ($ext =~ /png|gif|jpg/i){
                binmode $fh;
            }
            
            $data = do {
                local $/;
                <$fh>
            };
            close($fh);
        }
        
        else {
            $data = '';
        }
        
        if ($@){
            Carp::croak $@;
            return 1;
            $self->content_type('text/plain');
            $self->status_code('404');
            $self->body('File Doesn\'t Exists');
            return 1;
        }
        
        
        $self->content_type($content_type);
        $self->push_header("Etag: $hex");
        $self->body($data);
        return 1;
        
    }
    
    else {
        $self->NEXT::setup();
    }
    
}


register();


1;