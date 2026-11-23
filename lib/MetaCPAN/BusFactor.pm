package MetaCPAN::BusFactor;

use v5.40;

use Exporter   qw( import );
use List::Util qw( max );

our @EXPORT_OK = qw( bus_factor );

# The Perl 5 Porters act as a backstop for dual-life modules.
sub bus_factor {
    my ( $active, $is_dual_life ) = @_;
    my $n = @$active;
    return $is_dual_life ? max( $n, 5 ) : $n;
}

1;

=head1 NAME

MetaCPAN::BusFactor - bus factor calculation for CPAN distributions

=head1 FUNCTIONS

=head2 bus_factor( \@active_maintainers, $is_dual_life )

Returns the number of active maintainers, raised to at least 5 for dual-life
distributions.

=cut
