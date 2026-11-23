use v5.40;

use Test2::V0;

use Cpanel::JSON::XS ();

do './bin/bus-factor.pl' or die $@ || $!;

my $true  = Cpanel::JSON::XS::true;
my $false = Cpanel::JSON::XS::false;

is( bus_factor( [qw( A B )], $false ), 2, 'not dual-life: active count' );
is( bus_factor( [qw( A B )], $true ),  5, 'dual-life: raised to 5' );
is( bus_factor( [qw( A B C D E F )], $true ), 6, 'dual-life: above 5 kept' );
is(
    Cpanel::JSON::XS->new->encode( [ bus_factor( [], $true ) ] ),
    '[5]', 'encodes as a JSON number'
);

done_testing;
