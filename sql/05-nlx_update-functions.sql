/*
 *  NLX Update views and functions
 *
 *  Should be executed as NLX Update owner after `02-relations.sql`
 *  and `03-views.sql`.
 *  This file is safe to be re-executed.
 */
-- {{{ file triggers
CREATE OR REPLACE FUNCTION t_file_before() RETURNS trigger AS $t_file_before$
BEGIN
    IF NEW.modify_dt IS NULL        /* either `modify_dt` is NULL */
       OR (TG_OP='UPDATE'           /* or record was updated while `modify_dt` was not */
           AND OLD IS DISTINCT FROM NEW
           AND NOT OLD.modify_dt IS DISTINCT FROM NEW.modify_dt)
    THEN
        NEW.modify_dt := now();
    END IF;

    RETURN NEW;
END;
$t_file_before$ LANGUAGE plpgsql;
COMMENT ON FUNCTION t_file_before() IS $$Make sure `modify_dt` column is updated where appropriate$$;
CREATE OR REPLACE FUNCTION t_file_track() RETURNS trigger AS $t_file_track$
BEGIN
    IF TG_OP='UPDATE' AND NEW IS NOT DISTINCT FROM OLD THEN
        RETURN NEW;
    END IF;
    INSERT INTO file_track VALUES (NEW.file_id, NEW.modify_dt, NEW.file_type,
        CASE WHEN TG_OP='DELETE' THEN 'Pff' ELSE NEW.file_status END,
        NEW.update_url, NEW.downloaded_name, NEW.log_file_name,
        CASE WHEN TG_OP='INSERT' THEN 'I' WHEN TG_OP='UPDATE' THEN 'U' ELSE 'D' END);
    IF TG_OP='UPDATE' AND NEW.file_status='Updated' AND OLD.file_status IS DISTINCT FROM 'Updated' THEN
        PERFORM bag_stats(NEW.file_id);
    END IF;
    RETURN NEW;
END;
$t_file_track$ LANGUAGE plpgsql;
COMMENT ON FUNCTION t_file_track() IS $$Track changes to the `file` record. Force stats calculation if file had been uploaded$$;
-- }}}
-- {{{ mview triggers
CREATE OR REPLACE FUNCTION t_mview_before() RETURNS trigger AS $t_mview_before$
BEGIN
    IF NEW.modify_dt IS NULL
       OR (TG_OP='UPDATE'
           AND OLD IS DISTINCT FROM NEW
           AND NOT OLD.modify_dt IS DISTINCT FROM NEW.modify_dt)
    THEN
        NEW.modify_dt := now();
    END IF;

    RETURN NEW;
END;
$t_mview_before$ LANGUAGE plpgsql;
CREATE OR REPLACE FUNCTION t_mview_track() RETURNS trigger AS $t_mview_track$
BEGIN
    IF TG_OP='UPDATE' AND NEW IS NOT DISTINCT FROM OLD THEN
        RETURN NEW;
    END IF;
    INSERT INTO mview_track VALUES (NEW.mview_name, NEW.seq_no, NEW.refresh_no, NEW.refresh_type, NEW.modify_dt,
        CASE WHEN TG_OP='INSERT' THEN 'I' WHEN TG_OP='UPDATE' THEN 'U' ELSE 'D' END);
    RETURN NEW;
END;
$t_mview_track$ LANGUAGE plpgsql;
-- }}}
-- {{{ bag_stats()
CREATE OR REPLACE FUNCTION bag_stats(in_file int4) RETURNS int AS $bag_stats$
DECLARE
    _rec    record;
    _sql    text;
    _ttl    int DEFAULT 0;
BEGIN
    FOR _rec IN
        SELECT tc.relname table_name, n.nspname schema_name
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
             WHERE i1.indrelid=tc.oid AND i1.indisprimary)
    LOOP
        /*
         *  Query here requires sub-queries to avoid producing any rows
         *  in the case record for the file-table combination is already there
         */
        _sql := format($$INSERT INTO bag_stats
SELECT data.*
  FROM (SELECT %s, %L, count(*), max(gid) FROM %I.%I) data
 WHERE NOT EXISTS (SELECT 1 FROM bag_stats WHERE file_id=%s AND table_name=%L)$$,
                in_file, _rec.table_name, _rec.schema_name, _rec.table_name,
                in_file, _rec.table_name);

        EXECUTE _sql;
        _ttl := _ttl + 1;
        _sql := regexp_replace(_sql, E'[\\n\\r]+', ' ', 'g');
        RAISE DEBUG '  .oO( SQL: %', _sql;

    END LOOP;

    RETURN _ttl;
END;
$bag_stats$ LANGUAGE plpgsql;
COMMENT ON FUNCTION bag_stats(in_file int4) IS $$Save row counts and maximal `gid` after update uploads$$;
-- }}}
-- {{{ bag_duplicate()
CREATE OR REPLACE FUNCTION bag_deduplicate(in_file int4, in_verbose bool DEFAULT true) RETURNS int AS $bag_deduplicate$
DECLARE
    _rec    record;
    _sql    text;
    _ttl    int DEFAULT 0;
    _run    int;
    _gid    int;

BEGIN
    /*
     *  Explicitly call `bag_stats` to make sure there're statistics
     *  for the given file. If there are already, should be quick one
     */
    PERFORM bag_stats(in_file);
    FOR _rec IN SELECT * FROM affected_tables_v
    LOOP
        IF in_verbose THEN
            RAISE NOTICE '  .oO( Processing `%`', _rec.table_name;
        END IF;
        /*
         *  Get max_gid of the previous entry for the table, this
         *  makes search for the duplicates faster as we scan only
         *  newly added entries
         */
        EXECUTE format($$SELECT coalesce(max_gid, def) gid FROM (SELECT 0 def) f
  LEFT JOIN bag_stats ON table_name=%L AND file_id=($1 - 1)$$, _rec.table_name)
           INTO _gid USING in_file;

        /*  De-duplication query  */
        _sql := format($$WITH dups AS (
    SELECT %s,
           max(gid) gid
      FROM %I.%I
     WHERE gid > $1
     GROUP BY %s HAVING count(*) > 1
    UNION
    SELECT %s,
           max(n.gid) gid
      FROM %I.%I p
      JOIN %I.%I n USING(%s)
     WHERE n.gid > $1 AND p.gid <= $1
     GROUP BY %s
), del AS (
    DELETE FROM %I.%I
     WHERE (%s) IN (SELECT %s FROM dups)
       AND gid NOT IN (SELECT gid FROM dups)
    RETURNING *
)
INSERT INTO bag_duplicate
SELECT $2, %L, del.gid, %s,
       row_to_json(r)
  FROM del
  JOIN LATERAL (SELECT %s FROM %I.%I WHERE gid=del.gid) r ON true$$,
        /* CTE: dups */
        array_to_string(_rec.index_columns, ','),
        _rec.schema_name, _rec.table_name,
        array_to_string(_rec.index_columns, ','),
        array_to_string((SELECT array_agg('n.'||col) FROM unnest(_rec.index_columns) t(col)), ','),
        _rec.schema_name, _rec.table_name,
        _rec.schema_name, _rec.table_name,
        array_to_string(_rec.index_columns, ','),
        array_to_string((SELECT array_agg('n.'||col) FROM unnest(_rec.index_columns) t(col)), ','),
        /* CTE: del */
        _rec.schema_name, _rec.table_name,
        array_to_string(_rec.index_columns, ','),
        array_to_string(_rec.index_columns, ','),
        /* INSERT */
        _rec.table_name,
        array_to_string((SELECT array_agg('del.'||col) FROM unnest(_rec.index_columns) t(col)), ','),
        array_to_string(_rec.table_columns_no_gid, ','),
        _rec.schema_name, _rec.table_name);

        EXECUTE _sql USING _gid, in_file;
        GET DIAGNOSTICS _run = ROW_COUNT;
        _ttl := _ttl + _run;
        _sql := regexp_replace(_sql, E'[\\n\\r]+', ' ', 'g');
        RAISE DEBUG '  .oO( SQL: %', _sql;

        /*  Save duplicate count */
        UPDATE bag_stats SET
               dup_count = _run
         WHERE file_id=in_file AND table_name=_rec.table_name;

    END LOOP;

    RETURN _ttl;
END;
$bag_deduplicate$ LANGUAGE plpgsql;
COMMENT ON FUNCTION bag_deduplicate(in_file int4, in_verbose bool) IS $$Extract duplicates into a dedicated table, report back number of duplicates moved$$;
-- }}}
-- {{{ bag_dups()
CREATE OR REPLACE FUNCTION bag_dups() RETURNS TABLE (table_name text, dup_count int8) AS $bag_dups$
DECLARE
    _rec    record;
BEGIN
    FOR _rec IN
        SELECT format($$SELECT '%s'::text, coalesce((SELECT count(*) FROM %I.%I GROUP BY %s HAVING count(*) > 1), 0)$$,
                      v.table_name,v.schema_name,v.table_name,array_to_string(v.index_columns,',')) AS sql
          FROM affected_tables_v v
    LOOP
        RETURN QUERY EXECUTE _rec.sql;
    END LOOP;
    RETURN ;
END;
$bag_dups$ LANGUAGE plpgsql;
COMMENT ON FUNCTION bag_dups() IS $$Report duplicates for all affected tables using `count(*)`$$;
-- }}}
-- {{{ mview_refresh()
CREATE OR REPLACE FUNCTION mview_refresh(_mview text) RETURNS int4 AS $mview_refresh$
DECLARE
    _no     int4;
BEGIN
    UPDATE mview SET refresh_no=nextval('mview_refresh_no')
     WHERE mview_name=_mview RETURNING refresh_no INTO _no;
    EXECUTE format('REFRESH MATERIALIZED VIEW CONCURRENTLY $I', _mview);

    RETURN _no;
END;
$mview_refresh$ LANGUAGE plpgsql;
-- }}}
