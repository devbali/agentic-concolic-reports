<?php
include('./config.php');
// P3: a branch on a SANITIZED value (trim's result), then the value reaches a numeric context.
if (isset($_GET['q'])) {
    $q = trim($_GET['q']);
    if ($q === 'admin') {
        echo "no admin lookups\n";
    } else {
        $ret = mysqli_query($con, "select * from user where id=0" . $q);
        echo "looked up\n";
    }
}
