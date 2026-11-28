# UPGRADE LOG: v0.23.4 → v0.23.5

Branch: `my-config-v0.23.5` (built from `upstream-v0.23.5` = `a428f5344f777ccafe389c79d5b09384abef1437`)
Image: `ghcr.io/kuniakil/hermes-agent:v0.23.5`
Date: 2026-11-28

---

## 1. Scope

Official patch release rolling up **1,262 non-merge commits / 1,146 changed files / 338 merged PRs**
since v0.23.4 (official release notes, measured at commit `a428f5344f77`). Upstream states the
curated notes for this window ship with v0.24.0, so the audit below is diff-driven.

## 2. Irreversibility verdict: none

| Surface | v0.23.4 | v0.23.5 | Verdict |
|---|---|---|---|
| DB `SCHEMA_VERSION` | 33 | 33 | unchanged |
| `FTS_STORAGE_VERSION` | 3 | 3 | unchanged |
| `_schema_ddl.py` (whole-file md5) | `f222649b1a2050ee3c3929679b7d6211` | same | byte-identical → no DDL change → no FTS rebuild |
| config `_config_version` | 54 | 54 | unchanged → **no config migration fires** |
| config `SUPPORT_FLOOR_VERSION` | 12 | 12 | unchanged |
| `pyproject.toml` / `uv.lock` / `pnpm-lock.yaml` / `package.json` | — | upstream changed none | no dependency work, no audit remediation |
| `Dockerfile` / `docker/entrypoint-ssh.sh` / `docker-compose.yml` / `.env.example` / `AGENTS.md` | custom layer | upstream changed none | custom layer has zero overlap |

Rollback therefore only needs the previous image tag — **no `state.db` restore**.

## 3. Conflict surface (measured, not assumed)

`git merge-tree --write-tree upstream-v0.23.5 my-config-v0.23.4`:

- 21 × `CONFLICT (modify/delete)` — **all** under `.github/workflows/`, absorbed by the existing
  workflow purge.
- `Auto-merging docker/stage2-hook.sh` — clean (our SSH block sits near line 73; upstream's changes
  are near line 668).
- `Auto-merging hermes_cli/models_catalog_static.py` — clean (we touch the MiniMax rows, upstream
  touches the Gemini rows).

**Real content conflicts: 0.**

## 4. Custom patches carried over

| Commit | Purpose |
|---|---|
| `96e8962716` | re-port custom Docker layer (SSH, locales, extras, perms) |
| `6f8e4d0724` | `docker/stage2-hook.sh` SSH setup + npm cache handling |
| `c184d34ee6` | bake `--extra stt-whisper` (faster-whisper + av) into the image |
| `92571dc75d` | restore `docker/entrypoint-ssh.sh` (Zeabur compatibility) |
| `aa5e3319c0` | carry forward `docker-compose.yml` (HERMES_IMAGE, TZ=Asia/Taipei) |
| `9c45cf3c10` | MiniMax static catalog → `MiniMax-M3.1-Flash`, `MiniMax-M3` |
| `0b5712eca8` / `06a03ee802` | `.env.example` HERMES_IMAGE → `v0.23.5` |
| `6672ca6246` | purge official CI workflows; keep only `ghcr-publish.yml` |

## 5. Behavioural deltas found by diff audit (upstream notes omit them)

1. **Google AI Studio removed from the static model catalog.** `_PROVIDER_MODELS["gemini"]`,
   the `CANONICAL_PROVIDERS` row, the `google` provider group and the
   `google` / `google-gemini` / `google-ai-studio` aliases are all gone. Upstream also added
   `static_catalog_providers()`, which splices plugin providers ahead of built-ins — provider
   picker ordering changes. Our deployment uses the `minimax` provider, which is untouched.
2. **New bounded default-plugins preflight before the local gateway starts** (Docker, Desktop,
   CLI). `docker/stage2-hook.sh` now runs
   `python -m hermes_cli.default_plugins ensure --json --timeout 300` before the supervised
   services come up; it is skipped when `HERMES_CONFIG_BACKEND=remote`, and a non-zero exit only
   warns. Verified benign in our deployment: the live catalog currently marks **zero** plugins as
   `default`, so the preflight fetches the catalog and installs nothing.
3. **Dependency-generation collection rewritten** in `docker/stage2-hook.sh`: a selection that is
   already the image's own environment now boots that environment instead of rebuilding a copy on
   the volume, and a volume with no room falls back to the image environment.
4. **`hermes_cli/memory_provider_migration.py`**: a memory provider plugin named in
   `plugins.disabled` is now installed but **left off** (with a hint to run
   `hermes plugins enable`), instead of being force-enabled.
5. **`tui.program_resume` added** to `DEFAULT_CONFIG` (OSC 7577 resume reporting). Additive;
   `_config_version` was not bumped, so existing homes fall back to the code default.

## 6. Verification performed

- Backup of the data volume taken via tar streaming and independently validated: gzip integrity
  OK, `state.db` `PRAGMA integrity_check` = ok (schema 33, 48 tables), `config.yaml`
  `_config_version` = 54.
- GHCR build run: `prepare` + both arch build jobs + `merge` manifest job all green; image tags
  `v0.23.5` and `latest` verified.
- Rollout completed; the running image reports `v0.23.5` and its upstream commit matches this
  branch's HEAD.
- Gateway health endpoint returns `{"status": "ok", "version": "v0.23.5"}`.
- Custom layers verified in the running container: `C.UTF-8` locale, `sshd`, `rsync`, `tini`,
  `HOME=/opt/data`, `faster_whisper` + `av` in the sealed venv, sticky `/tmp/.npm-cache`.
- **Zero ERROR / CRITICAL log lines** after rollout (counted with the log's own
  space-separated timestamp format; the counting method was validated against the 388 historical
  ERROR lines so a zero is a real zero, not a grep artefact).
- Disk baseline re-measured after the upgrade and **identical to the pre-upgrade measurement**
  (`/opt/data`, `cache/uv`, `installs`, huggingface) — the preflight added nothing.
- **No memory embedding index rebuild** was performed, and none was needed: the DB schema, the
  embedding model and the embedding input format version are all unchanged.

## 7. Notes for the next upgrade

- `hermes doctor`'s disk warning remains unreliable (`hermes_cli/doctor_state.py` only scans
  `<HERMES_HOME>/cache/uv` and only warns above 1 GiB). Measure the uv caches directly.
- The `⚠ install out of sync (pnpm: not installed or outdated)` line at boot is **pre-existing**
  (it also appears in the previous release's logs) — not a regression from this upgrade.
