#!/usr/bin/env perl

# See https://www.olafalders.com/2021/06/30/cpan-bus-factor/ for what inspired
# this metric.

use v5.12;

# Remove this once https://github.com/metacpan/MetaCPAN-Client/pull/134 has
# been released.
use lib 'MetaCPAN-Client/lib';

use Cpanel::JSON::XS ();
use DateTime         ();
use MetaCPAN::Client ();
use Module::CoreList ();
use Ref::Util        qw( is_plain_arrayref );

my $mcpan = MetaCPAN::Client->new;

# Scroll all releases from the last 2 years, collect unique PAUSE IDs.
# These will be our "active" authors.

say STDERR "Phase 1: collecting active authors ...";

my $cutoff = DateTime->now->subtract( years => 2 )->ymd;

my $recent = $mcpan->all(
    'releases',
    {
        es_filter     => { range => { date => { gte => $cutoff } } },
        fields        => [qw( author )],
        scroller_size => 500,
    }
);

my %active_authors;
my $count = 0;

while ( my $release = $recent->next ) {
    my $author = $release->author;
    $active_authors{$author} = 1 if defined $author;
    $count++;
    say STDERR "  releases scanned: $count" if $count % 5000 == 0;
}

say STDERR "  releases scanned: $count (done)";
say STDERR "  active authors: " . scalar( keys %active_authors );

# Scroll all permissions, build module -> [owner, co_maintainers...] map.
# We may as well get them all now rather than making per-dist requests.

say STDERR "Phase 2: loading permissions ...";

my $perms = $mcpan->all( 'permissions', { scroller_size => 500 } );

# module_name => { owner => PAUSEID, all => [PAUSEID, ...] }
my %perms;
$count = 0;

while ( my $perm = $perms->next ) {
    my $module = $perm->module_name;
    next unless defined $module;

    my $owner = $perm->owner;
    my @all;
    push @all, $owner if defined $owner;
    if ( my $comaint = $perm->co_maintainers ) {
        push @all, @$comaint if is_plain_arrayref($comaint);
    }

    $perms{$module} = { owner => $owner, all => \@all } if @all;

    $count++;
    say STDERR "  permissions scanned: $count" if $count % 5000 == 0;
}

say STDERR "  permissions scanned: $count (done)";

# Scroll all latest releases, map distribution -> main_module,
# look up maintainers, count how many are active, apply core-module floor.
# We will obviously miss modules which are only on BackPAN or have permission
# problems.

say STDERR "Phase 3: computing bus factor for latest releases ...";

my $latest = $mcpan->all(
    'releases',
    {
        es_filter     => { term => { status => 'latest' } },
        fields        => [qw( distribution main_module )],
        scroller_size => 500,
    }
);

my %results;
$count = 0;

while ( my $release = $latest->next ) {
    my $dist = $release->distribution;
    my $main = $release->main_module;

    next unless defined $dist;

    my $perm = defined $main ? $perms{$main}     : undef;
    my @all  = $perm         ? @{ $perm->{all} } : ();

    my @active_maintainers   = sort grep { $active_authors{$_} } @all;
    my @inactive_maintainers = sort grep { !$active_authors{$_} } @all;
    my $is_dual_life
        = defined $main && Module::CoreList::is_core($main)
        ? Cpanel::JSON::XS::true
        : Cpanel::JSON::XS::false;

    $results{$dist} = {
        active_maintainers   => \@active_maintainers,
        inactive_maintainers => \@inactive_maintainers,
        is_dual_life         => $is_dual_life,
        owner                => $perm ? $perm->{owner} : undef,
    };

    $count++;
    say STDERR "  distributions processed: $count" if $count % 5000 == 0;
}

say STDERR "  distributions processed: $count (done)";

# ── Output ───────────────────────────────────────────────────────────

my $json = Cpanel::JSON::XS->new->canonical->indent->space_after;
print $json->encode( \%results );

say STDERR "Done. $count distributions written to STDOUT.";
