#!/bin/bash

# Используем ту же утилиту, что и install.sh (если передана)
ELEVATE_CMD="${ELEVATE_CMD:-sudo}"

checkmodule -M -m -o ./module/zapret.mod ./module/zapret.te
semodule_package -o ./module/zapret.pp -m ./module/zapret.mod

$ELEVATE_CMD semodule -i ./module/zapret.pp
$ELEVATE_CMD semanage fcontext -a -t bin_t "/opt/zapret/init.d/sysv/zapret"
$ELEVATE_CMD restorecon -v /opt/zapret/init.d/sysv/zapret
