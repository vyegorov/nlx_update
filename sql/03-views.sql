/*
 *  NLX Update views
 *
 *  Should be executed as NLX Update owner after `02-relations.sql`.
 *  This file is safe to be re-executed.
 */
CREATE OR REPLACE VIEW affected_tables_v AS
SELECT i.indrelid table_oid, i.indexrelid index_oid, (i.indkey::int2[])[-1:100] indkey, /* normalizing subscripts */
       n.nspname schema_name, tc.relname table_name, ic.relname index_name,
       (SELECT array_agg(ai.attname ORDER BY ai.attnum) FROM pg_attribute ai WHERE ai.attrelid=i.indexrelid) index_columns,
       (SELECT array_agg(at.attname ORDER BY at.attnum) FROM pg_attribute at
         WHERE at.attrelid=i.indrelid AND NOT at.attnum=ANY(i.indkey)
           AND at.attnum>0 AND NOT at.attisdropped) table_columns,
       (SELECT array_agg(at.attname ORDER BY at.attnum) FROM pg_attribute at
         WHERE at.attrelid=i.indrelid AND NOT at.attnum=ANY(i.indkey)
           AND at.attnum>0 AND NOT at.attisdropped AND NOT at.attname='gid') table_columns_no_gid
  FROM pg_index     i
  JOIN pg_class    ic ON ic.oid=i.indexrelid AND ic.relkind='i' AND ic.relname ~ '_key$'
  JOIN pg_namespace n ON n.oid=ic.relnamespace AND nspname='nlx_bag'
  JOIN pg_class    tc ON tc.oid=i.indrelid
 WHERE i.indnatts>1 AND i.indexprs IS NULL AND i.indpred IS NULL
   AND EXISTS ( /* table should have PK on `gid` column */
    SELECT 1
      FROM pg_index     i1
      JOIN pg_attribute a1 ON a1.attrelid=i1.indexrelid AND a1.attname='gid'
     WHERE i1.indrelid=i.indrelid AND i1.indisprimary);
