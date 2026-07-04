###############################################################################
# CurseForge modpack sync (optional).
#
# When curseforge_modpack_project_id is set, Terraform resolves the modpack's
# manifest.json via the CurseForge API and uses those download URLs on the
# server. Add mod_urls_extra for jars not in the pack (e.g. Modrinth-only mods).
#
# Requires CURSEFORGE_API_KEY in the environment during plan/apply:
#   export CURSEFORGE_API_KEY="your-token"   # https://console.curseforge.com/
###############################################################################

data "external" "curseforge_mod_urls" {
  count = var.curseforge_modpack_project_id > 0 ? 1 : 0

  program = ["${path.module}/../scripts/resolve-curseforge-modpack.sh"]

  query = {
    project_id        = tostring(var.curseforge_modpack_project_id)
    file_id           = var.curseforge_modpack_file_id > 0 ? tostring(var.curseforge_modpack_file_id) : ""
    minecraft_version = var.minecraft_version
    mod_loader        = var.mod_loader
    api_key           = var.curseforge_api_key
  }
}

locals {
  curseforge_mod_urls = var.curseforge_modpack_project_id > 0 ? (
    compact(split(",", try(data.external.curseforge_mod_urls[0].result.urls, "")))
  ) : []

  # CurseForge modpack URLs + any extra manual URLs (Modrinth-only mods, etc.).
  effective_mod_urls = var.curseforge_modpack_project_id > 0 ? concat(
    local.curseforge_mod_urls,
    var.mod_urls_extra,
  ) : var.mod_urls
}
