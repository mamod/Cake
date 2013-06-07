package App;
use Test::More;
use Cake;
use bytes;

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
    is($len, bytes::length('مرحبا محمود مهيار'));
    is($trans, 'مرحبا محمود مهيار');
    
    ##set en
    $c->set_lang('en');
    is($c->get_lang,'en',"language rolled back to English");
    my $trans2 = $c->loc('welcome',['Mamod','Mehyar']);
    my $len2 = length($trans2);
    is($len2, length('Welcome Mamod Mehyar'));
    is($trans2, 'Welcome Mamod Mehyar');
    
    ##render in template
    $c->render('I18N.tt');
    
    my $bd = $c->getBody();
    like($bd, qr/Welcome Mamod Mehyar/,'I18N match in Template');
    
});

done_testing();
