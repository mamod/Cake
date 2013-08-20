package Cake::View::TT;
use strict;
use warnings;
use Carp;
use Encode;
#=======================================================================
# Global REGex
#=======================================================================
my $L = "[%";
my $T = "%]";
my $PRE = qr/\Q$L/;
my $POST = qr/\Q$T/;

my $CODE = qr{
    $PRE
    \s*			# optional leading whitespace
    CODE		# required BLOCK token
    \s*			# optional whitespace
    $POST
    (.*?)		# grab block content
    $PRE
    \s*
    END
    \s*
    $POST
}xs;

my $VAR = qr {
    $PRE
    \s*
    (.*?)
    \s*
    $POST
}xs;

my $REP = qr {
    \{\{
    \s
    (\d+)
    \s
    \}\}
}x;

my $PROCESS = qr{
    ($PRE
    \s*
    PROCESS
    \s+
    .*?
    \s*
    $POST)
}x;

my $PROCESS_URL = qr{
    $PRE
    \s*
    PROCESS
    \s+
    (.*?)
    \s*
    $POST
}x;

my $MAIN = qr {
    $PRE
    \s*
    main
    \s*
    $POST
}x;

my $INCLUDE = qr{
    ($PRE
    \s*
    INCLUDE
    \s+
    .*?
    \s*
    $POST)
}x;

my $INCLUDE_URL = qr{
    $PRE
    \s*
    INCLUDE
    \s+
    (.*?)
    \s*
    $POST
}x;

my $SETTINGS = qr{
    ($PRE
    \s*			# optional leading whitespace
    SETTINGS		# required SETTINGS token
    \s*			# optional whitespace
    $POST
    .*?		# grab block content
    $PRE
    \s*
    END
    \s*
    $POST)
}xs;

my $SETTINGS_CONTENT = qr{
    $PRE
    \s*			# optional leading whitespace
    SETTINGS		# required SETTINGS token
    \s*			# optional whitespace
    $POST
    (.*?)		# grab block content
    $PRE
    \s*
    END
    \s*
    $POST
}xs;

=head1 Name

Cake::View::TT

=cut

=head1 SYNOPSIS

    use Cake::View::TT;
    
    my $temp = Cake::View::TT->new({
        path => '/some/global/path/to/template/folder',
        layout => 'layout.tmpl'
    });
    
    $temp->render('file.tmpl',{
        fname => 'Mamod',
        lname => 'Mehyar',
        options => ['opt1','opt2','opt3'],
        nested => {
            test => 'something',
            another => []
        }
    });

=cut

my $DEBUG = 0;
sub DEBUG {$DEBUG};

sub new {
    
    my $class = shift;
    my $options = shift;
    croak "You have to specify full path of your templat files location"
    if !$options->{path};
    
    $DEBUG = $options->{DEBUG};
    
    my $self = bless({
        path => $options->{path},
        layout => $options->{layout},
    },$class);
    
    return $self;
}

sub render {
    my $self = shift;
    my $file = shift;
    my $data = shift;
    $data->{me} = $self;
    
    $self->{obj} = bless($data,'Cake::View::Object');
    my @matches = $self->loadMatches($file);
    my $temp = $self->{temp};
    
    foreach my $match (@matches){
        my $perl = '';
        my $content = $match->{content};
        
        $self->{current} = {
            pos => $match->{start},
            index => $match->{index},
            file => $match->{file},
            content => $match->{content}
        };
        
        if ($match->{from} eq 'VAR'){
            $content =~ s/\n+//g;
            my $return = $self->setVar("$content","eval");
            if ($return){
                $self->pushData($return);
            }
        } else {
            $content =~ s/print\s+(.+?)\s*;/$self->_varsFromPrint($1)/ges;
            $content =~ s/$VAR/\$self->setVar("$1","eval")/g;
            eval $content;
        }
        
        ##better error handling
        if (DEBUG && $@){
            die {
                content => $self->{current}->{content},
                file => $self->{current}->{file},
                pos => $self->{current}->{pos},
                message => $@
            }
        }
    }
    
    while (my ($id) = $temp =~ m{$REP}){
        my $replace;
        if (my $data = $self->{data}->{$id}){
            $replace = join '', @{$data};
        } else {
            $replace = '';
        }
        
        my $length = $+[0] - $-[0];
        substr ($temp,$-[0],$length,$replace);
    }
    
    return $temp;
    $self->{temp} = $temp;
    $temp =~ s/\t+//g;
    return $self;
    
}

sub _varsFromPrint {
    my $self = shift;
    my $data = shift;
    $data =~ s/\n\s*//g;
    $data =~ s/(['"])\./$1,/g;
    
    my @captures;
    while ($data =~ s/((['"])(?:(?:.*?)*)$VAR(?:(?:.*?)*)\2)/\{\{POS\}\}/){
        my $capture = $1;
        my $ter = $2;
        $capture =~ s/$PRE/$ter,\$self->setVar($ter/g;
        $capture =~ s/$POST/$ter,"eval"),$ter/g;
        push @captures, $capture;
    };
    
    map {
        $data =~ s/\{\{POS\}\}/$_/;
    } @captures;
    
    return '$self->pushData('.($data).');';
}


sub loadMatches {
    my $self = shift;
    my $file = shift;
    my $temp = $self->load($file);
    if (my $layout = $self->{layout}){
        $layout = $self->load($layout);
        $layout =~ s/\{\{ main \}\}/$temp/g;
        $temp = $layout;
    }
    
    $self->{temp} = $temp;
    return ref $self->{matches} eq 'ARRAY' ? @{$self->{matches}} : ();
}

sub load {
    my ($self,$file) = @_;
    my ($data);
    $file = $self->{path}."/$file";
    
    if (open(my $fh,'<',$file)) {
        $data = do { local $/; <$fh> };
        close($fh);
        $data = Encode::decode_utf8($data);
        
        my @files;
        $data =~ s/$MAIN/{{ main }}/g;
        my $counter = 0;
        while (my ($settings,$include,$process,$code,$var) = $data =~ m{$SETTINGS|$INCLUDE|$PROCESS|$CODE|$VAR}){
            $counter++;
            if ($counter > 1000){
                die "recrusive loop $process";
            }
            
            my $length = $+[0] - $-[0];
            my $start = $-[0];
            if ($code || $var){
                my $content = $code || $var;
                push @{$self->{matches}},{
                    index => ++$self->{i},
                    content => $content,
                    start => $start,
                    from => $code ? 'CODE' : 'VAR',
                    file => $file
                };
                substr ($data,$start,$length,"{{ $self->{i} }}");
            } elsif ($process){
                my ($url) = $process =~ m/$PROCESS_URL/g;
                substr ($data,$start,$length,$self->load($url));
            } elsif($settings){
                my ($content) = $settings =~ m/$SETTINGS_CONTENT/g;
                substr ($data,$start,$length,$self->settings($content));
            } elsif ($include){
                my ($url) = $include =~ m/$INCLUDE_URL/g;
                push @files,$url;
                substr ($data,$start,$length,'{{% INC %}}');
            }
        }
        
        foreach my $f (@files){
            $data =~ s{\{\{% INC %\}\}}{ { $self->load($f) }}e;
        }
        
        return $data;
    }
    
    else {
        croak "Can't open file $file: $!";
    }
}

sub settings {
    my $self = shift;
    my $settings = shift;
    my @settings = split "\n",$settings;
    map {
        my ($m,$m2) = $_ =~ m/\s*(.*?)\s*:\s*(.*)\s*/g;
        if ($m){
            if ($m eq 'layout'){
                $self->{layout} = $m2;
            }else {
                $self->{obj}->{$m} = $self->setVar($m2,'eval') || $m2;
            }
        }
    } @settings;
    return '';
}

sub pushData {
    my $self = shift;
    my $cur = $self->{cur};
    push @{ $self->{data}->{$self->{current}->{index}} },@_;
}

sub setVar {
    my $self = shift;
    my $content = shift;
    my $eval = shift;
    my $local = shift;
    
    my $perl = '';
    my ($var,$val) = $content =~ m/\s*((?:\.*\w+(?:\(.*?\))*)+)(?:\s*=\s*(.*))*/;

    if ($val){
        ##set value
        my $var = $self->getVar($var);
        my $val = $self->getVar($val);
        $perl = "$var = $val;";
        eval $perl and return undef if $eval;
        
    } else {
        $content =~ s{(.*)}{$self->getVar($1)}e;
        $perl = $content;
    }
    
    $eval ? return eval $perl :
    return $perl;
}

sub getVar {
    
    my $self = shift;
    my $var = shift;
    
    if ($var =~ /^\$/ || $var =~ /^\s*['"]/){
        return $var;
    }
    
    my @sp;
    my $newsp;
    while ($var =~ s/(?: (?: (\w+(?:\(.*?\))*) | \.(\(.*?\)) )  )//x){
        push @sp,$1 || $2;
        my $match = $1 || $2;
        
        if ($match =~ m/\(.*?\)$/){
            $newsp .= '->'.$match;
        } else {
            $newsp .= '->{'.$match.'}';
        }
    }
    
    my $newvar = '$self->{obj}'.$newsp;
    return $newvar || '';
}

sub toHTML {
    my $self = shift;
    return join '', @{$self->{data}};
}

package Cake::View::Object;

1;

__END__

