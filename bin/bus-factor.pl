#!/usr/bin/env perl

# See https://www.olafalders.com/2021/06/30/cpan-bus-factor/ for what inspired
# this metric.

use v5.12;

use Cpanel::JSON::XS ();
use DateTime         ();
use MetaCPAN::Client ();
use Module::CoreList ();
use Ref::Util        qw( is_plain_arrayref );

{
    # The API intermittently answers a valid scroll request with
    # 500 {"message":"Scroll Id required"}. The request is rejected before it
    # reaches Elasticsearch, so the scroll has not advanced and resending the
    # identical request is safe (and in practice succeeds on the first retry).
    # Any other failure is left alone: blindly retrying a scroll request that
    # did reach Elasticsearch could silently skip a batch.

    package RetryingUA;
    use parent 'HTTP::Tiny';

    sub request {
        my ( $self, @args ) = @_;

        my $res;
        for my $attempt ( 1 .. 10 ) {
            $res = $self->SUPER::request(@args);
            return $res
                unless $res->{status} == 500
                && ( $res->{content} // q{} ) =~ /Scroll Id required/;
            say STDERR "  API said 'Scroll Id required'; retrying request ($attempt)";
            sleep 1;
        }
        return $res;
    }
}

my $mcpan = MetaCPAN::Client->new(
    ua => RetryingUA->new(
        agent =>
            "metacpan-bus-factor MetaCPAN::Client/$MetaCPAN::Client::VERSION",
        verify_SSL => 1,
    ),
);

# Backstop for any other mid-scroll failure ("failed to fetch next scrolled
# batch"). A scroll can't be safely resumed, so on failure we start the whole
# scroll over. The per-item handlers below are idempotent (they only assign
# hash keys), so replaying items from a failed attempt is harmless.

my $max_attempts = 5;

sub scroll_all {
    my ( $type, $params, $label, $handler ) = @_;

    for my $attempt ( 1 .. $max_attempts ) {
        my $count = 0;
        my $ok    = eval {

            # MetaCPAN::Client deletes keys from the params it is given.
            my $rs    = $mcpan->all( $type, {%$params} );
            my $total = $rs->total;

            while ( my $item = $rs->next ) {
                $handler->($item);
                $count++;
                say STDERR "  $label: $count" if $count % 5000 == 0;
            }

            die "scroll ended early: got $count of $total\n"
                if $count < $total;
            1;
        };

        if ($ok) {
            say STDERR "  $label: $count (done)";
            return $count;
        }

        my $err = $@ || 'unknown error';
        chomp $err;
        die "$label: giving up after $attempt attempts: $err\n"
            if $attempt == $max_attempts;

        my $delay = 30 * 2**( $attempt - 1 );
        say STDERR
            "  $label: attempt $attempt failed after $count items ($err); retrying in ${delay}s ...";
        sleep $delay;
    }
}

# Scroll all releases from the last 2 years, collect unique PAUSE IDs.
# These will be our "active" authors.

say STDERR "Phase 1: collecting active authors ...";

my $cutoff = DateTime->now->subtract( years => 2 )->ymd;

my %active_authors;

scroll_all(
    'releases',
    {
        es_filter     => { range => { date => { gte => $cutoff } } },
        fields        => [qw( author )],
        scroller_size => 500,
    },
    'releases scanned',
    sub {
        my $author = shift->author;
        $active_authors{$author} = 1 if defined $author;
    },
);

say STDERR "  active authors: " . scalar( keys %active_authors );

# Scroll all permissions, build module -> [owner, co_maintainers...] map.
# We may as well get them all now rather than making per-dist requests.

say STDERR "Phase 2: loading permissions ...";

# module_name => { owner => PAUSEID, all => [PAUSEID, ...] }
my %perms;

scroll_all(
    'permissions',
    { scroller_size => 500 },
    'permissions scanned',
    sub {
        my $perm   = shift;
        my $module = $perm->module_name;
        return unless defined $module;

        my $owner = $perm->owner;
        my @all;
        push @all, $owner if defined $owner;
        if ( my $comaint = $perm->co_maintainers ) {
            push @all, @$comaint if is_plain_arrayref($comaint);
        }

        $perms{$module} = { owner => $owner, all => \@all } if @all;
    },
);

# Scroll all latest releases, map distribution -> main_module,
# look up maintainers, count how many are active, apply core-module floor.
# We will obviously miss modules which are only on BackPAN or have permission
# problems.

say STDERR "Phase 3: computing bus factor for latest releases ...";

my %results;

scroll_all(
    'releases',
    {
        es_filter     => { term => { status => 'latest' } },
        fields        => [qw( distribution main_module )],
        scroller_size => 500,
    },
    'distributions processed',
    sub {
        my $release = shift;
        my $dist    = $release->distribution;
        my $main    = $release->main_module;

        return unless defined $dist;

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
    },
);

# ── Output ───────────────────────────────────────────────────────────

my $json = Cpanel::JSON::XS->new->canonical->indent->space_after;
print $json->encode( \%results );

say STDERR "Done. "
    . scalar( keys %results )
    . " distributions written to STDOUT.";
