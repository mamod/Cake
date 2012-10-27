package Cake::Exception;
use strict;
use Carp;
use Data::Dumper;
our $VERSION = "0.003";

our @CARP_NOT;
use base 'Exporter';

our @EXPORT = qw(
    error
    log
);


##For quick testing
BEGIN {
    $SIG{__DIE__} = \&trapper;
}


sub trapper {
my $message = shift;
$message = __PACKAGE__->backtrace($message);

print STDOUT <<END;
Content-Type: text/html

$message

END
}


## die nicely just to detach the flow sequence of Cake action
## and not a real die
my $kill_nicely = 0;

sub Mercy_Killing {
    my $c = shift;
    $kill_nicely = 1;
    die();
}

sub error {
    
    my ($self,$error) = @_;
    
    local @CARP_NOT = qw(Cake);
    
    if ($kill_nicely){
        ##reset value
        $kill_nicely = 0;
        return;
    }
    
    $self->status_code(500);
    
    #trace caller
    my ($message,$caller);
    
    if (ref $error eq 'HASH'){
        $message = $error->{message};
        $caller = $error->{caller};
        $error = $message.' at '.$caller->[1].' line '.$caller->[2];
    }
    
    if ($self->debug){
        $error = __PACKAGE__->backtrace($error) if $error;
        local $SIG{__DIE__} = \&handleErrors($self,$error);
    }
    
    else {
        
        if ($self->app->can('errors')){
            $self->app->errors($self,$error);
        }
        
        else {
            $self->body('something wrong is going on');
        }
    }
    
    return 1;
    
}


sub log {
    my $self = shift;
    if (@_ > 1){
        push @{$self->app->{log}},\@_;
        
    } else {
        push @{$self->app->{log}},shift;
    }
    
    return $self->{'app.log'};
}


sub warn {
    my $self = shift;
    warn shift;    
}


sub handleErrors {
    my $self = shift;
    my $message = shift;
    $self->body($message);
    return $self;
}


########proudly stolen from Dancer :P
sub backtrace {
    my ($self,$message) = @_;

    
    $message =
      qq|<pre class="error">| . _html_encode($message) . "</pre>";

    # the default perl warning/error pattern
    my ($file, $line) = ($message =~ /at (\S+) line (\d+)/);

    # the Devel::SimpleTrace pattern
    ($file, $line) = ($message =~ /at.*\((\S+):(\d+)\)/)
      unless $file and $line;

    # no file/line found, cannot open a file for context
    return $message unless ($file and $line);

    # file and line are located, let's read the source Luke!
    
    open FILE, "<$file" or return $message;
    my @lines = <FILE>;
    close FILE;

    my $backtrace = $message;

    $backtrace
      .= qq|<div class="title">| . "$file around line $line" . "</div>";

    $backtrace .= qq|<pre class="content">|;

    $line--;
    my $start = (($line - 3) >= 0)             ? ($line - 3) : 0;
    my $stop  = (($line + 3) < scalar(@lines)) ? ($line + 3) : scalar(@lines);

    for (my $l = $start; $l <= $stop; $l++) {
        chomp $lines[$l];

        if ($l == $line) {
            $backtrace
              .= qq|<span class="nu">|
              . tabulate($l + 1, $stop + 1)
              . qq|</span> <span style="color: red;">|
              . _html_encode($lines[$l])
              . "</span>\n";
        }
        else {
            my $thisline = $lines[$l];
            
            #if ($thisline =~ m/^\s*#/){
            #    $thisline = '<i>'.$thisline.'</i>';
            #}
            
            $backtrace
              .= qq|<span class="nu">|
              . tabulate($l + 1, $stop + 1)
              . "</span> "
              . _html_encode($thisline) . "\n";
        }
    }
    $backtrace .= "</pre>";


    return $backtrace;
}

sub _html_encode {
    my $value = shift;

    $value =~ s/&/&amp;/g;
    $value =~ s/</&lt;/g;
    $value =~ s/>/&gt;/g;
    $value =~ s/'/&#39;/g;
    $value =~ s/"/&quot;/g;

    return $value;
}

sub tabulate {
    my ($number, $max) = @_;
    my $len = length($max);
    return $number if length($number) == $len;
    return " $number";
}


1;


