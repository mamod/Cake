package Cake::Plugins::Simple::Cache;
use Cake 'Plugin';
use Carp;

my $settings;
my $cacheinstance;

sub _cache {
    $settings = settings if !$settings;   #memoize
    $cacheinstance = Cake::Plugins::Simple::Cache::Base->new(
        cache_root => $settings->{cache_root},
        expire_time => $settings->{expire_time},
        depth => $settings->{depth}
    );
    
    return $cacheinstance;
}

sub cache {
    my $self = shift;
    if (@_ > 1 && ref $_[1]){
        return _cache->set(@_);
    }
    
    return _cache->get(@_);
}


sub get_cache_location {
    shift;
    my ($path,$file) = _cache->_get_path_and_file(@_);
    
    wantarray ? return ($path,$file) : 
    return $path.'/'.$file;
}


sub newCache {
    my $self = shift;
    my %settings = @_;
    return Cake::Plugins::Simple::Cache::Base->new(%settings);
}


register();



package #hide
    Cake::Plugins::Simple::Cache::Base;
    use Digest::MD5 qw(md5_hex);
    use File::Spec;
    use File::Path qw(make_path);
    use Storable qw( retrieve nstore );
    
    
sub new {
    
    my $class = shift;
    my %options = @_;
    
    my $self = {
        expire_time => $options{expire_time} || 3600,
        cache_root => $options{cache_root} || '/',
        depth => $options{depth} || 3
    };
    
    $self = bless ($self,$class);
    return $self;
    
}


sub cache {
    my $self = shift;
    if (@_ > 1 && ref $_[1]){
        return $self->set(@_);
    }
    return $self->get(@_);
}

sub set {
    
    my $self = shift;
    my ($name,$data,$expire,$subfolder) = @_;
    
    ###get expire time
    my $expire_time = $self->_get_expire_time($expire || $self->{expire_time});
    
    ###get file and path
    my ($path,$file) = $self->_get_path_and_file($name,$subfolder);
    my $fullfile = $path.'/'.$file;
    
    make_path( $path, {
        mode => 0755
    }); #if !-d $path;
    #mkpath( $path, 0, 775 ) if !-d $path;
    
    my $ca = {
        expire_time => $expire_time,
        date_created => time(),
        data => $data
    };
    
    nstore ($ca, $fullfile) or die "can't write to $fullfile\n";
    return $data;
    
    
}

sub get {
    my ($self,$name,$subfolder) = @_;
    if ($subfolder && $subfolder =~ m/^\//){
        $self->{cache_root} = $subfolder;
        $subfolder = '';
    }
    
    my ($path,$file) = $self->_get_path_and_file($name,$subfolder);
    $file = $path.'/'.$file;
    
    local $SIG{__DIE__} = 'IGNORE';
    
    my $data;
    
    eval {
        $data = retrieve($file);
    };
    
    if ($@){
        #die $@;
        undef $@;
        return 0;
    } elsif (time() > $data->{expire_time}){
        return 0;
    }
    
    return $data->{data};
}


sub _get_expire_time {
    my $self = shift;
    my $length = shift;
    return Cake::Utils::to_epoch($length);
}


sub _get_path_and_file {
    
    my ($self,$name,$subfolder) = @_;
    my $digest = md5_hex($name);
    
    ###get folder map
    my @deep;
    my $file = $digest;
    
    push( @deep,
        map { substr( $digest, $_, 1 ) } ( 0 .. $self->{depth} - 1 ) );
    
    
    my $cache_root = $self->{cache_root};
    $cache_root .= '/'.$subfolder if $subfolder;
    
    #my $x = File::Spec->catfile(@deep, $file);
    my $path = join('/',$cache_root,@deep);
    return ($path,$file);
}

1;

__END__

=head1 NAME

Cake:;Plugin::Simple::Cache - Cake simple cache plugin

=head1 SYNOPSIS
    
    ##in the main app load this plugin
    plugins [
        'Simple::Cache' => {
            cache_root => '/path/to/cache/folder',
            expire_time => '1h',   ##expire time n(m,h,d,M,y)
            depth => '3' ##folder storage depth default 3
        },
        ....
    ];
    
    
    ##in a controller
    
    get '/cache' => sub {
        
        my ($self,$c) = @_;
        
        ##cache something
        $c->cache('unique_name',{
            key  => 'value',
            key2 => 'value2',
            ...
        });
        
        
        ###retrieve data
        my $data = $c->cache('unique_name');
        
        ##pretty print Data Dumper
        $c->dumper($data);
        
        
    };
    
=head1 DESCRIPTION

This is a very minimal file caching plugin, meaning it's designed for daily simple
caching tasks.

=head2 Override default options

By default Simple::Cache uses settings you specified in your app but if you want to
override these settings you can generate new cache instance by calling newCache()
method

    get '/cache' => sub {
        
        my ($self,$c) = @_;
        
        ##cache something in another cache folder
        
        my $othercache = $c->newCache(
            cache_root => '/some/new/caching/path',
            expire_time => '1y',
            depth => '6'
        );
        
        $othercache->cache('unique_name',{
            key  => 'value',
            key2 => 'value2',
            ...
        });
        
        
        ###retrieve data
        my $data = $othercache->cache('unique_name');
        
        ##or later any where else you can retrieve data
        
        my $data = $c->cache('unique_name','/some/new/caching/path');
        
        ##print Data Dumper
        $c->dumper($data);
        
    };

=head1 METHODS

=head2 cache

set/get cache

=over 4

=item L<cache('name',{hashref}, 'time')>

caching data, accepts 3 arguments

B<name:> a unique name for the data you want to cache - string - required

B<hashref:> data to be cached - hashref - required

B<time:> overrides the default time to expire - string - optional

=item L<cache('name','/absolute/path')>

retrieve cached data and return hashref, takes 2 arguments

B<name:> the name of the cached data to retrieve - string - required

B</absolute/path:> path from where to retrieve data - string - optional - use to retrieve data
that has been cached in non default location

=back

=head2 newCache

Overrides default application settings and returns a new Cake::Plugins::Simple::Cache::Base
object

=over 4

=item L<newCache(%options})>

B<cache_root:> overrides default cache_root

B<expire_time:> overrides default expire_time

B<depth:> overrides default depth

=back

=head1 AUTHOR

Mamod A. Mehyar, C<mamod.mehyar@gmail.com>

=cut
