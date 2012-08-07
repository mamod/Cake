package Cake::View::TT;
use strict;
use Carp;

sub new {
    
    my( $class, %option ) = @_;
    
    my $self = bless({}, $class);
    
    
    
    $self->{layout} = $option{layout};
    
    
    $self->{pre_delim} = qr/\[%/;
    
    $self->{post_delim} = qr/%\]/;
    
    $self->{path} = $option{path} || '';
    
    $self->{Debug} = $option{Debug} || '0';
    
    ###later to be used in combining the whole template
    $self->{placeholder} = 2;
    
    ###match [% main %] in the layout
    $self->{main} = qr{
	$self->{pre_delim}      
	\s*			# optional leading whitespace
	main			# match nain
	\s*			# optional trailing whitespace
	$self->{post_delim}
    }xi;
    
    ###match [% INCLUDE /some/other/file.tt %]
    $self->{include} = qr{
	$self->{pre_delim}
	\s*			# optional leading whitespace
	INCLUDE			# required INCLUDE token
	\s+			# required whitespace
	(.*?)			# grab the included template location/or block name
	\s*			# optional trailing whitespace
	$self->{post_delim}
    }xi;	
    
    $self->{process} = qr{
	$self->{pre_delim}
	\s*			# optional leading whitespace
	PROCESS			# required INCLUDE token
	\s+			# required whitespace
	(.*?)			# grab the included template name
	\s*			# optional trailing whitespace
	$self->{post_delim}
    }xi;
    
    
    
    return $self;
    
}


##reset layout
sub layout {
    $_[0]->{layout} = $_[1];
    return $_[0];
}

##reset base path
sub path {
    $_[0]->{path} = $_[1];
    return $_[0];
}

sub render {
    
    my $self = shift;
    my $template = shift;
    my $options = shift;
    
    my $layout;
    
    $self->{variables}->{_1} = $options;
    
    my $main = ($template =~ m/<.*?>|\n|\s+/g) ? $template : $self->load($template);
    
    
    if ($self->{layout}){
        $layout = $self->load($self->{layout},'1');
        
        ###replace [% main %] in layout
        $layout =~s/$self->{main}/$main/g;
    }
    
    else {
        $layout = $main;
	$self->{layout} = $main;
    }
    
    ###replace includes, each include has a special name space to reserve variables
    my $namespace = 2;
    while ($layout =~ s{$self->{include}}{ { $self->load($1,$namespace) }}e){
        $namespace++;
    };
    
    
    
    ##load process, processed files will not have special namespace
    while ($layout =~ s{$self->{process}}{ { $self->load($1) }}e){};
    
    ###check for open and close conditions
    #my $s = $self->_check($layout);
    
    $layout = $self->_render($layout);
    
    
    
    return $layout;
    
}


sub _check {
    
    my $self = shift;
    my $template = shift;
    
    ###check for opining and closing
    my $reg = qr{
        $self->{pre_delim}
	\s*			# optional leading whitespace
	IF|FOREACH|BLOCK|PERL|END
        \s+
        .*?
        $self->{post_delim}
    }x;
    
    my $count = 0;
    while( $template =~ m/$reg/ ) {
        $count++;
	substr( $template, 0, $+[0], '' ) ;
    };
    
    #die $count.' all conditions must be properly closed with [% END %]' if ($count % 2);
    
}

sub _render {
    
    my ($self,$temp) = @_;
    
    ###grab and process global variables
    $self->_global_variables($temp);
    
    ###check for parent/child condition - nested conditions
    $temp = $self->_parentChilds($temp);
    
    
    ###replace instant variables
    ### [% $var %]
    my $instantvariables = qr{
        $self->{pre_delim}
        \s+
        \$((\.*\w+(\(.*?\))*)+)
        \s+
        $self->{post_delim}
    }x;
    1 while ($temp =~ s{$instantvariables}{ { $self->{variables}->{_1}->{$1} }}e);
    
    
    ###process conditions
    $temp = $self->_process_blocks($temp);
    
    if ($@ && $self->{Debug}){
        return $@;
    }
    
    ###finalize, combine all processed blocks and serve the final view
    $temp = $self->_finalize($temp);
    
    return $temp;
    
}


sub _finalize {
    
    my ($self) = @_;
    
    ##get container
    
    my $temp = $self->{block}->{_1} || $self->{layout};
    #$temp = $self->{layout};
    
    ### [% PLACEHOLDER %] match
    my $reg = qr {
        $self->{pre_delim}
        PLACEHOLDER(_\d+)
        $self->{post_delim}
    }xs;
    
    while (my ($namespace) = $temp =~ m{$reg}){
        
        my $block = $self->{block}->{$namespace};
        
        my $length = $+[0] - $-[0];
        
        substr ($temp,$-[0],$length,$block);
        
    }
    
    ###remove [% anything %] leftovers
    $temp =~ s/\[%(.*?)%\]//gs;
    
    return $temp;
    
}



sub _process_blocks {
    
    my ($self,$temp,$return_content) = @_;
    
    ###no die we want to make our own die later
    local $SIG{__DIE__};
    
    ###match includes [% INCLUDE_namespace %]
    my $reg = qr{
        $self->{pre_delim}
        \s+
        INCLUDE
        (_\d+)
        \s+
        $self->{post_delim}
        (.*)
        $self->{pre_delim}
        \s+
        ENDINCLUDE
        \1
        \s+
        $self->{post_delim}
    }xis;
    
    ##match blokcs [% BLOCK-namespace %]
    my $block = qr{
        ($self->{pre_delim}
        \s+
        BLOCK
        (\w+\d+)
        \s+
        (.*?)
        \s+
        $self->{post_delim}
        (.*)
        $self->{pre_delim}
        \s+
        END
        \2
        \s+
        $self->{post_delim})
    }xis;
    
    
    
    ### matchin [% IF %] conditions
    my $ifcondition = qr{
        $self->{pre_delim}
        \s*
        IF(\w+\d+)
        \s+
        (.*?)
        $self->{post_delim}
        (.*?)
        $self->{pre_delim}
        \s*
        END
        \1
        \s*
        $self->{post_delim}
    }xs;
    
    ## match [% ELSIF %]
    my $elsifcondition = qr {
        $self->{pre_delim}
        \s*
        ELSIF
        \s+
        (.*?)
        $self->{post_delim}
        (.*?)
        ($self->{pre_delim}
        \s*
        (ELSIF(.*?)|ELSE)
        \s*
        $self->{post_delim}|$)
    }xs;
    
    #match [% ELSE %]
    my $elsecondition = qr {
        $self->{pre_delim}
        \s*
        ELSE
        \s+
        $self->{post_delim}
        (.*?)
        $
    }xs;
    
    ##match [%  FOREACH %]
    my $foreachcondition = qr{
        $self->{pre_delim}
        \s*
        FOREACH(\w+\d+)
        \s+
        (.*?)               #var name
        \s*
        =
        \s*
        (.*?)
        $self->{post_delim}
        (.*?)               ##content
        $self->{pre_delim}
        \s*
        END
        \1
        \s*
        $self->{post_delim}
    }xs;
    
    ###match [% PERL %]
    my $perl = qr {
        $self->{pre_delim}
        \s*
        PERL
        (\w+\d+)                ##id
        \s*
        $self->{post_delim}
        (.*?)                    ##code
        $self->{pre_delim}
        \s*
        END\1
        \s*
        $self->{post_delim}
    }xs;
    
    ##process variables
    my $variables = qr{
        $self->{pre_delim}
        \s*
        ((\.*\w+(\(.*?\))*)+)
        \s+
        $self->{post_delim}
    }xi;
    
    my $var = qr{
        $self->{pre_delim}
        \s*			# optional leading whitespace
        ([\w\d\-]+)			# any word
        \s*			# optional whitespace
        =                       # equal sign
        \s*                     #optional white space
        (.*?)			# grab the value
        \s+			# trailing whitespace
        $self->{post_delim}
    }xi;

    
    
    while( my( $namespace,$content ) = $temp =~ m{$reg} ) {
        
        #if ($namespace ne '_1'){
        #    $self->{variables}->{$namespace} = $self->{variables}->{_1};
        #}
        
        
        my $down = 0;
        my $co;
        
        substr( $temp, 0, $+[0], '' );
        
        if ($content =~ m{$reg}){
            $down = 1;
            $co = $content;
            
            ##add place holder in the place of icluded file/block
            while ($content =~ s{$reg}{ { '[%PLACEHOLDER_'.$self->{placeholder}.'%]' }}e){
                $self->{placeholder}++;
            };
            
            #$content =~ s/$reg//g;
        };
        
        
        
        ####foreach condition
        while ( my ($id,$var,$loopvar,$value) = $content =~ m{$foreachcondition} ){
           
            my $length = $+[0] - $-[0];
            my $left = $-[0];
            
            
            $loopvar =~ s/\s+//g;
            $loopvar = $self->_replace_loop_var($namespace,$loopvar);
            
            $loopvar = eval $loopvar;
            
            
            if (ref $loopvar eq 'HASH'){
                my @arr;
                
                while (my ($key,$value) = each (%{$loopvar})) {
                    push(@arr,{key => $key, value => $value});
                }
                
		
		
                $loopvar = \@arr;
            }
            
           
            my $newcontent;
            
	    my $cc = 0;
	    
	    ###ADD indexs
	    foreach my $arr (@{$loopvar}){
		$loopvar->[$cc]->{INDEX} = $cc+1;
		$cc++;
	    }
	    
            
	    
            push(@{$self->{variables}->{$namespace}->{$id}->{$var}},$loopvar);
	    
	    
            my $this = $#{$self->{variables}->{$namespace}->{$id}->{$var}};
            
            my $count = 0;
            if (ref($loopvar) eq 'ARRAY'){
                foreach my $t (@{$loopvar}){
                    
                    $newcontent .= $value;
                    $newcontent =~ s/(\[%.*?\s+)$var(.*?)(\s+.*?%\])/$1$id\.$var\.$this\.$count$2$3/g;
                    #$newcontent =~ s/(\[%.*?\s+)$var(.*?)(\s+.*?%\])/$1$id\.$var\.$this\.$count$2$3/g;
                    $count++;
                }
            }
            
            else {
                $newcontent .= $value;
                $newcontent =~ s/(\[%.*?\s+)$var(.*?)(\s+.*?%\])/$1$id\.$var\.$this\.$count$2$3/g;
            }
            
            substr($content,$left,$length,$newcontent);
            
        }
        
        #return $content;
        
        my $slashes;
	
        ####if condition
        while ( my ($id,$condition,$value) = $content =~ m{$ifcondition} ){
            
            #my $elsifcontent = $value;
            my $else;
            my $elsif;
            
            $condition = $self->_replace_var($condition);
            
            my $length = $+[0] - $-[0];
            my $left = $-[0];
            
            if ($value =~ s/$elsecondition//g){
                
                my $elsevalue = $self->_code($1,$slashes++);
                $else = qq{
                    else {
                        return $elsevalue
                    }
                };
                
            }
            
            
            
            while ( my ($elscondition,$elsvalue, $end) = $value =~ m{$elsifcondition} ){
                #return $end;
                my $sublength = $+[0] - $-[0];
                
                $elscondition = $self->_replace_var($elscondition);
                
                $elsvalue = $self->_code($elsvalue,$slashes++);
                
                $elsif .= qq{
                    
                    elsif ($elscondition){
                        return $elsvalue
                    }
                    
                };
                
                substr($value,$-[0],$sublength,$end);
                
            }
            
            
            #$value = $self->_replace($value,$slashes++);
            $value = $self->_code($value,$slashes++);
           
            my $newsub = qq{
                
                [% PERL$id %]
                my \$self = shift;
                if ($condition) {
                    return $value
                }
            };
            
            ###match ELSIF
            $newsub .= $elsif if $elsif;
            $newsub .= $else if $else;
            
            $newsub .= qq{
                [% END$id %]
            };
            
            substr($content,$left,$length,$newsub);
            
        }
        
        #return $content;
        
        while( my ( $id, $action, $var_name, $var_value, $svariable ) = $content =~ m{$perl|$var|$variables} ) {
            
            my $length = $+[0] - $-[0];
            
            ###PERL Blocks
            if ($id) {
                
                my $vars = $self->{variables}->{$namespace};
                
                my $code;
                my $sub = "sub {$action}";
                $code = eval $sub;
                
                $code = eval {
                    $code->($vars)
                };
                
                if ($@){
                    $@ = {
                        block => $id,
                        namespace => $namespace,
                        type => 'code',
                        action => $action,
                        start => $-[0],
                        end => $+[0],
                        message => $@
                    };
                }
                
                substr($content,$-[0],$length,$code);
            }
            
            ###VARIABLES
            else {
                my $newvar = '';
                
                if ($var_value){
                    my ($sign,$nval) = ('','');
                    #return $var_name;
                    if ($var_value =~ m/^[^"']/){
                        
                        ###allow calc operations
                        if ( $var_value =~ m/(.*?)\s*((?:\+|\-|\%\*)+)\s*(.*?)$/g ){
                            $var_value = $1;
                            $sign = $2;
                            $nval = $3;
                            
                            $nval = $self->_replace_loop_var($namespace,$nval) if $nval =~ /[^\d+]/;
                            #return $nval;
                        }
                        
                        $var_value = $self->_replace_loop_var($namespace,$var_value);
                        $var_value = eval "$var_value$sign$nval";
                        
                    }
                    
                    else {
                        $var_value =~ s/^["'](.*?)["']$/$1/;
                    }
                    
                    $self->{variables}->{$namespace}->{$var_name} = $var_value;
                    
                }
                
                else {
                    
                    
                    $newvar = $self->_replace_loop_var($namespace,$svariable);
                    
                    $newvar = eval $newvar;
                    
		#    if (!$newvar){
		#	$newvar =~ s/{_\d}/{_1}/g;
		#	$newvar = eval $newvar;
		#    }
		    
                    
                    if ($@){
                        $@ = {
                            variable => $svariable,
                            namespace => $namespace,
                            type => 'variable',
                            message => $@,
                            start => $-[0],
                            end => $+[0]
                        };
                    }
                    
                    
                }
                
                substr($content,$-[0],$length,$newvar);
            }
            
        };
        
        return $content if $return_content;
        
        ##save processed block
        $self->{block}->{$namespace} = $content;
        
        ###do we have more blocks? process them
        if ($down){
            $self->_process_blocks($co);
        };
	
        
    };
    
    return $self;
    
}

sub _code {
    
    my $self = shift;
    my $code = shift;
    my $id = shift;
    
    $code =~ s/^\s+//;
    
    return "<<'EOF$id'"."\n".$code."\n"."EOF$id";
    
    
}


sub _replace_loop_var {
    
    my ($self,$namespace,$var) = @_;
    
    ##FIX ME 'Need a split to avoid dots inside '' and "" 's
    my @sp = split /\.(?=\w)/,$var;
    
    #my @sp = $var =~ /([^"']\w+\.\w+[^"'])/g;
    
    my $newsp;
    
    map {
        $newsp .= '->{'.$_.'}';
    } @sp;
    
    
    my $newvar = '$self'."->{variables}->{$namespace}".$newsp;
    $newvar =~ s/\{(\d+)\}/\[$1\]/g;
    $newvar =~ s/\{(\w+\(.*?\))\}/$1/g;
    
    
    while ($newvar =~ m/\(\s*([^[{"'\$].*?)\s*\)/ ) {
        my $length = $+[0] - $-[0];
        
        my $nv = $self->_replace_loop_var($namespace,$1);
        
        substr($newvar,$-[0],$length,'('.$nv.')');
    }
    
    
    return $newvar;
    
    
}

sub _replace_var {
    
    my ($self,$content,$regex) = @_;
    
    my $var = $regex || qr{
        \s*
        #((\.*\w+)+(\(.*?\))*)
        ((\.*\w+(\(.*?\))*)+)
        \s+
    }x;
    
    while (my ($var) = $content =~ m{$var}){
        
        my $length = $+[0] - $-[0];
        my $left = $-[0];
       
        #return $var;
        my @sp = split(/\./,$var);
        
        my $newsp;
        
        
        map {
            $newsp .= '->{'.$_.'}';
        } @sp;
        
        
        
        my $newvar = '$self'.$newsp.' ';
        
        substr($content,$left,$length,$newvar);
        
    }
    
    $content =~ s/==/eq/g;
    $content =~ s/!=/ne/g;
    $content =~ s/\{(\w+\(.*?\))\}/$1/g;
    $content =~ s/\{(\d+)\}/\[$1\]/g;
    
    return $content;
    
    
}



sub _parentChilds {
    
    my ($self,$temp) = @_;
    
    my $reg = qr{
        ($self->{pre_delim}
        \s*)
        (FOREACH|IF|BLOCK|PERL|END)
        (\s+
        .*?
        $self->{post_delim})
    }x;
    
    my $extract = $temp;
    my $length = length($temp);
    #$temp =~ s/$reg/$1-/;
    
    my $ends = 0;
    my $name = 'a';
    
    my $whole = $temp;
    while (my ($start,$key,$end) = $temp =~ m{$reg}){
        
        
        $name++ if $ends == 0;
        
        my $left_index = $-[0] ;
	my $right_index = $+[0];
        my $chunk;
        
        #my $length = length($start.$key.$end);
        my $length = $right_index - $left_index;
        
        if ($key =~ /FOREACH|IF|BLOCK|PERL/){
            $ends++;
            $chunk = $start.$key.$name.$ends.$end;
        }
        
        else {
            $chunk = $start.$key.$name.$ends.$end;
            $ends--;
        }
        
        
        substr( $temp, $left_index, $length, $chunk );
    }
    
    return $temp;
    
    
    
}


sub _grab_variables {
    
    my ($self,$temp) = @_;
    
    my $reg = qr{
        $self->{pre_delim}
        \s+
        INCLUDE
        (_\d+)
        \s+
        $self->{post_delim}
        (.*)
        $self->{pre_delim}
        \s+
        ENDINCLUDE
        \1
        \s+
        $self->{post_delim}
    }xis;
    
    my $reg2 = qr{
        $self->{pre_delim}
	\s*			# optional leading whitespace
	([\w\d\-]+)			# any word
	\s*			# optional whitespace
        =                       # equal sign
        \s*                     #optional white space
	(.*?)			# grab the value
	\s*			# optional trailing whitespace
	$self->{post_delim}
    }xi;
    
    while( my( $namespace,$content ) = $temp =~ m{$reg} ) {
        
        my $right_chunk = $+[0];
        
        substr( $temp, 0, $right_chunk, '' );
        
        if ($content =~ m{$reg}){
            $self->_grab_variables($content);
            $content =~ s/$reg//g;
        };
        
        while( my( $var_name, $var_value ) = $content =~ m{$reg2} ) {
            
            #my ($tvar,$tt) = $var_value =~ m/(.*?)\s+(.*)$/g;
            
            if ($var_value =~ m/^[^"']/){
                $var_value = $self->_replace_loop_var($namespace,$var_value);
                $var_value = eval "$var_value";
            }
            
            else {
                $var_value =~ s/^["'](.*?)["']$/$1/;
            }
            
            $self->{variables}->{$namespace}->{$var_name} = $var_value;
            
            # truncate the matched text so the next match starts at begining of string
            substr( $content, 0, $+[0], '' ) ;
        };
	
        
    };
    
    return $self;
    
}





sub _global_variables {
    
    my ($self,$temp) = @_;
    
    
    
    my $reg2 = qr{
        $self->{pre_delim}
	\s*		# optional leading whitespace
	global
	\s+
	([\w\d\-]+)			# any word
	\s*			# optional whitespace
        =                       # equal sign
        \s*                     #optional white space
	(.*?)			# grab the value
	\s*			# optional trailing whitespace
	$self->{post_delim}
    }xi;
    
    
        
        while( my( $var_name, $var_value ) = $temp =~ m{$reg2} ) {
            
            #my ($tvar,$tt) = $var_value =~ m/(.*?)\s+(.*)$/g;
            
            if ($var_value =~ m/^[^"']/){
                $var_value = $self->_replace_loop_var('_1',$var_value);
                $var_value = eval "$var_value";
            }
            
            else {
                $var_value =~ s/^["'](.*?)["']$/$1/;
            }
            
            $self->{variables}->{'_1'}->{$var_name} = $var_value;
            
            # truncate the matched text so the next match starts at begining of string
            substr( $temp, 0, $+[0], '' ) ;
        };
    
    return $self;
    
}







####read from files
sub load {
    
    my ($self,$file,$namespace) = @_;
    my ($data);
    
    local $/;
    
    ##cant include file inside it self
    
    
    #!$self->{includes}->{$file} ? $self->{includes}->{$file} = 1 : return '';
    $file = $self->{path}."/$file" if $self->{path};
    
    if (open(my $fh,'<',$file)) {
	
        $data = <$fh>;
        close($fh);
        
        if ($namespace){
            
            $data = qq/[% INCLUDE_$namespace %] $data [% ENDINCLUDE_$namespace %]/;
            
        }
        
        return $data;
    }
    
    else {
        croak "Can't open file $file: $!";
    }
    
}




1;