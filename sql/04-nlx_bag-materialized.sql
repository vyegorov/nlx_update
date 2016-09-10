/*
 *  NLX Update views
 *
 *  Should be executed as BAG schema owner after `02-relations.sql`.
 */

-- {{{ nummeraanduidingpostcode
CREATE VIEW nummeraanduidingpostcode AS
SELECT gid,
       identificatie,
       aanduidingrecordinactief,
       aanduidingrecordcorrectie,
       officieel,
       inonderzoek,
       documentnummer,
       documentdatum,
       huisnummer,
       huisletter,
       huisnummertoevoeging,
       postcode,
       nummeraanduidingstatus,
       typeadresseerbaarobject,
       gerelateerdeopenbareruimte,
       gerelateerdewoonplaats,
       begindatumtijdvakgeldigheid,
       einddatumtijdvakgeldigheid
  FROM nummeraanduiding
 WHERE now() >= nummeraanduiding.begindatumtijdvakgeldigheid
   AND now() <= COALESCE(nummeraanduiding.einddatumtijdvakgeldigheid::timestamp with time zone, now())
   AND NOT nummeraanduiding.aanduidingrecordinactief
   AND nummeraanduiding.nummeraanduidingstatus <> 'Naamgeving ingetrokken'::nummeraanduidingstatus;
-- }}}

-- {{{ gzoemeente
CREATE MATERIALIZED VIEW gemeente AS
WITH _r(no)     AS (SELECT refresh_no FROM nlx_update.mview WHERE mview_name='gemeente'),
     _g(gid,no) AS (SELECT setval('gemeente_gid',1,false), no FROM _r)
SELECT _g.no                    refresh_no, -- no of refresh
       nextval('gemeente_gid')  gid,        -- gid
       s.*
  FROM (
    SELECT gw.gemeentecode,
           gp.gemeentenaam,
           ST_Multi(ST_Union(w.geovlak)) geovlak
      FROM gemeente_woonplaatsactueelbestaand gw
      JOIN woonplaatsactueelbestaand w ON w.identificatie = gw.woonplaatscode
      JOIN gemeente_provincie gp ON gp.gemeentecode = gw.gemeentecode
     GROUP BY gw.gemeentecode, gp.gemeentenaam
     ORDER BY gw.gemeentecode, gp.gemeentenaam, ST_Multi(ST_Union(w.geovlak))
    ) s
 CROSS JOIN _g
WITH NO DATA;

CREATE UNIQUE INDEX gemeente_pkey ON gemeente(gid, refresh_no);
CREATE INDEX gemeente_geom_idx ON gemeente USING gist (geovlak);
CREATE INDEX gemeente_naam ON gemeente USING btree (gemeentenaam);
-- }}}
-- {{{ provincie
CREATE MATERIALIZED VIEW provincie AS
WITH _r(no)     AS (SELECT refresh_no FROM nlx_update.mview WHERE mview_name='provincie'),
     _g(gid,no) AS (SELECT setval('provincie_gid',1,false), no FROM _r)
SELECT _g.no                    refresh_no, -- no of refresh
       nextval('provincie_gid') gid,        -- gid
       s.*
  FROM (
    SELECT gp.provinciecode,
           gp.provincienaam,
           ST_Multi(ST_Union(g.geovlak)) geovlak
      FROM gemeente_provincie gp
      JOIN gemeente g USING (gemeentecode)
     GROUP BY gp.provinciecode, gp.provincienaam
     ORDER BY gp.provinciecode, gp.provincienaam, ST_Multi(ST_Union(g.geovlak))
    ) s
 CROSS JOIN _g
WITH NO DATA;

CREATE UNIQUE INDEX provincie_pkey ON provincie(gid,refresh_no);
CREATE INDEX provincie_geom_idx ON provincie USING gist (geovlak);
CREATE INDEX provincie_naam ON provincie USING btree (provincienaam);
-- }}}
-- {{{ adres
CREATE MATERIALIZED VIEW adres AS
WITH _r(no)     AS (SELECT refresh_no FROM nlx_update.mview WHERE mview_name='adres'),
     _g(gid,no) AS (SELECT setval('adres_gid',1,false), no FROM _r)
SELECT _g.no                    refresh_no, -- no of refresh
       nextval('adres_gid')     gid,        -- gid
       a.*
  FROM (
    SELECT o.openbareruimtenaam::varchar(80)    openbareruimtenaam,
           n.huisnummer::numeric(5,0)           huisnummer,
           n.huisletter::varchar(1)             huisletter,
           n.huisnummertoevoeging::varchar(4)   huisnummertoevoeging,
           n.postcode::varchar(6)               postcode,
           (CASE WHEN wp2.woonplaatsnaam IS NULL THEN w.woonplaatsnaam ELSE wp2.woonplaatsnaam END)::varchar(80) woonplaatsnaam,
           (CASE WHEN p2.gemeentenaam IS NULL THEN  p.gemeentenaam ELSE p2.gemeentenaam END)::varchar(80)        gemeentenaam,
           (CASE WHEN p2.provincienaam IS NULL THEN  p.provincienaam ELSE p2.provincienaam END)::varchar(16)     provincienaam,
           'VBO'::varchar(3)                    typeadresseerbaarobject,
           v.identificatie::numeric(16,0)       adresseerbaarobject,
           n.identificatie::numeric(16,0)       nummeraanduiding,
           false::boolean                       nevenadres,
           v.geopunt::geometry                  geopunt,
           to_tsvector(openbareruimtenaam||' '||huisnummer||' '||trim(coalesce(huisletter,'')||' '||coalesce(huisnummertoevoeging,''))||' '||
                       (CASE WHEN wp2.woonplaatsnaam IS NULL THEN w.woonplaatsnaam ELSE wp2.woonplaatsnaam END)) textsearchable_adres
      FROM verblijfsobjectactueelbestaand v
      JOIN nummeraanduidingpostcode                  n ON n.identificatie = v.hoofdadres
      JOIN openbareruimteactueelbestaand             o ON n.gerelateerdeopenbareruimte = o.identificatie
      JOIN woonplaatsactueelbestaand                 w ON o.gerelateerdewoonplaats = w.identificatie
      JOIN gemeente_woonplaatsactueelbestaand        g ON g.woonplaatscode = w.identificatie
      JOIN gemeente_provincie                        p ON g.gemeentecode = p.gemeentecode
      LEFT JOIN woonplaatsactueelbestaand          wp2 ON n.gerelateerdewoonplaats = wp2.identificatie
      LEFT JOIN gemeente_woonplaatsactueelbestaand  g2 ON g2.woonplaatscode = wp2.identificatie
      LEFT JOIN gemeente_provincie                  p2 ON g2.gemeentecode = p2.gemeentecode
    UNION ALL
    SELECT o.openbareruimtenaam,
           n.huisnummer,
           n.huisletter,
           n.huisnummertoevoeging,
           n.postcode,
           (CASE WHEN wp2.woonplaatsnaam IS NULL THEN w.woonplaatsnaam ELSE wp2.woonplaatsnaam END),
           (CASE WHEN p2.gemeentenaam IS NULL THEN  p.gemeentenaam ELSE  p2.gemeentenaam END),
           (CASE WHEN p2.provincienaam IS NULL THEN  p.provincienaam ELSE  p2.provincienaam END),
           'LIG'                                typeadresseerbaarobject,
           l.identificatie                      adresseerbaarobject,
           n.identificatie                      nummeraanduiding,
           false                                nevenadres,
           ST_Force_3D(ST_Centroid(l.geovlak))  geopunt,
           to_tsvector(openbareruimtenaam||' '||huisnummer||' '||trim(coalesce(huisletter,'')||' '||coalesce(huisnummertoevoeging,''))||' '||
                       (CASE WHEN wp2.woonplaatsnaam IS NULL THEN w.woonplaatsnaam ELSE wp2.woonplaatsnaam END)) textsearchable_adres
      FROM ligplaatsactueelbestaand l
      JOIN nummeraanduidingpostcode                  n ON n.identificatie = l.hoofdadres
      JOIN openbareruimteactueelbestaand             o ON n.gerelateerdeopenbareruimte = o.identificatie
      JOIN woonplaatsactueelbestaand                 w ON o.gerelateerdewoonplaats = w.identificatie
      JOIN gemeente_woonplaatsactueelbestaand        g ON g.woonplaatscode = w.identificatie
      JOIN gemeente_provincie                        p ON g.gemeentecode = p.gemeentecode
      LEFT JOIN woonplaatsactueelbestaand          wp2 ON n.gerelateerdewoonplaats = wp2.identificatie
      LEFT JOIN gemeente_woonplaatsactueelbestaand  g2 ON g2.woonplaatscode = wp2.identificatie
      LEFT JOIN gemeente_provincie                  p2 ON g2.gemeentecode = p2.gemeentecode
    UNION ALL
    SELECT o.openbareruimtenaam,
           n.huisnummer,
           n.huisletter,
           n.huisnummertoevoeging,
           n.postcode,
           (CASE WHEN wp2.woonplaatsnaam IS NULL THEN w.woonplaatsnaam ELSE wp2.woonplaatsnaam END),
           (CASE WHEN p2.gemeentenaam IS NULL THEN  p.gemeentenaam ELSE  p2.gemeentenaam END),
           (CASE WHEN p2.provincienaam IS NULL THEN  p.provincienaam ELSE  p2.provincienaam END),
           'STA'                                typeadresseerbaarobject,
           s.identificatie                      adresseerbaarobject,
           n.identificatie                      nummeraanduiding,
           false                                nevenadres,
           ST_Force_3D(ST_Centroid(s.geovlak))  geopunt,
           to_tsvector(openbareruimtenaam||' '||huisnummer||' '||trim(coalesce(huisletter,'')||' '||coalesce(huisnummertoevoeging,''))||' '||
                       (CASE WHEN wp2.woonplaatsnaam IS NULL THEN w.woonplaatsnaam ELSE wp2.woonplaatsnaam END)) textsearchable_adres
      FROM standplaatsactueelbestaand s
      JOIN nummeraanduidingpostcode                  n ON n.identificatie = s.hoofdadres
      JOIN openbareruimteactueelbestaand             o ON n.gerelateerdeopenbareruimte = o.identificatie
      JOIN woonplaatsactueelbestaand                 w ON o.gerelateerdewoonplaats = w.identificatie
      JOIN gemeente_woonplaatsactueelbestaand        g ON g.woonplaatscode = w.identificatie
      JOIN gemeente_provincie                        p ON g.gemeentecode = p.gemeentecode
      LEFT JOIN woonplaatsactueelbestaand          wp2 ON n.gerelateerdewoonplaats = wp2.identificatie
      LEFT JOIN gemeente_woonplaatsactueelbestaand  g2 ON g2.woonplaatscode = wp2.identificatie
      LEFT JOIN gemeente_provincie                  p2 ON g2.gemeentecode = p2.gemeentecode
    UNION ALL
    SELECT o.openbareruimtenaam,
           n.huisnummer,
           n.huisletter,
           n.huisnummertoevoeging,
           n.postcode,
           coalesce(wp2.woonplaatsnaam,w.woonplaatsnaam),
           coalesce(p2.gemeentenaam,p.gemeentenaam),
           coalesce(p2.provincienaam,p.provincienaam),
           'VBO'                                typeadresseerbaarobject,
           an.identificatie                     adresseerbaarobject,
           n.identificatie                      nummeraanduiding,
           true,
           v.geopunt,
           to_tsvector(openbareruimtenaam||' '||huisnummer||' '||trim(coalesce(huisletter,'')||' '||coalesce(huisnummertoevoeging,''))||' '||
                       coalesce(wp2.woonplaatsnaam,w.woonplaatsnaam)) textsearchable_adres
      FROM adresseerbaarobjectnevenadresactueel an
      JOIN nummeraanduidingpostcode                  n ON an.nevenadres = n.identificatie
      JOIN verblijfsobjectactueelbestaand            v ON an.identificatie = v.identificatie
      JOIN openbareruimteactueelbestaand             o ON n.gerelateerdeopenbareruimte = o.identificatie
      JOIN woonplaatsactueelbestaand                 w ON o.gerelateerdewoonplaats = w.identificatie
      JOIN gemeente_woonplaatsactueelbestaand        g ON g.woonplaatscode = w.identificatie
      JOIN gemeente_provincie                        p ON g.gemeentecode = p.gemeentecode
      LEFT JOIN woonplaatsactueelbestaand          wp2 ON n.gerelateerdewoonplaats = wp2.identificatie
      LEFT JOIN gemeente_woonplaatsactueelbestaand  g2 ON g2.woonplaatscode = wp2.identificatie
      LEFT JOIN gemeente_provincie                  p2 ON g2.gemeentecode = p2.gemeentecode
    UNION ALL
    SELECT o.openbareruimtenaam,
           n.huisnummer,
           n.huisletter,
           n.huisnummertoevoeging,
           n.postcode,
           coalesce(wp2.woonplaatsnaam,w.woonplaatsnaam),
           coalesce(p2.gemeentenaam,p.gemeentenaam),
           coalesce(p2.provincienaam,p.provincienaam),
           'LIG'                                typeadresseerbaarobject,
           an.identificatie                     adresseerbaarobject,
           n.identificatie                      nummeraanduiding,
           true,
           ST_Force_3D(ST_Centroid(l.geovlak))  geopunt,
           to_tsvector(openbareruimtenaam||' '||huisnummer||' '||trim(coalesce(huisletter,'')||' '||coalesce(huisnummertoevoeging,''))||' '||
                       coalesce(wp2.woonplaatsnaam,w.woonplaatsnaam)) textsearchable_adres
      FROM adresseerbaarobjectnevenadresactueel an
      JOIN nummeraanduidingpostcode                  n ON an.nevenadres = n.identificatie AND n.typeadresseerbaarobject = 'Ligplaats'
      JOIN ligplaatsactueelbestaand                  l ON an.identificatie = l.identificatie
      JOIN openbareruimteactueelbestaand             o ON n.gerelateerdeopenbareruimte = o.identificatie
      JOIN woonplaatsactueelbestaand                 w ON o.gerelateerdewoonplaats = w.identificatie
      JOIN gemeente_woonplaatsactueelbestaand        g ON g.woonplaatscode = w.identificatie
      JOIN gemeente_provincie                        p ON g.gemeentecode = p.gemeentecode
      LEFT JOIN woonplaatsactueelbestaand          wp2 ON n.gerelateerdewoonplaats = wp2.identificatie
      LEFT JOIN gemeente_woonplaatsactueelbestaand  g2 ON g2.woonplaatscode = wp2.identificatie
      LEFT JOIN gemeente_provincie                  p2 ON g2.gemeentecode = p2.gemeentecode
    UNION ALL
    SELECT o.openbareruimtenaam,
           n.huisnummer,
           n.huisletter,
           n.huisnummertoevoeging,
           n.postcode,
           coalesce(wp2.woonplaatsnaam,w.woonplaatsnaam),
           coalesce(p2.gemeentenaam,p.gemeentenaam),
           coalesce(p2.provincienaam,p.provincienaam),
           'STA'                                typeadresseerbaarobject,
           an.identificatie                     adresseerbaarobject,
           n.identificatie                      nummeraanduiding,
           true,
           ST_Force_3D(ST_Centroid(s.geovlak))  geopunt,
           to_tsvector(openbareruimtenaam||' '||huisnummer||' '||trim(coalesce(huisletter,'')||' '||coalesce(huisnummertoevoeging,''))||' '||
                       coalesce(wp2.woonplaatsnaam,w.woonplaatsnaam)) textsearchable_adres
      FROM adresseerbaarobjectnevenadresactueel an
      JOIN nummeraanduidingpostcode                  n ON an.nevenadres = n.identificatie AND n.typeadresseerbaarobject = 'Standplaats'
      JOIN standplaatsactueelbestaand                s ON an.identificatie = s.identificatie
      JOIN openbareruimteactueelbestaand             o ON n.gerelateerdeopenbareruimte = o.identificatie
      JOIN woonplaatsactueelbestaand                 w ON o.gerelateerdewoonplaats = w.identificatie
      JOIN gemeente_woonplaatsactueelbestaand        g ON g.woonplaatscode = w.identificatie
      JOIN gemeente_provincie                        p ON g.gemeentecode = p.gemeentecode
      LEFT JOIN woonplaatsactueelbestaand          wp2 ON n.gerelateerdewoonplaats = wp2.identificatie
      LEFT JOIN gemeente_woonplaatsactueelbestaand  g2 ON g2.woonplaatscode = wp2.identificatie
      LEFT JOIN gemeente_provincie                  p2 ON g2.gemeentecode = p2.gemeentecode
     ORDER BY 1,2,3,4,5,6,7
    ) a
 CROSS JOIN _g
WITH NO DATA;

CREATE UNIQUE INDEX adres_pkey ON adres(gid, refresh_no);
CREATE INDEX adres_geom_idx ON adres USING gist (geopunt);
CREATE INDEX adres_adreseerbaarobject ON adres USING btree (adresseerbaarobject);
CREATE INDEX adres_nummeraanduiding ON adres USING btree (nummeraanduiding);
CREATE INDEX adresvol_idx ON adres USING gin (textsearchable_adres);
-- }}}
-- {{{ geo_adres
CREATE MATERIALIZED VIEW geo_adres AS
WITH _r(no)     AS (SELECT refresh_no FROM nlx_update.mview WHERE mview_name='geo_adres'),
     _g(gid,no) AS (SELECT setval('geo_adres_gid',1,false), no FROM _r)
SELECT _g.no                    refresh_no, -- no of refresh
       nextval('geo_adres_gid') gid,        -- gid
       ga.*
  FROM (
    SELECT o.openbareruimtenaam::varchar(80)    straatnaam,
           n.huisnummer::numeric(5,0)           huisnummer,
           n.huisletter::varchar(1)             huisletter,
           n.huisnummertoevoeging::varchar(4)   toevoeging,
           n.postcode::varchar(6)               postcode,
           w.woonplaatsnaam::varchar(80)        woonplaats,
           p.gemeentenaam::varchar(80)          gemeente,
           p.provincienaam::varchar(16)         provincie,
           v.geopunt::geometry                  geopunt
      FROM verblijfsobjectactueelbestaand     v
      JOIN nummeraanduidingactueelbestaand    n ON n.identificatie=v.hoofdadres
      JOIN openbareruimteactueelbestaand      o ON o.identificatie=n.gerelateerdeopenbareruimte
      JOIN woonplaatsactueel                  w ON w.identificatie=o.gerelateerdewoonplaats
      JOIN gemeente_woonplaatsactueelbestaand g ON g.woonplaatscode=w.identificatie
      JOIN gemeente_provincie                 p ON p.gemeentecode=g.gemeentecode
    UNION ALL
    SELECT o.openbareruimtenaam,
           n.huisnummer,
           n.huisletter,
           n.huisnummertoevoeging,
           n.postcode,
           w.woonplaatsnaam,
           p.gemeentenaam,
           p.provincienaam,
           -- Vlak geometrie wordt punt
           ST_Force_3D(ST_Centroid(l.geovlak))  as geopunt
      FROM ligplaatsactueelbestaand           l
      JOIN nummeraanduidingactueelbestaand    n ON n.identificatie=l.hoofdadres
      JOIN openbareruimteactueelbestaand      o ON o.identificatie=n.gerelateerdeopenbareruimte
      JOIN woonplaatsactueel                  w ON w.identificatie=o.gerelateerdewoonplaats
      JOIN gemeente_woonplaatsactueelbestaand g ON g.woonplaatscode=w.identificatie
      JOIN gemeente_provincie                 p ON p.gemeentecode=g.gemeentecode
    UNION ALL
    SELECT o.openbareruimtenaam,
           n.huisnummer,
           n.huisletter,
           n.huisnummertoevoeging,
           n.postcode,
           w.woonplaatsnaam,
           p.gemeentenaam,
           p.provincienaam,
           -- Vlak geometrie wordt punt
           ST_Force_3D(ST_Centroid(l.geovlak)) as geopunt
      FROM standplaatsactueelbestaand         l
      JOIN nummeraanduidingactueelbestaand    n ON n.identificatie=l.hoofdadres
      JOIN openbareruimteactueelbestaand      o ON o.identificatie=n.gerelateerdeopenbareruimte
      JOIN woonplaatsactueel                  w ON w.identificatie=o.gerelateerdewoonplaats
      JOIN gemeente_woonplaatsactueelbestaand g ON g.woonplaatscode=w.identificatie
      JOIN gemeente_provincie                 p ON p.gemeentecode=g.gemeentecode
    UNION ALL
    SELECT o.openbareruimtenaam,
           n.huisnummer,
           n.huisletter,
           n.huisnummertoevoeging,
           n.postcode,
           w.woonplaatsnaam,
           p.gemeentenaam,
           p.provincienaam,
           v.geopunt
      FROM adresseerbaarobjectnevenadresactueel aon
      JOIN verblijfsobjectactueelbestaand       v   ON v.identificatie=aon.identificatie
      JOIN nummeraanduidingactueelbestaand      n   ON n.identificatie=aon.nevenadres
      JOIN openbareruimteactueelbestaand        o   ON o.identificatie=n.gerelateerdeopenbareruimte
      JOIN woonplaatsactueel                    w   ON w.identificatie=o.gerelateerdewoonplaats
      JOIN gemeente_woonplaatsactueelbestaand   g   ON g.woonplaatscode=w.identificatie
      JOIN gemeente_provincie                   p   ON p.gemeentecode=g.gemeentecode
    UNION ALL
    SELECT o.openbareruimtenaam,
           n.huisnummer,
           n.huisletter,
           n.huisnummertoevoeging,
           n.postcode,
           w.woonplaatsnaam,
           p.gemeentenaam,
           p.provincienaam,
           -- Vlak geometrie wordt punt
           ST_Force_3D(ST_Centroid(l.geovlak))  as geopunt
      FROM adresseerbaarobjectnevenadresactueel aon
      JOIN ligplaatsactueelbestaand             l   ON l.identificatie=aon.identificatie
      JOIN nummeraanduidingactueelbestaand      n   ON n.identificatie=aon.nevenadres
      JOIN openbareruimteactueelbestaand        o   ON o.identificatie=n.gerelateerdeopenbareruimte
      JOIN woonplaatsactueel                    w   ON w.identificatie=o.gerelateerdewoonplaats
      JOIN gemeente_woonplaatsactueelbestaand   g   ON g.woonplaatscode=w.identificatie
      JOIN gemeente_provincie                   p   ON p.gemeentecode=g.gemeentecode
    UNION ALL
    SELECT o.openbareruimtenaam,
           n.huisnummer,
           n.huisletter,
           n.huisnummertoevoeging,
           n.postcode,
           w.woonplaatsnaam,
           p.gemeentenaam,
           p.provincienaam,
           -- Vlak geometrie wordt punt
           ST_Force_3D(ST_Centroid(s.geovlak))  as geopunt
      FROM adresseerbaarobjectnevenadresactueel aon
      JOIN standplaatsactueelbestaand           s   ON s.identificatie=aon.identificatie
      JOIN nummeraanduidingactueelbestaand      n   ON n.identificatie=aon.nevenadres
      JOIN openbareruimteactueelbestaand        o   ON o.identificatie=n.gerelateerdeopenbareruimte
      JOIN woonplaatsactueel                    w   ON w.identificatie=o.gerelateerdewoonplaats
      JOIN gemeente_woonplaatsactueelbestaand   g   ON g.woonplaatscode=w.identificatie
      JOIN gemeente_provincie                   p   ON p.gemeentecode=g.gemeentecode
     ORDER BY 1,2,3,4,5,6,7,8
    ) ga
 CROSS JOIN _g
WITH NO DATA;

CREATE UNIQUE INDEX geo_adres_pkey ON geo_adres(gid, refresh_no);
CREATE INDEX geo_adres_geom ON geo_adres USING gist (geopunt);
CREATE INDEX geo_adres_postcode_huisnummer ON geo_adres (postcode, huisnummer);
-- }}}
-- {{{ geo_postcode6
CREATE MATERIALIZED VIEW geo_postcode6 AS
WITH _r(no)     AS (SELECT refresh_no FROM nlx_update.mview WHERE mview_name='geo_postcode6'),
     _g(gid,no) AS (SELECT setval('geo_postcode6_gid',1,false), no FROM _r)
SELECT _g.no                        refresh_no, -- no of refresh
       nextval('geo_postcode6_gid') gid,        -- gid
       s.*
  FROM (
    SELECT DISTINCT ON (provincie, gemeente, woonplaats, straatnaam, postcode)
           provincie,
           gemeente,
           woonplaats,
           straatnaam,
           postcode,
           ST_Force_2D(geopunt) geopunt
      FROM geo_adres
     ORDER BY provincie, gemeente, woonplaats, straatnaam, postcode
    ) s
 CROSS JOIN _g
WITH NO DATA;

CREATE UNIQUE INDEX geo_postcode6_pkey ON geo_postcode6(gid, refresh_no);
CREATE INDEX geo_postcode6_postcode ON geo_postcode6(postcode);
CREATE INDEX geo_postcode6_woonplaats ON geo_postcode6(woonplaats);
CREATE INDEX geo_postcode6_gemeente ON geo_postcode6(gemeente);
CREATE INDEX geo_postcode6_straatnaam ON geo_postcode6(straatnaam);
CREATE INDEX geo_postcode6_sdx on geo_postcode6 USING GIST (geopunt);
-- }}}
-- {{{ geo_postcode4
CREATE MATERIALIZED VIEW geo_postcode4 AS
WITH _r(no)     AS (SELECT refresh_no FROM nlx_update.mview WHERE mview_name='geo_postcode4'),
     _g(gid,no) AS (SELECT setval('geo_postcode4_gid',1,false), no FROM _r)
SELECT _g.no                        refresh_no, -- no of refresh
       nextval('geo_postcode4_gid') gid,        -- gid
       s.*
  FROM (
    SELECT DISTINCT ON (provincie, gemeente, woonplaats)
           provincie,
           gemeente,
           woonplaats,
           substring(postcode FOR 4) AS postcode,
           geopunt
      FROM geo_postcode6
     ORDER BY provincie, gemeente, woonplaats
    ) s
 CROSS JOIN _g
WITH NO DATA;

CREATE UNIQUE INDEX geo_postcode4_pkey ON geo_postcode4(gid, refresh_no);
CREATE INDEX geo_postcode4_postcode ON geo_postcode4(postcode);
CREATE INDEX geo_postcode4_woonplaats ON geo_postcode4(woonplaats);
CREATE INDEX geo_postcode4_gemeente ON geo_postcode4(gemeente);
CREATE INDEX geo_postcode4_sdx ON geo_postcode4 USING gist (geopunt);
-- }}}
-- {{{ geo_straatnaam
CREATE MATERIALIZED VIEW geo_straatnaam AS
WITH _r(no)     AS (SELECT refresh_no FROM nlx_update.mview WHERE mview_name='geo_straatnaam'),
     _g(gid,no) AS (SELECT setval('geo_straatnaam_gid',1,false), no FROM _r)
SELECT _g.no                            refresh_no, -- no of refresh
       nextval('geo_straatnaam_gid')    gid,        -- gid
       s.*
  FROM (
    SELECT DISTINCT ON (provincie, gemeente, woonplaats, straatnaam)
           provincie,
           gemeente,
           woonplaats,
           straatnaam,
           geopunt
      FROM geo_postcode6
     ORDER BY provincie, gemeente, woonplaats, straatnaam
    ) s
 CROSS JOIN _g
WITH NO DATA;

CREATE UNIQUE INDEX geo_straatnaam_pkey ON geo_straatnaam(gid, refresh_no);
CREATE INDEX geo_straatnaam_straatnaam ON geo_straatnaam(straatnaam);
CREATE INDEX geo_straatnaam_gemeente ON geo_straatnaam(gemeente);
CREATE INDEX geo_straatnaam_woonplaats ON geo_straatnaam(woonplaats);
CREATE INDEX geo_straatnaam_sdx ON geo_straatnaam USING GIST (geopunt);
-- }}}
-- {{{ geo_woonplaats
CREATE MATERIALIZED VIEW geo_woonplaats AS
WITH _r(no)     AS (SELECT refresh_no FROM nlx_update.mview WHERE mview_name='geo_woonplaats'),
     _g(gid,no) AS (SELECT setval('geo_woonplaats_gid',1,false), no FROM _r)
SELECT _g.no                            refresh_no, -- no of refresh
       nextval('geo_woonplaats_gid')    gid,        -- gid
       s.*
  FROM (
    SELECT p.provincienaam                      provincie,
           p.gemeentenaam                       gemeente,
           w.woonplaatsnaam                     woonplaats,
           ST_Force_2D(ST_Centroid(w.geovlak))  geopunt
      FROM woonplaatsactueel w
      JOIN gemeente_woonplaatsactueelbestaand g ON g.woonplaatscode=w.identificatie
      JOIN gemeente_provincie                 p ON p.gemeentecode=g.gemeentecode
     ORDER BY 1, 2, 3
    ) s
 CROSS JOIN _g
WITH NO DATA;

CREATE UNIQUE INDEX geo_woonplaats_pkey ON geo_woonplaats(gid, refresh_no);
CREATE INDEX geo_woonplaats_sdx ON geo_woonplaats USING gist (geopunt);
CREATE INDEX geo_woonplaats_woonplaats ON geo_woonplaats(woonplaats);
CREATE INDEX geo_woonplaats_woonplaats_gem ON geo_woonplaats(gemeente, woonplaats);
-- }}}
-- {{{ geo_gemeente
CREATE MATERIALIZED VIEW geo_gemeente AS
WITH _r(no)     AS (SELECT refresh_no FROM nlx_update.mview WHERE mview_name='geo_gemeente'),
     _g(gid,no) AS (SELECT setval('geo_gemeente_gid',1,false), no FROM _r)
SELECT _g.no                            refresh_no, -- no of refresh
       nextval('geo_gemeente_gid')    gid,        -- gid
       s.*
  FROM (
    SELECT p.provincienaam                      provincie,
           g.gemeentenaam                       gemeente,
           ST_Force_2D(ST_Centroid(g.geovlak))  geopunt
      FROM gemeente g
      JOIN gemeente_provincie p ON p.gemeentecode=g.gemeentecode
     ORDER BY 1,2
    ) s
 CROSS JOIN _g
WITH NO DATA;

CREATE UNIQUE INDEX geo_gemeente_pkey ON geo_gemeente(gid, refresh_no);
CREATE INDEX geo_gemeente_geopunt ON geo_gemeente USING gist (geopunt);
CREATE INDEX geo_gemeente_gemeente ON geo_gemeente(gemeente);
-- }}}
-- {{{ geo_provincie
CREATE MATERIALIZED VIEW geo_provincie AS
WITH _r(no)     AS (SELECT refresh_no FROM nlx_update.mview WHERE mview_name='geo_provincie'),
     _g(gid,no) AS (SELECT setval('geo_provincie_gid',1,false), no FROM _r)
SELECT _g.no                        refresh_no, -- no of refresh
       nextval('geo_provincie_gid') gid,        -- gid
       s.*
  FROM (
    SELECT p.provincienaam                      provincie,
           ST_Force_2D(ST_Centroid(p.geovlak))  geopunt
      FROM provincie p
     ORDER BY 1,2
    ) s
 CROSS JOIN _g
WITH NO DATA;

CREATE UNIQUE INDEX geo_provincie_pkey ON geo_provincie(gid, refresh_no);
CREATE INDEX geo_provincie_geopunt ON geo_provincie USING gist (geopunt);
-- }}}

INSERT INTO nlx_update.mview VALUES
  ('gemeente', 1, 0, 'A', now()),
  ('provincie', 2, 0, 'A', now()),
  ('adres', 3, 0, 'A', now()),
  ('geo_adres', 4, 0, 'A', now()),
  ('geo_postcode6', 5, 0, 'A', now()),
  ('geo_postcode4', 6, 0, 'A', now()),
  ('geo_straatnaam', 7, 0, 'A', now()),
  ('geo_woonplaats', 8, 0, 'A', now()),
  ('geo_gemeente', 9, 0, 'A', now()),
  ('geo_provincie', 10, 0, 'A', now())
;
