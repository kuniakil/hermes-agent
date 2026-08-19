# Hermes Agent 升級待辦清單 (TODO)

## 📌 下次升級 Docker Image 整合項目 (Fully-Baked Dependencies)

為了確保容器符合「不可變基礎設施（Immutable Infrastructure）」原則，避免運行期動態下載或跨架構殘留問題，在下次升級官方 Release Tag 時，請一併將以下模組編入 `Dockerfile`：

### 1. `Dockerfile` 依賴擴充 (`uv sync`)

將 `Dockerfile` 中的 `uv sync` 指令擴展為包含所有常用/二進制依賴：

```dockerfile
RUN uv sync --frozen --no-install-project \
    --extra all \
    --extra messaging \
    --extra dingtalk \
    --extra feishu \
    --extra matrix \
    --extra voice \
    --extra wake \
    --extra edge-tts \
    --extra exa \
    --extra firecrawl \
    --extra anthropic \
    --extra bedrock \
    --extra azure-identity \
    --extra hindsight \
    --extra otlp
```

#### 包含項目與原因：
- **`--extra voice`**：包含 `faster-whisper`, `sounddevice`, `numpy` 等 C-extensions（已於 v2026.8.18 加入）。
- **`--extra wake`**：包含 `openwakeword`, `onnxruntime`, `sherpa-onnx` 等 C++/ONNX 喚醒詞引擎，避免運行期在 Linux x86_64 上即時編譯/下載。
- **`--extra edge-tts`**：預設 TTS 語音生成引擎。
- **`--extra dingtalk`, `--extra feishu`**：通訊平台擴充支援。
- **`--extra exa`, `--extra firecrawl`**：官方搜尋 Provider SDK。
- **`firecrawl-anydoc` (`tool.doc_extract`)**：文檔解析（PDF, Office 等，含 Rust native bindings），待官方釋出 extra 或直接在 Dockerfile 中 `uv pip install`。

---

### 2. 持久卷 (Persistent Volume `/opt/data`) 定期清理項目

在新 Image 建置並部屬完成後，可排查並刪除 `/opt/data` 歷史動態安裝的舊套件，保持 PV 純粹（只留配置、對話狀態與資料）：

```bash
# 進入容器或透過 kubectl exec
rm -rf /opt/data/lazy-packages
rm -rf /opt/data/.pkgs
rm -rf /opt/data/agent-reach-venv
```

---

### 3. 環境變數傳遞維護確認

- 確認 `docker/stage2-hook.sh` 中 SSH `.bashrc` / `.profile` 自動 source `/run/s6/container_environment/*` 的邏輯有隨新 Tag 保留（避免 SSH session 遺失 `AGENT_BROWSER_EXECUTABLE_PATH`）。
- 確認 K8s Deployment 沒有多餘覆蓋的空環境變數（如 `PYTHONPATH: ""`）。
