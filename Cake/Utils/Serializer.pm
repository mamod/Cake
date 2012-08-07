package Cake::Utils::Serializer;
use strict;
use warnings;
use Carp;
use Data::Dumper;
our $VERSION = '0.002';

=head1 NAME

Cake:;Serializer - serializing object from to perl

=head1 SYNOPSIS

Do not call this package directly, call it through Cake instance, from Cake
controller for example by calling serialize method

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
    
};

=head1 DESCRIPTION

Very minimal json serializer written in pure perl and work in most cases where
you need a simple fast way to send json objects

It does validate json string before converting it to perl but does not
give a specific error message about the error, so don't use it as a validator

=cut

sub new {
    
    if (!$_[2]){
        $_[2] = $_[1]
    }
    
    return bless({
        c => $_[1],
        data => $_[2]
    },__PACKAGE__);
    
}



##from json to perl object
sub to_perl {
    
    my $self = shift;
    
    ##validate
    $self->validate_json();
    
    
    my $data = $self->{data};
    
    ##function are not surrounded with quotes
    ##change that for ever
    
    if ($data){
        ##not really implemented in json spec but to wrap null,false, and true values
        $data =~ s/(["'](?:\s?)+:)(?:\s?)+([^"](null|true|false)),/$1"$2",/g;
        $data =~ s/["'](\s?)+:/"=>/g;
    }
    
    my $tt = eval "$data";
    
    return _stringify($tt);
    
}


sub to_json {
    
    my $self = shift;
    my $perl_object = $self->{data};

    my $dumper = Data::Dumper->new([ _stringify($perl_object,'encode') ]);
    $dumper->Purity(1)->Terse(1)->Indent(1)->Deparse(1)->Pair(' : ');
    
    my $json = $dumper->Dump;
    
    $json =~ s/('((.*?)[^\\'])?')/"$2"/g;
    $json =~ s/\\'/'/g;
    $json =~ s/\\\\/\\/g;
    
    $json =~ s/(\\x\{(.*?)\})/chr(hex($2))/ge;
    
    #$json =~ s/\s+//g;
    #$json =~ s/\n+//g;
    return $json;
    
}



sub validate_json {
    
    my $self = shift;
    my $data = $self->{data};
    
    eval "$data";
    
    ##fastest way to check valid json.. I guess!!
    $data =~ s/"(\\.|[^"\\])*"//g;
    if ( $data =~ m/[^,:{}\[\]0-9.\-+Eaeflnr-u \n\r\t]/g && $@){
        
        #die({
        #    message => 'Invalid json string',
        #    caller => [caller(1)]
        #});
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
    }
    
    else {
        $loop = $hash
    }
    
    while (my ($key,$value) = each (%{$loop}) ) {
        
        
        if (ref $value eq 'HASH'){
            $newhash->{$key} = _stringify($value,$type);
        }
        
        elsif (ref $value eq 'ARRAY'){
            push @{$newhash->{$key}}, map { _stringify($_,$type) } @{$value};
        }
        
        else {
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
    
    foreach (0..$#search) { 
        $str =~ s/\Q$search[$_]/$replace[$_]/;
    }
    
    return $str;
}


sub _encode_string {
    
    my $str = shift;
    
    return '' if !$str;
    
    my @search  = ('\\', "\n", "\t", "\r", "\b", "\f", '"');
    my @replace = ('\\\\', '\\n', '\\t', '\\r', '\\b', '\\f', '\"');
    
    foreach (0..$#search) { 
        $str =~ s/\Q$search[$_]/$replace[$_]/g;
    }
    
    return $str;
}



1;