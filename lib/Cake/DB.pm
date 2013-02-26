package Cake::DB;
###NoSql Database
use strict;
use warnings;
use Storable qw (store retrieve);
use Carp;
use Data::Dumper;
use XML::Simple;
use Cake::Event::Fork;

use constant 'Size' => 1024;
use constant 'MaxBuff' => Size * 2;
use constant 'DEBUG' => 1;


sub size {  return shift->{size} }
sub fh {  return shift->{_fh}->{read} }
sub temp {  return shift->{_fh}->{temp} }
sub results {  return shift->{results} }

sub new {
    
    my $class = shift;
    my %options = @_;
    
    my $self = bless({
        path => '/xampp/htdocs/CakeBlog/files',
        Max => 100,
        results => []
    },$class);
    
    return $self;
}




##create new database
sub create {
    my ($self,$database) = @_;
    #create new path for database
}



##set/get database
sub db {
    my ($self,$db) = @_;
    return $self->{db} if !$db;
    $self->{db} = $db;
    return $self;
}


##set / get collection
sub collection {
    my ($self,$collection) = @_;
    return $self->{collection} if !$collection;
    $self->{collection} = $collection;
    
    my $file = $self->getFile;
    
    
    open my $fh2,'+<',$file or die $!. " ".$file;
    
    open my $fh1,'<',$file or die $!;
    open my $temp_fh, '>>', '/xampp/htdocs/CakeBlog/files/test/_temp.txt';
    
    $self->{_fh}->{bind} = $fh2;
    $self->{_fh}->{read} = $fh1;
    $self->{_fh}->{temp} = $temp_fh;
    
    
    $self->{size} = -s $fh1;
    
    return $self;
}



sub add {
    
    my ($self,@data) = @_;
    
    
    ##block request
    $self->block_request();
    
    my $xml = '';
    $self->meta;
    
    while (@data){
        my $key = lc shift @data;
        my $val = shift @data;
        
        ##encode values
        
        $xml .= "<$key>".$val."</$key>";
    }
    
    
    
    $self->meta->{ID}++;
    
    syswrite $self->{_fh}->{bind},'<B><I>'.$self->meta->{ID}.'</I>'.$xml.'</B>';
    
    return $self->meta->{ID};
}



sub meta {
    my $self = shift;
    
    return $self->{meta} if $self->{meta};
    my $meta = $self->getFile('meta','tmp');
    eval { $self->{meta} = retrieve $meta };
    if ($@){
        $self->{meta} = {};
    }
    
    return $self->{meta};
}




sub getFile {
    
    my $self = shift;
    my $fl = shift || $self->{collection};
    my $ext = shift || 'txt';
    my $file = $self->{path}.'/'.$self->db.'/'.$fl.'.'.$ext;
    return $file;
}

use constant 'CHILDS' => 30;
sub parallel {
    
    my ($self,$action) = @_;
    
    my $pm = Cake::Event::Fork->new(CHILDS);
    my @childs = ();
    my $fh = $self->fh;
    my $s = $self->size;
    $self->{_max_to_read} = $s / CHILDS;
    
    map {
        $s = $s / CHILDS;
        
        my $seek_to;
        $seek_to = $self->{_max_to_read} * $_;
        
        #$fh->seek( $self->{_max_to_read} * $_+1 ,0);
        
        print Dumper tell $fh;
        
        #while (1){
        #my $buf;
        #$fh->seek( - Size ,0);
        #sysread ($fh,$buf,Size);
        #
        #if  ( $buf !~ /<\/B>$/ ) {
        #    my @b = split /(.*)<\/B>/,$buf;
        #    print Dumper \@b;
        #    #sleep 1;
        #    last;
        #}
        #
        #}
        
        push @childs, $seek_to;
        
    } (0..CHILDS);
    
    print Dumper \@childs;
    my $t = 0;
    foreach my $i (@childs){
        
        #my $fh = $self->{_fh}->{read};
        $t++;
        
        $pm->start;
        unless ($pm->is_parent()){
            
            
            
            $self->fh->seek( $i, 0);
            $self->{position} = tell $fh;
            $self->search($action);
            print Dumper $self->{results};
            
        }
        $pm->finish;
    }
    
    $pm->wait_all;
    print "ALL FInished\n\n";
    
}


sub search {
    
    my ($self,$action) = @_;
    
    my $fh = $self->fh;
    
    $self->{found} = 0;
    
    
    
    my $actionStr = '';
    
    ##prepare search string
    foreach my $key ( keys %{ $action } ){
        $actionStr = "<$key>".$action->{$key}."</$key>";
    }
    
    $self->{results} = [];
    $self->{dat} = '';
    
    local $/ = '</B>';
    
    while (1){
        
        my $dat = <$fh>;
        
        if (!$dat){
            last;
        }
        
        elsif ($dat !~ /^<B>/ ){
            next;
        }
        else {
            
            #$dat =~ s/^.*?(<B>.*)/$1/;
            my $end_pos = tell $fh;
            my $start_pos = $end_pos - length $dat;
            
            while ($dat =~ s/<B>(.*?)<\/B>/$1/ ) {
                
                if ( $dat =~ qr/$actionStr/ ){
                    $self->{found}++;
                    my $hash = xmlParse($dat);
                    $hash->{end_pos} = $end_pos;
                    $hash->{start_pos} = $start_pos;
                    push @{ $self->{results} } , $hash;
                    
                }
            }
        }
        last if $self->{found} >= $self->Max;
    }
    
    return $self;
}





sub _get_id {
    
    my $fh = shift;
    my $id;
    
    while (read ($fh, my $cur_id, 1 ) ){
        if ($cur_id eq '>'){
            last;
        } else {
            $id .= $cur_id;
        }
    }
    
    $id =~ s/<.*// if $id;
    return $id || 0;
}


sub find {
    
    my ($self,$id) = @_;
    my $rec = 0;
    
    return {} if $id < 0;
    
    my $fh = $self->fh;
    my $size = $self->size;
    
    local $self->{Max} = 1;
    
    ##just make normal search if we are looking for the first elements
    if ($id < 100){
        return $self->search({I => $id})->results->[0];
    }
    
    $id = $id-1;
    
    $fh->seek( $size / 2 ,0);
    
    my $seek_to = 0;
    
    my ($m,$l);
    
    local $/ = '<I>';
    
    FIND : {
        
        my $current_match;
        
        if (defined $m && defined $l) {
            
            my $av = ($l - $m) / 2;
            $fh->seek( $m + $av ,0 );
            
            $l = $l + 10;
            $m = $m - 10;
        }
        
        my $found = <$fh>;
        
        
        $current_match = _get_id($fh);
        return {} if !$current_match;
        
        my $tell = tell $fh;
        
        if ( $id > $current_match ){
            
            $m = $tell;
            DEBUG and print tell($fh) . "   ID LARGER\n";
            $seek_to = $tell + ( ($size - $tell) / 2);
            
        }
        
        elsif ($id < $current_match ) {
            
            $l = $tell;
            DEBUG and print $tell . "   ID SMALLER\n";
            $seek_to  =  ( $tell - ($tell/2)   ) / 2;
            
        } else {
            $self->search({I => '.*'});
            return $self->results->[0];
        }
        
        $fh->seek( $seek_to, 0 );
        redo FIND;
    }
    
}

##update records
sub update {
    
    my $self = shift;
    my $id = shift;
    my $update = shift;
    
    ##get object
    my $obj = $self->find($id);
    
    
    
    $obj = {%{$obj},%{$update}};
    
    my $start = delete $obj->{start_pos};
    my $end = delete $obj->{end_pos};
    my $i = delete $obj->{I};
    
    my @data = %{$obj};
    print Dumper $end;
    my $xml;
    while (@data){
        my $key = lc shift @data;
        my $val = shift @data;
        
        ##encode values
        
        $xml .= "<$key>".$val."</$key>";
    }
    
    
    my $xml2 = '<B><I>'.$i.'</I>'.$xml.'</B>';
    
    print Dumper $xml2;
    
    my $temp = $self->temp;
    my $fh = $self->{_fh}->{bind};
    my $text = <$fh>;
    print $temp $text;
    
    #$fh->seek($start,0);
    
    #syswrite $fh, '++';
    
    #print $fh $xml2;
    
    
    #print Dumper -s $temp;
    #while ( sysread $temp, my $buf, MaxBuff ){
    #    print Dumper $buf;
    #    #last;
    #}
    
}


sub xmlParse {
    #return shift;
    my $str = shift;
    my $hash = {};
    while ($str =~ s/<(.*?)>(.*?)<\/.*?>//){
        $hash->{$1} = $2;
    }
    
    return $hash;
}


sub Max {
    return shift->{Max};
}

sub BUFF {
    
    my $self = shift;
    
    if ($self->{size} >= Size){
        
        $self->{size} = $self->{size} - Size;
        return Size;
        
    } else {
        return $self->{size};
    }
}


sub block_request {
    
    my $self = shift;
    my $file = shift || 'block.tmp';
    
}


sub block_update {
    
}



sub DESTROY {
    my $self = shift;
    print "DESTROY $$\n";
    store $self->meta,$self->getFile('meta','tmp');
}


1;


__END__
