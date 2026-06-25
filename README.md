# Tencent Cloud OpenClaw provider test package

Rehearsal OpenClaw provider plugin for Tencent Cloud. This package uses plugin
runtime id `tencent-test` so ClawHub testing does not claim the official
`tencent` runtime id.

## Install

```sh
openclaw plugins install clawhub:openclaw-tencent-test-provider
```

## Validation scope

This package is a ClawHub rehearsal package, not the final official Tencent
provider package. The runtime id was renamed from `tencent` to `tencent-test`
after the first OpenClaw main-repo externalization proof, so read the validation
history with this split:

- The earlier full OpenClaw E2E proof covered the official-shape runtime id
  `tencent`: onboarding, ClawHub install, npm install, plugin inspect, and
  model discovery for `tencent-tokenhub/hy3-preview`.
- After the rehearsal runtime id changed to `tencent-test`, the ClawHub proof
  was rerun as a focused install smoke only: `openclaw plugins install
  clawhub:openclaw-tencent-test-provider`, `plugins inspect tencent-test`, and
  `models list --all`.
- That focused smoke confirmed the test package installs as plugin
  `tencent-test` and still exposes provider/model ids
  `tencent-tokenhub` and `tencent-tokenhub/hy3-preview`.
- It does not replace the final official ClawHub E2E. Before upstreaming or
  launching the official package, rerun the full OpenClaw catalog/onboarding E2E
  against the Tencent-owned or OpenClaw-official package that uses runtime id
  `tencent`.

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
