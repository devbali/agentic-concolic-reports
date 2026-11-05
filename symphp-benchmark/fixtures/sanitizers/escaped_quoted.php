<?php
include('./config.php');
// P3 CONTROL: the parameter is escaped and used INSIDE quotes -- no input breaks the statement.
if (isset($_GET['name'])) {
    $name = mysqli_real_escape_string($con, $_GET['name']);
    $ret = mysqli_query($con, "select * from user where username='$name'");
    echo "looked up\n";
}
