<html>
<head>
<meta charset="utf-8">
<title>BAG Updates</title>
<style type='text/css'>

.info {
    font-family: monospace;
    padding: 1em;
    margin: auto;
    display: inline-block;
    display: -moz-inline-block;
    *display: inline;
    border-radius: 15px;
    -moz-border-radius: 15px;
}

#para { text-align: center; }
.title { font: 30px monospace; color: #669999; }
.error { background-color: #ffcccc; color: #660000; border: solid 1px #660000; }
.confirm { background-color: #ccffcc; color: #006600; border: solid 1px #006600; }
.highligh { background-color: #ffcc99; color: #663300; border: solid 1px #663300; }

.urls { font-family: monospace; border-spacing: 2px; }
.urls tr:hover td { background-color: #99cccc; }
tr.highlight { background-color: #ffcc99; }
tr.stopped { color: #cccccc; }
td { padding: 2px; }
th { background-color: #99cccc; text-align: center; font-weight: bold; padding: 5px }
form { padding: 1em; }

</style>
</head>
<body>
<div id="para"><h1 class="info title"><a href="">BAG Updates</a></h1></div><?php

function pg_err_msg()
{
    $err="";
    foreach (explode("\n", pg_last_error()) as $l) {
        $err=$err.str_repeat("&nbsp;", strspn($l, " ")).substr($l, strspn($l, " "))."<br/>";
    }
    return $err;
}

error_reporting(E_ALL); // or E_STRICT
ini_set("display_errors",1);
ini_set("memory_limit","1024M");

date_default_timezone_set("GMT");

$MAX_SIZE=64*1024;
$DIR_LOGS="/var/www/public/logs/";
$FAILURE=0;
$HIGHLIGHT="-1";
$db_stmt = array(
    "bag.ins" => "INSERT INTO file(file_type,update_url) VALUES ('BAG',$1)",
    "all.sel" => "SELECT update_url, file_type, file_status,
                         to_char(modify_dt, 'DD-Mon/YYYY HH24:MI') modify_dt,
                         downloaded_name, log_file_name
                    FROM file WHERE file_status != 'Archived' ORDER BY nlx_update.modify_dt DESC LIMIT 100",
    "url.sel" => "SELECT update_url FROM file WHERE update_url=$1 AND file_status != 'Archived'",
    "old.upd" => "UPDATE file SET file_status = 'Archived' WHERE now() - modify_dt > '3 years'::interval AND file_status != 'Archived'"
);
$MSG_TYPE="error";

if (($db_conn = pg_connect("dbname=kadaster user=nlx_update password=nlx_update")) === FALSE) {
    $MSG_TEXT="Cannot connect to the database.";
    $FAILURE=1;
} else {
    pg_query("SET timezone TO 'GMT'");
    foreach ($db_stmt as $n => $q) {
        $res = pg_prepare($db_conn, $n, $q);
        $FAILURE += intval($res === FALSE);
        $PANIC=$FAILURE;

        if ($FAILURE) {
            $MSG_TEXT="<table><tr><td>Cannot prepare query <i>&#171;$q&#187;</i> due to:</td></tr>".
                "<tr><td><span style='text-align: left'>".pg_err_msg()."</span></td></tr></table>";
            break;
        }
    }
}

$bag_url="";
if (!$FAILURE && isset($_POST['bag_url'])) {
    $bag_url = $_POST['bag_url'];

    if (!$FAILURE && filter_var($bag_url, FILTER_VALIDATE_URL) === FALSE) {
        $MSG_TEXT="Specified URL <i>&#171;$bag_url&#187;</i> is not valid";
        $FAILURE=1;
    }

    if (!$FAILURE) {
        if (($res = pg_execute($db_conn, "url.sel", array($bag_url))) === FALSE) {
            $MSG_TEXT="<table><tr><td>Cannot check URL uniqueness:</td></tr>".
                "<tr><td><span style='text-align: left'>".pg_err_msg()."</span></td></tr></table>";
            $FAILURE=1;
        }
        else if (pg_num_rows($res) > 0) {
            $HIGHLIGHT=pg_fetch_result($res, 0, 0);
            $MSG_TEXT="Provided URL already registered (highlighted)";
            $FAILURE=1;
        }
    }

    if (!$FAILURE) {
        $res=pg_execute($db_conn, "bag.ins", array($bag_url));
        if ($res === FALSE) {
            $MSG_TEXT="<table><tr><td>Cannot register URL due to:</td></tr>".
                "<tr><td><span style='text-align: left'>".pg_err_msg()."</span></td></tr></table>";
            $FAILURE=1;
        }
    }

    if (!$FAILURE) {
        $MSG_TEXT="URL registered, please, wait for the notification soon";
        $MSG_TYPE="confirm";
        $bag_url="";

        pg_execute($db_conn, "old.upd", array());
    }
}

$i=0;
if (!$PANIC) {
    $urls="";
    $uri=implode("/", (explode('/', $_SERVER["REQUEST_URI"], -1)));
    if (($res = pg_execute($db_conn, "all.sel", array())) !== FALSE) {
        $n=pg_num_fields($res);
        for ($i=0; $i<pg_num_rows($res); $i++) {
            $row=pg_fetch_row($res);

            if (in_array($HIGHLIGHT, $row) || strcmp($row[1], "Error") == 0)
                $urls .= "<tr class='highlight'>";
            else
                $urls .= "<tr>";

            $urls .= "<td>".$row[1]."</td><td><span title='".$row[0]."'>...".substr($row[0], -39)."</span></td>";
            $urls .= "<td>".$row[4]."</td><td>".$row[3]."</td><td>".$row[2]."</td>";
            $urls .= "<td><a href='$uri/logs/".$row[5]."' title='".$row[5]."'>".substr($row[5], 0, 20).(strlen($row[5])>=20?"...":"")."</a></td></tr>";
        }
    } else {
        $MSG_TEXT="<table><tr><td>Cannot generate list of BAG Update URLs:</td></tr>".
            "<tr><td><span style='text-align: left'>".pg_err_msg()."</span></td></tr></table>";
        $MSG_TYPE="error";
    }
}

if ($i == 0) {
    $urls="<tr><td colspan='5'><div id='para'><p class='info'>No URLs registered</p></div></td></tr>";
}

pg_close($db_conn);

if (!empty($MSG_TEXT)) {
    echo "<div id='para'><p class='info $MSG_TYPE'>$MSG_TEXT</p></div>\n";
}

echo "<div class='info'><table class='urls'>
<tr><th>Type</th><th>Update URL</th><th>Downloaded name</th><th>Modified (GMT)</th><th>Status</th><th>Log</th></tr>
$urls</table></div>";

?>

<br/>
<div class="info" style="border: solid 1px; margin: 1em 0 0 1em;"><form method='post'>
<table><tr><td><label for='bag_url'>BAG Update URL:</label></td><td><input type='text' id='bag_url' name='bag_url' size='50' value='<?
echo $bag_url; ?>'></td><td></td></tr>
<tr><td colspan="2" style="padding: 2em 0 0 2em"><input type='submit' value=' Request BAG Update! ' ></td><td></td></tr></table>
</form></div>
</body>
</html>
