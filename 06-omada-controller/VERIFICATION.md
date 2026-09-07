# Omada Software Controller 6.3.0.45 on Ubuntu 24.04

Everything below was run on a real VM (GCE e2-standard-2, 2 vCPU / 8 GB,
Ubuntu 24.04.4 LTS, kernel 7.0.0-1011-gcp) on 2026-09-07. Commands and their
output, including the things that did not work.

## MongoDB 8 does not start on a current kernel

The usual instruction is "add the MongoDB 8.0 repo". On this box that fails:

    $ sudo systemctl status mongod
    × mongod.service - MongoDB Database Server
         Active: failed (Result: exit-code)

    mongod[360939]: {"s":"F","c":"CONTROL","id":12257600,"ctx":"main",
      "msg":"MongoDB cannot start: Linux kernel versions 6.19 and newer has a
       known incompatibility with this version of MongoDB."}

This is a deliberate guard, not a crash: MongoDB SERVER-121912, TCMalloc
violating the upstream rseq ABI. No config or env var works around it.

MongoDB 7.0.40 on the same kernel:

    is-active: active
    db version v7.0.40
    ping: 1

Omada 6.3 declares `mongodb-org-server (>= 3.0.0)` and `(<< 8.1.0)`, so 7.0 is
inside the supported range. Pinned to 7.0.

## Omada runs its own mongod, not the system service

`properties/omada.properties`:

    eap.mongod.port=27217
    eap.mongod.db=../data/db
    eap.mongod.host=127.0.0.1

    $ ps -eo pid,ppid,comm,args | grep [m]ongod
    363519 363518 mongod /opt/tplink/EAPController/bin/mongod --port 27217 ...

    $ readlink -f /opt/tplink/EAPController/bin/mongod
    /usr/bin/mongod

Two consequences. A backup aimed at 27017 dumps an empty database and exits 0.
And because the bundled path is a symlink to the system binary, the system
package version still decides what Omada runs, so the kernel problem above
applies to Omada's own instance.

The system `mongod.service` on 27017 is redundant. Disabling it freed 154 MB
and Omada kept running (verified: 8043 -> 200, ping 1).

## A claim I had to withdraw

Before testing I believed the .deb would need `dpkg --ignore-depends=jsvc` on
24.04, because TP-Link documents that workaround for JSVC >= 1.1.0. Ubuntu
24.04 ships jsvc 1.0.15, so it does not apply. Plain install, exit 0:

    JRE 17.0.20 is greater than 8 and JSVC  is less than 1.1.0
    Install Omada Network Application succeeded!
    dpkg exit: 0

Written down because it was wrong, and only measurement showed it.

## Ports Omada actually opens

    TCP  8043 8044 8088 8843 9098 29811-29817
    UDP  19810 27001 29810

Only 8043 is an admin interface. The rest are device management and captive
portal. Left on 0.0.0.0 they are twelve unnecessary internet-facing services,
so device ports are scoped to the site prefix and the admin UI goes behind a
reverse proxy with a real certificate.

## ufw filters container-to-host traffic

Published container ports bypass ufw, which is well known. The reverse is not:
after enabling default-deny, the proxy returned 502.

    [UFW BLOCK] IN=br-718950ae6f3a SRC=172.18.0.4 DST=172.17.0.1 DPT=8043 SYN

Omada answered 200 on localhost the whole time. Fixed with an explicit rule
from the compose network to the host gateway.

## Backup and restore

Restore into a scratch database, then compared against live:

    collections: 70
    IDENTICAL - every collection and every document count matches

    live  _id  : AP7650 v1.0
    restored   : found, 8 fields
    byte-equal : true
    total docs   live=1439 restored=1439

Scratch database dropped, live untouched (70 collections after).

## Reboot test

Reboot at 15:23:23Z, boot at 15:26:57Z.

    omada controller       RUNNING
    omada mongod :27217    LISTENING
    system mongod          inactive / disabled
    ufw                    active
    fail2ban               active
    omada-backup.timer     active

From outside the network:

    15:28:03Z  omada=502  n8n=200
    15:28:49Z  omada=502  n8n=200
    15:29:06Z  omada=200  n8n=200

Roughly two minutes from boot to serving, all of it Java startup. Document
count after reboot: 1439, unchanged. Worth telling a client so a restart during
a maintenance window is not mistaken for a failure.

## A mistake made along the way

Patching `extra_hosts` into the Caddy service inserted it in the middle of the
`volumes:` list, absorbing `caddy_data:/data`. `docker compose config` reported
the file valid, because the YAML was valid and only the meaning was wrong. The
running container was untouched, so nothing went down; restored from the
timestamped backup and reapplied at the correct position.
