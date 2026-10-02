# Haku Local LLM Server

Local language-model serving for Haku's Pepper robot conversation pipeline. This repository supplies an Ollama Docker launcher, model-management scripts, and Modelfiles that guide responses towards short spoken dialogue with robot behaviour commands.

Inference runs on a workstation rather than Pepper. The web controller calls Ollama's native HTTP API and forwards streamed responses to the robot handler for speech and animation.

## What is included

- A GPU-enabled Ollama container with persistent model data in the repository mount.
- Scripts to create, preload, attach to, stop, and replace a custom model.
- Robot-specific system prompts, behaviour vocabulary, and conversation-ending tags.
- Alternative Modelfiles for different interaction contexts.

This repository does not include the browser controller, speech recognition, a model-weight download checked into Git, or a separate API server implementation. Ollama supplies the HTTP service.

## Requirements

- Bash, Docker, and curl on the host.
- An NVIDIA GPU, compatible driver, and NVIDIA Container Toolkit: `scripts/docker-run` always uses `--gpus=all`.
- Enough GPU/system memory and disk space for the selected base model and workload. The supplied alternatives use Mistral Small 3.1 24B; there is no documented minimum VRAM benchmark for this project.
- Internet access for the container image and initial model downloads.

## Quick start

```bash
git clone https://github.com/S3942721/robo-llm-server.git
cd robo-llm-server
./scripts/docker-run
./scripts/model-run
```

The launcher creates a container named `ollama`, mounts this repository at `/root/.ollama`, and publishes host port `11434`. It removes any existing container with the configured name before launching, so use a different `CONTAINER_NAME` if that name belongs to another service. Downloaded models persist in the host mount; stopping/removing the container does not remove those files.

`model-run` attempts to create the custom model when missing, starts it detached by default, and sends a preload request. Model creation/downloads can take time. If you've edited a Modelfile, explicitly recreate the model rather than relying on `model-run` to update an existing one.

## Verify the API

```bash
curl http://localhost:11434/api/tags
curl http://localhost:11434/api/generate \
  -H 'Content-Type: application/json' \
  -d '{"model":"Haku","prompt":"Introduce yourself briefly.","stream":false}'
```

Use the model name returned by `/api/tags` consistently in clients. The script default is `Haku`; the controller's example `.env` uses `haku` and should be aligned with the created model.

Configure the web controller:

```dotenv
LLM_PROVIDER=ollama
OLLAMA_HOST=192.168.1.10
OLLAMA_PORT=11434
OLLAMA_MODEL=Haku
OLLAMA_TIMEOUT=120000
```

Replace the address with the Ollama host; use `127.0.0.1` when both services run on the same host. The controller's `utils/ollama-client.js` calls `/api/generate` and reads newline-delimited streaming JSON. `OLLAMA_HOST` is a bare hostname/IP, not a URL. For streamed testing, change `"stream":false` to `true` in the curl request.

The container publishes the API on the host without authentication. Keep access within the intended service network.

## Script reference

Run commands from this repository's root.

| Command | Purpose |
| --- | --- |
| `./scripts/docker-run` | Recreate and start the GPU-enabled Ollama container |
| `./scripts/docker-attach` | Open a shell in the container |
| `./scripts/model-run` | Create the configured model if needed, run detached, and preload |
| `./scripts/model-run --attach` | Run an interactive model session |
| `./scripts/model-attach` | Open an interactive session with the configured model |
| `./scripts/model-stop` | Unload the configured model |
| `./scripts/model-stop --rm` | Unload and remove the custom model |
| `./scripts/model-set BASE_MODEL` | Change the active Modelfile's `FROM` line and recreate the custom model |
| `./scripts/model-set --file PATH` | Replace the active Modelfile and recreate the custom model |

Model commands accept `--name` and `--container` overrides. `model-set` stops and removes the existing custom model before recreating it. On failure it attempts to restore the host Modelfile, but does not guarantee restoration of the previous model instance.

To apply edits to the current Modelfile without copying it onto itself:

```bash
. ./scripts/config.sh
docker exec "$CONTAINER_NAME" ollama create "$MODEL_NAME" -f "$CONTAINER_MODELF"
./scripts/model-run
```

## Configuration

[scripts/config.sh](scripts/config.sh) resolves configuration from environment variables; it does **not** load a `.env` file. Export overrides before running scripts so every invocation sees the same settings.

| Variable | Default | Purpose |
| --- | --- | --- |
| `CONTAINER_NAME` | `ollama` | Docker container name |
| `MODEL_NAME` | `Haku` | Custom Ollama model name |
| `HOST_REPO_DIR` | Repository root | Host directory mounted into the container |
| `CONTAINER_REPO_DIR` | `/root/.ollama` | Container mount / Ollama data directory |
| `HOST_MODELF` | Root `Modelfile`, then `models/modelfiles/Modelfile` | Active host Modelfile |
| `CONTAINER_MODELF` | Mapped host Modelfile path | Active Modelfile inside the container |

The launcher also sets `OLLAMA_KEEP_ALIVE=-1`, `OLLAMA_MAX_LOADED_MODELS=4`, and `OLLAMA_NUM_PARALLEL=3`. These are launcher settings rather than variables exposed by `config.sh`; edit the launcher if you need different resource behaviour.

Select a different checked-in prompt without overwriting the default:

```bash
export HOST_MODELF="$PWD/models/modelfiles/ModelfileFast"
./scripts/docker-run
./scripts/model-run --name HakuFast
```

Keep `HOST_MODELF` set when running subsequent model commands. Changing it does not automatically replace an already-created model with the same name.

## Prompts and response format

| File | Base model declared in the file | Role |
| --- | --- | --- |
| [Modelfile](models/modelfiles/Modelfile) | `LoTUs5494/mistral-small-3.1:latest` | Default Haku prompt |
| [ModelfileFast](models/modelfiles/ModelfileFast) | `mistral-small3.1:24b` | Alternative conversational prompt |
| [ModelfileCityNorth](models/modelfiles/ModelfileCityNorth) | `mistral-small3.1:24b` | City North interaction prompt |

The prompts request concise Australian English suitable for text-to-speech, behaviour commands such as `^start(hey)` / `^wait(hey)`, and a final `{conversation_ongoing: True|False}` tag. The word "Fast" is a filename, not a measured latency claim. Keep prompt behaviour names aligned with the handler's catalogue and installed robot behaviours.

An illustrative response:

```text
^start(hey) Hi, I'm Haku. How are you today? ^wait(hey) {conversation_ongoing: True}
```

Prompt instructions do not enforce a schema or guarantee valid behaviour markup. The controller and handler still need to buffer and sanitise generated text. Review event-specific facts and behaviour names before reusing a prompt for a different deployment.

## Troubleshooting

- **Docker reports no GPU device driver:** verify NVIDIA driver and Container Toolkit installation; the supplied launcher has no CPU fallback flag.
- **Model not found:** inspect `docker exec ollama ollama list` and `/api/tags`, then align the client and script names.
- **Connection refused:** check `docker ps`, `docker logs ollama`, the `11434` mapping, and the client's host address.
- **Out of memory / timeouts:** inspect model size and competing workloads, and reduce launcher concurrency or choose a smaller base model. Increase the controller timeout only after checking model loading.
- **Prompt edits have no effect:** recreate the custom model explicitly; `model-run` is not a prompt-update command.
- **Missing Modelfile:** check the host path and its mapped container path using `scripts/config.sh`.

Model data under `models/blobs/` and `models/manifests/` is ignored by Git. Do not add downloaded weights or local runtime data to commits.

## Related services and licence

See [Haku Control System](https://github.com/S3942721/haku_control_system) for the complete deployment and [Robot Web Controller](https://github.com/S3942721/robo-web-controller) for conversation routing.

Repository code is distributed under [GPL-3.0](LICENSE). Ollama and each base model have separate licences and usage terms.
