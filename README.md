# Syno-Webmin

Fresh Webmin SPK project for Synology DSM.

This repository is intentionally small. The GitHub Actions workflow downloads
Webmin 2.651 during build and places it into `src/webmin` before
calling `tomgrv/synology-package-builder`.

## Target runtime paths

- Webmin app: `/var/packages/webmin/target/webmin`
- Config: `/var/packages/webmin/target/etc/miniserv.conf`
- Start script: `/var/packages/webmin/target/etc/start`
- Stop script: `/var/packages/webmin/target/etc/stop`

No `systemctl` is used. DSM package start/stop is handled by
`scripts/start-stop-status`.

## Build

The workflow builds for DSM 7.0 / geminilake by default.

You can run it from GitHub:

`Actions -> Build Webmin SPK -> Run workflow`
