package Cake::DBI::Class;
use strict;
use warnings;
use Cake::DBI::Abstract;
use DBI;
use POSIX 'ceil';
use Carp;


sub new {
    my $class = shift;
    my $self = {};
    $self->{_connect} = \@_;
    $self->{sql} = Cake::DBI::Abstract->new();
    return bless ($self,$class);
}

sub _connect {
    my $self = shift;
    $self->{dbh} = DBI->connect(@{$self->{_connect}});
    return $self->{dbh};
}

sub sql { return shift->{sql}; }

sub dbh {
    my $self = shift;
    return $self->{dbh} || $self->_connect();
}

sub commit {
    return shift->dbh->commit;
}

##turn auto-commit off while working
sub begin_work {
    my $self = shift;
    $self->dbh->begin_work;
}



sub _dbi {
    
    my ($self,$query,$values,$type) = @_;
    my (@rows,$rows);
    
    my $dbh = $self->dbh;
    
    ##prepare sql statement
    my $sth = $dbh->prepare($query);
    
    ##set error handler
    $dbh->{HandleError} = sub {
        my $message = shift;
        croak $message;
    };
    
    if ($type eq 'count'){
        
        $sth->execute( @{$values} );
        my ($total_count) = $sth->fetchrow;
        $sth->finish();
        return $total_count;
    }
    
    elsif ($type eq 'create'){
        my $num = $sth->execute( @{$values} );
        my $id = $dbh->{ q{mysql_insertid}};
        
        if (!$id){
            $id = $dbh->last_insert_id(undef, undef, undef, undef);
        }
        
        $sth->finish();
        return $id;
    }
    
    elsif ($type eq 'update'){
        my $num = $sth->execute( @{$values} );
        $sth->finish();
        return $num;
    }
    
    elsif ($type eq 'delete'){
        my $num = $sth->execute( @{$values} );
        $sth->finish();
        return $num;
    }
    
    elsif ($type eq 'all'){
        $rows = $dbh->selectall_arrayref($sth,{ Slice => {} }, @{$values});
        $self->{cached_results} = $rows;
        return wantarray ? @{$rows} : $rows;
    }
    
    elsif ($type eq 'single') {
        my $hash_ref = $dbh->selectrow_hashref($sth,undef, @{$values});
        return $hash_ref;
    }
    
    else {
        $rows = $dbh->selectall_arrayref($sth,{ Slice => {} }, @{$values});
        $self->{cached_results} = $rows;
        return wantarray ? @{$rows} : $rows;
    }
    
    return @rows;
}


sub DESTROY {
    my $self = shift;
    if (my $dbh = $self->{dbh}) {
        %{ $dbh->{CachedKids} } = ();
        $dbh->disconnect;
        $self->{_connect} = undef;
    }
}




*find = \&search;
sub search {
    my $self = shift;
    $self->sql->where(@_);
    return $self;
}

*tables = \&table;
sub table {
    my $self = shift;
    $self->sql->from(@_);
    return $self;
}


sub columns {
    my $self = shift;
    $self->sql->select(@_);
    return $self;
}

sub all {
    my $self = shift;
    my ($sql,@binds) = $self->sql->query;
    return $self->_dbi($sql,\@binds,'all');
}


sub single {
    my $self = shift;
    my ($sql,@binds) = $self->sql->query;
    return $self->_dbi($sql,\@binds,'single');
}


sub first {
    my $self = shift;
    return $self->next;
}


sub next {
    my $self = shift;   
    if (my $cache = $self->{cached_results}){
        $self->{cache_position} ||= 0;
        return $cache->[$self->{cache_position}++];
    }
    
    my @results = $self->all;
    my ($row,@rows)  = @results;
    $self->{cached_results} = \@rows;
    return $row;
}

sub create {
    my $self = shift;
    my ($sql,@binds) = $self->sql->create(@_);
    return $self->_dbi($sql,\@binds,'create');
}

sub delete {
    my $self = shift;
    my $args = shift;
    if ($args){
        croak "Delete Only accept HASH ref" if ref $args ne 'HASH';
        $self->sql->where($args);
    }
    my ($sql,@binds) = $self->sql->delete('DELETE');
    return $self->_dbi($sql,\@binds,'delete');
}

sub update {
    my $self = shift;
    my ($sql,@binds) = $self->sql->update(@_);
    return $self->_dbi($sql,\@binds,'update');
}


sub literal {
    my $self = shift;
    $self->sql->literal(@_);
    return $self;
    #return $self->_dbi($sql,$binds,'all');
}


sub total {
    
    my $self = shift;
    my $total;
    my $limit = $self->sql->limit;
    
    return $self->{_total} if $self->{_total};
    
    ###if no limits then return cached numbers
    if (!$limit && $self->{cached_results}){
        $total = scalar @{$self->{cached_results}};
    }
    
    else {
        my ($sql,@binds) = $self->sql->count();
        $total = $self->_dbi($sql,\@binds,'count');
    }
    
    $self->{_total} = $total;
    return $total;
    
}

sub limit {
    my $self = shift;
    $self->sql->limit(@_);
    return $self;
}

sub order {
    my $self = shift;
    $self->sql->order(@_);
    return $self;
}

sub pages {
    my $self = shift;
    my $total = $self->total;
    my $rows = $self->sql->{limit}->{rows} || undef;
    if ($rows){
        my $total_pages = $total < $rows ? 1 : POSIX::ceil($total / $rows);
        return $total_pages;
    } else {
        return 1;
    }
}



1;


__END__

=head1 NAME

Cake::DBI::Class

=head1 DESCRIPTION

Simple Mysql & sqlite Database abstraction layer

=head1 SYNOPSIS

    use Cake::DBI::Class;
    
    my $sql = Cake::DBI::Class->new(
        'dbi:mysql:table',
        'root',
        'password',
        { RaiseError => 1, AutoCommit => 0 }
    );
    
    $sql->table('users');
    $sql->find(
        uid => '1'
    );
    
    $sql->single;
    
=cut

=head1 Methods

=head2 new

new constructor - accept list of database connection options,
the same as DBI connect
    
    ->new(
        'dbi:mysql:table',
        'root',
        'password',
        { RaiseError => 1, AutoCommit => 0 }
    );


=head2 search

=head2 find

An aliase for search

=head2 all

returns all matched records as a list of hash refs
    
    [
        {
            col1 => val1
        },
        {
            col1 => val1
        },
        ...
    ]
    
=cut

=head2 single

fetches first matched record and returns it as a hash ref

    {
        col => val
    }

=cut

=head2 first

fetches all matched records and cache them then returns the first record only as a hash ref

    {
        col => val
    }

=cut
