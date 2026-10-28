<?php
include('./config.php');
// NEGATIVE CONTROL: the same sink, reachable only when the parameter equals a
// fixed, harmless value -- no reachable input breaks the statement.
if (isset($_GET['id']) && $_GET['id'] === 'trickE') {
    $id = $_GET['id'];
    $ret = mysqli_query($con, "select * from user where username='$id'");
    echo "looked up\n";
}
