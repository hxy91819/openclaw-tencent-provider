# Tencent Cloud OpenClaw provider test package

Rehearsal OpenClaw provider plugin for Tencent Cloud. This package uses plugin
runtime id `tencent-test` so ClawHub testing does not claim the official
`tencent` runtime id.

## Install

```sh
openclaw plugins install clawhub:openclaw-tencent-test-provider
```

## Release

Release settings live in `.env`; use `.env.example` for the expected variable
names. The release script is dry-run by default:

```sh
scripts/publish.sh --target clawhub
scripts/publish.sh --target clawhub --publish
scripts/publish.sh --target npm --publish
```

Run dependency installation in Docker or CI before publishing. The script does
not run `npm ci` automatically because the build dependencies include OpenClaw.

## Docs

See `docs/providers/tencent.md` in the OpenClaw repository, or the published docs at `https://docs.openclaw.ai/providers/tencent`.
