<?php
include('./config.php');
// P3: the parameter is escaped but used in a NUMERIC context -- escaping does not help.
if (isset($_GET['id'])) {
    $id = addslashes($_GET['id']);
    $ret = mysqli_query($con, "select * from user where id=0$id");
    echo "looked up\n";
}
