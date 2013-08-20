package Cake::Utils;
use warnings;
use strict;
use Carp;
use Cake::Utils::Serializer;
use base 'Exporter';
our @EXPORT = qw(
    run_once
    get_file
    create_file
    create_folder
    crlf
    serialize
);

our $VERSION = '0.004';

# copied from Plack which in return copied from HTTP::Status
my %StatusCode = (
    100 => 'Continue',
    101 => 'Switching Protocols',
    102 => 'Processing',                      # RFC 2518 (WebDAV)
    200 => 'OK',
    201 => 'Created',
    202 => 'Accepted',
    203 => 'Non-Authoritative Information',
    204 => 'No Content',
    205 => 'Reset Content',
    206 => 'Partial Content',
    207 => 'Multi-Status',                    # RFC 2518 (WebDAV)
    300 => 'Multiple Choices',
    301 => 'Moved Permanently',
    302 => 'Found',
    303 => 'See Other',
    304 => 'Not Modified',
    305 => 'Use Proxy',
    307 => 'Temporary Redirect',
    400 => 'Bad Request',
    401 => 'Unauthorized',
    402 => 'Payment Required',
    403 => 'Forbidden',
    404 => 'Not Found',
    405 => 'Method Not Allowed',
    406 => 'Not Acceptable',
    407 => 'Proxy Authentication Required',
    408 => 'Request Timeout',
    409 => 'Conflict',
    410 => 'Gone',
    411 => 'Length Required',
    412 => 'Precondition Failed',
    413 => 'Request Entity Too Large',
    414 => 'Request-URI Too Large',
    415 => 'Unsupported Media Type',
    416 => 'Request Range Not Satisfiable',
    417 => 'Expectation Failed',
    422 => 'Unprocessable Entity',            # RFC 2518 (WebDAV)
    423 => 'Locked',                          # RFC 2518 (WebDAV)
    424 => 'Failed Dependency',               # RFC 2518 (WebDAV)
    425 => 'No code',                         # WebDAV Advanced Collections
    426 => 'Upgrade Required',                # RFC 2817
    449 => 'Retry with',                      # unofficial Microsoft
    500 => 'Internal Server Error',
    501 => 'Not Implemented',
    502 => 'Bad Gateway',
    503 => 'Service Unavailable',
    504 => 'Gateway Timeout',
    505 => 'HTTP Version Not Supported',
    506 => 'Variant Also Negotiates',         # RFC 2295
    507 => 'Insufficient Storage',            # RFC 2518 (WebDAV)
    509 => 'Bandwidth Limit Exceeded',        # unofficial
    510 => 'Not Extended',                    # RFC 2774
);

=head2 get_file

Get content of a file

    Cake::Utils::get_file('/path/to/some/file');

=cut

sub get_file {
    my $file = shift;
    open my $cont, '<', $file or croak "Can't open $file for input:\n$!";
    local $/;
    my $content = <$cont>;
    close $cont;
    return $content;
}

sub create_file {
    my ($options) = @_;
    my $folder = $options->{folder};
    my $file = $options->{file} || croak "You must provide a file name";
    my $content = $options->{content} || "";
    
    if ($folder){
        #create_folder($folder);
        $folder =~ s/\/$//;
        $file =~ s/^\///;
        $file = $folder.'/'.$file;
    } else {
        my @paths = split '/', $file;
        my $file = pop @paths;
        my $folder = join '/', @paths;
        $file = $folder.'/'.$file;
    }
    
    return $file;
}

sub create_folder {
    my $folder = shift;
    if (! -e "$folder") {
        mkdir($folder) or croak "Can't create $folder : $!\n";
    }
}

sub combineHashes {
    my ($hash1,$hash2) = @_;
    while (my($key,$value) = each(%{$hash2})) {
        
        if ($hash1->{$key}){
            if (!ref $hash1->{$key}){
                my $holds = [$hash1->{$key},$value];
                $hash1->{$key} = $holds;
            } else {
                push (@{$hash1->{$key}},$value);
            }
        } else {
            $hash1->{$key} = $value;
        }
    }
    return $hash1;
}

sub content_length {
    my $body = shift;
    return unless defined $body;
    if (!ref $body) {
        return length($body);
    } elsif ( ref $body eq 'GLOB' ) {
        return tell($body);
    }
    return;
}

#============================================================================
# Require & noRequire
#============================================================================
sub Require {
    return noRequire(@_,'Require');
}

sub noRequire {
    my $class = shift;
    my $namespace = shift;
    my $require = shift;
    if ($namespace){
        unless ($class =~ s/^\+//){
            $class = $namespace.'::'.$class;
        }
    }
    
    my $package = $class;
    $package =~ s/::/\//g;
    $package .= '.pm';
    
    if ($require){
        if (!$INC->{$package}){
            eval 'require "$package"';
        } if ($@){
            croak ($@);
        }
    }
    return $class;
}


sub get_status_code {
    my $env = shift;
    my $message = $StatusCode{$_[0]};
    
    if ($env->{'http.version'} && $env->{'http.version'} == 1.0){
        return "HTTP/1.0 $_[0] $message\015\012";
    }
    return "Status: $_[0] $message\015\012";
}

#============================================================================
# convert givin date to epoch
#============================================================================

=head1 to_epoch('1m')

convert predefined values to Unix machine time

    Cake::Utils::to_epoch('1h');
    
    #values
    
    y = year
    M = month
    d = day
    h = hour
    m = minute
    "othing"  = seconds

=cut

sub to_epoch {
    my $length = shift || '1h'; ##one hour is the default value
    my $types = {
        'm' => sub {return 60*$_[0]},  ##minute
        'h' => sub {return 3600*$_[0]},  ##hour
        'd' => sub {return (24*3600)*$_[0]},  ##day
        'M' => sub {return (30*24*3600)*$_[0]}, ##month
        'y' => sub {return (365*24*3600)*$_[0]}, ##year
    };
    
    my ($num,$type) = $length =~ /(\d*)(\w)/;
    $num = 1 if !$num;
    my $expire;
    if ($types->{$type}){
        $expire = $types->{$type}->($num);
    }
    
    else {
        $expire = $length || 3600;
    }
    
    return $expire+time();
}

#============================================================================
# OS crlf : copied from CGI::Simple
#============================================================================
sub crlf {
    #return "\n";
    my ( $self, $CRLF ) = @_;
    $self->{'app.crlf'} = $CRLF if $CRLF;    # allow value to be set manually
    unless ( $self->{'app.crlf'} ) {
      my $OS = $^O;
      $self->{'app.crlf'}
       = ( $OS =~ m/VMS/i ) ? "\n"
       : ( "\t" ne "\011" ) ? "\r\n"
       :                      "\015\012";
    }
    
    return $self->{'app.crlf'};
}

#============================================================================
# Random String Generator
#============================================================================
sub random_string {
    my $num = shift || 16;
    return time().join '',map { sprintf q|%X|, rand($num) } 1 .. 36;
}

sub serialize {
    shift; #shift cake class
    return Cake::Utils::Serializer->new(shift);
}
#============================================================================
# Check for persistance
# FIXME: I'm not sure if this has no bugs at all
#
# FROM perldocs
# --------------------------------------------------------------------------
# The CHECK and INIT blocks in code compiled by require, string do, or string
# eval will not be executed if they occur after the end of the main compilation
# phase; that can be a problem in mod_perl and other persistent environments
# which use those functions to load code at runtime.
#
# Which exactly what I'm using as an advantage :)
#============================================================================
my $run_once = 0;

{
    no warnings;  
    INIT {
        $run_once = 1;
    }
}

sub run_once {
    my $self = shift;
    if (exists $self->env->{run_once}){
        return $self->env->{run_once};
    }
    return $run_once;
}

1;

__END__
