/*
 *  NLX Update removal
 *
 *  Use this script to get rid of `nlx_update` schema.
 *  Same assumptions as for `01-init.sql` applies.
 */
REVOKE DELETE ON ligplaats FROM nlx_update;
REVOKE DELETE ON standplaats FROM nlx_update;
REVOKE DELETE ON verblijfsobject FROM nlx_update;
REVOKE DELETE ON pand FROM nlx_update;
REVOKE DELETE ON nummeraanduiding FROM nlx_update;
REVOKE DELETE ON openbareruimte FROM nlx_update;
REVOKE DELETE ON woonplaats FROM nlx_update;
DROP SEQUENCE mview_refresh_no;
DROP SEQUENCE gemeente_gid;
DROP SEQUENCE provincie_gid;
DROP SEQUENCE adres_gid;
DROP SEQUENCE geo_adres_gid;
DROP SEQUENCE geo_postcode6_gid;
DROP SEQUENCE geo_postcode4_gid;
DROP SEQUENCE geo_straatnaam_gid;
DROP SEQUENCE geo_woonplaats_gid;
DROP SEQUENCE geo_gemeente_gid;
DROP SEQUENCE geo_provincie_gid;
DROP MATERIALIZED VIEW gemeente;
DROP MATERIALIZED VIEW geo_provincie;
DROP MATERIALIZED VIEW geo_gemeente;
DROP MATERIALIZED VIEW geo_woonplaats;
DROP MATERIALIZED VIEW geo_straatnaam;
DROP MATERIALIZED VIEW geo_postcode4;
DROP MATERIALIZED VIEW geo_postcode6;
DROP MATERIALIZED VIEW geo_adres;
DROP MATERIALIZED VIEW adres;
DROP MATERIALIZED VIEW provincie;
DROP VIEW nummeraanduidingpostcode;
DROP SCHEMA nlx_update CASCADE;
DROP ROLE nlx_update;
