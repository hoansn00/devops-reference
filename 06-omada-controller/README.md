# Omada Software Controller on Ubuntu 24.04

TP-Link's Omada SDN controller on a hardened Ubuntu VPS: reverse proxy with a
real certificate, ufw scoped to the ports that are actually needed, fail2ban,
unattended-upgrades that were checked rather than assumed, and a backup with a
restore that was performed.

`VERIFICATION.md` has the commands and their output, including a claim I made
before testing and had to withdraw.

## What is here

    scripts/omada-backup.sh    mongodump against Omada's own mongod on 27217
    scripts/restore-test.sh    restore into a scratch db, diff against live
    VERIFICATION.md            measurements, negative results included

## Notes worth keeping

MongoDB 8.0.x will not start on Linux kernel 6.19 or newer (SERVER-121912). Pin
7.0 unless the kernel is older.

Omada does not use the system MongoDB service. It starts its own mongod on port
27217 against `/opt/tplink/EAPController/data/db`. A backup pointed at 27017
succeeds and contains nothing.

Omada opens twelve ports. One of them is the admin interface.
