/*
 *  BAG Update Procedure
 *  https://github.com/opengeogroep/NLExtract
 *
 *  NLExtract has a couple of drawbacks:
 *  1. addresses are not generated for objects without post code, which is not
 *     good, as quite some entries are missed;
 *  2. a bigger issue is usage of surrogate `gid` key, that in no way protects
 *     data from duplicates. There're multicolumn indexes that are candidates
 *     for the uniqueness checks though. Still, loading monthly BAG updates
 *     leads to duplicated data.
 *
 *
 */
CREATE ROLE nlx_update LOGIN;
CREATE SCHEMA AUTHORIZATION nlx_update;
CREATE VIEW affected_tables_v AS
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
-- {{{ file_status
CREATE TABLE file_status (
    file_status         text    NOT NULL CONSTRAINT p_file_status PRIMARY KEY
);
INSERT INTO file_status VALUES ('Registered'),('Downloaded'),('Updated'),('Error'),('Archived');
-- }}}
-- {{{ file_type
CREATE TABLE file_type (
    file_type           text    NOT NULL CONSTRAINT p_file_type PRIMARY KEY
);
INSERT INTO file_type VALUES ('BAG');
-- }}}
-- {{{ file
CREATE SEQUENCE file_id START WITH 1001;
CREATE TABLE file (
    file_id             int4        NOT NULL DEFAULT nextval('file_id'),
    file_type           text        NOT NULL,
    file_status         text        NOT NULL DEFAULT 'Registered',
    update_url          text        NOT NULL,
    modify_dt           timestamptz NOT NULL DEFAULT now(),
    downloaded_name     text,
    log_file_name       text,
    CONSTRAINT p_file PRIMARY KEY (file_id),
    CONSTRAINT f_file_type FOREIGN KEY (file_type) REFERENCES file_type,
    CONSTRAINT f_file_status FOREIGN KEY (file_status) REFERENCES file_status,
    CONSTRAINT u_file_url UNIQUE (update_url)
);
ALTER SEQUENCE file_id OWNED BY file.file_id;
ALTER TABLE file ADD CONSTRAINT c_file_downloaded
    CHECK ((NOT file_status IN ('Downloaded','Updated'))
        OR (file_status IN ('Downloaded', 'Updated') AND downloaded_name IS NOT NULL));
ALTER TABLE file ADD CONSTRAINT c_fil_updated
    CHECK ((NOT file_status = 'Updated')
        OR (file_status='Updated' AND log_file_name IS NOT NULL));
CREATE TABLE file_track (
    file_id             int4        NOT NULL,
    modify_dt           timestamptz NOT NULL,
    file_type           text,
    file_status         text,
    update_url          text,
    download_name       text,
    log_file_name       text,
    operation           char(1)     CHECK (operation IN ('I','U','D')),
    CONSTRAINT p_file_track PRIMARY KEY (file_id, modify_dt),
    CONSTRAINT f_file_track_id FOREIGN KEY (file_id) REFERENCES file
);
CREATE OR REPLACE FUNCTION t_file_before() RETURNS trigger AS $t_file_before$
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
$t_file_before$ LANGUAGE plpgsql;
CREATE TRIGGER t_file_modify BEFORE INSERT OR UPDATE ON file FOR EACH ROW
    EXECUTE PROCEDURE t_file_before();
CREATE OR REPLACE FUNCTION t_file_track() RETURNS trigger AS $t_file_track$
BEGIN
    IF TG_OP='UPDATE' AND NEW IS NOT DISTINCT FROM OLD THEN
        RETURN NEW;
    END IF;
    INSERT INTO file_track VALUES (NEW.file_id, NEW.modify_dt, NEW.file_type,
        CASE WHEN TG_OP='DELETE' THEN 'Pff' ELSE NEW.file_status END,
        NEW.update_url, NEW.downloaded_name, NEW.log_file_name,
        CASE WHEN TG_OP='INSERT' THEN 'I' WHEN TG_OP='UPDATE' THEN 'U' ELSE 'D' END);
    IF TG_OP='UPDATE' AND NEW.file_status='Updated' THEN
        PERFORM bag_stats(NEW.file_id);
    END IF;
    RETURN NEW;
END;
$t_file_track$ LANGUAGE plpgsql;
CREATE TRIGGER t_file_track AFTER INSERT OR UPDATE OR DELETE ON file FOR EACH ROW
    EXECUTE PROCEDURE t_file_track();
-- }}}
-- {{{ bag_stats
CREATE TABLE bag_stats (
    file_id                     int4        NOT NULL,
    table_name                  text        NOT NULL,
    row_count                   int8        NOT NULL,
    max_gid                     int8        NOT NULL,
    CONSTRAINT p_bag_stats PRIMARY KEY (file_id, table_name),
    CONSTRAINT f_bag_stats_file FOREIGN KEY (file_id) REFERENCES file
);
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
-- }}}
-- }}}
-- {{{ bag_duplicate
--     deleted `bag` duplicates
CREATE TABLE bag_duplicate (
    file_id                     int4        NOT NULL,
    table_name                  text        NOT NULL,
    gid                         int4        NOT NULL,
    identificatie               numeric(16) NOT NULL,
    aanduidingrecordinactief    bool        NOT NULL,
    aanduidingrecordcorrectie   integer     NOT NULL,
    begindatumtijdvakgeldigheid timestamp   NOT NULL,
    rest                        json        NOT NULL,
    CONSTRAINT p_bag_duplicate PRIMARY KEY (file_id, table_name, gid),
    CONSTRAINT f_bag_duplicate_file FOREIGN KEY (file_id) REFERENCES file
);
-- {{{ bag_duplicate()
CREATE OR REPLACE FUNCTION bag_deduplicate(in_file int4, in_verbose bool DEFAULT true) RETURNS int AS $bag_deduplicate$
DECLARE
    _rec    record;
    _sql    text;
    _ttl    int DEFAULT 0;
    _run    int;
    _gid    int;

BEGIN
    FOR _rec IN SELECT * FROM affected_tables_v
    LOOP
        IF in_verbose THEN
            RAISE NOTICE '  .oO( Processing `%`', _rec.table_name;
        END IF;
        EXECUTE format($$SELECT coalesce(max_gid, def) gid FROM (SELECT 0 def) f
  LEFT JOIN bag_stats ON table_name=%L AND file_id=($1 - 1)$$, _rec.table_name)
           INTO _gid USING in_file;

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

    END LOOP;

    RETURN _ttl;
END;
$bag_deduplicate$ LANGUAGE plpgsql;
-- }}}
-- {{{ bag_dups
CREATE OR REPLACE FUNCTION bag_dups() RETURNS TABLE (table_name text, dup_count int8) AS $bag_dups$
DECLARE
    _rec    record;
BEGIN
    FOR _rec IN
        SELECT format($$SELECT '%s'::text, coalesce((SELECT count(*) FROM %I.%I GROUP BY %s HAVING count(*) > 1), 0)$$,
                      v.table_name,v.schema_name,v.table_name,array_to_string(v.index_columns,',')) sql
          FROM affected_tables_v v
    LOOP
        RETURN QUERY EXECUTE _rec.sql;
    END LOOP;
    RETURN ;
END;
$bag_dups$ LANGUAGE plpgsql;
-- }}}
-- }}}
-- {{{ grants, execute after *all* schemas are in place
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
-- }}}
-- {{{ getting rid of
REVOKE ALL ON ALL TABLES IN SCHEMA nlx_bag FROM nlx_update;
REVOKE USAGE ON SCHEMA nlx_bag FROM nlx_update;
DROP SCHEMA nlx_update CASCADE;
DROP ROLE nlx_update;
-- }}}
