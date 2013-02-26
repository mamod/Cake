package Cake::Actions::Form;
use strict;
use warnings;

sub execute {
    my $self = shift;
    my ($controller,$c) = @_;
    $self->{_errorMsgs} = ();
    
    ##TODO more tests to add
    my $table = {
        'required' => sub {
            if ($_[0]){
                return 0;
            }
            return 1;
        },
        
        'number' => sub {
            if ($_[0] =~ /\d+/){
                return 0;
            }
            return 1;
        }
    };
    
    $self->{_errors} = [];
    my $errors = 0;
    
    if ($c->method eq 'post'){
        $self->{_is_submitted} = 1;
        my $hasError = 0;
        
        ##do form validation
        my %hash;
        if (ref $self->{fields} eq 'ARRAY'){
           %hash = @{$self->{fields}};
        } else {
            %hash = %{$self->{fields}};
        }
        
        while (my ($key,$value) = each(%hash)){
            my $content = $c->param($key);
            $self->{content} = $content;
            if (ref $value->{formatter} eq 'CODE'){
                $content = $value->{formatter}->($content);
                $c->param($key,$content);
            }
            
            if (ref $value->{is} eq 'Regexp'){
                $hasError = ( $content !~ /$value->{is}/ );
            } else {
                $hasError = $table->{$value->{is}}->($content);
            }
            
            if ($hasError){
                ++$errors;
                $hash{$key}->{hasError} = 1;
                push (@{$self->{_errorMsgs}},ref $value->{errorMsg} eq 'CODE' ? $value->{errorMsg}->($c) : $value->{errorMsg});
            }
        }
        
        $self->{__errors} = $errors;
    }
    
    #$self->NEXT::execute(@_);
}


sub hasError {
    my $self = shift;
    return 1 if $self->{__errors} > 0;
    return 0;
}

sub isSubmitted {
    my $self = shift;
    return 1 if $self->{_is_submitted};
    return 0;
}

sub errors {
    my $self = shift;
    my $join = shift;
    if ($join){
        return join ($join,@{$self->{_errorMsgs}});
    }
    
    return @{$self->{_errorMsgs}};
}


1;


__END__
