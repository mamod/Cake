package Cake::Model::DBI;
use strict;
use warnings;
use Carp;
use base 'Cake::DBI::Class';
use Data::Dumper;
my $TABLES = {};
my $CONNECT = {};

sub init {
    my $self = shift;
    my $c = shift;
    
    ##search down parent packages until we get connection
    my $package = $self;
    my $connect;
    
    $connect = $CONNECT->{$self};
    while ( !$connect && $package =~ s/(.*)::// ){
        $connect = $CONNECT->{$1};
    }
    
    my @connect = $connect ? ref $connect->[0] eq 'CODE' ?
    @{ $connect->[0]->($c) } : @{$connect}
    : _con($c);
    
    my $blessed = $self->new(@connect);
    $blessed->table(@{$TABLES->{$self}});
    ##pass c object
    $blessed->{c} = $c;
    return $blessed;
}

sub _con {
    my $self = shift;
    my $info = $self->{settings}->{dbic_connect};
    return @{$info};
}

sub table {
    my $self = shift;
    my @tb = @_;
    if ( !ref $self ){
        $TABLES->{$self} = \@tb;
    } else {
        $self->NEXT::table(@_);
    }
}

sub connect {
    my $self = shift;
    if ( !ref $self ){
        $CONNECT->{$self} = \@_;
    }
}

1;


__END__

=head1 NAME

Cake::Model::DBI

=head1 SYNOPSIS

    #In your App Model Folder create a module ex: DB.pm

    package App::Model::DB;
    use base 'Cake::Model::DBI';
    
    __PACKAGE__->connect(
        ##same as DBI connect info
        'dbi:SQLite:dbname=/absolute/path/test.s3db',
        '',
        '',
        { RaiseError => 1, AutoCommit => 1 }
    );
    
    1;
    
    #Now From your Controllers You can call this model
    
    package App::Controllers::Test;
    use Cake;
    
    get 'db' => sub {
        my ($self,$c) = @_;
        
        my $records = $c->model('DB')->table('users')->find(
            uid => 1
        );
        
        $c->dumper($records->single);
    };
    
    1;

=head1 DESCRIPTION

Cake glue module for Cake::DBI::Class, for more information on supported methods
please see L<Cake::DBI::Class>

=head1 PreDefine Modules and Tables

It's better practice to predefine tables in seperate modules instead of calling
table method every you want to select a table like : 

    $c->model('DB')->table('users')

To do that create a seperate model class for the table in your database

    package App::Model::DB::Users;
    
    #now define table
    
    __PACKAGE__->table('users');
    
    ##you also can predefine some methods
    
    sub get_all_users {
        
        my $self = shift;
        my $c = $self->{c};
        
        return $self->all;
        
    }
    
    
    1;

    ## call it from your controller
    
    package App::Controllers::Test;
    use Cake;
    
    get 'users' => sub {
        my ($self,$c) = @_;
        my $users = $c->model('DB::Users')->get_all_users;
        $c->dumper($users);
    };
    
    ##or maybe something not defined
    get 'user' => sub {
        my ($self,$c) = @_;
        my $user = $c->model('DB::Users')->find(
            uid => $c->param('uid')
        );
        
        $c->dumper($user);
    };
    
    
    1;
    
You can join multiple tables when you predfine table in classes
    
    package App::Model::DB::Users;
    __PACKAGE__->table(
        users => {as => 'me'},
        '-left_join' => [
            hobbies => {as => 'h'},
            '-on' => [
                'h.uid' => 'me.uid'
            ]
        ]
    );
    

=cut
