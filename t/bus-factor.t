use v5.40;

use Test2::V0;

use Cpanel::JSON::XS ();

use MetaCPAN::BusFactor qw( bus_factor );

my $true  = Cpanel::JSON::XS::true;
my $false = Cpanel::JSON::XS::false;

is( bus_factor( [], $false ),         0, 'not dual-life: no actives' );
is( bus_factor( [qw( A B )], $false ), 2, 'not dual-life: active count' );
is( bus_factor( [qw( A B )], $true ),  5, 'dual-life: raised to 5' );
is( bus_factor( [qw( A B C D )], $true ), 5, 'dual-life: 4 raised to 5' );
is( bus_factor( [qw( A B C D E F )], $true ), 6, 'dual-life: above 5 kept' );
is(
    Cpanel::JSON::XS->new->encode(
        [ bus_factor( [], $true ), bus_factor( [qw( A B C D E F )], $true ) ]
    ),
    '[5,6]', 'encodes as JSON numbers'
);

done_testing;
