package Cake::Engine;
use strict;
use warnings;
use Carp;
use IO::File;
our $VERSION = "0.011";

sub init {
    
    my $self = shift;
    
    my $uri = $self->env->{'REQUEST_URI'};
    
    my($path, $query) = ( $uri =~ /^([^?]*)(?:\?(.*))?$/s );
    
    ##remove script name from path info
    my $script = $self->env->{SCRIPT_NAME};
    $path =~ s/^$script//;
    
    #for ($path, $query) { s/\#.*$// if length } # dumb clients sending URI fragments

    $self->env->{PATH_INFO}    = Cake::URI::uri_decode($path);
    $self->env->{QUERY_STRING} = $query || '';
    
    $self->engine(bless {}, __PACKAGE__);
    
}

#BEGIN { open (STDERR, ">>/xampp/htdocs/CakeBlog/error.txt"); }

#=============================================================================
# finalize output
#=============================================================================
sub finalize {
    my $self = shift;
    $self->printDebug();
    return $self;
}

sub printDebug {
    my $self = shift;
    if ($self->debug and my $logs = $self->app->{log}){
        
        my $debug = "\n=======================\n";
        $debug .=   "   DEBUGGING CONSOLE ||\n";
        $debug .=   _charFormatter('=');
        $debug .=   "REQUEST PATH : ".$self->path . "\n";
        $debug .=   _charFormatter('#');
        $debug .=   _charFormatter(' ');
        
        my $i = 0;
        foreach my $log (@{$logs}){
            
            if (ref $log eq "ARRAY"){
                $log = join "\n",@{$log};
            }
            
            if (ref $log eq 'CODE') {
                $log = $log->();
            }
            
            if (length($log) > 65){
                my @logs = unpack("(A62)*", $log);
                my $last = pop @logs;
                foreach my $lo (@logs){
                    $lo .= "->";
                    $debug .= _printFormatter($lo);
                }
                $log = $last;
            }
            
            $debug .= _printFormatter($log);
            $debug .= _charFormatter(' ');
            
        }
        $debug .=     _charFormatter('#');
        warn $debug."\n";
    }
    
    $self->app->{log} = [];
}

sub _printFormatter {
    my $text = shift;
    my $padd = shift || ' ';
    my $form .= "$text";
    $form .= $padd x (64 - length($text)) . "#\n";
    return $form;
}

sub _charFormatter {
    my $char = shift;
    my $multi = shift || 64;
    return ($char x $multi) . "#\n";
}


#=============================================================================
# serve output
#=============================================================================
sub serve {
    
    my $self = shift;
    my $type = shift;
    
    if ($type){
        
        return $self->serve_as_psgi if uc $type eq 'PSGI';
        
        if (ref $type eq 'CODE'){
            return $type->($self,$self->env->{client});
        }
        
        $self->Require($type,'');
        
        {
            no strict 'refs';
            *{"${type}::serve"}->($self);
        }
    }
    
    else {
        $self->print_headers();
        $self->print_body();
    }
    
    close $self->{response}->{body};
}



#=============================================================================
# get parameters
#=============================================================================
sub get_parameters {
    my $self = shift;
    return $self->_parse_parameters($self->env->{'QUERY_STRING'});
}

#=============================================================================
# body parameters
#=============================================================================
sub post_parameters {
    my $self = shift;
    my $buffer;
    
    return {} if $self->method ne 'post';
    
    if (my $tt = ($self->env->{'client.input'} || $self->env->{'psgi.input'})){
        {
            local $/;
            $buffer = <$tt>;
        }
    }
    
    else {
        read( STDIN, $buffer, $self->env->{ "CONTENT_LENGTH" } );
    }
    
    if ($self->env->{CONTENT_TYPE} =~ /^multipart\/form-data/i){
        $self->env->{CONTENT_TYPE} =~ m/boundary=(.*)/;
        my $boundary = $1;
        return $self->_multipart_parameters($buffer,$boundary);
    }
    
    return $self->_parse_parameters($buffer);
}

#=============================================================================
# process multipart body parameters
#=============================================================================
sub _multipart_parameters {
    
    my $self = shift;
    my $params = shift;
    my $boundary = shift;
    
    my $CRLF = $self->crlf;
    
    $boundary = '--'.$boundary;
    
    if ($params =~ s/$CRLF$boundary--//g){
        #return 'ok';
    }
    
    my @params = split($boundary.$CRLF,$params);
    
    my @query;
    my $handle;
    
    for my $field (@params){
        
        ##remove first line
        $field =~ s/^$CRLF//;
      
        ##remove last blank
        $field =~ s/$CRLF$//;
        
        ##split on first 2 line breaks
        my ($header,$content) = split(/$CRLF$CRLF/,$field,2);
        
        if (!$header){
            next;
        }
        
        ##split header on line break
        my ($name,$filename,$contenttype) =
        $header =~ m/
        name="?([^\";]*)"?
        (?:;\s+filename="?([^\"]*)"?$CRLF)?
        (?:Content-Type:(.*))?
        /x;
        
        my $fh;
        if($filename){
            
            $fh = IO::File->new("> /xampp/htdocs/CakeBlog/$filename");
            if (defined $fh) {
                binmode($fh);
                print $fh $content;
                $fh->close;
                $handle = $fh;
            }
            
            $self->{uploads}->{$name} = {
                'filehandle' => $handle,
                'filename' => $filename,
                'content-type' => $contenttype
            };
            
            $content = $filename;
        }
        
        push(@query,$name.'='.Cake::URI::uri_encode($content));
    }
    
    my $query = join('&',@query);
    return $self->_parse_parameters($query);
}

#=============================================================================
# return processed parameters
#=============================================================================
sub parameters {
    my $self = shift;
    return $self->{'params'} if $self->{'params'};
    my $params = Cake::Utils::combineHashes($self->get_parameters,$self->post_parameters);
    $self->{'params'} = $params;
    return $params;
}

#=============================================================================
# parse parameters
#=============================================================================
sub _parse_parameters {
    
    my $self = shift;
    my $content = shift;
    my $params = {};
    
    my @pairs = split(/[&;]/, $content);
    foreach my $pair (@pairs) {
        my ($name, $value) = map Cake::URI::uri_decode($_), split( "=", $pair, 2 );
        
        if ($name =~ s/\[(\d+)\]\[(.*?)\]//){
            my $index = $1;
            my $n = $2;
            if (!ref $params->{$name}){
                $params->{$name} = [];
            }
            $params->{$name}->[$index]->{$n} = $value;
        } else {
            
            if ($name =~ s/\[\]$// && !ref $params->{$name}){
                $params->{$name} = [];
            }
            
            if ($params->{$name}){
                if (!ref $params->{$name}){
                    my $holds = [$params->{$name},$value];
                    $params->{$name} = $holds;
                } else {
                    push (@{$params->{$name}},$value);
                }
            } else {
                $params->{$name} = $value;
            }
        }
    }
    
    return $params;
}



#=============================================================================
# XXX - TODO return uploads info & file handle
#=============================================================================
sub uploads {
    
    my $self = shift;
    
    #didn't parse params yet 
    unless (defined $self->{'params'}){
        $self->parameters();
    }
    
    return {} if !$self->{uploads};
    return $self->{uploads};
}

#serve content as psgi
sub serve_as_psgi {
    
    my $self = shift;
    
    my @headers = $self->_get_psgi_headers;
    
    my $body = $self->body();
    
    seek($body,0,0) if ref $body eq 'GLOB';
    
    if (!ref $body){
        $body = [ $body ];
    }
    
    elsif (ref $body eq 'CODE'){
        
        return sub {
            my $response = shift;
            my $w = $response->([ $self->status_code(), \@headers ]);
            $body->($w);
        };
        
        return $body;
    }
    
    return [ $self->status_code, \@headers, $body ];
}


sub _get_psgi_headers {
    
    my $self = shift;
    
    my @headers = ('Content-Type',$self->content_type);
    
    foreach my $header (@{$self->headers}){
        my @nh = split(/:/,$header,2);
        push (@headers,@nh);
    }
    
    return @headers;
}


sub print_headers {
    
    my $self = shift;
    
    my $headers;
    
    ##normal print/ for CGI
    my $content_type_header = 'Content-Type: '.$self->content_type;
    my $status_code = 'Status-code: '.$self->status_code;
    
    $headers = Cake::Utils::get_status_code($self->env,$self->status_code);
    $headers = "HTTP/1.1 Status: ".$self->status_code."\015\012";
    
    $headers .= "$content_type_header\015\012";
    
    my $found_content_length;
    foreach my $header (@{$self->headers}){
        $headers .= $header."\015\012";
        $found_content_length = 1
        if $header =~ /^Content-Length/i && !$found_content_length;
    }
    
    unless ($found_content_length){
        my $body = $self->body();
        $headers .= "Content-Length: ".Cake::Utils::content_length($body)."\015\012";
    }
    
    $headers .= "\015\012";
    my $stdout = $self->stdout;
    print $stdout $headers;
    
}


sub print_body {
    
    my $self = shift;
    my $body = $self->body();
    
    my $stdout = $self->stdout;
    binmode $stdout;
    
    if (ref $body eq 'GLOB'){
        ##seek to the start
        seek($body,0,0);
        local $/ = undef;
        $body = <$body>;
        print $stdout $body;
    }
    
    elsif (ref $body eq 'CODE'){
        $body->(__PACKAGE__);
        #print $body->();
    }
}


#=============================================================================
# ENV
#=============================================================================
sub path {
    if (@_ > 1){
        $_[0]->env->{PATH_INFO} = $_[1];
        return $_[0];
    }
    return $_[0]->env->{PATH_INFO} || '/';
}


sub method {
    if (@_ > 1){
        $_[0]->env->{REQUEST_METHOD} = $_[1];
    }
    return lc $_[0]->env->{REQUEST_METHOD};
}

sub is_secure {
    return $_[0]->env->{'SSL_PROTOCOL'} ? 1 : 0;
}

sub base {
    my $self = shift;
    my $base = 'http';
    $base .='s' if $self->is_secure();
    $base .= '://'.$self->env->{HTTP_HOST};
    return $base;
}


sub host {
    return $_[0]->env->{HTTP_HOST};
}

sub server_protocol {
    return shift->env->{SERVER_PROTOCOL} || 'HTTP/1.1';
}


sub request_header {
    
    my $self = shift;
    my $header = uc shift;
    my $response_headers = {
        'ETAG' => 'IF-NONE-MATCH'
    };
    $header =~ s/^(HTTP[-_])//;
    $header =~ s/[-\s]/_/g;
    $header = $response_headers->{$header} || $header;
    $header = 'HTTP_'.$header;
    return $self->env->{$header};
}


sub stdout {
    my $self = shift;
    if (@_){
        $self->env->{client} = shift;
    }
    return $self->env->{client} || \*STDOUT;
}


#=============================================================================
# cookies : return cookies list as hash - copied from plack
#=============================================================================
sub cookies {
    my $self = shift;

    return {} unless $self->env->{HTTP_COOKIE};

    # HTTP_COOKIE hasn't changed: reuse the parsed cookie
    if (   $self->env->{'cake.cookie.parsed'}
        && $self->env->{'cake.cookie.string'} eq $self->env->{HTTP_COOKIE}) {
        return $self->env->{'cake.cookie.parsed'};
    }

    $self->env->{'cake.cookie.string'} = $self->env->{HTTP_COOKIE};

    my %results;
    my @pairs = grep /=/, split "[;,] ?", $self->env->{'cake.cookie.string'};
    
    for my $pair ( @pairs ) {
        # trim leading trailing whitespace
        $pair =~ s/^\s+//; $pair =~ s/\s+$//;
        #my ($key, $value) = split( "=", $pair, 2 );
        my ($key, $value) = map Cake::URI::uri_decode($_), split( "=", $pair, 2 );
        # Take the first one like CGI.pm or rack do
        $results{$key} = $value unless exists $results{$key};
    }

    $self->env->{'cake.cookie.parsed'} = \%results;
    return \%results;
}

#=============================================================================
# set/get a cookie
#=============================================================================
sub cookie {
    my $self = shift;
    
    if (ref $_[0] eq 'HASH'){
        
        my $args = shift;
        my $name = Cake::URI::uri_encode($args->{name} || ref $self->app);
        my $value = Cake::URI::uri_encode($args->{value} || '');
        my $secure = $args->{secure} || '0';
        my $path = $args->{path} || '/';
        
        my $time = '';
        
        if ($args->{length}){
            my $length = Cake::Utils::to_epoch($args->{length});
            $time = gmtime($length)." GMT";
        }
        
        my $cookie = "$name=$value; path=$path; expires=$time; $secure";
        $self->push_header('Set-Cookie: '.$cookie);
    }
    
    croak 'cookie method only accepts Hash ref for setting and string for getting'
    if ref $_[0] || @_ > 1;
    
    my $name = shift || '';
    return $self->cookies->{$name};
    
}


1;