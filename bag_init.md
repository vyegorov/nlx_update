1. setup the NLExtract

    Currently, NLExtract is installed in `/opt/postgres/nlx/` and
    `/opt/postgres/nlx/rel/` points to the actual release.

    cd ~/prj/ecofys/nlx
    . env/bin/activate

2. create a user (superuser)

    System set up to be owned by `nlx_bag` user and objects are loaded
    into equally named schema. Create user first and make it a superuser, as
    scripts do not check for pre-existing schema and try to create it.

    create database kadaster;
    create user nlx_bag superuser login;

    `bag/extract.conf` configuration file should be updated according to the
    choosen setup.

    Make sure PostGIS is installed and drop `nlx_bag` schema, if exists.

3. create structures `-c`

        /opt/postgres/nlx/rel/bag/bin/bag-extract.sh -c

    Revoke superuser rights from `nlx_bag`.

4. create `nlx_update`

    As `nlx_bag` execute `01-init.sql`. Fix permissions.
    Connect as `nlx_update` and execute rest of the scripts, except for `99-wipeout.sql`.

5. process the file

    # register the file
    INSERT INTO file (file_type, update_url, downloaded_name, file_status)
        VALUES ('BAG','http://full', 'DNLDLXEE02-0000648756-0086004376-08032015.zip', 'Downloaded');

    # kick off processing
    $PG_BASE/bin/pgjob nlx_update NLX

    # monitor progress in the $PG_LOG/nlx_update-$(date +%Y%m).log
