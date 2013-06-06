use Cake::Utils::Serializer;
use FindBin qw($Bin);
open my $fh, '<', $Bin . '/json/5.json';
local $/;
my $data = <$fh>;
close $fh;
use Data::Dumper;

my $js = Cake::Utils::Serializer->new($data)->to_perl;

#print Dumper $js->bb(0)->[0];

#my $tt = $js->to_perl(1);
print Dumper $js;
#
#my $rr = Cake::Utils::Serializer->new($tt)->to_json;
#
#print Dumper $rr;