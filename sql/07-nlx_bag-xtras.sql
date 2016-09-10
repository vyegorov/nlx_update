/*
 *  NLX grants
 *
 *  Should be executed as BAG schema owner
 */
GRANT USAGE ON SCHEMA nlx_bag TO public;
GRANT SELECT ON ALL TABLES IN SCHEMA nlx_bag TO public;
GRANT DELETE ON ligplaats TO nlx_update;
GRANT DELETE ON standplaats TO nlx_update;
GRANT DELETE ON verblijfsobject TO nlx_update;
GRANT DELETE ON pand TO nlx_update;
GRANT DELETE ON nummeraanduiding TO nlx_update;
GRANT DELETE ON openbareruimte TO nlx_update;
GRANT DELETE ON woonplaats TO nlx_update;

ALTER TABLE verblijfsobject ALTER identificatie SET STATISTICS 1000;
ALTER TABLE verblijfsobject ALTER aanduidingrecordinactief SET STATISTICS 1000;
ALTER TABLE verblijfsobject ALTER aanduidingrecordcorrectie SET STATISTICS 1000;
ALTER TABLE verblijfsobject ALTER begindatumtijdvakgeldigheid SET STATISTICS 1000;
ALTER TABLE verblijfsobjectpand ALTER identificatie SET STATISTICS 1000;
ALTER TABLE verblijfsobjectgebruiksdoel ALTER identificatie SET STATISTICS 1000;
ALTER TABLE pand ALTER identificatie SET STATISTICS 1000;
