package Cake::Server::Simple;
use IO::Socket::INET;
use strict;
use Carp;
use Cake::URI;
use constant DEBUG => 1;
use IO::Select;

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
        prefork            => $args{prefork},
        select             => IO::Select->new()
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
    
    $self->{env} = {
        SERVER_PORT => $self->{port},
        SERVER_NAME => $self->{host},
        SCRIPT_NAME => '',
        REMOTE_ADDR => $self->{socket}->peerhost,
        'psgi.version' => [ 1, 1 ],
        'http.version' => 1.1,
        'psgi.errors'  => *STDERR,
        'psgi.url_scheme' => $self->{ssl} ? 'https' : 'http',
        'psgix.io'        => $self->{socket},
        'run_once' => 0,
        'cake.server' => $self
    };
    
    if (my $num = $self->{prefork}) {
        for (1 .. $num){
            if (my $pid = fork()){
                next;
            } else {
                $self->loop($app);
            }
        }
    } else {
        $self->loop($app);
    }
    
    exit(0);
}

sub loop {
    my ($self,$app) = @_;
    print "listen on $self->{port}\n";
    my $fh = $self->{socket};
    $self->{socket}->blocking(0);
    $self->{select}->add($fh);
    
    while (1){
        select(undef,undef,undef,.01);
        my @ready = $self->{select}->can_read(0.01);
        foreach my $fh (@ready){
            if ( $fh == $self->{socket} ){
                my $new = $fh->accept();
                $self->{select}->add($new);
            } else {
                $self->{select}->remove($fh);
                DEBUG and warn "Sending To Process [$$]\n";
                my $env = $self->process($fh);
                $fh->shutdown(2) && next if $env == -1;
                $app->($env);
                $fh->shutdown(2);
                $fh->close;
            }
        }
    }
    return;
}

##mostly from plack
sub process {
    my ($self,$fh,$app,$env) = @_;
    my $content;
    $env = { %{ $self->{env} } };
    $env->{client} = $fh;
    $fh->blocking(0);
    my $disconnect = 0;
    
    ##TO DO handle timeouts
    while (1) {
        my $bytes_read = sysread($fh, my $buf, 1024);
        if (defined $bytes_read && $bytes_read > 0){
            $content .= $buf;
            ##on read
        } elsif (defined $bytes_read && $bytes_read == 0) {
            #on client disconnect
            DEBUG and warn "client disconnected \n";
            $disconnect = 1;
            last;
        } elsif (!defined $bytes_read){
            #on EOF
            DEBUG and warn "EOF\n";
            last;
        }
    };
    
    return -1 if $disconnect;
    my ($headers,$body) = split /\x0d?\x0a\x0d?\x0a/, $content, 2;
    my @headers  = split /\x0d?\x0a/,$headers;
    my $request = shift @headers;
    my ($method,$uri,$http) = split / /,$request;
    
    return -1 unless $http and $http =~ /^HTTP\/(\d+)\.(\d+)$/i;
    
    my ($major, $minor) = ($1, $2);
    $env->{SERVER_NAME}  = 'CAKE-SERVER-SIMPLE';
    $env->{REQUEST_METHOD}  = $method;
    $env->{SERVER_PROTOCOL} = "HTTP/$major.$minor";
    
    $env->{REQUEST_URI}     = $uri;
    my($path, $query) = ( $uri =~ /^([^?]*)(?:\?(.*))?$/s );
    for ($path, $query) { s/\#.*$// if defined && length } # dumb clients sending URI fragments
    $env->{PATH_INFO}    = Cake::URI::uri_encode($path);
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


1;

__END__


=head1 NAME

Cake::Server::Simple

=head1 SYNOPSIS

    use Cake::Server::Simple;
    use App;
    
    my $app = sub {
        my $env = shift;
        App->bake($env)->serve();
    };
    
    my $server = Cake::Server::Prefork->new(
        port => 8080,
        host => 'localhost',
        prefork => 2 ##number of child process
    );

    $server->run($app);
    
    1;

=head1 DESCRIPTION

Cake embeded development server, mainly for testing and development purposes, but can work with simple projects too
This server is meant to act kinda like Plack servers so you can port your code to plack later if you want.

=head1 OPTIONS

=head2 port

port number to listen to

=head2 host

=head2 prefork

set number of child processes to prefork, value must be a number 1 and more
you can omit this option completely and the server will be event based

