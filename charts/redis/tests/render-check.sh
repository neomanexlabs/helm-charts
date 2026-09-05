#!/usr/bin/env bash
# render-check.sh: template-level verification for the redis chart.
#
# Renders the chart and asserts:
#   A. DEFAULT values render at all, carry no ExternalSecret, carry exactly
#      one Secret, and that Secret does NOT hold a well-known default
#      password. Every volumeMount in every StatefulSet resolves to a
#      declared volume or volumeClaimTemplate (an unresolved mount is
#      rejected by the API server at install time).
#   B. examples/ha-sentinel.yaml renders the full HA topology: three
#      StatefulSets (master, replicas, sentinel), a Sentinel
#      PodDisruptionBudget, the watchdog sidecar on the master pod, the
#      Sentinel spread constraints, and min-replicas-to-write in redis.conf.
#   C. tests/values-eso-fixture.yaml renders an ExternalSecret pointing at the
#      declared store and remote keys, and renders NO Secret: the passwords
#      live outside the chart.
#   D. tests/values-spread-fixture.yaml sets topologySpreadConstraints on
#      master, replica and sentinel, so all three StatefulSets carry them.
#   E. the Sentinel bootstrap waits for EVERY replica, not a fixed two: with
#      replica.replicaCount=3 the start-sentinel script must probe the third
#      replica host as well.
#   F. examples/minimal.yaml renders exactly one StatefulSet and no
#      ExternalSecret.
#   G. an unimplemented architecture is rejected: architecture=cluster must
#      fail the render rather than silently produce a release with no Redis
#      in it.
#   H. identifier check: no private registry, private git host or company
#      mailbox anywhere in the chart directory. The same step rejects em
#      dashes (published text uses plain punctuation) and comments pointing
#      at an external documentation tree.
#
# Usage: tests/render-check.sh   (from the chart root, or pass the chart dir)
set -euo pipefail

CHART_DIR="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
ESO_FIXTURE="$CHART_DIR/tests/values-eso-fixture.yaml"
SPREAD_FIXTURE="$CHART_DIR/tests/values-spread-fixture.yaml"
HA_EXAMPLE="$CHART_DIR/examples/ha-sentinel.yaml"
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

# Counts documents of kind $2 in the render at $1.
count_kind() {
  grep -c "^kind: $2\$" "$1" || true
}

# Extracts the first document of kind $2 carrying component label $3, from the
# render at $1. Documents are separated by lines that are exactly "---"; both
# conditions must hold in the SAME document, so a Service cannot stand in for
# the StatefulSet that shares its component label.
extract_doc() {
  awk -v RS='\n---\n' -v kind="kind: $2" -v comp="app.kubernetes.io/component: $3" '
    index($0, kind) && index($0, comp) { print; exit }
  ' "$1"
}

# Writes every StatefulSet document of the render at $1 into directory $2.
split_statefulsets() {
  mkdir -p "$2"
  awk -v RS='\n---\n' -v out="$2" '
    index($0, "kind: StatefulSet") { n++; print > (out "/sts-" n ".yaml") }
  ' "$1"
}

# Fails unless every volumeMount name in the StatefulSet document $1 resolves
# to a declared volume or volumeClaimTemplate.
assert_mounts_resolve() {
  local doc="$1" label="$2" declared mounted v
  declared="$(awk '/^      volumes:/{f=1} /^  volumeClaimTemplates:/{f=1} f && /^        - name: /{print $3} f && /^        name: /{print $2}' "$doc" | sort -u)"
  mounted="$(awk '/volumeMounts:/{f=1;next} f && /^ *- name: /{print $3;next} f && !/^ *(mountPath|subPath|readOnly):/{f=0}' "$doc" | sort -u)"
  [ -n "$mounted" ] || fail "$label: no volumeMounts found at all (the parser broke, or the StatefulSet has no containers)"
  for v in $mounted; do
    printf '%s\n' "$declared" | grep -qx "$v" \
      || fail "$label: volumeMount '$v' has no matching volume or volumeClaimTemplate (the API server would reject this StatefulSet)"
  done
}

# --- A. defaults render, no ESO, one Secret, no well-known password ----------
render "$TMP/default.yaml"

[ "$(count_kind "$TMP/default.yaml" ExternalSecret)" -eq 0 ] \
  || fail "defaults: an ExternalSecret rendered without externalSecrets.enabled"

[ "$(count_kind "$TMP/default.yaml" Secret)" -eq 1 ] \
  || fail "defaults: expected exactly one Secret, got $(count_kind "$TMP/default.yaml" Secret)"

SECRET_DOC="$(awk -v RS='\n---\n' 'index($0, "kind: Secret") { print; exit }' "$TMP/default.yaml")"
[ -n "$SECRET_DOC" ] || fail "defaults: Secret document not found"
for weak in "change-me-in-production" "change-sentinel-password-in-production"; do
  weak_b64="$(printf '%s' "$weak" | base64 | tr -d '\n')"
  printf '%s' "$SECRET_DOC" | grep -q "$weak_b64" \
    && fail "defaults: the rendered Secret carries the well-known default password '$weak'; a chart must not ship an installable, publicly known credential"
done

split_statefulsets "$TMP/default.yaml" "$TMP/default-sts"
[ -n "$(ls -A "$TMP/default-sts" 2>/dev/null)" ] \
  || fail "defaults: no StatefulSet rendered at all"
for doc in "$TMP/default-sts"/*.yaml; do
  assert_mounts_resolve "$doc" "defaults ($(basename "$doc"))"
done

echo "PASS: render-check A (defaults render, no ESO, one Secret without a well-known password, mounts resolve)"

# --- B. HA example: full sentinel topology ----------------------------------
render "$TMP/ha.yaml" -f "$HA_EXAMPLE"

[ "$(count_kind "$TMP/ha.yaml" StatefulSet)" -eq 3 ] \
  || fail "ha example: expected 3 StatefulSets (master, replicas, sentinel), got $(count_kind "$TMP/ha.yaml" StatefulSet)"

for comp in master replica sentinel; do
  [ -n "$(extract_doc "$TMP/ha.yaml" StatefulSet "$comp")" ] \
    || fail "ha example: no StatefulSet with component '$comp'"
done

SENTINEL_PDB="$(extract_doc "$TMP/ha.yaml" PodDisruptionBudget sentinel)"
[ -n "$SENTINEL_PDB" ] \
  || fail "ha example: no Sentinel PodDisruptionBudget (a rolling node drain could take the whole quorum at once)"

MASTER_STS="$(extract_doc "$TMP/ha.yaml" StatefulSet master)"
printf '%s' "$MASTER_STS" | grep -q '^        - name: watchdog$' \
  || fail "ha example: master pod has no watchdog sidecar container despite master.watchdog.enabled: true"

SENTINEL_STS="$(extract_doc "$TMP/ha.yaml" StatefulSet sentinel)"
printf '%s' "$SENTINEL_STS" | grep -q 'topologySpreadConstraints:' \
  || fail "ha example: sentinel StatefulSet drops sentinel.topologySpreadConstraints (all three Sentinels could land on one node)"

grep -q 'min-replicas-to-write 1' "$TMP/ha.yaml" \
  || fail "ha example: redis.conf does not carry min-replicas-to-write from configuration"

echo "PASS: render-check B (HA example: three StatefulSets, sentinel PDB, watchdog sidecar, sentinel spread, min-replicas-to-write)"

# --- C. ESO fixture: ExternalSecret instead of a Secret ----------------------
render "$TMP/eso.yaml" -f "$ESO_FIXTURE"

[ "$(count_kind "$TMP/eso.yaml" ExternalSecret)" -ge 1 ] \
  || fail "eso fixture: no ExternalSecret rendered with externalSecrets.enabled: true"
[ "$(count_kind "$TMP/eso.yaml" Secret)" -eq 0 ] \
  || fail "eso fixture: a Secret rendered alongside the ExternalSecret; the chart would fight the operator over the same object"

ES_DOC="$(awk -v RS='\n---\n' 'index($0, "kind: ExternalSecret") { print; exit }' "$TMP/eso.yaml")"
printf '%s' "$ES_DOC" | grep -q 'name: example-store' \
  || fail "eso fixture: ExternalSecret does not reference externalSecrets.secretStore.name"
printf '%s' "$ES_DOC" | grep -q 'kind: ClusterSecretStore' \
  || fail "eso fixture: ExternalSecret does not reference externalSecrets.secretStore.kind"
printf '%s' "$ES_DOC" | grep -q 'key: example-redis-password' \
  || fail "eso fixture: ExternalSecret is missing the Redis password remote key"
printf '%s' "$ES_DOC" | grep -q 'key: example-sentinel-password' \
  || fail "eso fixture: ExternalSecret is missing the Sentinel password remote key"

echo "PASS: render-check C (ESO fixture: ExternalSecret with store and remote keys, no in-chart Secret)"

# --- D. spread fixture: all three workloads honour the constraints -----------
render "$TMP/spread.yaml" -f "$SPREAD_FIXTURE"

for comp in master replica sentinel; do
  SPREAD_DOC="$(extract_doc "$TMP/spread.yaml" StatefulSet "$comp")"
  [ -n "$SPREAD_DOC" ] || fail "spread fixture: no StatefulSet with component '$comp'"
  printf '%s' "$SPREAD_DOC" | grep -q 'topologySpreadConstraints:' \
    || fail "spread fixture: $comp StatefulSet drops ${comp}.topologySpreadConstraints"
done

echo "PASS: render-check D (topology spread constraints render on master, replica and sentinel)"

# --- E. sentinel bootstrap waits for every replica --------------------------
# The Sentinel start script probes Redis nodes before it starts. With three
# replicas it must probe all three; a host list that stops at the second
# replica leaves the third invisible to the bootstrap probe.
render "$TMP/ha-3.yaml" -f "$HA_EXAMPLE" --set replica.replicaCount=3

SCRIPTS_CM="$(awk -v RS='\n---\n' 'index($0, "kind: ConfigMap") && index($0, "start-sentinel.sh") { print; exit }' "$TMP/ha-3.yaml")"
[ -n "$SCRIPTS_CM" ] || fail "scripts ConfigMap with start-sentinel.sh not found"
printf '%s' "$SCRIPTS_CM" | grep -q 'REPLICA_HOSTS=' \
  || fail "start-sentinel.sh no longer builds a REPLICA_HOSTS list; update this assertion to the new form"
printf '%s' "$SCRIPTS_CM" | grep -q -- '-replicas-2\.' \
  || fail "start-sentinel.sh does not probe replica 2 with replica.replicaCount=3 (the replica host list is fixed at two)"

echo "PASS: render-check E (sentinel bootstrap probes every replica)"

# --- F. minimal example ------------------------------------------------------
render "$TMP/minimal.yaml" -f "$MINIMAL_EXAMPLE"

[ "$(count_kind "$TMP/minimal.yaml" StatefulSet)" -eq 1 ] \
  || fail "minimal example: expected exactly one StatefulSet, got $(count_kind "$TMP/minimal.yaml" StatefulSet)"
[ "$(count_kind "$TMP/minimal.yaml" ExternalSecret)" -eq 0 ] \
  || fail "minimal example: an ExternalSecret rendered without externalSecrets.enabled"

split_statefulsets "$TMP/minimal.yaml" "$TMP/minimal-sts"
for doc in "$TMP/minimal-sts"/*.yaml; do
  assert_mounts_resolve "$doc" "minimal example ($(basename "$doc"))"
done

echo "PASS: render-check F (minimal example: one StatefulSet, no ESO, mounts resolve)"

# --- G. unimplemented architecture is rejected ------------------------------
# The chart ships no cluster templates, so architecture=cluster would install a
# release with no Redis in it. It must fail loudly instead.
if helm template rel "$CHART_DIR" --set architecture=cluster > "$TMP/cluster.yaml" 2> "$TMP/cluster.err"; then
  fail "architecture=cluster rendered successfully; an unimplemented architecture must be rejected by values validation"
fi

echo "PASS: render-check G (unimplemented architecture rejected)"

# --- H. published-content checks --------------------------------------------
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

echo "PASS: render-check H1 (identifier check clean)"

# Published text uses plain punctuation only, so no em dash anywhere in the
# chart. The character is built with printf so this script stays free of it and
# is scanned by the same rule as every other file.
EM_DASH="$(printf '\xe2\x80\x94')"
EM_HITS="$(grep -rn "$EM_DASH" "$CHART_DIR" || true)"
if [ -n "$EM_HITS" ]; then
  echo "$EM_HITS" >&2
  fail "punctuation check: em dash present in the chart (see hits above); use a period, comma, colon or parentheses"
fi

echo "PASS: render-check H2 (punctuation check clean)"

# Comments must explain themselves. A reference to a documentation tree that
# ships elsewhere is meaningless to a chart user. Only THIS script is excluded,
# because it carries the pattern.
DOCPATH_HITS="$(grep -rn "documentation/" "$CHART_DIR" --exclude=render-check.sh || true)"
if [ -n "$DOCPATH_HITS" ]; then
  echo "$DOCPATH_HITS" >&2
  fail "internal path check: reference to an external documentation path present in the chart (see hits above)"
fi

echo "PASS: render-check H3 (internal path check clean)"
