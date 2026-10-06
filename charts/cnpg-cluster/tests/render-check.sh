#!/usr/bin/env bash
# render-check.sh: template-level verification for the cnpg-cluster chart.
#
# Renders the chart and asserts:
#   A. DEFAULT values render exactly one Cluster and nothing else: no Secret,
#      no ExternalSecret, no Pooler, no CronJob. Superuser access is off and no
#      superuserSecret is named, no initdb secret is named, and the default
#      pg_hba allows the three RFC 1918 ranges only.
#   B. examples/minimal.yaml renders one single-instance Cluster with the
#      PodDisruptionBudget off.
#   C. examples/ha-spot.yaml renders the production topology: Cluster, rw
#      Pooler, ScheduledBackup and the replica recovery CronJob. Backups go to
#      gs:// through Workload Identity, instances tolerate the spot taint, and
#      the recovery job runs the pinned image (no :latest anywhere).
#   D. tests/values-scheduling-fixture.yaml: the rw pooler takes every pooler
#      default (tolerations, priority class, spread); the ro pooler overrides
#      tolerations and priority class, and renders with pgbouncer defaults
#      although its entry has no pgbouncer block.
#   E. superuser: enabled with nothing supplied lets the operator generate the
#      secret (no superuserSecret, no Secret); enabled with a password renders
#      the Secret and names it.
#   F. application user: a supplied password renders the Secret and initdb
#      reads it; an explicit bootstrap.initdb.secret wins.
#   G. backups: S3 with a region renders s3Credentials once and the region
#      from the same secret; Azure builds an https blob address and fails
#      without a storage account.
#   H. tests/values-eso-fixture.yaml renders two ExternalSecrets against the
#      named store and no Secret, and the Cluster names both secrets. With
#      ESO on, no store name and no provider, the render fails.
#   I. published-content checks: no private registry, private git host or
#      company mailbox anywhere in the chart directory, no em dash, and no
#      comment pointing at an external documentation tree.
#   J. chart label: helm.sh/chart is name-version with semver build metadata
#      stripped, so a +sha suffix never rolls the pooler pods.
#
# Usage: tests/render-check.sh   (from the chart root, or pass the chart dir)
set -euo pipefail

CHART_DIR="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
SCHED_FIXTURE="$CHART_DIR/tests/values-scheduling-fixture.yaml"
ESO_FIXTURE="$CHART_DIR/tests/values-eso-fixture.yaml"
HA_EXAMPLE="$CHART_DIR/examples/ha-spot.yaml"
MINIMAL_EXAMPLE="$CHART_DIR/examples/minimal.yaml"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $1" >&2; exit 1; }

# Renders the chart into $1; any helm error is printed before failing, so a
# broken template shows its own message rather than an empty render.
render() {
  local out="$1"; shift
  if ! helm template rel "$CHART_DIR" "$@" > "$out" 2> "$out.err"; then
    cat "$out.err" >&2
    fail "helm template failed (args: ${*:-none})"
  fi
}

# Fails unless the render with the given args is rejected and its error
# carries the text $2. $1 names the case.
render_fails() {
  local name="$1" needle="$2"; shift 2
  if helm template rel "$CHART_DIR" "$@" > "$TMP/neg.yaml" 2> "$TMP/neg.err"; then
    fail "$name: the render succeeded but must be rejected"
  fi
  grep -qF "$needle" "$TMP/neg.err" \
    || { cat "$TMP/neg.err" >&2; fail "$name: rejected, but without '$needle'"; }
}

# Counts documents of kind $2 in the render at $1.
count_kind() {
  grep -c "^kind: $2\$" "$1" || true
}

# Extracts the first document of kind $2 that also contains the text $3, from
# the render at $1. Documents are separated by lines that are exactly "---";
# both conditions must hold in the SAME document.
extract_doc() {
  awk -v RS='\n---\n' -v kind="kind: $2" -v needle="$3" '
    index($0, kind) && index($0, needle) { print; exit }
  ' "$1"
}

# Fails unless the file $1 contains the fixed text $2. $3 names the case.
has() { grep -qF -- "$2" "$1" || fail "$3: expected '$2'"; }

# Fails if the file $1 contains the fixed text $2. $3 names the case.
lacks() { ! grep -qF -- "$2" "$1" || fail "$3: unexpected '$2'"; }

# --- A. defaults -------------------------------------------------------------
render "$TMP/default.yaml"
[ "$(count_kind "$TMP/default.yaml" Cluster)" = 1 ] || fail "defaults: expected exactly one Cluster"
for kind in Secret ExternalSecret Pooler CronJob ScheduledBackup PodMonitor NetworkPolicy SecretStore; do
  [ "$(count_kind "$TMP/default.yaml" "$kind")" = 0 ] || fail "defaults: a $kind rendered with default values"
done
has   "$TMP/default.yaml" "enableSuperuserAccess: false" "defaults"
lacks "$TMP/default.yaml" "superuserSecret:" "defaults"
lacks "$TMP/default.yaml" "      secret:" "defaults (initdb secret)"
for range in 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16; do
  has "$TMP/default.yaml" "host all all $range scram-sha-256" "defaults (pg_hba)"
done
[ "$(grep -c 'host all all' "$TMP/default.yaml")" = 3 ] || fail "defaults: expected exactly three pg_hba rules"

echo "PASS: render-check A (defaults: one Cluster, superuser off, private-range pg_hba)"

# --- B. minimal example ------------------------------------------------------
render "$TMP/minimal.yaml" -f "$MINIMAL_EXAMPLE"
[ "$(count_kind "$TMP/minimal.yaml" Cluster)" = 1 ] || fail "minimal example: expected one Cluster"
has "$TMP/minimal.yaml" "  instances: 1" "minimal example"
has "$TMP/minimal.yaml" "enablePDB: false" "minimal example"

echo "PASS: render-check B (minimal example)"

# --- C. high availability example --------------------------------------------
render "$TMP/ha.yaml" -f "$HA_EXAMPLE"
for kind in Cluster Pooler ScheduledBackup CronJob; do
  [ "$(count_kind "$TMP/ha.yaml" "$kind")" = 1 ] || fail "ha example: expected one $kind"
done
CLUSTER="$TMP/ha-cluster.yaml"
extract_doc "$TMP/ha.yaml" Cluster "barmanObjectStore" > "$CLUSTER"
has "$CLUSTER" "destinationPath: gs://my-postgres-backups/rel-cnpg-cluster" "ha example"
has "$CLUSTER" "gkeEnvironment: true" "ha example"
has "$CLUSTER" "key: cloud.google.com/gke-spot" "ha example (instance tolerations)"
has "$CLUSTER" "reusePVC: true" "ha example"
CRON="$TMP/ha-cron.yaml"
extract_doc "$TMP/ha.yaml" CronJob "schedule:" > "$CRON"
has "$CRON" "image: alpine/k8s:1.33.5" "ha example (recovery image)"
lacks "$TMP/ha.yaml" ":latest" "ha example"

echo "PASS: render-check C (ha example: pooler, GCS backups, pinned recovery image)"

# --- D. pooler scheduling -----------------------------------------------------
render "$TMP/sched.yaml" -f "$SCHED_FIXTURE"
[ "$(count_kind "$TMP/sched.yaml" Pooler)" = 2 ] || fail "scheduling: expected two Poolers"
RW="$TMP/sched-rw.yaml"; RO="$TMP/sched-ro.yaml"
extract_doc "$TMP/sched.yaml" Pooler "rel-cnpg-cluster-pooler-rw" > "$RW"
extract_doc "$TMP/sched.yaml" Pooler "rel-cnpg-cluster-pooler-ro" > "$RO"
has   "$RW" "poolMode: session" "scheduling (rw pgbouncer)"
has   "$RW" "value: postgres" "scheduling (rw default tolerations)"
has   "$RW" 'priorityClassName: "high-priority"' "scheduling (rw default priority)"
has   "$RW" "topologySpreadConstraints:" "scheduling (rw default spread)"
has   "$RO" "poolMode: transaction" "scheduling (ro pgbouncer defaults)"
has   "$RO" 'default_pool_size: "25"' "scheduling (ro pgbouncer defaults)"
has   "$RO" "value: readonly" "scheduling (ro tolerations override)"
lacks "$RO" "value: postgres" "scheduling (ro tolerations override)"
has   "$RO" 'priorityClassName: "low-priority"' "scheduling (ro priority override)"
INSTANCES="$TMP/sched-cluster.yaml"
extract_doc "$TMP/sched.yaml" Cluster "instances:" > "$INSTANCES"
has "$INSTANCES" "value: postgres" "scheduling (instance tolerations)"

echo "PASS: render-check D (pooler defaults, per-pooler overrides, pgbouncer defaults)"

# --- E. superuser secret --------------------------------------------------------
render "$TMP/su-gen.yaml" --set auth.superuser.enabled=true
has   "$TMP/su-gen.yaml" "enableSuperuserAccess: true" "superuser generated"
lacks "$TMP/su-gen.yaml" "superuserSecret:" "superuser generated"
[ "$(count_kind "$TMP/su-gen.yaml" Secret)" = 0 ] || fail "superuser generated: the chart rendered a Secret"

render "$TMP/su-pw.yaml" --set auth.superuser.enabled=true --set auth.superuser.password=example
has "$TMP/su-pw.yaml" "superuserSecret:" "superuser password"
has "$TMP/su-pw.yaml" "name: rel-cnpg-cluster-superuser" "superuser password"
[ "$(count_kind "$TMP/su-pw.yaml" Secret)" = 1 ] || fail "superuser password: expected one Secret"

echo "PASS: render-check E (superuser secret named only when one exists)"

# --- F. application user secret -------------------------------------------------
render "$TMP/app-pw.yaml" --set auth.appUser.password=example
has "$TMP/app-pw.yaml" "name: rel-cnpg-cluster-app-user" "app user password"
extract_doc "$TMP/app-pw.yaml" Cluster "initdb:" | grep -A1 '      secret:' | grep -qF "name: rel-cnpg-cluster-app-user" \
  || fail "app user password: initdb does not read the rendered app user secret"

render "$TMP/app-explicit.yaml" --set auth.appUser.password=example --set bootstrap.initdb.secret.name=explicit
extract_doc "$TMP/app-explicit.yaml" Cluster "initdb:" | grep -A1 '      secret:' | grep -qF "name: explicit" \
  || fail "app user explicit: bootstrap.initdb.secret did not win"

echo "PASS: render-check F (app user secret reaches initdb, explicit secret wins)"

# --- G. backup destinations -----------------------------------------------------
render "$TMP/s3.yaml" --set backup.enabled=true --set backup.provider=s3 \
  --set backup.s3.bucket=example --set backup.s3.region=us-east-1 \
  --set backup.credentials.createSecret=true \
  --set backup.s3.credentials.accessKeyId=example --set backup.s3.credentials.secretAccessKey=example
[ "$(grep -c 's3Credentials:' "$TMP/s3.yaml")" = 1 ] || fail "s3: s3Credentials must render exactly once"
has "$TMP/s3.yaml" "key: AWS_REGION" "s3"
has "$TMP/s3.yaml" "destinationPath: s3://example/rel-cnpg-cluster" "s3"

render "$TMP/azure.yaml" --set backup.enabled=true --set backup.provider=azure \
  --set backup.azure.container=example --set backup.azure.storageAccount=account \
  --set backup.azure.inheritFromAzureAD=true
has "$TMP/azure.yaml" "destinationPath: https://account.blob.core.windows.net/example/rel-cnpg-cluster" "azure"
render_fails "azure without account" "backup.azure.storageAccount is required" \
  --set backup.enabled=true --set backup.provider=azure \
  --set backup.azure.container=example --set backup.azure.inheritFromAzureAD=true

echo "PASS: render-check G (S3 credentials once, Azure https address)"

# --- H. External Secrets --------------------------------------------------------
render "$TMP/eso.yaml" -f "$ESO_FIXTURE"
[ "$(count_kind "$TMP/eso.yaml" ExternalSecret)" = 2 ] || fail "eso: expected two ExternalSecrets"
[ "$(count_kind "$TMP/eso.yaml" Secret)" = 0 ] || fail "eso: the chart rendered a Secret of its own"
[ "$(count_kind "$TMP/eso.yaml" SecretStore)" = 0 ] || fail "eso: a SecretStore rendered although a store is named"
has "$TMP/eso.yaml" "name: example-store" "eso"
has "$TMP/eso.yaml" "kind: ClusterSecretStore" "eso"
has "$TMP/eso.yaml" "superuserSecret:" "eso"
extract_doc "$TMP/eso.yaml" Cluster "initdb:" | grep -A1 '      secret:' | grep -qF "name: rel-cnpg-cluster-app-user" \
  || fail "eso: initdb does not read the external app user secret"
render_fails "eso without provider" "externalSecrets.provider is required" \
  --set externalSecrets.enabled=true

echo "PASS: render-check H (External Secrets, provider required)"

# --- I. published-content checks ------------------------------------------------
# The pattern is generic by design (registry hosts, private git hosts,
# mailboxes); it names no specific deployment. Only THIS script is excluded,
# because it carries the pattern; the fixtures and examples ARE scanned and are
# written generically for exactly that reason.
IDENT_PATTERN='pkg\.dev|gcr\.io|gitlab\.com|@neomanex\.com'
IDENT_HITS="$(grep -rniE "$IDENT_PATTERN" "$CHART_DIR" --exclude=render-check.sh || true)"
if [ -n "$IDENT_HITS" ]; then
  echo "$IDENT_HITS" >&2
  fail "identifier check: deployment-specific identifiers present in the chart (see hits above)"
fi

echo "PASS: render-check I1 (identifier check clean)"

# Published text uses plain punctuation only, so no em dash anywhere in the
# chart. The character is built with printf so this script stays free of it and
# is scanned by the same rule as every other file.
EM_DASH="$(printf '\xe2\x80\x94')"
EM_HITS="$(grep -rn "$EM_DASH" "$CHART_DIR" || true)"
if [ -n "$EM_HITS" ]; then
  echo "$EM_HITS" >&2
  fail "punctuation check: em dash present in the chart (see hits above); use a period, comma, colon or parentheses"
fi

echo "PASS: render-check I2 (punctuation check clean)"

# Comments must explain themselves. A reference to a documentation tree that
# ships elsewhere is meaningless to a chart user. Full http(s) URLs to public
# documentation explain themselves and pass. Only THIS script is excluded,
# because it carries the pattern.
DOCPATH_HITS="$(grep -rnoE "[^[:space:]\"'\`(<]*documentation/" "$CHART_DIR" --exclude=render-check.sh \
  | grep -vE ':[0-9]+:https?://' || true)"
if [ -n "$DOCPATH_HITS" ]; then
  echo "$DOCPATH_HITS" >&2
  fail "internal path check: reference to an external documentation path present in the chart (see hits above)"
fi

echo "PASS: render-check I3 (internal path check clean)"

# --- J. chart label ignores semver build metadata -------------------------------
# A version such as 1.0.0+abc123 must label the pods cnpg-cluster-1.0.0: the
# label sits in the pooler pod template, so anything volatile in it rolls them.
cp -R "$CHART_DIR" "$TMP/meta"
sed -E 's/^version: (.*)$/version: \1+abc123/' "$TMP/meta/Chart.yaml" > "$TMP/meta/Chart.yaml.new"
mv "$TMP/meta/Chart.yaml.new" "$TMP/meta/Chart.yaml"
grep -q '^version: .*+abc123$' "$TMP/meta/Chart.yaml" \
  || fail "chart label: could not inject build metadata into the scratch Chart.yaml"
helm template rel "$TMP/meta" > "$TMP/meta.yaml" 2>/dev/null \
  || fail "chart label: render with build metadata failed"
META_LABEL="$(grep -m1 'helm.sh/chart:' "$TMP/meta.yaml" | awk '{print $2}')"
BASE_VERSION="$(sed -nE 's/^version: ([^+]*).*$/\1/p' "$CHART_DIR/Chart.yaml")"
[ "$META_LABEL" = "cnpg-cluster-$BASE_VERSION" ] \
  || fail "chart label: expected cnpg-cluster-$BASE_VERSION with build metadata stripped, got '$META_LABEL'"
PLAIN_LABEL="$(grep -m1 'helm.sh/chart:' "$TMP/default.yaml" | awk '{print $2}')"
[ "$PLAIN_LABEL" = "cnpg-cluster-$BASE_VERSION" ] \
  || fail "chart label: expected cnpg-cluster-$BASE_VERSION on the default render, got '$PLAIN_LABEL'"

echo "PASS: render-check J (chart label strips build metadata)"
