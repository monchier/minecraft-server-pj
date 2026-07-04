#!/usr/bin/env bash
# Resolve a CurseForge modpack manifest into comma-separated mod .jar download URLs.
# Used by Terraform's external data source (reads JSON query from stdin, prints JSON).
#
# Requires CURSEFORGE_API_KEY in the environment, or api_key in the query JSON.
# Get a key: https://console.curseforge.com/ → API Keys
set -euo pipefail

API_BASE="https://api.curseforge.com/v1"

query_json=$(cat)
api_key="${CURSEFORGE_API_KEY:-$(echo "$query_json" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("api_key",""))')}"

project_id=$(echo "$query_json" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("project_id",""))')
file_id=$(echo "$query_json" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("file_id",""))')
mc_version=$(echo "$query_json" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("minecraft_version","1.20.1"))')
mod_loader=$(echo "$query_json" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("mod_loader","FORGE"))')

fail() {
  python3 -c "import json,sys; print(json.dumps({'error': sys.argv[1], 'urls': '', 'count': '0'}))" "$1" >&2
  exit 1
}

[ -n "$api_key" ] || fail "CURSEFORGE_API_KEY is not set (export it or pass api_key in query)"
[ -n "$project_id" ] && [ "$project_id" != "0" ] || fail "curseforge_modpack_project_id is not set"

cf_get() {
  curl -fsS -H "x-api-key: $api_key" -H "Accept: application/json" "$@"
}

# Map Forge/FABRIC/... to CurseForge modLoaderType id.
loader_type=$(python3 -c "
loaders = {'FORGE': 1, 'FABRIC': 4, 'QUILT': 5, 'NEOFORGE': 6}
print(loaders.get('${mod_loader}'.upper(), 1))
")

# Pick modpack file: explicit file_id, or latest non-server-pack release for this MC version.
if [ -n "$file_id" ] && [ "$file_id" != "0" ]; then
  pack_file_id="$file_id"
else
  pack_file_id=$(cf_get \
    "$API_BASE/mods/$project_id/files?gameVersion=$mc_version&modLoaderType=$loader_type&pageSize=50" \
    | python3 -c "
import sys, json
data = json.load(sys.stdin).get('data', [])
candidates = [
    f for f in data
    if not f.get('isServerPack')
    and any(gv == '$mc_version' for gv in f.get('gameVersions', []))
]
if not candidates:
    sys.exit('No modpack file found for $mc_version / $mod_loader')
# Prefer Release (1), then newest fileDate.
candidates.sort(key=lambda f: (f.get('releaseType', 0) != 1, -f.get('fileDate', 0)))
print(candidates[0]['id'])
" 2>/dev/null) || fail "Could not find a modpack file for project $project_id ($mc_version / $mod_loader)"
fi

# Download modpack zip and extract manifest.json.
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

download_url=$(cf_get "$API_BASE/mods/$project_id/files/$pack_file_id/download-url" \
  | python3 -c 'import sys,json; print(json.load(sys.stdin)["data"])')

curl -fsSL "$download_url" -o "$tmpdir/modpack.zip"
unzip -q "$tmpdir/modpack.zip" manifest.json -d "$tmpdir"

# Resolve each mod in the manifest to a download URL.
python3 <<PY
import json, os, subprocess, sys

api_base = "$API_BASE"
api_key = "$api_key"
project_id = int("$project_id")
pack_file_id = int("$pack_file_id")
tmpdir = "$tmpdir"

with open(os.path.join(tmpdir, "manifest.json")) as f:
    manifest = json.load(f)

files = manifest.get("files", [])
if not files:
    print(json.dumps({"error": "manifest.json contains no mods", "urls": "", "count": "0"}))
    sys.exit(1)

urls = []
errors = []

for entry in files:
    pid = entry["projectID"]
    fid = entry["fileID"]
    try:
        out = subprocess.check_output(
            ["curl", "-fsS", "-H", f"x-api-key: {api_key}", "-H", "Accept: application/json",
             f"{api_base}/mods/{pid}/files/{fid}/download-url"],
            text=True,
        )
        url = json.loads(out)["data"]
        urls.append(url)
    except subprocess.CalledProcessError as e:
        errors.append(f"projectID={pid} fileID={fid}: {e}")

if errors:
    print(json.dumps({"error": "; ".join(errors), "urls": "", "count": "0"}))
    sys.exit(1)

print(json.dumps({
    "urls": ",".join(urls),
    "count": str(len(urls)),
    "modpack_file_id": str(pack_file_id),
    "modpack_name": manifest.get("name", ""),
    "modpack_version": manifest.get("version", ""),
}))
PY
