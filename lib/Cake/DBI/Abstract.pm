package Cake::DBI::Abstract;
use strict;
use warnings;
use Data::Dumper;
use Carp;

sub new {
    my $class = shift;
    my $self = bless({},$class);
    $self->{binds} = [];
    return $self;
}

sub _preserv_array {
    my $self = shift;
    my @array = @_;
    my @new;
    my $counter = 0;
    my $DIS;$DIS = {
        '-IN' => sub {
            my $value = shift;
            croak "-in and -not_in caluse must be an array ref" if ref $value ne "ARRAY";
            my @values = @{$value};
            #push @{$self->{binds}},@values;
            my $x = join (',', grep {s/$_/?/} (0..$#values) );
            
            return {
                _text => '('.$x.')',
                _binds => \@values
            };
            
            return '('.$x.')';
        },
        '-NOT_IN' => sub {
            $DIS->{-IN}->(@_);
        }
    };
    ##die Dumper \@array;
    while (@array){
        my $key = shift @array;
        if ($key =~ /(-or|-and|-on)/i){
            push @new,$key;
        } elsif (ref $key eq 'ARRAY'){
            push @new,$self->_preserv_array(@{$key});
        } elsif (ref $key eq 'HASH') {
            my $value = $self->_preserv_array(%{$key});
            if (scalar @{$value} == 1){
                $value = $value->[0];
            }
            push @new,$value;
        } else {
            my $value = shift @array;
            if ($key =~ s/^(-(.*?))/$1/){
                
                my $newkey = uc $key;
                
                if ($DIS->{$newkey}){
                    $value = $DIS->{$newkey}->($value);
                    $newkey =~ s/-(\w+)/ uc(join(" ", split("_",$1))); /ge;
                    $key = $newkey;
                } else {
                    #croak 'not defined operator '.$key;
                }
                
            } elsif (ref $value eq 'HASH'){
                $value = $self->_preserv_array(%$value)->[0];
            }
            
            push @new,{$key => ref $value eq 'ARRAY' ? $self->_preserv_array(@{$value}) : $value };
        }
    }
    
    return \@new;
}

#==============================================================================
# Set/Get columns
#==============================================================================
sub select  {
    my $self = shift;
    my $columns = ref $_[0] eq 'ARRAY' ? $_[0] : \@_;
    $self->{columns} = $columns;
    return $self;
}

sub _select {
    my $self = shift;
    my $cols = $self->{columns};
    if (!$cols){
        return '*';
    }
    my $columns = join ",", @{$cols};
    return $columns;
}

#==============================================================================
# Set/Get Where Clause
#==============================================================================
sub where {
    my $self = shift;
    my $values = $self->_preserv_array(@_);
    push @{$self->{where}},@{$values};
    return $self;
}

sub _where {
    my $self = shift;
    my $values = $self->{where};
    return undef if !$values;
    my $sql = $self->_translate($values);
    return $sql || undef;
}

sub _translate {
    
    my $self = shift;
    my $values = shift || $self->{where};
    my $nobinds = shift;
    
    my @query = @{$values};
    my @string;
    my $i = 0;
    
    foreach my $query (@query){
        
        if ($query eq '-on' || ($i != 0 && $string[-1] !~/AND|OR|ON/) ){
            if ($query =~ /-(or|on)/i){
                push @string,uc $1;
                next;
            } else {
                push @string,'AND';
            }
        }
        
        if (ref $query eq 'HASH'){
            while (my ($key,$value) = each(%{$query})){
                
                if (!$value){
                    #die 'no value';
                }
                
                if (!ref $value){
                    if (!$nobinds){
                        push @{$self->{binds}},$value;
                        $value = '?';
                    }
                    push @string,($key,'=',$value);
                }
                
                elsif (ref $value eq 'HASH') {
                    my @keys = keys %$value;
                    my @values = values %$value;
                    
                    if (ref $value->{$keys[0]} eq 'HASH' && $value->{$keys[0]}->{_text}){
                        
                        push @{$self->{binds}},@{$value->{$keys[0]}->{_binds}};
                        push @string,($key,@keys,$value->{$keys[0]}->{_text});
                    } else {
                        push @{$self->{binds}},@values;
                        push @string,($key,@keys,'?');
                    }
                }
                
                elsif (ref $value eq 'ARRAY'){
                    push @string,'(';
                    my @str;
                    map {
                        if (ref $_){
                            push @str,{$key => $_};
                        } else {
                            push @str,$_
                        }
                    } @{$value};
                    
                    @str = $self->_translate(\@str,$nobinds);
                    
                    push @string, @str;
                    push @string,')';
                }
            }
        } elsif (ref $query eq 'ARRAY'){
            my @new = $self->_translate($query,$nobinds);
            push @string,'(',@new,')';
        }
        
        $i++;
    }
    
    return wantarray ? @string :
    join ' ',@string;
    
}

#==============================================================================
# Set/Get tables
#==============================================================================
sub from {
    my $self = shift;
    
    if (!$self->{tables}){
        my $first_table = shift @_;
        my $second = $_[0];
        if (!ref $second){
            splice(@_,0,0,{$first_table => $second && $second !~ /^-(\w)*join$/i ? {'as' => shift @_} : {'as' => 'me'}});
        } elsif (ref $second eq 'HASH') {
            splice(@_,0,0,{$first_table => shift @_});
        } else {
            croak "from table syntax is wrong please make sure to use the following styntax to set primary table\n"
            ."->from( 'table' => { as => 't'} ) OR ->from('table')";
        }
        
        ##save primary table
        $self->{_primary_table} = $first_table;
    }
    
    my $table = $self->_preserv_array(@_);
    if (!$self->{tables}){
        $self->{tables} = $table;
    } else {
        push @{$self->{tables}},@{$table};
    }
    #die Dumper $self->{tables};
    return $self;
}

sub _from {
    my $self = shift;
    my $values = $self->{tables};
    
    ###get primary/first table
    if ($_[0]){
        return $values->[0];
    }
    
    croak 'You need to set a table name' if !$values;
    $self->_translate_from($values);
    
    my @tables = @{$self->{__tables}};
    
    #if (scalar @tables > 1 && $tables[0] !~ /\sAs\s/i){
    #    $tables[0] = $tables[0].' AS me';
    #}
    
    my $tables = join " ", @tables;
    return $tables;
}

sub primaryTable {
    return shift->{_primary_table};
}

sub  _translate_from {
    my $self = shift;
    my $values = shift;
    
    my @tables = @{$values};
    my $first_table = shift @tables;
    
    #reset tables
    $self->{__tables} = [];
    
    $self->_push_table($first_table);
    
    foreach my $val (@tables){
        ##if not hash ref
        
        for (keys %$val){
            if ($_ !~ /^-(\w)*join$/){
                croak "secondary tables must be of a join type, use one of the join syntaxes like -join / -left_join / -inner_join ...\n"
                ."EX: '-left_join' => [ 'table' = > {as => 't'},\n '-on' => [ ... ] \n]"
            } elsif (ref $val->{$_} ne 'ARRAY'){
                croak 'secondary tables options must be an array \'-join\' => [...] ';
            }
            
            my $table = $val->{$_}->[0];
            
            if ($val->{$_}->[1] !~ /^-on/i){
                croak "second argument can only be '-on'";
            } elsif (ref $val->{$_}->[2] ne 'ARRAY'){
                croak "-on clause in from method must be an array ref\n"
                ." '-on' => [ ... ] ";
            }
            
            my $options = [ $val->{$_}->[1], $val->{$_}->[2] ];
            
            my $prefix = $_;
            $prefix =~ s/-(\w+)/ uc(join(" ", split("_",$1))); /ge;
            $self->_push_table($table,$prefix);
            
            push @{$self->{__tables}},$self->_translate($options,'ON');
            
        }
    }
    return $self;
}


sub _push_table {
    
    my $self = shift;
    my $table = shift;
    my $prefix = shift;
    
    my $tb = $prefix ? $prefix.' ' : '';
    
    while (my ($key,$val) = each (%{$table})){
        
        $tb .= $key;
        
        if (ref $val eq 'HASH' && $val->{as}){
            $tb .= ' AS '.$val->{as};
        } elsif ($val) {
            $tb .= ' AS '.$val;
        }
        
        push @{$self->{__tables}},$tb;
    }
    
}

#==============================================================================
# Set/Get limit : ->limit({ rows => 100, page => 2 })
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
        return undef if !$self->{limit};
        my $rows = $self->{limit}->{rows} if $self->{limit}->{rows} && $self->{limit}->{rows} =~ /^\d+$/;
        my $page = ($self->{limit}->{page} - 1)*$rows if $self->{limit}->{page} && $self->{limit}->{page} =~ /^\d+$/;
        
        if ($page && $page > 0 && $rows){
            return "$page,$rows";
        } elsif ($rows){
            return "$rows";
        } else {
            return '';
        }
    }
    
    return $self;
}

#==============================================================================
# Set/Get order : 
#==============================================================================
sub order {
    
    my ($self,$val) = @_;
    if ($val){
        croak 'order method only accepts hashref' if ref $val ne 'HASH'; 
        $self->{order} = $val;
        return $self;
    }
    
    else {
        
        return undef if !$self->{order};
        
        if ($self->{order}->{by}){
            my $order = $self->{order}->{by};
            $order .= ' '.$self->{order}->{type} if $self->{order}->{type};
            return  $order;
        }
    }
    
    return $self;
}

#==============================================================================
# generate count sql
#==============================================================================
sub count {
    
    my $self = shift;
    my $total;
    
    ##reset binds
    $self->{binds} = [];
    
    ###if no limits then return cached numbers
    my $from = $self->_from;
    my $where = $self->_where;
    
    my $sql = 'SELECT COUNT(*) ';
    $sql .= ' FROM '.$from if defined $from;
    $sql .= ' WHERE '.$where if defined $where;
    return wantarray ? ($sql,@{$self->{binds}}) : $sql;
    
}

sub literal {
    my $self = shift;
    my $sql = shift;
    my $binds = shift;
    push @{$self->{_literal}}, $sql;
    push @{$self->{_literal}}, $binds if $binds;
    return $self;
}

#==============================================================================
# Set/Get query
#==============================================================================
sub query {
    
    my $self = shift;
    my $set = shift;
    
    my $literal = delete $self->{_literal};
    return @{$literal} if $literal;
    ##make sure to reset binds
    $self->{binds} = [];
    
    if ($set && ref $set eq 'HASH'){
        $self->select($set->{select}) if $set->{select};
        $self->where(@{$set->{where}}) if $set->{where};
        $self->from(@{$set->{from}}) if $set->{from};
        return $self;
    }
    
    
    
    my $select = $self->_select;
    my $from = $self->_from;
    my $where = $self->_where;
    my $limit = $self->limit;
    my $order = $self->order;
    
    my $sql = '';
    
    if ($set && $set eq 'DELETE'){
        $sql = 'DELETE';
        if ($from){
            $from =~ s/AS\s\w+/ /g;
            $sql .= ' FROM '.$from;
        }
        
    } else {
        $sql = 'SELECT '.$select;
        $sql .= ' FROM '.$from if defined $from;
    }
    #$sql = $set eq 'DELETE' ? 'DELETE' : 'SELECT '.$select;
    #$sql .= ' FROM '.$from if defined $from;
    
    $sql .= ' WHERE '.$where if defined $where;
    $sql .= ' ORDER BY '.$order if $order;
    $sql .= ' LIMIT '.$limit if $limit;
    return wantarray ? ($sql,@{$self->{binds}}) : $sql;
}

#==============================================================================
# Get create query
#==============================================================================
sub create {
    
    my $self = shift;
    my $data = shift;
    
    unless (ref $data eq 'HASH'){
        croak 'Create method can only take hash ref';
    }
    
    for (keys %$data){
        delete $data->{$_} if !$_ || $_ eq '';
    }
    
    my $columns = join (',', keys %$data );
    my @values = values %$data;
    my $x = join (',', grep {s/$_/?/} (0..$#values) );
    
    ###get main table
    my $table = $self->_from(1);
    $table = [keys %$table]->[0];
    
    my $sql = "INSERT INTO "
    .$table
    ." ($columns) VALUES ($x)";
    
    return wantarray ? ($sql,@values) : $sql;
}


#==============================================================================
# Get delete query
#==============================================================================
sub delete {
    return shift->query('DELETE');
}

#==============================================================================
# Get update query
#==============================================================================
sub update {
    my $self = shift;
    my $data = shift;
    
    unless (ref $data eq 'HASH'){
        croak 'Update method can only take hash ref';
    }
    
    $self->{binds} = [];
    
    my $where = $self->_where;
    my $limit = $self->limit;
    
    my $columns = join (',',keys %$data);
    $columns =~ s/,/ = ?,/g;
    $columns .= ' = ?';
    
    my @values = values %$data;
    push @values,@{$self->{binds}};
    
    my $sql = "UPDATE ".$self->primaryTable;
    $sql .= " SET $columns";
    $sql .= " WHERE ".$where if $where;
    $sql .= " LIMIT ".$limit if $limit;
    
    return wantarray ? ($sql,@values) : $sql;
}

1;


__END__

=head1 NAME

Cake::DBI::Abstract

=head1 SYNOPSIS

    use Cake::DBI::Abstract;
    my $query = Cake::DBI::Abstract->new();
    
    #set tables
    $query->table(
        'users' => {'as' => 'u'},
        '-left_join' => [
            hobbies => {'as' => 'h'},
            '-on' => [
                'h.uid' => 'u.uid'
            ]
        ]
    );
    
    ##select records
    $query->from('u.*','h.username NAME');
    
    $query->where(
        uid => 1,
        '-or',
        name => {'LIKE' => '%m%'},
        '-or' => [
            
            uid => 2,
            name => 't'
            
        ]
    );
    
    ##generate sql string and bind values
    my ($sql,@binds) = $query->query();

=cut

=head1 DESCRIPTION

This module generates sql syntaxes like (SELECT,UPDATE,INSERT) directly from Perl 

=head1 Methods

=head2 create

Accepts hash ref of options

    my ($sql,@binds) = $query->create({
        '-insert_mode' => 'DELAYED' || 'LOW_PRIORITY' || 'HIGH_PRIORITY' || 'IGNORE',
        '-on_duplicate' => {
            col1 => val
        }, 
        col1 => val1,
        col2 => val2
    });
    


    
=cut
