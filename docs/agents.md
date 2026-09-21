# Coding agents in the VM

Omarchy has a first-class notion of a **default coding agent**. This is how it
works, read out of `omarchy-default-agent` and `omarchy-agent` on the VM — the
mechanics aren't in the manual.

## Setting one

```json
{ "default_agent": "claude" }
```

Then `vagrant provision --provision-with agent`. Leave it empty and nothing is
touched; Omarchy deliberately ships with no default.

Thirteen agents are supported: `pi`, `omp`, `opencode`, `claude`, `codex`,
`grok`, `gemini`, `openclaw`, `hermes`, `copilot`, `crush`, `cursor-agent`,
`muse`.

## What it actually does

Two things, which is why the provisioner can replicate it:

1. **Installs the agent through `mise`** — `mise use -g <package>`. The package
   is the agent's name, except `grok` (`npm:@xai-official/grok`), `omp`
   (`github:can1357/oh-my-pi`) and `muse` (Meta's own launcher). `openclaw` and
   `hermes` go through their own installers instead, because they need a pinned
   interpreter.
2. **Records the choice** in `~/.config/omarchy/defaults/agent`, one line.

`omarchy default agent <name>` does both and then `exec`s the agent, which is
fine for a human and fatal in a provisioner — hence doing the halves directly.

> **Don't install the agent some other way.** `omarchy-default-agent` only
> recognises a pre-existing install at `~/.local/bin/<agent>`. A pacman package
> in `/usr/bin` is invisible to that check, so using the menu later installs a
> second copy through mise and you end up with two, updated by two different
> things. This repo learned that the hard way.

## Using it

| Command | What it does |
|---|---|
| `omarchy agent` | Launches the default agent in a floating terminal |
| `omarchy agent --inline` | In the current terminal instead |
| `omarchy agent prompt "…"` | Launches it with a prompt |
| `omarchy agent crash <pid>` | Hands a crashed process to it to diagnose |
| `omarchy agent usage …` | Usage data, with per-agent views |

Two details worth knowing:

- Claude is launched as `claude --permission-mode auto`. Other agents get their
  equivalent (`--yolo`, `--approval-mode never`), so **the agent starts with
  approvals relaxed**. That is the intended experience inside a machine you can
  destroy; it is also the reason to keep credentials out of this VM.
- Launching from `$HOME` changes directory to `~/Work` first, because agents
  won't remember trust for `$HOME`. The provisioner creates that folder.

## Signing in

The provisioner installs the agent and nothing else. Authentication is yours:
open a terminal in the VM and run the agent once — for Claude Code, `claude` —
which opens a browser to log in.

## Why bother running an agent in here

Not capability — blast radius. An agent in this VM has the repos, Terraform and
Docker it needs, cannot reach the Windows host, and anything it breaks is undone
by `vagrant destroy`. The relaxed permission mode above is much easier to live
with when the worst case is fifteen minutes of rebuild.

The flip side: this is a disposable VM with a weak password and passwordless
sudo. Before giving an agent in here real credentials — cloud, compliance tools,
anything — change the password and use short-lived, read-only ones.
