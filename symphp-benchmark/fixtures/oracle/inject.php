<?php
include('./config.php');
// A real injection: the parameter is interpolated into a quoted literal.
if (isset($_GET['id'])) {
    $id = $_GET['id'];
    $ret = mysqli_query($con, "select * from user where username='$id'");
    echo "looked up\n";
}
