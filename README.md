# hiveos-vast

The official **HiveOS** client in a Docker image, made for renting GPUs on **Vast.ai**.
Start an instance with your farm hash and it shows up as a worker in your HiveOS
dashboard, where you control it like any rig: flight sheets, miner logs, Hive Shell,
stats.

* The HiveOS client is installed from HiveOS's own signed apt repository at build
time (currently `hive 0.6-231`); nothing in `/hive` is modified.
* Container helpers make HiveOS behave on a rented, shared machine (details below).
* Works with NVIDIA GPUs (what Vast mostly rents). The binaries of T-Rex, Rigel,
lolMiner, BzMiner, GMiner, OneZeroMiner, SRBMiner-Multi, WildRig and miniZ were
checked to load all their libraries in this image.

> \*\*Vast's terms:\*\* Vast's Terms of Service prohibit cryptocurrency mining for users
> who buy their credits \*\*with a credit card\*\* (Prohibited Activities section,
> <https://vast.ai/terms>). Check how your account is funded before mining.

\---

## 1\. Publish the image (once)

Vast pulls images from a registry, so the image has to live somewhere public.

**Option A — GitHub Actions (no Docker needed on your computer)**

1. Create a GitHub repository and upload this folder's contents (keep `.github/`).
2. The workflow in `.github/workflows/publish.yml` builds and pushes
`ghcr.io/<your-github-user>/hiveos-vast:latest` (and a tag with the HiveOS
version, e.g. `:0.6-231`). It runs on every push, weekly (to pick up new HiveOS
releases), and from the Actions tab ("Run workflow").
3. After the first run, make the package public: GitHub → your profile → **Packages**
→ `hiveos-vast` → **Package settings** → **Change visibility** → Public.
4. Optional, Docker Hub too: add repository secrets `DOCKERHUB\_USERNAME` and
`DOCKERHUB\_TOKEN` (Settings → Secrets and variables → Actions). The workflow then
also pushes `<DOCKERHUB\_USERNAME>/hiveos-vast`.

**Option B — build on your own computer**

```bash
docker build -t YOUR\_DOCKERHUB\_USER/hiveos-vast:latest .
docker login
docker push YOUR\_DOCKERHUB\_USER/hiveos-vast:latest
```

Pin a specific HiveOS client with `--build-arg HIVE\_VERSION=0.6-231`.

## 2\. Create the Vast template

In Vast: **Templates** → **New** (or edit your existing template):

|Field|Value|
|-|-|
|Image Path:Tag|`ghcr.io/YOUR\_GITHUB\_USER/hiveos-vast:latest` or `YOUR\_DOCKERHUB\_USER/hiveos-vast:latest`|
|Docker Options|`-e FARM\_HASH=your\_40\_character\_farm\_hash`|
|Launch Mode|**docker ENTRYPOINT** (leave the arguments field empty)|
|Disk Space|16 GB|
|Extra Filters|CUDA (max supported) ≥ 12.0 — see note below|
|Visibility|Private — never make a template public while it holds your farm hash|

Find the farm hash in HiveOS: **Farm → Settings → Hash**.

Rather keep the hash out of the template? Put `FARM\_HASH` under **Account Settings →
Environment Variables** in Vast instead; Vast injects those into every instance.

Same template from the Vast CLI:

```bash
vastai create template \\
  --name "HiveOS" \\
  --image YOUR\_DOCKERHUB\_USER/hiveos-vast --image\_tag latest \\
  --env "-e FARM\_HASH=your\_40\_character\_farm\_hash" \\
  --search\_params "cuda\_vers>=12.0" \\
  --disk\_space 16
```

(No `--ssh`/`--jupyter` flag means "docker ENTRYPOINT" mode.)

### Want SSH access to the instance as well?

Use Launch Mode **Interactive shell server, SSH** and put this single line in the
**On-start Script**:

```bash
/usr/local/bin/hiveos-vast-onstart
```

In SSH/Jupyter modes Vast replaces the image's entrypoint, so HiveOS is started from
the on-start script; its log goes to `/var/log/hiveos-vast.log`.
**Do not** add the `env >> /etc/environment` line that Vast's docs suggest: in this
image `/etc/environment` is HiveOS's own settings file, and appending the container's
variables breaks HiveOS and copies your credentials into it.

You usually don't need SSH: HiveOS's **Hive Shell** (worker → Remote access) gives you
a terminal from the dashboard.

## 3\. Rent and mine

1. Rent an instance with the template.
2. Within a minute a worker named `vast-<instance id>` appears in your farm.
3. Apply a flight sheet to it. HiveOS installs the miner and starts it.

To control many instances, select the workers in HiveOS and apply the flight sheet in
bulk. To mine immediately on boot, create the worker in HiveOS first, give it a flight
sheet, and start the instance with `RIG\_ID` + `RIG\_PASSWD` instead of `FARM\_HASH`
(one instance per worker).

\---

## Settings (environment variables)

|Variable|Meaning|
|-|-|
|`FARM\_HASH`|Farm hash. Creates a worker automatically on the first start.|
|`RIG\_ID`, `RIG\_PASSWD`|Use an existing worker instead (from its settings in HiveOS).|
|`WORKER\_NAME`|Name for a worker created with `FARM\_HASH`. Default `vast-<Vast instance id>`. Leave it unset when you run several instances, so each gets its own name.|
|`HIVE\_HOST\_URL`|HiveOS API server. Default `http://api.hiveos.farm`.|
|`LOG\_MINER`|`1` (default) copies the miner console to the instance log; `0` turns that off.|

`rig\_id` / `rig\_pass` (the names Clore.ai uses) are accepted too.

Check a configuration without starting anything: `hiveos-vast-start --check`
(prints the mode, the GPUs and whether the HiveOS API is reachable).

## Logs

* **docker ENTRYPOINT mode:** the instance's **Logs** button in Vast shows the start-up
steps, the HiveOS agent log and the miner console.
* **SSH mode:** `tail -f /var/log/hiveos-vast.log`.
* Either mode, from Hive Shell or SSH: `miner` (attach to the miner screen, detach with
Ctrl+A then D), `miner log`, `agent-screen log`.

A healthy start looks like:

```
\[hiveos-vast] HiveOS client 0.6-231 in a container
\[hiveos-vast] Mode: FARM\_HASH (on first start HiveOS creates a worker named 'vast-12345678')
\[hiveos-vast] GPUs assigned to this container:
\[hiveos-vast]   GPU 0: NVIDIA GeForce RTX 4090 (UUID: GPU-…)
\[hiveos-vast] PCI: assigned GPU slots: 0000:41:00; NVIDIA PCI functions in host: 16, hidden from HiveOS: 14
\[hiveos-vast] HiveOS sees 1 NVIDIA GPU(s)
\[hiveos-vast] Connecting to HiveOS (http://api.hiveos.farm), attempt 1
\[hiveos-vast] hello: > Sending Hello
\[hiveos-vast] hello: OK
\[hiveos-vast] Connected as worker 'vast-12345678' (RIG\_ID 1234567)
\[hiveos-vast] Starting the HiveOS agent
\[hiveos-vast] Starting the miner from the worker's flight sheet
\[hiveos-vast] HiveOS is running. Control the miner from your HiveOS dashboard.
```

## What differs from a HiveOS rig

A rented container shares a machine with other people and doesn't own the hardware.

|HiveOS feature|In this image|
|-|-|
|Flight sheets, miners, stats, hashrate, Hive Shell, remote commands, self-upgrade|Work normally|
|Overclocking, power limits, fan control (`nvidia-oc`, `amd-oc`, `autofan`, `tweakers`)|Disabled; the host controls them. The OC log in the dashboard says so.|
|NVIDIA driver updates|Disabled; the driver belongs to the host. Pick hosts by CUDA version instead.|
|Reboot (dashboard or watchdog)|Restarts the HiveOS miner and agent. Rate-limited (60 s; 15 min for the watchdog's load-average reboot, because inside a container the load average is the whole host's).|
|Shutdown (dashboard)|Stops the miner. To stop paying, stop or destroy the instance in Vast.|
|AMD GPUs|Not supported.|

### What the container helpers do

|Helper|Why|
|-|-|
|`hiveos-vast-start` (entrypoint)|Replaces HiveOS's machine boot script: writes `rig.conf` from your variables, registers the worker, starts the agent, miner and watchdog, streams logs, stops cleanly on `docker stop`. On restarts it reuses the registered worker so `FARM\_HASH` doesn't create duplicates.|
|`lspci` filter|Inside a container `lspci` lists every GPU in the host, including cards rented to other people. HiveOS would count them and mark them failed. The filter hides cards the NVIDIA driver doesn't give this container.|
|CUDA runtime links|Runs HiveOS's own `nvidia-driver-update --cuda` at start, so `/hive/lib/libcudart.so`, `libnvrtc.so` and `libnvrtc-builtins.so` match the host driver (CUDA 11, 12 or 13). Miners such as T-Rex load these by name.|
|OpenCL ICD file|`/etc/OpenCL/vendors/nvidia.icd`, so OpenCL miners find the NVIDIA driver.|
|`lsmod`|HiveOS disables NVIDIA GPUs when `lsmod` doesn't list the `nvidia` module, which can happen in a container.|
|`systemctl`, `reboot`, `shutdown`, `update-grub` stubs|No systemd or bootloader in a container.|
|`tini`|Proper PID 1: reaps the many short-lived processes HiveOS spawns and passes on stop signals.|

## Troubleshooting

* **"HiveOS rejected this worker's credentials"** — wrong `FARM\_HASH`, or wrong
`RIG\_ID`/`RIG\_PASSWD`. The line above it shows HiveOS's message ("Farm not found",
"Worker not found"). The container stops so you aren't billed for an idle GPU.
* **"could not reach HiveOS; retrying"** — network trouble; it retries until it connects.
* **Miner fails with CUDA errors** — the host driver is too old for that miner version.
Raise the CUDA filter (e.g. 12.4+ or 12.8+ for RTX 50-series) or pick an older miner
version in the flight sheet.
* **Old workers pile up in HiveOS** — every new instance started with `FARM\_HASH`
registers a new worker; destroyed instances leave theirs behind. Delete them in the
dashboard, or use `RIG\_ID`/`RIG\_PASSWD` to reuse a worker.
* **"no NVIDIA GPU is visible in this container"** — the instance has no GPU attached;
only CPU mining can work.

## Security notes

* Use a **separate HiveOS farm** for rented GPUs. Whoever runs the host machine can,
in principle, read anything in your container, including the farm hash or worker
password. A farm hash lets someone add workers to that farm, so keep it apart from
your own rigs.
* Keep templates that contain credentials private.

## Existing images (surveyed October 2026)

|Image|Notes|
|-|-|
|`cloreai/hiveos`|Most pulled (270k+), made for Clore.ai, last updated Feb 2025. Ships a frozen copy of `/hive` from early 2025 rather than the packaged client, plus CUDA 11.7 and NVIDIA 515 driver libraries baked in.|
|`shatll/hiveos`, `grinvest/hiveos`, `neuroai/hiveos`|Built on `cloreai/hiveos:0.4` with extra miners. `shatll` injects an opaque `LD\_PRELOAD` library (`redirect.so`) into miniZ.|
|`forsbors/hiveos`|One squashed layer with no build history; can't be audited.|
|`hanaik/hiveos`|Ships its author's own HiveOS worker credentials as default variables: if one of yours is missing or misspelled, your GPU mines on the author's worker. Avoid.|
|`clusmi/hiveostemplate`|The closest existing match: current HiveOS 0.6-231 from the signed repo (verified byte-identical to the official package) with sensible container shims. Lacks the CUDA runtime links (T-Rex-style miners fail) and the OpenCL ICD file; single unknown maintainer, so pin it by digest if you use it.|



