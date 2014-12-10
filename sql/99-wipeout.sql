/*
 *  NLX Update removal
 *
 *  Use this script to get rid of `nlx_update` schema.
 *  Same assumptions as for `01-init.sql` applies.
 */
REVOKE ALL ON ALL TABLES IN SCHEMA nlx_bag FROM nlx_update;
REVOKE USAGE ON SCHEMA nlx_bag FROM nlx_update;
DROP SCHEMA nlx_update CASCADE;
DROP ROLE nlx_update;
