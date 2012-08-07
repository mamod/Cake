package Cake::Model::DBIC;
use strict;
use Carp;
use DBI;
use POSIX 'ceil';
our $VERSION = '0.004';
my ($TABLE,$COLUMNS,$TABLES,$CONNECT);
use Data::Dumper;
#==============================================================================
# connect
#==============================================================================
sub connect {
    my $self = shift;
    $CONNECT = \@_ if @_;
    #die Dumper $CONNECT;
}


sub _connect {
    my $self = shift;
    my $query = shift;
    
    my $info = $CONNECT || $self->{c}->{settings}->{dbic_connect};
    
    if (!$info){
        croak qq/You need to set dbic settings in your application, under
        settings dbic_connect this takes an array ref the same as DBI
        connect arguments/;
    }
    
    $self->{connect_info} = $info;
    
    my $dbh = DBI->connect(@{$info});
    
    $self->{dbh} = $dbh;
    
    return $dbh;
}

###########################Destroy dbi connection
sub DESTROY {
    
    my $self = shift;
    
    my $c = $self->{c};
    
    #
    #if ($c->debug){
    #    $c->log('database',[$self]);
    #}
    
    if (my $dbh = $self->{dbh}) {
        %{ $dbh->{CachedKids} } = ();
        $dbh->disconnect;
    }
}



#==============================================================================
# main sub
#==============================================================================
sub dbh {
    my $self = shift;
    return $self->{dbh} || $self->_connect();
}

##commit
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
    
    
    ##connect if no handle
    if (!$self->{dbh}){
        $self->_connect();
    }
    
    $self->{query} = $query;
    
    my $dbh = $self->{dbh};
    
    ##prepare sql statement
    my $sth = $dbh->prepare($query);
    
    $dbh->{HandleError} = sub {
        my $message = shift;
        $message =~ s/(.*?)at (.*)/$1/g;
        die({ message => $message ,caller=>[caller(4)]});
    };
    
    #croak $sth->err if $sth->err;
    
    if ($type eq 'count'){
        
        $sth->execute( @{$values} );
        my ($total_count) = $sth->fetchrow;
        $sth->finish();
        return $total_count;
    }
    
    elsif ($type eq 'create'){
        my $num = $sth->execute( @{$values} );
        my $id = $dbh->{ q{mysql_insertid}};
        $sth->finish();
        return $id;
    }
    
    elsif ($type eq 'update'){
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

#==============================================================================
# set/get tables - private method
#==============================================================================
sub _tb {
    my $self = shift;
    
    my $tables = $self->{tables};
    my $table = $TABLE->{ref $self};
    
    if ($tables){
        $table .= ' As me';
        $tables = join(' ',($table,@{$self->{tables}}));
    }
    
    else {
        $tables = $table;
    }
    
    return " ".$tables;
}




sub table {
    
    my $self = shift;
    my $table = shift;
    
    $TABLE->{$self} = $table;
    #use Data::Dumper;
    #
    #$TABLE = $table;
    #use Data::Dumper;
    
    return $self;
    
    if (!$table) {
        my $package = ref($self);
        no strict 'refs';
        $table = ${"${package}::settings"}->{table};
    }
    
    croak 'You have to set table/tables name first'.ref $self if !$table;
    
    ###set main table
    $self->{table} = $table =~ /\s+\w+/ ? $table : $table;
    
    return $self;
    
}


sub tables {
    
    my ($self) = shift;
    my %where = @_;
    
    my $tables = $self->_preserv(@_);
    
    $self->{__tables} = $tables;
    
    $self->_translate_tables;
    return $self;
    
}

#==============================================================================
# translate tables
#==============================================================================
sub _translate_tables {
    
    my $self = shift;
    my @tables = @{$self->{__tables}};
    #return \@where;
    
    my (@sql,$sql);
    
    my $switch = 'AND';
    
    foreach my $table (@tables){
        
        my $key = $table->[0];
        my $val = $table->[1];
        
        
        
        $sql = $self->_table($key,$val);
        
        if (ref $sql eq 'ARRAY' ){
            
            push(@sql,@{$sql});
            
        }
        
        else {
            
            push(@sql,$sql);
            
        }
        
        
    }
    
    ##delete first element ""AND/OR;
    #delete $sql[0];
    #return join(' ',@sql);
    
    push (@{$self->{tables}},@sql);
    
    return $self;
}


sub _table {
    
    my ($self,$key,$val,$opr,$type) = @_;
    
    
    my $cmp = $opr || 'As';
    my $switch = $type;
    my $sql;
    
    
    if ($key =~ /^-literal/i){
        return $val;
    }
    
    elsif (!ref $val && $key !~ /^-/){
        $sql = $key.' '.$cmp.' '.$val.$switch if $val;
        $sql = '('.$key.')'.$switch if !$val;
    }
    
    else {
        
        if (!ref $val){
            $val = [$val];
        }
        
        
        
        if ($key =~ m/^-(.*)$/gi){
            
            $self->_is_valid('-'.$1,@{$val}) if $1 != 'using';
            
            my @new = @{$val};
            my (@s,$start,$end);
            
            
            
            $switch = uc($1);
            $switch =~ s/_/ /g;
            
            if ($switch !~ /join/gi){
                $cmp = '=';
            }
            
            if ($switch eq 'ON'){
                
                $start = '(';
                $end = ')';
                
                $type = 'AND';
            }
            
            
            #$sql .= '( ';
            
            my $x = -1;
            for my $n (@new){
                
                $x++;
                next if ($x % 2);
                
                my $k = $new[$x];
                my $v = $new[$x+1];
                
                
                my $s = $self->_table($k,$v,$cmp);
                push(@s,$s);
                
            }
            
            $sql .= $switch." $start".join(" $type ", @s)."$end";
            
            #$sql .= ' )';
            
            
        }
        
        elsif (ref $val eq 'ARRAY'){
            
            $sql .= '( ';
            
            my (@s);
            foreach my $v (@{$val}){
                my $s = $self->_table($key,$v,$cmp);
                push(@s,$s);
            }
            
            $sql .= join(' OR ', @s);
            
            $sql .= ' )';
            
        }
        
        elsif (ref $val eq 'HASH'){
            
            my @map = %{$val};
            
            my $newcmp = uc($map[0]);
            
            $val = $map[1];
            $sql = $self->_table($key,$val,$newcmp,' AND');
        }
        
        
    }
    
    
    return wantarray ? ($sql,$val) : $sql;
    
}

sub _preserv {
    
    my ($self) = shift;
    my %where = @_;
    my $where = \%where;
    
    ##check if vallid hash, no single key allowed
    $self->_is_valid('table/search/find',@_);
    
    my @new;
    my $i = 0;
    my %hash = map { $i++ => $_ } @_;
    #return \%hash;
    
    #/////////////////////////////////////////
    # preserv hash order and convert to array
    #/////////////////////////////////////////
    my $index = 0;
    foreach my $key (@_){
        if (defined $where{$key}){
            push(@new,[$key,$hash{$index+1}]);
        }
        
        $index++;
    }
    
    return \@new;
    
}

sub _is_valid {
    
    my $self = shift;
    my $type = shift;
    
    if (@_ % 2){
        croak $type.' arguments must be Hashes of x => b type no single keys \'x\' allowed';
    }
    
}

#==============================================================================
# set/get columns
#==============================================================================
sub columns {
    my ($self,$val) = @_;
    
    if ($val){
        $self->{columns} = $_[1];
    }
    
    else {
        my $columns = $self->{columns};
        if ($columns){
            $columns = join(',', @{$columns});
            return ' '.$columns;
        }
        
        else {
            return ' *';
        }
        
    }
    
    
    
    return $self;
}

#==============================================================================
# search literal
#==============================================================================
sub search_literal {
    
    my $self = shift;
    my $query = shift;
    my $binds = shift;
    
    
    
    $self->{literal} = $query;
    
    if ($binds){
        $self->bind($binds);
    }
    
    return $self;
    
    #$_[0]->_dbi($_[1],$_[2]);
    #return shift;
}


sub bind {
    
    my $self = shift;
    
    if (exists $self->{bind}){
        push (@{$self->{bind}}, $_[0]);
    }
    
    else {
        $self->{bind} = $_[0];
    }
    
    return $self;
    
}


#==============================================================================
# return where
#==============================================================================
sub where {
    
    my $self = shift;
    
    return ' '.$self->{literal} if $self->{literal};
    
    if ($self->{sql}){
        my @where = @{$self->{sql}};
        #@where = map {$_ if defined ($_)} @where;
        delete $where[0];
        return ' WHERE'.join(' ',@where) if $where[1];
    }
    
    return '';
}

#==============================================================================
# search
#==============================================================================
*find = \&search;
sub search {
    
    my ($self) = shift;
    
    
    my $new = $_[0];
    
    if (wantarray){
        return @{$new};
    }
    
    $self->{where} = $new;
    $self->_translate_where;
    return $self;
    
}

#==============================================================================
# translate where clause
#==============================================================================
sub _translate_where {
    
    my $self = shift;
    my $where = shift || $self->{where};
    #return \@where;
    
    my (@sql,@bind,$sql,$bind);
    my $switch = 'AND';
    
    #foreach my $where (@where){
    while (my ($key,$val) = each (%{$where}) ){
        #my $key = $where->[0];
        #my $val = $where->[1];
        
        if ($key =~ /^-literal$/gi){
            push(@sql,$val);
            next;
        }
        
        if ($key =~ /^-tables$/i){
            $self->tables(@{$val});
            delete $where->{$key};
            next;
        }
        
        elsif ($key =~ /^-or-create$/i){
            $self->create($val);
            delete $where->{$key};
            next;
        }
        
        elsif ($key =~ /^-switch$/i){
            $switch = uc($val);
            next;
        }
        
        elsif ($key =~ /^-limit$/i){
            $self->limit($val);
            next;
        }
        
        
        
        
        
        
        ($sql,$bind) = $self->_sql($key,$val);
        
        if ($sql){
            
            push(@sql,$switch);
            push(@sql,$sql);
            
            if (ref $bind eq 'ARRAY'){
                map {push(@bind,$_)} @{$bind};
            }
            
            else {
                push(@bind,$bind);
            }
        }
        
        
    }
    
    push (@{$self->{sql}},@sql);
    push (@{$self->{bind}},@bind);
    return $self;
}


sub _translate_where2 {
    
    my $self = shift;
    my @where = shift || @{$self->{where}};
    #return \@where;
    
    my (@sql,@bind,$sql,$bind);
    my $switch = 'AND';
    
    foreach my $where (@where){
        
        my $key = $where->[0];
        my $val = $where->[1];
        
        if ($key =~ /^-literal$/gi){
            push(@sql,$val);
            next;
        }
        
        if ($key =~ /^-tables$/i){
            $self->tables(@{$val});
            delete $where->[0];
            delete $where->[1];
            next;
        }
        
        elsif ($key =~ /^-or-create$/i){
            $self->create($val);
            delete $where->[0];
            delete $where->[1];
            next;
        }
        
        elsif ($key =~ /^-switch$/i){
            $switch = uc($val);
            next;
        }
        
        elsif ($key =~ /^-limit$/i){
            $self->limit($val);
            next;
        }
        
        
        
        
        
        
        ($sql,$bind) = $self->_sql($key,$val);
        
        if ($sql){
            
            push(@sql,$switch);
            push(@sql,$sql);
            
            if (ref $bind eq 'ARRAY'){
                map {push(@bind,$_)} @{$bind};
            }
            
            else {
                push(@bind,$bind) if $bind;
            }
        }
        
        
    }
    
    push (@{$self->{sql}},@sql);
    push (@{$self->{bind}},@bind);
    
    return $self;
}

sub _sql {
    
    my ($self,$key,$val,$opr,$type) = @_;
    
    
    my $cmp = $opr || '=';
    my $switch = $type || ' AND ';
    my $sql;
    
    if ($key =~ /^-literal/i){
        return ($val);
    }
    
    if (!ref $val){
        $sql = $key.' '.$cmp.' ?';
    }
    
    else {
        
        if ($key =~ m/^-(.*)$/gi){
            
            my @new = @{$val};
            my @s;
            my @v;
            
            $switch = uc($1);
            
            $sql .= '( ';
            
            my $s;
            my $x = -1;
            for my $n (@new){
                
                $x++;
                next if ($x % 2);
                
                #return $new[$x+1];
                my $k = $new[$x];
                my $v = $new[$x+1];
                
                
                my ($s,$val) = $self->_sql($k,$v);
                push(@s,$s);
                
                if (ref $val eq 'ARRAY'){
                    map {push(@v,$_)} @{$val};
                }
                else {push(@v,$val) if $val;}
                #return $val;
                #return ($sql,$val) = $self->_sql(@new2);
            }
            
            $sql .= join(' '.$switch.' ', @s);
            
            $sql .= ' )';
            
            $val = \@v;
            
        }
        
        elsif (ref $val eq 'ARRAY'){
            
            $sql .= '( ';
            
            my (@s);
            foreach my $v (@{$val}){
                my $s = $self->_sql($key,$v,$cmp);
                push(@s,$s);
            }
            
            $sql .= join(' OR ', @s);
            
            $sql .= ' )';
            
        }
        
        elsif (ref $val eq 'HASH'){
            
            my @map = %{$val};
            
            my $newcmp = uc($map[0]);
            
            $val = $map[1];
            $sql = $self->_sql($key,$val,$newcmp);
        }
        
        
    }
    
    
    return wantarray ? ($sql,$val) : $sql;
    
}




#==============================================================================
# set/get limit
#==============================================================================
sub limit {
    my ($self,$val) = @_;
    
    ##set
    if ($val){
        
        if (ref $val ne 'HASH'){
            croak 'Limit method only accepts hashref' if ref $val ne 'HASH'; 
        }
        
        $self->{limit} = $val;
    } 
    
    ##get
    else {
        my $rows = $self->{limit}->{rows} if $self->{limit}->{rows} =~ /^\d+$/;
        my $page = ($self->{limit}->{page} - 1)*$rows if $self->{limit}->{page} =~ /^\d+$/;
        
        if ($page > 0 && $rows){
            return " LIMIT $page,$rows";
        }
        
        elsif ($rows){
            return " LIMIT $rows";
        }
        
        else {
            return '';
        }
        
    }
    
    return $self;
}


sub order {
    
    my ($self,$val) = @_;
    
    if ($val){
        croak 'order method only accepts hashref' if ref $val ne 'HASH'; 
        $self->{order} = $val;
        return $self;
    }
    
    else {
        
        if ($self->{order}->{by}){
            my $order = ' ORDER BY '.$self->{order}->{by};
            $order .= ' '.$self->{order}->{type}.' ' if $self->{order}->{type};
            return  $order;
        }
        
        return '';
        
    }
    
    
}

#==============================================================================
# return sql string
#==============================================================================

sub _select_sql {
    
    my $self = shift;
    my $sql = 'SELECT'.$self->columns.' FROM'.$self->_tb.$self->where.$self->order.$self->limit;
    return $sql;
}


sub query {
    return shift->_select_sql;
}


#==============================================================================
# search functions
#==============================================================================
sub all {
    my $self = shift;
    my $sql = $self->_select_sql;
    return $self->_dbi($sql,$self->{bind},'all');
}

sub single {
    my $self = shift;
    my $sql = $self->_select_sql;
    return $self->_dbi($sql,$self->{bind},'single');
}

sub first {
    my $self = shift;
    #my $sql = $self->_select_sql;
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

sub total {
    
    my $self = shift;
    
    my $total;
    my $limit = $self->limit;
    
    if ($self->{_total}){
        return $self->{_total};
    }
    
    ###if no limits then return cached numbers
    
    elsif (!$limit && $self->{cached_results}){
        $total = scalar @{$self->{cached_results}};
    }
    
    else {
        my $sql = 'SELECT COUNT(*) FROM'.$self->_tb.$self->where;
        $total = $self->_dbi($sql,$self->{bind},'count');
    }
    
    $self->{_total} = $total;
    return $total;
    
}

sub pages {
    
    my $self = shift;
    my $total = $self->total;
    my $rows = $self->{limit}->{rows};
    
    my $total_pages = $total < $rows ? 1 : POSIX::ceil($total / $rows);
    return $total_pages;
    
}

#==============================================================================
# create new record
#==============================================================================
sub create {
    
    my $self = shift;
    my $data = shift;
    
    unless (ref $data eq 'HASH'){
        croak 'Create method can only take hash ref';
    }
    
    while (my ($key,$val) = each(%$data)){
        delete $data->{$key} if !$val || $val eq '';
    }
    
    ###
    my $columns = join (',', keys %$data );
    my @values = values %$data;
    
    #@values = grep { $_ && $_ ne '' } @values;
    
    my $x = join (',', grep {s/$_/?/} (0..$#values) );
    
    my $sql = "INSERT INTO ".$self->_tb." ($columns) VALUES ($x)";
    return $self->_dbi($sql,\@values,'create');
    
}

sub update {
    #UPDATE people SET age = age+1 WHERE id = 247
    
    my $self = shift;
    my $data = shift;
    
    unless (ref $data eq 'HASH'){
        croak 'Update method can only take hash ref';
    }
    
    ###
    my $columns = join (',',keys %$data);
    
    $columns =~ s/,/ = ?,/g;
    $columns .= ' = ?';
    
    my @values = values %$data;
    
    push @values,@{$self->{bind}};
    
    #my $x = join (',', grep {s/$_/?/} @values );
    
    
    
    my $sql = "UPDATE ".$self->_tb." SET $columns".$self->where.$self->limit;
    #return $sql;
    return $self->_dbi($sql,\@values,'update');
    
}



1;
