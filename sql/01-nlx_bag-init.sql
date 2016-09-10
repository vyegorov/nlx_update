/*
 *  NLX Update user and grants
 *
 *  Should be executed after NL Extract schema is initialized.
 *  Assumptions:
 *  - BAG schema is named `nlx_bag`;
 *  - BAG schema owning user has SUPERUSER rights, which is required
 *    by NL Extract to initialize the schema;
 *  - executed as BAG schema owner.
 *
 *  Note: statements returned by the last query are executed in the same session.
 */
CREATE ROLE nlx_update LOGIN;
CREATE SCHEMA AUTHORIZATION nlx_update;

GRANT USAGE ON SCHEMA nlx_bag TO nlx_update;
SELECT format($$GRANT ALL ON TABLE %I.%I TO nlx_update;$$, n.nspname, tc.relname)
  FROM pg_class tc
  JOIN pg_namespace n ON n.oid=tc.relnamespace AND n.nspname='nlx_bag'
 WHERE tc.relkind='r'
   AND EXISTS (SELECT 1 FROM pg_attribute at
                WHERE attrelid=tc.oid AND attnum>0 AND NOT attisdropped
                  AND attname='gid')
   AND EXISTS ( /* table should have PK on `gid` column */
    SELECT 1
      FROM pg_index     i1
      JOIN pg_attribute a1 ON a1.attrelid=i1.indexrelid AND a1.attname='gid'
     WHERE i1.indrelid=tc.oid AND i1.indisprimary);

CREATE SEQUENCE mview_refresh_no;
GRANT USAGE ON SEQUENCE mview_refresh_no TO nlx_update;
CREATE SEQUENCE gemeente_gid;
GRANT USAGE ON SEQUENCE gemeente_gid TO nlx_update;
CREATE SEQUENCE provincie_gid;
GRANT USAGE ON SEQUENCE provincie_gid TO nlx_update;
CREATE SEQUENCE adres_gid;
GRANT USAGE ON SEQUENCE adres_gid TO nlx_update;
CREATE SEQUENCE geo_adres_gid;
GRANT USAGE ON SEQUENCE geo_adres_gid TO nlx_update;
CREATE SEQUENCE geo_postcode6_gid;
GRANT USAGE ON SEQUENCE geo_postcode6_gid TO nlx_update;
CREATE SEQUENCE geo_postcode4_gid;
GRANT USAGE ON SEQUENCE geo_postcode4_gid TO nlx_update;
CREATE SEQUENCE geo_straatnaam_gid;
GRANT USAGE ON SEQUENCE geo_straatnaam_gid TO nlx_update;
CREATE SEQUENCE geo_woonplaats_gid;
GRANT USAGE ON SEQUENCE geo_woonplaats_gid TO nlx_update;
CREATE SEQUENCE geo_gemeente_gid;
GRANT USAGE ON SEQUENCE geo_gemeente_gid TO nlx_update;
CREATE SEQUENCE geo_provincie_gid;
GRANT USAGE ON SEQUENCE geo_provincie_gid TO nlx_update;
