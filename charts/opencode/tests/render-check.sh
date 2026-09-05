#!/usr/bin/env bash
# render-check.sh: template-level verification for the opencode chart:
# live-edit features, per-workspace tools rendering, git identity, autosave,
# the ESO-less minimal example, and the published-content identifier check.
#
# Renders the chart and asserts:
#   A. DEFAULT values (toggles off)   -> none of the new objects/flags render
#      (backward compat for existing deploys)
#   B. tests/values-live-edit-fixture.yaml (toggles on)
#      -> expose Role/RoleBinding, netpol :3000, gitSync skip, safe.directory '*'
#   C. DEFAULT values (no fixture)    -> no top-level "tools" key in any
#      ConfigMap (backward compat: no config.tools / no $ws.tools declared)
#   D. tests/values-tools-fixture.yaml -> per-workspace `tools` merge:
#      global config.tools deep-copied, mergeOverwrite'd with $ws.tools
#      (workspace key wins per key); a workspace with no tools map inherits
#      the global map unchanged; every rendered opencode.json is valid JSON.
#   E. tests/values-identity-fixture.yaml -> git commit identity comes from
#      git.user.name / git.user.email and renders in BOTH the git-init
#      initContainer script and the runtime container command; the DEFAULT
#      render (one workspace, no identity values) carries no hardcoded
#      commit identity anywhere.
#   F. tests/values-identity-fixture.yaml -> per-workspace
#      gitSync.autosave: {enabled, paths, userName, userEmail} renders the
#      git-sync CronJob autosave block with the workspace identity and paths;
#      the legacy gitSync.push: true alias still renders one, falling back to
#      git.user.*; a workspace with neither renders no autosave block.
#   H. examples/minimal.yaml (externalSecrets.enabled: false) -> the
#      StatefulSet is installable: every volumeMount name in every container
#      resolves to a declared volume or volumeClaimTemplate, the git-init
#      script does not copy an SSH key that was never mounted, and neither
#      container carries a GIT_SSH_COMMAND pointing at a key that does not
#      exist. With ESO ON (identity fixture) the ssh-key mount, the copy and
#      GIT_SSH_COMMAND all still render.
#   G. identifier check: no private registry, private git host, in-cluster
#      service address, deployment-specific release name or mailbox anywhere
#      in the chart directory. The label key opencode.neomanex.com/workspace
#      is the chart's reserved label namespace and is deliberately NOT matched.
#      The same step also rejects em dashes (published text uses plain
#      punctuation) and comments pointing at an external documentation tree.
#
# Usage: tests/render-check.sh   (from the chart root, or pass the chart dir)
set -euo pipefail

CHART_DIR="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
FIXTURE="$CHART_DIR/tests/values-live-edit-fixture.yaml"
TOOLS_FIXTURE="$CHART_DIR/tests/values-tools-fixture.yaml"
IDENTITY_FIXTURE="$CHART_DIR/tests/values-identity-fixture.yaml"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $1" >&2; exit 1; }

# Extracts the ConfigMap document whose workspace label matches $2, from a
# full `helm template` render at path $1. Docs are separated by lines that
# are exactly "---"; matches on BOTH "kind: ConfigMap" and the workspace
# label being present in the SAME document, so it can't accidentally grab
# a StatefulSet/Service doc that happens to carry the same workspace label.
extract_configmap_doc() {
  awk -v RS='\n---\n' -v ws="opencode.neomanex.com/workspace: $2" '
    index($0, "kind: ConfigMap") && index($0, ws) { print; exit }
  ' "$1"
}

# Extracts the opencode.json body (de-indented) from a ConfigMap doc on stdin.
extract_opencode_json() {
  awk '/opencode\.json: \|/{f=1;next} f' | sed 's/^    //'
}

helm template rel "$CHART_DIR" > "$TMP/default.yaml" 2>/dev/null
helm template rel "$CHART_DIR" -f "$FIXTURE" > "$TMP/live-edit.yaml" 2>/dev/null
helm template rel "$CHART_DIR" -f "$TOOLS_FIXTURE" > "$TMP/tools.yaml" 2>/dev/null
helm template rel "$CHART_DIR" -f "$IDENTITY_FIXTURE" > "$TMP/identity.yaml" 2>/dev/null
# Defaults ship `workspaces: []`, so the stock default render has no
# StatefulSet at all and any "no hardcoded identity" grep over it would pass
# vacuously. Render the defaults WITH one minimal workspace so the assertion
# can actually fail.
helm template rel "$CHART_DIR" \
  --set 'workspaces[0].name=demo' \
  --set 'workspaces[0].repo=git@example.com:org/demo.git' \
  --set 'workspaces[0].branch=main' \
  --set 'workspaces[0].size=10Gi' > "$TMP/default-ws.yaml" 2>/dev/null

# --- A. defaults: nothing new renders ---------------------------------------
! grep -q 'name: rel-expose' "$TMP/default.yaml" \
  || fail "defaults: expose Role/RoleBinding rendered with rbac.exposeRole unset"
! grep -q 'port: 3000' "$TMP/default.yaml" \
  || fail "defaults: port 3000 rendered without networkPolicy.additionalPorts"

# --- B. fixture: every live-edit feature renders ----------------------------
# 1. expose RBAC. Assertions scoped to the Role DOCUMENT (not the whole
#    render, where comments/other objects would satisfy a bare grep).
ROLE_DOC="$(awk '/^kind: Role$/,/^---$/' "$TMP/live-edit.yaml")"
printf '%s' "$ROLE_DOC" | grep -q 'name: rel-expose' \
  || fail "fixture: Role rel-expose not rendered (rbac.exposeRole: true)"
printf '%s' "$ROLE_DOC" | grep -q '"patch"' \
  || fail "fixture: expose Role missing pods patch verb"
printf '%s' "$ROLE_DOC" | grep -q '"delete"' \
  || fail "fixture: expose Role missing secrets delete verb (teardown)"

# 2. networkPolicy additionalPorts
grep -q 'port: 3000' "$TMP/live-edit.yaml" \
  || fail "fixture: NetworkPolicy missing additionalPort 3000"

# 3. git-sync per-workspace skip: the docs-site workspace must NOT appear
#    in the CronJob's exec loop while ops must.
GITSYNC="$(awk '/kind: CronJob/,0' "$TMP/live-edit.yaml")"
printf '%s' "$GITSYNC" | grep -q '/workspace/ops' \
  || fail "fixture: git-sync CronJob lost the ops workspace"
printf '%s' "$GITSYNC" | grep -q '/workspace/docs-site' \
  && fail "fixture: git-sync CronJob still includes docs-site (gitSync.enabled: false ignored)"

# 3b. git-init restart path honours the same opt-out: the docs-site
#     StatefulSet keeps submodules that sit on a branch, while ops (gitSync on)
#     still runs the blanket submodule update. Default render must not carry
#     the branch-keep loop at all.
extract_sts_doc() {
  awk -v RS='\n---\n' -v ws="opencode.neomanex.com/workspace: $2" '
    index($0, "kind: StatefulSet") && index($0, ws) { print; exit }
  ' "$1"
}
SR_STS="$(extract_sts_doc "$TMP/live-edit.yaml" docs-site)"
OPS_STS="$(extract_sts_doc "$TMP/live-edit.yaml" ops)"
[ -n "$SR_STS" ] || fail "fixture: docs-site StatefulSet doc not found"
[ -n "$OPS_STS" ] || fail "fixture: ops StatefulSet doc not found"
printf '%s' "$SR_STS" | grep -q 'symbolic-ref -q HEAD' \
  || fail "fixture: docs-site git-init lacks the branch-keep submodule loop (gitSync.enabled: false ignored on restart path)"
printf '%s' "$OPS_STS" | grep -q 'symbolic-ref -q HEAD' \
  && fail "fixture: ops git-init carries the branch-keep loop (gitSync on must keep the blanket update)"
grep -q 'symbolic-ref -q HEAD' "$TMP/default.yaml" \
  && fail "default: git-init carries the branch-keep loop with gitSync at defaults"

# 4. per-workspace instructions: only the docs-site workspace's ConfigMap
#    carries the instructions array; defaults render none at all.
! grep -q '"instructions"' "$TMP/default.yaml" \
  || fail "defaults: instructions rendered without any workspace setting them"
grep -q '"instructions": \["/workspace/docs-site/docs/live-edit.md"\]' "$TMP/live-edit.yaml" \
  || fail "fixture: docs-site workspace ConfigMap missing instructions array"
[ "$(grep -c '"instructions"' "$TMP/live-edit.yaml")" -eq 1 ] \
  || fail "fixture: instructions leaked into more than one workspace ConfigMap"

# 5. runtime safe.directory '*' + commit identity (all renders, not toggle-gated)
grep -q "safe.directory '\*'" "$TMP/live-edit.yaml" \
  || grep -q 'safe.directory \*' "$TMP/live-edit.yaml" \
  || grep -q 'safe.directory "' "$TMP/live-edit.yaml" \
  || fail "fixture: runtime start command missing safe.directory wildcard"
grep -q 'user.email' "$TMP/live-edit.yaml" \
  || fail "fixture: runtime start command missing commit identity"

# 6. permission string passthrough: with config.permission set as the string
#    shorthand and NO tools map anywhere, every workspace renders the string
#    VERBATIM (byte-identical to pre-1.3.x renders -- no map normalization).
grep -q '"permission": "allow",' "$TMP/live-edit.yaml" \
  || fail "fixture: string-form permission not passed through verbatim"
! grep -q '"permission": {' "$TMP/live-edit.yaml" \
  || fail "fixture: permission normalized to map form despite no tools filter"

echo "PASS: render-check (defaults clean, live-edit features render)"

# --- C. defaults (no fixture): no filter rendering at all --------------------
! grep -q '"tools"' "$TMP/default.yaml" \
  || fail "defaults: a tools key rendered without config.tools / \$ws.tools set anywhere"
! grep -q '"permission"' "$TMP/default.yaml" \
  || fail "defaults: permission rendered without config.permission or any tools map set"

# --- D. tools fixture: per-workspace filter folded into permission -----------
# The merged tools map renders INSIDE the "permission" object (allow/deny),
# never as a top-level "tools" key -- opencode's last-matching-rule resolution
# lets a catch-all `"*": allow` permission defeat a tools-map deny, while
# toJson's byte-wise key sort ("*" < "srv*" < "srv_tool") makes the folded
# form resolve catch-all < deny-glob < allow-specific. Assertions pin BOTH
# the values AND that ordering contract.
! grep -q '"tools"' "$TMP/tools.yaml" \
  || fail "tools fixture: top-level tools key rendered (must fold into permission instead)"

# 1. workspace "web-app" (declares its own tools map): permission must
#    carry the catch-all plus the merged map -- workspace ADDS example-mcp keys
#    and its playwright* override beats the global false -- in byte order.
WEB_APP_DOC="$(extract_configmap_doc "$TMP/tools.yaml" web-app)"
[ -n "$WEB_APP_DOC" ] \
  || fail "tools fixture: web-app ConfigMap document not found"
WEB_APP_JSON="$(printf '%s' "$WEB_APP_DOC" | extract_opencode_json)"
printf '%s' "$WEB_APP_JSON" | python3 -c '
import json, sys
from collections import OrderedDict
cfg = json.loads(sys.stdin.read(), object_pairs_hook=OrderedDict)
assert "tools" not in cfg, "web-app: top-level tools key must not render"
perm = cfg.get("permission")
assert perm is not None, "web-app: opencode.json missing permission object"
assert perm.get("*") == "allow", f"web-app: catch-all lost, got: {perm}"
assert perm.get("example-mcp*") == "deny", f"web-app: example-mcp* should be deny, got: {perm}"
assert perm.get("example-mcp_post_get") == "allow", f"web-app: example-mcp_post_get should be allow, got: {perm}"
assert perm.get("playwright*") == "allow", f"web-app: playwright* workspace override should win (allow) over the global deny, got: {perm}"
keys = list(perm.keys())
assert keys == sorted(keys), f"web-app: permission keys must render byte-sorted (ordering contract), got: {keys}"
assert keys.index("*") < keys.index("example-mcp*") < keys.index("example-mcp_post_get"), f"web-app: catch-all < deny-glob < allow-specific order broken: {keys}"
' || fail "web-app: permission fold assertion failed (or opencode.json is not valid JSON)"

# 2. workspace "ops" (declares NO tools map): permission must equal the
#    catch-all plus the GLOBAL tools map only -- no example-mcp leakage from
#    the sibling workspace.
OPS_DOC="$(extract_configmap_doc "$TMP/tools.yaml" ops)"
[ -n "$OPS_DOC" ] \
  || fail "tools fixture: ops ConfigMap document not found"
OPS_JSON="$(printf '%s' "$OPS_DOC" | extract_opencode_json)"
printf '%s' "$OPS_JSON" | python3 -c '
import json, sys
cfg = json.loads(sys.stdin.read())
assert "tools" not in cfg, "ops: top-level tools key must not render"
perm = cfg.get("permission")
assert perm == {"*": "allow", "playwright*": "deny"}, f"ops: permission should be catch-all + global map exactly, got: {perm}"
' || fail "ops: permission should equal catch-all + global map only (or opencode.json is not valid JSON)"

echo "PASS: render-check (tools filter folded into permission: merge, ordering contract, omit-when-empty, valid JSON)"

# --- E. git commit identity comes from values, not from the templates -------
# The identity must render in BOTH scripts that set it: the git-init
# initContainer (runs as root, seeds /root/.gitconfig) and the runtime
# container start command (uid 1000). Assertions are scoped to each script
# section so a single templated occurrence cannot satisfy both.
extract_sts_init() {
  awk '/- name: git-init/{f=1} /- name: opencode/{f=0} f'
}
extract_sts_runtime() {
  awk '/- name: opencode/{f=1} f'
}
IDENT_STS="$(extract_sts_doc "$TMP/identity.yaml" autosave-ws)"
[ -n "$IDENT_STS" ] \
  || fail "identity fixture: autosave-ws StatefulSet doc not found"
IDENT_INIT="$(printf '%s' "$IDENT_STS" | extract_sts_init)"
IDENT_RUNTIME="$(printf '%s' "$IDENT_STS" | extract_sts_runtime)"
[ -n "$IDENT_INIT" ] || fail "identity fixture: git-init container section not found"
[ -n "$IDENT_RUNTIME" ] || fail "identity fixture: runtime container section not found"

printf '%s' "$IDENT_INIT" | grep -qF 'git config --global user.name "Example Bot"' \
  || fail "identity fixture: git-init does not take user.name from git.user.name"
printf '%s' "$IDENT_INIT" | grep -qF 'git config --global user.email "bot@example.com"' \
  || fail "identity fixture: git-init does not take user.email from git.user.email"
printf '%s' "$IDENT_RUNTIME" | grep -qF 'git config --global user.name "Example Bot"' \
  || fail "identity fixture: runtime command does not take user.name from git.user.name"
printf '%s' "$IDENT_RUNTIME" | grep -qF 'git config --global user.email "bot@example.com"' \
  || fail "identity fixture: runtime command does not take user.email from git.user.email"

# Defaults (one workspace, no git.user.* set) must carry no baked-in identity.
! grep -q 'opencode@neomanex.com' "$TMP/default-ws.yaml" \
  || fail "defaults: a hardcoded commit identity rendered"

echo "PASS: render-check (git identity templated from git.user.* in both scripts, no hardcoded default)"

# --- F. autosave identity + paths from values, legacy push alias ------------
extract_cronjob_doc() {
  awk -v RS='\n---\n' -v ws="opencode.neomanex.com/workspace: $2" '
    index($0, "kind: CronJob") && index($0, ws) { print; exit }
  ' "$1"
}

# 1. explicit autosave block: identity and paths come from the workspace.
AUTOSAVE_CRON="$(extract_cronjob_doc "$TMP/identity.yaml" autosave-ws)"
[ -n "$AUTOSAVE_CRON" ] \
  || fail "identity fixture: autosave-ws git-sync CronJob doc not found"
printf '%s' "$AUTOSAVE_CRON" | grep -qF 'user.email=autosave@example.com' \
  || fail "identity fixture: autosave block does not take user.email from gitSync.autosave.userEmail"
printf '%s' "$AUTOSAVE_CRON" | grep -qF 'user.name="Autosave Bot"' \
  || fail "identity fixture: autosave block does not take user.name from gitSync.autosave.userName"
printf '%s' "$AUTOSAVE_CRON" | grep -qF 'git add places/' \
  || fail "identity fixture: autosave block does not stage gitSync.autosave.paths"

# 2. legacy `gitSync.push: true` alias (honored one release): the autosave
#    block still renders and the identity falls back to git.user.*.
LEGACY_CRON="$(extract_cronjob_doc "$TMP/identity.yaml" legacy-ws)"
[ -n "$LEGACY_CRON" ] \
  || fail "identity fixture: legacy-ws git-sync CronJob doc not found"
printf '%s' "$LEGACY_CRON" | grep -q 'autosave' \
  || fail "identity fixture: legacy gitSync.push: true no longer renders an autosave block (alias dropped too early)"
printf '%s' "$LEGACY_CRON" | grep -qF 'user.email=bot@example.com' \
  || fail "identity fixture: legacy autosave identity does not fall back to git.user.email"
printf '%s' "$LEGACY_CRON" | grep -qF 'user.name="Example Bot"' \
  || fail "identity fixture: legacy autosave identity does not fall back to git.user.name"

# 3. no autosave configured at all -> no autosave block.
PLAIN_CRON="$(extract_cronjob_doc "$TMP/identity.yaml" plain-ws)"
[ -n "$PLAIN_CRON" ] \
  || fail "identity fixture: plain-ws git-sync CronJob doc not found"
printf '%s' "$PLAIN_CRON" | grep -q 'autosave' \
  && fail "identity fixture: plain-ws renders an autosave block without gitSync.autosave or gitSync.push"

echo "PASS: render-check (autosave identity/paths from values, legacy push alias, opt-out clean)"

# --- H. minimal example (ESO off) is installable ----------------------------
MINIMAL="$CHART_DIR/examples/minimal.yaml"
helm template t "$CHART_DIR" -f "$MINIMAL" > "$TMP/minimal.yaml"
MIN_STS="$(extract_sts_doc "$TMP/minimal.yaml" demo)"
[ -n "$MIN_STS" ] || fail "minimal: demo StatefulSet doc not found"
# Every mounted volume name must be declared (volumes: or volumeClaimTemplates)
MIN_DECLARED="$(printf '%s' "$MIN_STS" | awk '/^      volumes:/{f=1} /^  volumeClaimTemplates:/{f=1} f && /^        - name: /{print $3} f && /^        name: /{print $2}' | sort -u)"
MIN_MOUNTED="$(printf '%s' "$MIN_STS" | awk '/volumeMounts:/{f=1;next} f && /^ *- name: /{print $3;next} f && !/^ *(mountPath|subPath|readOnly):/{f=0}' | sort -u)"
for v in $MIN_MOUNTED; do
  printf '%s\n' "$MIN_DECLARED" | grep -qx "$v" \
    || fail "minimal: volumeMount '$v' has no matching volume (StatefulSet would be rejected by the API server)"
done
MIN_INIT="$(printf '%s' "$MIN_STS" | extract_sts_init)"
! printf '%s' "$MIN_INIT" | grep -q '/mnt/ssh-key' \
  || fail "minimal: git-init still copies /mnt/ssh-key with externalSecrets.enabled: false"
! printf '%s' "$MIN_STS" | grep -q 'GIT_SSH_COMMAND' \
  || fail "minimal: GIT_SSH_COMMAND rendered without an SSH key"
# ESO on: the SSH path still renders in full
helm template t "$CHART_DIR" -f "$MINIMAL" --set externalSecrets.enabled=true > "$TMP/minimal-eso.yaml"
ESO_STS="$(extract_sts_doc "$TMP/minimal-eso.yaml" demo)"
[ -n "$ESO_STS" ] || fail "minimal (ESO on): demo StatefulSet doc not found"
[ "$(printf '%s' "$ESO_STS" | extract_sts_init | grep -c '/mnt/ssh-key')" -ge 2 ] \
  || fail "minimal (ESO on): git-init lost the ssh-key mount or copy"
[ "$(printf '%s' "$ESO_STS" | grep -c 'GIT_SSH_COMMAND')" -eq 2 ] \
  || fail "minimal (ESO on): GIT_SSH_COMMAND must render in both containers"

echo "PASS: render-check (minimal example installable without ESO; SSH path intact with ESO)"

# --- G. identifier check: nothing deployment-specific in the published chart --
# The pattern is generic by design (registry hosts, private git hosts,
# mailboxes); it names no
# specific deployment. Only THIS script is excluded, because it carries the
# pattern; the fixtures under tests/ ARE scanned and are written generically
# for exactly that reason. The label key opencode.neomanex.com/workspace is
# the chart's reserved label namespace and is NOT matched -- keep it that way.
IDENT_PATTERN='pkg\.dev|gcr\.io|gitlab\.com|@neomanex\.com'
IDENT_HITS="$(grep -rniE "$IDENT_PATTERN" "$CHART_DIR" --exclude=render-check.sh || true)"
if [ -n "$IDENT_HITS" ]; then
  echo "$IDENT_HITS" >&2
  fail "identifier check: deployment-specific identifiers present in the chart (see hits above)"
fi

echo "PASS: render-check (identifier check clean)"

# Published text uses plain punctuation only, so no em dash anywhere in the
# chart. The character is built with printf so this script stays free of it and
# is scanned by the same rule as every other file.
EM_DASH="$(printf '\u2014')"
EM_HITS="$(grep -rn "$EM_DASH" "$CHART_DIR" || true)"
if [ -n "$EM_HITS" ]; then
  echo "$EM_HITS" >&2
  fail "punctuation check: em dash present in the chart (see hits above); use a period, comma, colon or parentheses"
fi

echo "PASS: render-check (punctuation check clean)"

# Comments must explain themselves. A reference to a documentation tree that
# ships elsewhere is meaningless to a chart user. Only THIS script is excluded,
# because it carries the pattern.
DOCPATH_HITS="$(grep -rn "documentation/" "$CHART_DIR" --exclude=render-check.sh || true)"
if [ -n "$DOCPATH_HITS" ]; then
  echo "$DOCPATH_HITS" >&2
  fail "internal path check: reference to an external documentation path present in the chart (see hits above)"
fi

echo "PASS: render-check (internal path check clean)"

# The chart label must ignore semver build metadata. A version such as
# 1.4.4+abc123 labels the objects opencode-1.4.4: the label sits in the pod
# template, so anything volatile in it rolls every pod.
cp -R "$CHART_DIR" "$TMP/meta"
sed -E 's/^version: (.*)$/version: \1+abc123/' "$TMP/meta/Chart.yaml" > "$TMP/meta/Chart.yaml.new"
mv "$TMP/meta/Chart.yaml.new" "$TMP/meta/Chart.yaml"
grep -q '^version: .*+abc123$' "$TMP/meta/Chart.yaml" \
  || fail "chart label: could not inject build metadata into the scratch Chart.yaml"
helm template rel "$TMP/meta" > "$TMP/meta.yaml" 2>/dev/null \
  || fail "chart label: render with build metadata failed"
META_LABEL="$(grep -m1 'helm.sh/chart:' "$TMP/meta.yaml" | awk '{print $2}')"
BASE_VERSION="$(sed -nE 's/^version: ([^+]*).*$/\1/p' "$CHART_DIR/Chart.yaml")"
[ "$META_LABEL" = "opencode-$BASE_VERSION" ] \
  || fail "chart label: expected opencode-$BASE_VERSION with build metadata stripped, got '$META_LABEL'"
PLAIN_LABEL="$(grep -m1 'helm.sh/chart:' "$TMP/default.yaml" | awk '{print $2}')"
[ "$PLAIN_LABEL" = "opencode-$BASE_VERSION" ] \
  || fail "chart label: expected opencode-$BASE_VERSION on the default render, got '$PLAIN_LABEL'"

echo "PASS: render-check (chart label strips build metadata)"
