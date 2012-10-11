package Cake::Engine::PSGI;
use strict;
use warnings;
use Cake::Utils::Accessor;
use Plack::Request;

__PACKAGE__->Accessor('psgi');

sub init {
    my $self = shift;
    my $req = Plack::Request->new($self->env);
    $self->psgi($req);
    return $self;
}


sub parameters {
    my $self = shift;
    return $self->psgi->parameters();
}

#=============================================================================
#
#=============================================================================
sub path {
    my $self = $_[0];
    
    if (@_ > 1){
        $_[0]->env->{PATH_INFO} = $_[1];
        return $_[0];
    }
    
    return $self->psgi->path;
}



sub method {
    my $self = shift;
    return $self->psgi->method;
}

sub is_secure {
    $_[0]->env->{'psgi.url_scheme'} eq 'https'
}



##############################################################################
##TODO
##############################################################################
sub upload {
    
    my( $self, $param ) = @_;
    
    my $upload = $self->psgi->uploads->{$param};
    
    
    
    if (!$upload){
        return;
    }
    
    $upload->copy_to('/path/to/targe');
    
    my $content = $self->get_file_content($upload->path);
    return $content;
    
    return( {
        unique_key => time . rand( 6 ),
        fullname   => $upload->filename,
        name       => $upload->basename,
        #suffix     => $suffix,
        #size       => ( $q->upload_info( $filename, 'size' ) || 0 ),
        #mime       => $q->upload_info( $filename, 'mime' ),
        content_type => $upload->content_type,
        filehandle => $upload->path,
    });
    
    
}

1;

