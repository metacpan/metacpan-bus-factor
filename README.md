# CPAN Bus Factor

The [bus factor](https://www.olafalders.com/2021/06/30/cpan-bus-factor/) of a
CPAN distribution is the number of people with indexing permission who have
released *anything* to CPAN in the last two years. Dual-life modules (those
shipped with the Perl core) get a floor of 5, since the Perl 5 Porters act as a
backstop.

A bus factor of 1 means only a single maintainer appears to able to release new
versions. A bus factor of 0 means nobody with upload permission has been active
recently. We define "active recently" as anyone who has uploaded anything to
CPAN in the last 2 years.

This repository generates a nightly JSON snapshot of bus factor data for every
distribution on CPAN which has a status of "latest" and publishes it to GitHub
Pages. That means we don't track BackPAN-only packages or distributions which
never had an authorized release.

The nightly JSON will be used by MetaCPAN to provide bus factor numbers in the
sidebar. If you think those numbers are incorrect, this is the place to supply
a fix.

## Download

- [bus_factor.json](https://metacpan.github.io/metacpan-bus-factor/bus_factor.json)
- [bus_factor.json.gz](https://metacpan.github.io/metacpan-bus-factor/bus_factor.json.gz)

The JSON is keyed by distribution name:

```json
{
  "Moose": {
    "active_maintainers": ["DROLSKY", "ETHER"],
    "inactive_maintainers": ["DOY", "FLORA"],
    "owner": "STEVAN",
    "is_dual_life": false
  }
}
```

## Credits

The original CPAN bus factor script was written by
[Neil Bowers](https://metacpan.org/author/NEILB). This version is a reimplementation
inspired by his work.
