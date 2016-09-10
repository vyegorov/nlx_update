/*
 *  NLX Update tables
 *
 *  Should be executed as NLX Update owner, created by `01-init.sql`.
 */
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
ALTER TABLE file ADD CONSTRAINT c_file_updated
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
-- }}}
-- {{{ bag_stats
CREATE TABLE bag_stats (
    file_id                     int4        NOT NULL,
    table_name                  text        NOT NULL,
    row_count                   int8        NOT NULL,
    max_gid                     int8        NOT NULL,
    dup_count                   int8,       /* can be NULL, 2-step process */
    CONSTRAINT p_bag_stats PRIMARY KEY (file_id, table_name),
    CONSTRAINT f_bag_stats_file FOREIGN KEY (file_id) REFERENCES file
);
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
-- }}}
-- {{{ mview
--     Materialized views instead of tables
CREATE TABLE mview (
    mview_name      text        NOT NULL,
    seq_no          int4        NOT NULL,
    refresh_no      int4        NOT NULL,
    refresh_type    char(1)     NOT NULL CHECK (refresh_type IN ('A', 'M')), -- Automatic, Manual
    modify_dt       timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT p_mview PRIMARY KEY (mview_name),
    CONSTRAINT u_refresh_seq UNIQUE (refresh_type, seq_no)
);
-- }}}
-- {{{ mview_track
CREATE TABLE mview_track (
    mview_name      text        NOT NULL,
    seq_no          int4        NOT NULL,
    refresh_no      int4        NOT NULL,
    refresh_type    char(1)     NOT NULL CHECK (refresh_type IN ('A', 'M')),
    modify_dt       timestamptz NOT NULL,
    operation       char(1)     CHECK (operation IN ('I','U','D')),
    CONSTRAINT p_mview_track PRIMARY KEY (mview_name, modify_dt),
    CONSTRAINT f_mview_track FOREIGN KEY (mview_name) REFERENCES mview
);
-- }}}
