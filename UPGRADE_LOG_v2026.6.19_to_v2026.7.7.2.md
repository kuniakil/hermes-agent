# Upgrade Log: v2026.6.19 → v2026.7.7.2

## Date: 2026-07-12

## Summary

成功將 Hermes Agent 從 `v2026.6.19`（官方 `v0.17.0`）升級到 `v2026.7.7.2`（官方 `v0.18.2`）。

## Branch Structure

| Branch | Version | Status |
|--------|---------|--------|
| `backup/my-config-v2026.6.19` | v2026.6.19 | 舊版備份分支 |
| `my-config-v2026.7.7.2` | v2026.7.7.2 | 升級後新分支 |

## Official Changes (v0.18.2)

### 重大新功能與變更
- **lazy-packages 新機制**：引進 `HERMES_LAZY_INSTALL_TARGET=/opt/data/lazy-packages`，解決了 runtime lazy_deps 的寫入問題，同時保持 `/opt/hermes/.venv` 處於 sealed 狀態。
- **COPY 優化**：使用 `COPY --link --chmod` 提升 Docker Image 建置效率，大幅縮短建置時間。
- **Baileys 依賴修正**：修復了 WhatsApp Baileys 依賴對應的 git commit 問題，改用正式釋出的 `7.0.0-rc13` 版本。

## Custom Commits Applied

我們重新 cherry-pick 並套用了以下自定義提交：

| Commit | Description |
|--------|-------------|
| `73b0ecaf3` | feat: integrate SSH into official s6-overlay architecture |
| `aa9283d68` | chore: add .env with HERMES_IMAGE for docker-compose |
| `2eb8b970b` | chore: add ghcr-publish workflow for Docker image build |
| `1ec45e5f8` | feat: add entrypoint-ssh.sh for Zeabur compatibility |
| `10b755299` | fix: handle non-PID 1 environment (Zeabur) |
| `ec125c963` | fix: use su-exec instead of main-wrapper.sh for Zeabur |
| `0d457f64a` | fix: use su instead of su-exec for Zeabur |
| `4546183f8` | chore: restore docker-compose.yml from my-config-v2026.5.16 |
| `f3c1955c5` | fix(docker): export HERMES_TUI_DIR in SSH session rc to skip runtime npm install |
| `3cc124710` | docs: add GEMINI.md upgrade SOP and behavior rules |
| `00b0530ad` | docs: update GEMINI.md upgrade SOP to use GitHub CI/CD |
| `c356e7e19` | docs: improve GEMINI.md conflict guidelines |
| `9f880affc` | docs: update upgrade log to document hotfixes and C/C++ toolchain addition |
| `1ee05f697` | docs: add upgrade log v2026.6.5→v2026.6.19, update GEMINI.md SOP, restore v5.16 upgrade log |
| `56646cdf1` | docs: document SSH hermes --tui EACCES hotfix in upgrade log |
| `975af3dc7` | chore: bump HERMES_IMAGE tag to v2026.7.7.2 |

## 捨棄的 Commits

以下與 venv 寫入及 edge-tts 安裝相關的舊版自定義 commits 均已被官方 `lazy-packages` 封裝設計完美取代，故在本次升級中直接捨棄，使專案結構更貼近官方原生設計：
- `f1ce436cf` (venv write access)
- `ae85a8ad4` (stage2-hook venv permission)
- `e819fdb25` (venv chown at build time)
- `af397b491` (g++ build-essential) - *官方已原生整合*
- `c9b73542f` / `624a8591a` / `aab395f41` (edge-tts 相關)

## Testing Results

| Test Target | Status | Notes |
|-------------|--------|-------|
| git cherry-pick | ✅ Success | 除 edge-tts 因空提交跳過外，其餘全數成功自動合併，無衝突。 |
