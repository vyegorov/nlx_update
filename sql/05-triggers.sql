/*
 *  NLX Update triggers
 *
 *  Should be executed as NLX Update owner after `04-functions.sql`.
 */
CREATE TRIGGER t_file_modify BEFORE INSERT OR UPDATE ON file FOR EACH ROW
    EXECUTE PROCEDURE t_file_before();
CREATE TRIGGER t_file_track AFTER INSERT OR UPDATE OR DELETE ON file FOR EACH ROW
    EXECUTE PROCEDURE t_file_track();
