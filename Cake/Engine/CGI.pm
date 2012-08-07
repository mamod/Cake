package Cake::Engine::CGI;
use strict;
use warnings;
use CGI;
use File::Basename;
#use base 'Cake::Base';
use Cake::Utils::Accessor;
__PACKAGE__->Accessor('cgi');

sub init {
    
    my $self = shift;
    my $cgi = new CGI();
    $self->cgi($cgi);
    
    ###reset some enviroments
    my $uri = $self->env->{'REQUEST_URI'};
    
    my($path, $query) = ( $uri =~ /^([^?]*)(?:\?(.*))?$/s );
    
    ##remove script name from path info
    my $script = $self->env->{SCRIPT_NAME};
    $path =~ s/^$script//;
    
    for ($path, $query) { s/\#.*$// if length } # dumb clients sending URI fragments

    $self->env->{PATH_INFO}    = URI::Escape::uri_unescape($path);
    $self->env->{QUERY_STRING} = $query || '';
    ####################
    return $self;
}



#=============================================================================
# parameters
#=============================================================================
sub parameters {
    
    my $self = shift;
    
    my %params = $self->cgi->Vars();
    
    while ( my ($key,$value) = each(%params) ){
        
        my @values = split("\0",$value);
        
        if (@values > 1){
            $params{$key} = \@values;
        }
        
    }
    
    return \%params;
    
}

#=============================================================================
# upload
#=============================================================================
sub upload {
    my( $self, $param ) = @_;

    die "file param required" if ! $param;
    
    my $q = $self->cgi;
    my $filename = $q->param( $param );
    
    $filename =~ s/\\/\//g;
    
    #return $filename;
    
    my( $name, $path, $suffix ) = fileparse( 
        $filename, 
        qr/\.(tar\.gz$|[^.]*)/ 
    );  
    
    return({
        unique_key => time . rand( 6 ),
        fullname   => ( $name . $suffix ),
        name       => $name,
        suffix     => $suffix,
        filehandle => $q->upload( $filename ),
    });

}




1;