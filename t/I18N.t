package App;
use Test::More;
use Cake;
use bytes;
use Encode;
use utf8;
use FindBin qw($Bin);

plugins [
    
    'Static' => {
        dir => $Bin . '/static'
    },
    
    'View' => {
        path => $Bin . '/temp',
        layout => 'layout.tt'
    },
    
    'I18N' => {
        path => $Bin . '/I18N',
        lang => 'en'
    }
];

App->bake()->serve(sub {
    my $c = shift;
    $c->set_lang('ar');
    is($c->get_lang,'ar',"language set to Arabic");
    my $trans = $c->loc('welcome',['محمود','مهيار']);
    my $len = bytes::length($trans);
    is($len, bytes::length('مرحبا محمود مهيار'),"Arabic Byte length Match");
    is($trans, 'مرحبا محمود مهيار',"Arabic translation");
    
    ##set en
    $c->set_lang('en');
    is($c->get_lang,'en',"language rolled back to English");
    my $trans2 = $c->loc('welcome',['Mamod','Mehyar']);
    my $len2 = length($trans2);
    is($len2, length('Welcome Mamod Mehyar'),"English Bytelength Match");
    is($trans2, 'Welcome Mamod Mehyar',"English Translation");
    
    ##render in template
    ##contain a mix of translations
    $c->render('I18N.tt');
    
    my $bd = $c->getBody();
    like($bd, qr/Welcome Mamod Mehyar/,'I18N match in Template');
    
    ##encode body
    my $octets = encode("utf8", "مرحبا");
    #diag $octets;
    
    like($bd, qr/$octets/,'I18N Arabic match in Template');

    ##tests from sub folders
    
    $c->set_lang('en');
    
    my $sub1 = $c->loc(['sub','test']);
    is($sub1,"Test");
    
    $c->set_lang('ar');
    my $sub2 = $c->loc(['sub','test']);
    is($sub2,"اختبار");
    
});

done_testing();

