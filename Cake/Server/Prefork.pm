package Cake::Server::Prefork;
use IO::Socket::INET;
use strict;
use Data::Dumper;
use IO::Handle;
use Cake::Event::Loop;
use Cake::Event::Fork;
use Carp;
use POSIX ":sys_wait_h";
use Errno qw(EAGAIN EINTR EWOULDBLOCK);
use URI::Escape;
use Storable qw(store retrieve);
use constant MAX_PROCESSES => 3;
use constant DEBUG => 1;
my $FILE = '/xampp/htdocs/CakeBlog/temp.txt';
my @socks;

my %shared;

my $CONNECTIONS = 0;

sub new {
    
    my($class, %args) = @_;

    my $self = bless {
        host               => $args{host} || 0,
        port               => $args{port} || 8080,
        timeout            => $args{timeout} || 15,
        server_software    => $args{server_software} || $class,
        server_ready       => $args{server_ready} || sub {},
        ssl                => $args{ssl},
        ipv6               => $args{ipv6},
        ssl_key_file       => $args{ssl_key_file},
        ssl_cert_file      => $args{ssl_cert_file},
    }, $class;
    
    return $self;
    
}

sub run {
    
    my ($self,$app) = @_;
    
    $self->{socket} = IO::Socket::INET->new(
        LocalHost => $self->{host},
        LocalPort => $self->{port},
        Listen    => SOMAXCONN,
        Proto => 'tcp',
        Reuse => 1
    ) or die "Cant't create a listening socket: $@";
    
    my $parent;
    
    #my $data2 = {pp=>'kk'};
    #store $data2,$FILE;
    
    $self->{env} = {
        SERVER_PORT => $self->{port},
        SERVER_NAME => $self->{host},
        SCRIPT_NAME => '',
        REMOTE_ADDR => $self->{socket}->peerhost,
        'psgi.version' => [ 1, 1 ],
        'http.version' => 1.0,
        'psgi.errors'  => *STDERR,
        'psgi.url_scheme' => $self->{ssl} ? 'https' : 'http',
        'psgix.io'        => $self->{socket},
        'run_once' => 0,
        'cake.server' => $self
    };
    
    
    my $servers = Cake::Event::Fork->new(MAX_PROCESSES);
    while (1){
        $servers->start();
        unless ($servers->is_parent){
            $self->handle_connection($app);
        }
        $servers->finish();
    }
    
    $servers->wait_all();
    return 1;
}

sub handle_connection {
    
    my ($self,$app) = @_;
    my $loop = Cake::Event::Loop->new();
    my $sel = $loop->io_select;
    
    $self->{socket}->blocking(0);
    my $counter = 0;
    
    $loop->io(
        fh => $self->{socket},
        poll => 'read',
        idle => sub {
            
            $counter++;
            exit $$ if $counter > 1000;
            
        },
        
        callback => sub {
            
            my $fh = shift;
            
            select(undef,undef,undef,0.01);
            
            if ( $fh == $self->{socket} ){
                my $new = $fh->accept();
                $sel->add($new);
            }
            
            else {
                
                $sel->remove($fh);
                DEBUG and warn "Sending To Process [$$]\n";
                my $env = $self->process($fh);
                $fh->shutdown(2) && return if $env == -1;
                
                $app->($env);
                $fh->shutdown(2);
                $fh->close;
            }
            
            $counter = 0;
            
        }
        
    );
    
    print "listen on $self->{port}\n";
    $loop->loop;
    
}




sub process {
    
    my ($self,$fh,$app,$env) = @_;
    
    my $content;
    $env = { %{ $self->{env} } };
    $env->{client} = $fh;
    $fh->blocking(0);
    
    my $disconnect = 0;
    
    my $event = Cake::Event::Loop->new();
    $event->timer(
        
        after => 2, #timeout
        
        callback => sub {
            die;
            DEBUG and  "Client Time Out\n";
            $disconnect = 1;
        },
        
        ##read buffer while idle
        idle => sub {
            
            my $bytes_read = sysread($fh, my $buf, 1024);
            
            if (defined $bytes_read && $bytes_read > 0){
                $content .= $buf;
                ##on read
            } elsif (defined $bytes_read && $bytes_read == 0) {
                #on client disconnect
                DEBUG and warn "client disconnected \n";
                $disconnect = 1;
                $event->terminate;
                
            } elsif (!defined $bytes_read){
                #on EOF
                DEBUG and warn "EOF\n";
                $event->terminate;
            }
        }
    );
    
    $event->loop;
    
    return -1 if $disconnect;
    
    
    my ($headers,$body) = split /\x0d?\x0a\x0d?\x0a/, $content, 2;
    my @headers  = split /\x0d?\x0a/,$headers;
    my $request = shift @headers;
    
    my ($method,$uri,$http) = split / /,$request;
    
    return -1 unless $http and $http =~ /^HTTP\/(\d+)\.(\d+)$/i;
    
    my ($major, $minor) = ($1, $2);
    
    $env->{SERVER_NAME}  = 'CAKE-SERVER-PREFORK';
    $env->{REQUEST_METHOD}  = $method;
    
    $env->{SERVER_PROTOCOL} = "HTTP/$major.$minor";
    
    $env->{REQUEST_URI}     = $uri;
    my($path, $query) = ( $uri =~ /^([^?]*)(?:\?(.*))?$/s );
    for ($path, $query) { s/\#.*$// if defined && length } # dumb clients sending URI fragments
    $env->{PATH_INFO}    = URI::Escape::uri_unescape($path);
    $env->{QUERY_STRING} = $query || '';
    $env->{SCRIPT_NAME}  = '';
    
    my $token = qr/[^][\x00-\x1f\x7f()<>@,;:\\"\/?={} \t]+/;
    my $k;
    for my $header (@headers) {
        
        if ( $header =~ s/^($token): ?// ) {
            $k = $1;
            $k =~ s/-/_/g;
            $k = uc $k;

            if ($k !~ /^(?:CONTENT_LENGTH|CONTENT_TYPE)$/) {
                $k = "HTTP_$k";
            }
        } elsif ( $header =~ /^\s+/) {
            # multiline header
            
        }
        
        if (exists $env->{$k}) {
            $env->{$k} .= ", $header";
        } else {
            $env->{$k} = $header;
        }
    }
    
    
    if ($env->{CONTENT_LENGTH} && $env->{REQUEST_METHOD} =~ /^(?:POST|PUT)$/) {
        open my $body_fd, "<", \$body;
        $env->{'client.input'} = $body_fd;
    }
    
    
    return $env;
}



#sub write_parent {
#    my $self = shift;
#    #my $data = {test=>'val'};
#    #store $data,$FILE;
#    open (my $io,'>>',$FILE);
#    $io->write('hi');
#}


1;



__END__











