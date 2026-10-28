# `$DSH_HOME` for a box

The `dsh` profile the box's batch agent runs under, as DATA — four small files
and no credential in any of them.

`profiles/sdk/cordis.patch.yml` is the whole of the OpenRouter route:

    api:        openai-completions
    baseURL:    https://openrouter.ai/api/v1
    apiKeyEnv:  OPENROUTER_API_KEY
    model:      deepseek/deepseek-chat

**`apiKeyEnv` is why this directory is safe to put in the bundle.** `dsh`
reads the key from the named ENVIRONMENT VARIABLE at run time; the value is
never in this tree, never in the tarball, and never in anything synced back.
The value reaches the VM through SkyPilot's `envs`
(`SkyPilotBackend(secret_envs=("OPENROUTER_API_KEY",))`), which resolves it
from the coordinator's own process environment at launch and puts it nowhere
else — see `TaskPlan.secret_envs`.

This lives under `reports/` and not under `src_new/sweep/box/` for the same
reason `manifest.json` does: nothing in the source tree may name an
application or a domain's configuration
(`tests/test_self_contained.py::NoAppPathsInTheSource`).

`dsh` writes `sessions/` and `storages/` under `$DSH_HOME` at run time. They
are deliberately NOT shipped: a box starts with no session history, and the
manifest's `writable` list covers `/home/dev/project` so the directory is
writable once the bundle is unpacked.
