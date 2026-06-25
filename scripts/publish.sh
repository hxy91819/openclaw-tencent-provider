#!/usr/bin/env bash
set -euo pipefail

# Definition:
#   Build, validate, dry-run, and optionally publish this OpenClaw Tencent plugin
#   package to ClawHub and/or npm using local .env release settings.
#
# Parameters:
#   --target <clawhub|npm|all> chooses the registry target. Default: all.
#   --publish performs the real publish. Default: dry-run only.
#   --env-file <path> selects the dotenv file. Default: .env when present.
#
# Outputs:
#   Prints a release summary and writes temporary auth config only under a
#   throwaway temp directory. Tokens are never printed.
#
# Decision:
#   This script intentionally does not run npm install. This repo depends on the
#   OpenClaw package for build-time SDK types, so dependency installation belongs
#   in Docker/CI or another explicit release environment.

usage() {
  cat <<'EOF'
Usage:
  scripts/publish.sh [options]

Description:
  Build and validate the Tencent provider package, then dry-run or publish it to
  ClawHub and/or npm. Release settings are read from .env by default.

Options:
  --target <clawhub|npm|all>
      Registry target to run. Default: all.
  --publish
      Perform the real publish. Without this flag the script uses dry-run mode.
  --env-file <path>
      Dotenv file to load. Default: .env if it exists.
  --allow-dirty
      Allow real publish from a dirty git checkout. Dry-runs allow dirty state.
  --skip-build
      Skip npm run build. Use only after a fresh build in the same checkout.
  -h, --help
      Show this help.

Environment (.env):
  CLAWHUB_TOKEN
      Required for real ClawHub publish. Dry-run can use an existing login.
  CLAWHUB_OWNER
      ClawHub owner handle. Default: hxy91819.
  CLAWHUB_NAME
      ClawHub package name. Default: package.json name.
  CLAWHUB_SOURCE_REPO
      Source repo metadata, e.g. hxy91819/openclaw-tencent-provider.
  CLAWHUB_SOURCE_REF
      Source ref metadata. Default: current git branch.
  CLAWHUB_SOURCE_COMMIT
      Source commit metadata. Default: current HEAD.
  CLAWHUB_CHANGELOG
      Changelog text for ClawHub publish.
  CLAWHUB_TAGS / CLAWHUB_CATEGORIES / CLAWHUB_TOPICS
      Optional comma-separated ClawHub metadata.
  NPM_TOKEN
      Required for real npm publish.
  NPM_REGISTRY
      npm registry URL. Default: https://registry.npmjs.org/.
  NPM_TAG
      npm dist tag. Default: latest.
  NPM_ACCESS
      npm access. Default: public.
  NPM_OTP
      Optional npm one-time password.

Outputs:
  - stdout: target, mode, package, version, source metadata, and publish result.
  - temp files: isolated ClawHub config and npm userconfig under a temp dir.
  - exit code 0: requested dry-run/publish completed.
  - non-zero: validation, auth, build, or publish failed.

Examples:
  scripts/publish.sh --target clawhub
  scripts/publish.sh --target clawhub --publish
  scripts/publish.sh --target npm
  scripts/publish.sh --target all --publish
EOF
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

info() {
  echo "INFO: $*"
}

repo_root() {
  git rev-parse --show-toplevel 2>/dev/null || pwd
}

json_field() {
  local field="$1"
  node -e '
const fs = require("node:fs");
const field = process.argv[1];
const pkg = JSON.parse(fs.readFileSync("package.json", "utf8"));
const value = field.split(".").reduce((current, key) => current?.[key], pkg);
if (typeof value === "string") process.stdout.write(value);
' "$field"
}

load_env_file() {
  local file="$1"
  [ -f "$file" ] || return 0

  while IFS= read -r line || [ -n "$line" ]; do
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" || "$line" == \#* ]] && continue
    [[ "$line" == export\ * ]] && line="${line#export }"
    [[ "$line" == *=* ]] || die "Invalid dotenv line in $file: $line"
    local key="${line%%=*}"
    local value="${line#*=}"
    key="${key%"${key##*[![:space:]]}"}"
    [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || die "Invalid env key in $file: $key"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    if [[ "$value" == \"*\" && "$value" == *\" ]]; then
      value="${value:1:${#value}-2}"
    elif [[ "$value" == \'*\' && "$value" == *\' ]]; then
      value="${value:1:${#value}-2}"
    fi
    export "$key=$value"
  done <"$file"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"
}

require_clean_git() {
  git diff --quiet || die "Working tree has unstaged changes. Commit them or use --allow-dirty."
  git diff --cached --quiet || die "Working tree has staged changes. Commit them or use --allow-dirty."
}

require_built_dependencies() {
  [ -x node_modules/.bin/tsc ] || die "Missing node_modules/.bin/tsc. Run npm ci in Docker/CI before publishing."
}

build_package() {
  require_built_dependencies
  info "Building package"
  npm run build
}

validate_clawhub() {
  require_command clawhub
  info "Validating ClawHub package"
  local validate_json="$tmp_dir/clawhub-validate.json"
  clawhub package validate . --json >"$validate_json"
  node -e '
const fs = require("node:fs");
const data = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
if (data.status !== "pass") {
  console.error(JSON.stringify(data.summary ?? data, null, 2));
  process.exit(1);
}
const warnings = data.summary?.warningCount ?? 0;
const issues = data.summary?.issueCount ?? 0;
if (warnings !== 0 || issues !== 0) {
  console.error(JSON.stringify(data.summary, null, 2));
  process.exit(1);
}
console.log(`INFO: ClawHub validate pass warnings=${warnings} issues=${issues}`);
' "$validate_json"
}

setup_clawhub_auth() {
  [ -n "${CLAWHUB_TOKEN:-}" ] || return 0
  export CLAWHUB_CONFIG_PATH="$tmp_dir/clawhub/config.json"
  mkdir -p "$(dirname "$CLAWHUB_CONFIG_PATH")"
  local registry="${CLAWHUB_REGISTRY:-}"
  if [ -z "$registry" ]; then
    node -e '
const fs = require("node:fs");
const token = process.env.CLAWHUB_TOKEN;
fs.writeFileSync(process.env.CLAWHUB_CONFIG_PATH, JSON.stringify({ token }, null, 2) + "\n", { mode: 0o600 });
'
  else
    node -e '
const fs = require("node:fs");
const token = process.env.CLAWHUB_TOKEN;
const registry = process.env.CLAWHUB_REGISTRY;
fs.writeFileSync(process.env.CLAWHUB_CONFIG_PATH, JSON.stringify({ token, registry }, null, 2) + "\n", { mode: 0o600 });
'
  fi
}

publish_clawhub() {
  require_command clawhub
  validate_clawhub

  local package_name version source_ref source_commit owner changelog
  package_name="${CLAWHUB_NAME:-$(json_field name)}"
  version="${PUBLISH_VERSION:-$(json_field version)}"
  source_ref="${CLAWHUB_SOURCE_REF:-$(git branch --show-current)}"
  source_commit="${CLAWHUB_SOURCE_COMMIT:-$(git rev-parse HEAD)}"
  owner="${CLAWHUB_OWNER:-hxy91819}"
  changelog="${CLAWHUB_CHANGELOG:-Release $package_name@$version.}"

  [ -n "$package_name" ] || die "Missing ClawHub package name."
  [ -n "$version" ] || die "Missing package version."
  [ -n "$source_ref" ] || die "Missing CLAWHUB_SOURCE_REF and current branch is detached."

  local args=(
    package publish .
    --owner "$owner"
    --name "$package_name"
    --version "$version"
    --source-commit "$source_commit"
    --source-ref "$source_ref"
    --changelog "$changelog"
    --json
  )
  [ -n "${CLAWHUB_SOURCE_REPO:-}" ] && args+=(--source-repo "$CLAWHUB_SOURCE_REPO")
  [ -n "${CLAWHUB_TAGS:-}" ] && args+=(--tags "$CLAWHUB_TAGS")
  [ -n "${CLAWHUB_CATEGORIES:-}" ] && args+=(--categories "$CLAWHUB_CATEGORIES")
  [ -n "${CLAWHUB_TOPICS:-}" ] && args+=(--topics "$CLAWHUB_TOPICS")
  [ "$publish" = "true" ] || args+=(--dry-run)

  setup_clawhub_auth
  info "ClawHub target package=$package_name version=$version owner=$owner mode=$mode"
  clawhub "${args[@]}"
}

setup_npm_auth() {
  export NPM_CONFIG_USERCONFIG="$tmp_dir/npmrc"
  local registry="${NPM_REGISTRY:-https://registry.npmjs.org/}"
  if [ "$publish" = "true" ]; then
    [ -n "${NPM_TOKEN:-}" ] || die "NPM_TOKEN is required for real npm publish."
  fi
  if [ -n "${NPM_TOKEN:-}" ]; then
    node -e '
const fs = require("node:fs");
const registry = new URL(process.env.NPM_REGISTRY || "https://registry.npmjs.org/");
const host = `${registry.host}${registry.pathname}`.replace(/\/?$/, "/");
fs.writeFileSync(process.env.NPM_CONFIG_USERCONFIG, `//${host}:_authToken=${process.env.NPM_TOKEN}\n`, { mode: 0o600 });
'
  else
    : >"$NPM_CONFIG_USERCONFIG"
  fi
}

publish_npm() {
  local package_name version registry tag access
  package_name="$(json_field name)"
  version="${PUBLISH_VERSION:-$(json_field version)}"
  registry="${NPM_REGISTRY:-https://registry.npmjs.org/}"
  tag="${NPM_TAG:-latest}"
  access="${NPM_ACCESS:-public}"

  [ -n "$package_name" ] || die "Missing package name."
  [ -n "$version" ] || die "Missing package version."

  setup_npm_auth
  local args=(publish --registry "$registry" --tag "$tag" --access "$access")
  [ "$publish" = "true" ] || args+=(--dry-run)
  [ -n "${NPM_OTP:-}" ] && args+=(--otp "$NPM_OTP")

  info "npm target package=$package_name version=$version tag=$tag mode=$mode"
  npm "${args[@]}"
}

target="all"
publish="false"
allow_dirty="false"
skip_build="false"
env_file=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --target)
      [ "$#" -ge 2 ] || die "--target requires a value."
      target="$2"
      shift 2
      ;;
    --publish)
      publish="true"
      shift
      ;;
    --env-file)
      [ "$#" -ge 2 ] || die "--env-file requires a value."
      env_file="$2"
      shift 2
      ;;
    --allow-dirty)
      allow_dirty="true"
      shift
      ;;
    --skip-build)
      skip_build="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown option: $1"
      ;;
  esac
done

case "$target" in
  clawhub|npm|all) ;;
  *) die "--target must be clawhub, npm, or all." ;;
esac

root="$(repo_root)"
cd "$root"

if [ -z "$env_file" ] && [ -f .env ]; then
  env_file=".env"
fi
[ -z "$env_file" ] || load_env_file "$env_file"

mode="dry-run"
[ "$publish" = "true" ] && mode="publish"

require_command git
require_command node
require_command npm

if [ "$publish" = "true" ] && [ "$allow_dirty" != "true" ]; then
  require_clean_git
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

info "Release mode=$mode target=$target env_file=${env_file:-<none>}"
info "Package $(json_field name)@$(json_field version)"

if [ "$skip_build" != "true" ]; then
  build_package
fi

case "$target" in
  clawhub)
    publish_clawhub
    ;;
  npm)
    publish_npm
    ;;
  all)
    publish_clawhub
    publish_npm
    ;;
esac
