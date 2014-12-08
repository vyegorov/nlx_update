nlx_update
==========

Load Netherland's kadaster dumps into PostgreSQL

Dependencies
------------
This tool depends on the [NL
Extract](https://github.com/opengeogroep/NLExtract) and also on
[pgenv](https://github.com/vyegorov/pgenv).

It is expected, that appropriate PostgreSQL and PostGIS versions
are already installed.

Overview
--------
So far this script is designed to load BAG updates. Per design, BAG data is
loaded into a dedicated `nlx_bag` schema. Due to the flaw in the `NLExtract`
tool loading monthly updates from kadaster will cause duplicated data.
`nlx_update` script will scan major tables after the update and move
duplicated data into a table in the `nlx_update` schema.
