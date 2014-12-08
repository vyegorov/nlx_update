1.  unpack the FULL file, or out-of-memory will happen

    BAG extracts are found in `${PG_BASE}/var/bag/`

    Unzipped <kbd>the</kbd> following way:

        mkdir -p ${PG_BASE}/tmp/t
        cd ${PG_BASE}/tmp/t
        unzip ${PG_BASE}/var/bag/full/DNLDLXEE02-...

2. setup the NLExtract

    Currently, NLExtract is installed in `/opt/postgres/nlx/` and
    `/opt/postgres/nlx/rel/` points to the actual release.

3. create a user (superuser)

    System set up to be owned by `nlx_bag` user and objects are loaded
    into equally named schema. Create user first and make it a superuser, as
    scripts do not check for pre-existing schema and try to create it.

    `bag/extract.conf` configuration file should be updated according to the
    choosen setup.

4. create structures `-c`

        /opt/postgres/nlx/rel/bag/bin/bag-extract.sh -c

    Revoke superuser rights from `nlx_bag`.

5. load the file `-e`

        /opt/postgres/nlx/rel/bag/bin/bag-extract.sh -e ${PG_BASE}/tmp/t

    It is also wise to import all pending deltas received from the
    Kadaster, using:

        /opt/postgres/nlx/rel/bag/bin/bag-extract.sh -e DNLDLXEE02-...-delta

6. NLExtract creates Key indexes, but those are not unique. It is
necessary to make them so via the constraints.

    The following check query will show all indexes in the `nlx_bag`
    schema that are not yet unqiue:

        SELECT t.relname table_name, i.relname index_name
          FROM pg_index ind
          JOIN pg_class t ON t.oid=ind.indrelid AND t.relkind='r'
          JOIN pg_class i ON i.oid=ind.indexrelid AND i.relkind='i'
          JOIN pg_namespace n ON n.oid=t.relnamespace
         WHERE n.nspname='nlx_bag'
           AND NOT (ind.indisunique OR ind.indisprimary)
           AND i.relname ~ 'key$';

    After indexes are outlined, it is necessary to do the following for
    *each* of them:

        ALTER INDEX <ind> RENAME TO <ind>__;
        ALTER TABLE <tab> ADD CONSTRAINT <ind> UNIQUE (<columns>);
        DROP INDEX <ind>__;

    As soon as the check query returns no rows -- all is fine.

7. load extras, in order:

    7.1. `-q db/script/gemeente-provincie-tabel.sql`

    7.2. `psql -f db/script/adres-tabel.sql`

    7.3. `-q db/script/geocode/geocode-tabellen.sql`

    7.4. `-q db/script/geocode/geocode-functies.sql`

9. grant permissions

        GRANT USAGE ON SCHEMA nlx_bag To public;
        GRANT SELECT ON ALL TABLES IN SCHEMA nlx_bag TO public;

10. xtras

        ALTER TABLE verblijfsobject ALTER identificatie SET STATISTICS 1000;
        ALTER TABLE verblijfsobject ALTER aanduidingrecordinactief SET STATISTICS 1000;
        ALTER TABLE verblijfsobject ALTER aanduidingrecordcorrectie SET STATISTICS 1000;
        ALTER TABLE verblijfsobject ALTER begindatumtijdvakgeldigheid SET STATISTICS 1000;
        ALTER TABLE verblijfsobjectpand ALTER identificatie SET STATISTICS 1000;
        ALTER TABLE verblijfsobjectgebruiksdoel ALTER identificatie SET STATISTICS 1000;
        ALTER TABLE pand ALTER identificatie SET STATISTICS 1000;

