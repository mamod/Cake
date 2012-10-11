package Cake::View::TT;
use strict;
use warnings;
use Carp;
use Data::Dumper;

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
    $PRE
    \s*
    PROCESS
    \s+
    (.*?)
    \s*
    $POST
}x;

my $INCLUDE = qr{
    $PRE
    \s*
    INCLUDE
    \s+
    (.*?)
    \s*
    $POST
}x;


my $SETTINGS = qr{
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

Cake::View::TTT
    
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
sub DEBUG{$DEBUG};

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
                msg => $@
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
    return @{$self->{matches}};
}


sub load {
    
    my ($self,$file) = @_;
    my ($data);
    
    local $/;
    
    $file = $self->{path}."/$file";
    
    if (open(my $fh,'<',$file)) {
        $data = <$fh>;
        close($fh);
        
        my @files;
        while ($data =~ s{$SETTINGS}{ { $self->settings($1) }}e){};
        while ($data =~ s{$PROCESS}{ { $self->load($1) }}e){};
        while ($data =~ s{$INCLUDE}{ { '{{% INC %}}' }}e){
            push @files,$1;
        };
        
        while (my ($m1,$m2,$m3) = $data =~ m{$CODE|$VAR}){
            my $content = $m1 || $m2;
            push @{$self->{matches}},{
                index => ++$self->{i},
                content => $content,
                start => $-[0],
                from => $m1 ? 'CODE' : 'VAR',
                file => $file
            };
            
            my $length = $+[0] - $-[0];
            substr ($data,$-[0],$length,"{{ $self->{i} }}");
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
        my ($m,$m2) = $_ =~ m/\s*(.*?)\s*:\s*(.*?)\s*/;
        if ($m eq 'layout'){
            $self->{layout} = $m2;
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
    
    #my @sp = split(/((\.*\w+(\(.*?\))*)+)/,$var);
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


=head1 NAME

Cake::View::TT

=head1 STNOPSIS

=head1 DESCRIPTION


