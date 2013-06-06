package Cake::Utils::Serializer;
use strict;
use warnings;
use Carp;
use Data::Dumper;

sub new {
    my $class = shift;
    return bless({data => shift},$class);
}

sub true {'true' }
sub false { undef }
sub null { 'null' }
    
##from json to perl
sub to_perl {
    my $self = shift;
    #remove comments
    $self->{data} =~ s/\n+\s+/\n/g;
    $self->{data} =~ s/[\n\s+]\/\*.*?\*\/|[\n\s+]\/\/.*?\n/\n/gs;
    my $data = $self->{data};
    
    if ($data){
        $data =~ s/(["'])(?:\s?)+:/$1=>/g;
        $data =~ s/[^\\]([\@\$].*?\s*)/ \\$1/g;
    }
    
    my $str = eval "$data";
    croak "invalid json" if $@;
    
    #return bless($str,'Cake::Utils::Serializer::Base');
    
    return $str;
    return _stringify($data);
}

sub to_json {
    my $self = shift;
    my $trim = shift;
    my $perl_object = $self->{data};
    my $dumper = Data::Dumper->new([ _stringify($perl_object,'encode') ]);
    $dumper->Purity(1)->Terse(1)->Indent(1)->Deparse(1)->Pair(' : ');
    my $json = $dumper->Dump;
    $json =~ s/(?:'((.*?)[^\\'])?')/$1 ? '"'.$1.'"' : '""'/ge;
    $json =~ s/\\'/'/g;
    $json =~ s/\\\\/\\/g;
    $json =~ s/(\\x\{(.*?)\})/chr(hex($2))/ge;
    if ($trim){
        $json =~ s/\n//g;
        $json =~ s/\s+//g;
    }
    return $json;
}


sub validate_json {
    
    my $self = shift;
    my $data = $self->{data};
    eval "$data";
    ##fastest way to check valid json.. I guess!!
    $data =~ s/"(\\.|[^"\\])*"//g;
    if ( $data =~ m/[^,:{}\[\]0-9.\-+Eaeflnr-u \n\r\t]/g && $@){
        croak('invalid json string');
    }
}


sub _stringify {
    my $hash = shift;
    my $type = shift || 'decode';
    my $action = {
        decode => \&_decode_string,
        encode => \&_encode_string,
    };
    
    if (!ref $hash){
        return $action->{$type}($hash);
    }
    
    my $newhash = {};
    my $array = 0;
    my $loop;
    
    #ref $hash eq 'ARRAY' ? $loop->{array} = $hash : $loop = $hash;
    if (ref $hash eq 'ARRAY') {
        $loop->{array} = $hash;
        $array = 1;
    } else {
        $loop = $hash
    }
    
    while (my ($key,$value) = each (%{$loop}) ) {
        if (ref $value eq 'HASH'){
            $newhash->{$key} = _stringify($value,$type);
        } elsif (ref $value eq 'ARRAY'){
            push @{$newhash->{$key}}, map { _stringify($_,$type) } @{$value};
        } else {
            $newhash->{$key} = $action->{$type}->($value);
        }
    }
    return !$array ? $newhash : $newhash->{array};
}


sub _decode_string {
    my $str = shift;
    return '' if !$str;
    my @search  = ('\\\\', '\\n', '\\t', '\\r', '\\b', '\\f', '\"');
    my @replace = ('\\', "\n", "\t", "\r", "\b", "\f", '"');
    map { $str =~ s/\Q$search[$_]/$replace[$_]/ } (0..$#search);    
    return $str;
}


sub _encode_string {
    my $str = shift;
    return 0 if $str && $str =~ /^\d$/ && $str == 0;
    return '' if !$str;
    my @search  = ('\\', "\n", "\t", "\r", "\b", "\f", '"');
    my @replace = ('\\\\', '\\n', '\\t', '\\r', '\\b', '\\f', '\"');
    map { $str =~ s/\Q$search[$_]/$replace[$_]/g } (0..$#search);
    return $str;
}

package Cake::Utils::Serializer::Base;
use Data::Dumper;
our $AUTOLOAD;
sub AUTOLOAD {
    my $self = shift;
    my $index = shift;
    my $sub = $AUTOLOAD;
    
    $sub =~ s/.*:://;
    my $val = $self->{$sub};
    
    return undef if (!defined $val);
    
    if ($index && ref $val eq 'ARRAY'){
        $val = $val->[$index];
    }
    
    if (ref $val){
        return bless($val,__PACKAGE__);
    } else {
        return $val;
    }
}

1;


__END__

=head1 NAME

Cake::Utils::Serializer - serializing object from json to perl and vise verca

=head1 SYNOPSIS

    get '/serialize' => sub {
        
        my $self = shift;
        my $c = shift;
        
        my $hash = {
            something => {
                somethingelse => ['data',2]
            }
        };
        
        my $json = $c->serialize($hash)->to_json;
        $c->body($json);
        
        
        #now back to perl
        my $newhash = $c->serialize($json)->to_perl;
        $c->dumper($newhash);
        
    };

=head1 DESCRIPTION

Very minimal json serializer written in pure perl and work in most cases where
you need a simple fast way to send json objects

It doesn't validate json string before converting it to perl but does not
give a specific error message about the error.

=cut