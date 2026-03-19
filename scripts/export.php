<?php

require_once 'scripts/common.php';
ensure_authenticated();

/* Prevent XSS input */
$_GET  = filter_input_array(INPUT_GET, FILTER_SANITIZE_STRING);
$_POST = filter_input_array(INPUT_POST, FILTER_SANITIZE_STRING);

$date_from      = isset($_GET['date_from'])      ? $_GET['date_from']      : '';
$date_to        = isset($_GET['date_to'])        ? $_GET['date_to']        : '';
$min_confidence = isset($_GET['min_confidence']) ? $_GET['min_confidence'] : '';
$species_filter = isset($_GET['species'])        ? $_GET['species']        : '';
$do_export      = isset($_GET['export']);

if ($do_export) {
    $db = new SQLite3('./scripts/birds.db', SQLITE3_OPEN_READONLY);
    $db->busyTimeout(1000);

    $conditions = [];
    $safe_params = [];

    if ($date_from !== '') {
        $conditions[] = "Date >= :date_from";
        $safe_params[':date_from'] = $date_from;
    }
    if ($date_to !== '') {
        $conditions[] = "Date <= :date_to";
        $safe_params[':date_to'] = $date_to;
    }
    if ($min_confidence !== '' && is_numeric($min_confidence)) {
        $conditions[] = "Confidence >= :min_confidence";
        $safe_params[':min_confidence'] = floatval($min_confidence);
    }
    if ($species_filter !== '') {
        $conditions[] = "(Com_Name LIKE :species OR Sci_Name LIKE :species)";
        $safe_params[':species'] = '%' . $species_filter . '%';
    }

    $where = count($conditions) ? 'WHERE ' . implode(' AND ', $conditions) : '';
    $statement = $db->prepare("SELECT Date, Time, Com_Name, Sci_Name, Confidence, Lat, Lon, Cutoff, Week, Sens, Overlap, File_Name, Model_Name FROM detections $where ORDER BY Date DESC, Time DESC");

    foreach ($safe_params as $key => $val) {
        if (is_float($val)) {
            $statement->bindValue($key, $val, SQLITE3_FLOAT);
        } else {
            $statement->bindValue($key, $val, SQLITE3_TEXT);
        }
    }

    $parts = ['detections'];
    if ($date_from !== '') $parts[] = "from-$date_from";
    if ($date_to !== '')   $parts[] = "to-$date_to";
    $filename = implode('_', $parts) . '.csv';

    header('Content-Type: text/csv');
    header("Content-Disposition: attachment; filename=\"$filename\"");
    header('Pragma: no-cache');
    header('Expires: 0');

    $output = fopen('php://output', 'w');
    fputcsv($output, ['Date', 'Time', 'Com_Name', 'Sci_Name', 'Confidence', 'Lat', 'Lon', 'Cutoff', 'Week', 'Sens', 'Overlap', 'File_Name', 'Model_Name']);

    $result = $statement->execute();
    while ($row = $result->fetchArray(SQLITE3_NUM)) {
        fputcsv($output, $row);
    }
    fclose($output);
    $db->close();
    exit;
}

if (get_included_files()[0] === __FILE__) {
    echo '<!DOCTYPE html><html lang="en"><head></head><body>';
}
?>
<div class="centered">
  <h2>Export Detections CSV</h2>
  <form method="GET" action="scripts/export.php" target="_blank">
    <input type="hidden" name="export" value="1">
    <table>
      <tr>
        <td>Date from:</td>
        <td><input type="date" name="date_from" value="<?php echo htmlspecialchars($date_from); ?>"></td>
      </tr>
      <tr>
        <td>Date to:</td>
        <td><input type="date" name="date_to" value="<?php echo htmlspecialchars($date_to); ?>"></td>
      </tr>
      <tr>
        <td>Min confidence (0–1):</td>
        <td><input type="number" name="min_confidence" min="0" max="1" step="0.05"
             placeholder="e.g. 0.7" value="<?php echo htmlspecialchars($min_confidence); ?>"></td>
      </tr>
      <tr>
        <td>Species (name contains):</td>
        <td><input type="text" name="species" placeholder="e.g. Robin"
             value="<?php echo htmlspecialchars($species_filter); ?>"></td>
      </tr>
    </table>
    <br>
    <button type="submit">Download CSV</button>
    <span style="margin-left:1em; font-size:small">Leave fields blank to export all detections.</span>
  </form>
</div>
<?php
if (get_included_files()[0] === __FILE__) {
    echo '</body></html>';
}
