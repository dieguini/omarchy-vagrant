# Azure DevOps from the VM

`azure-cli` comes from the `packages` list; the `az repos`, `az pipelines` and
`az boards` subcommands live in a separate extension, declared per machine:

```json
{
  "packages": ["azure-cli"],
  "az_extensions": ["azure-devops"]
}
```

```powershell
vagrant provision --provision-with azure
```

## Signing in

Two different logins, and they are not interchangeable.

**`az login`** authenticates the CLI. In a VM with no default browser wired up,
use the device code flow:

```bash
az login --use-device-code
```

It prints a code, you open the URL in the VM's Chromium and paste it. Add
`--tenant <tenant-id>` if your account spans several tenants.

**Git over HTTPS** does *not* use that session. Cloning a repo asks for a
username and password, where the password is a **Personal Access Token** from
Azure DevOps (User settings → Personal access tokens), scoped to *Code: Read*
or *Read & write*.

The `git-identity` provisioner points git's credential helper at
`git-credential-libsecret`, so that PAT lands in the desktop keyring rather
than in plaintext at `~/.git-credentials`. You type it once.

## Day to day

```bash
# Point the CLI at your organisation and project once
az devops configure --defaults \
  organization=https://dev.azure.com/<org> project=<project>

# What's there
az repos list -o table
az pipelines list -o table
az boards work-item show --id 1234

# Clone (asks for the PAT the first time, then the keyring answers)
git clone https://dev.azure.com/<org>/<project>/_git/<repo> ~/Work/<repo>

# Or let the CLI work out the URL
az repos list --query "[?name=='<repo>'].webUrl" -o tsv
```

## SSH instead of a PAT

If you'd rather not handle tokens, Azure DevOps takes SSH keys:

```bash
ssh-keygen -t ed25519 -C "omarchy-vm"
cat ~/.ssh/id_ed25519.pub     # paste into User settings → SSH public keys
git clone git@ssh.dev.azure.com:v3/<org>/<project>/<repo>
```

A key generated inside the VM never leaves it, and `vagrant destroy` disposes
of it — which is the right lifecycle for a disposable machine. Remember to
remove the public key from Azure DevOps when you retire the VM.

## A word on scope

This VM has a weak password and passwordless sudo. Whatever you authenticate
here is reachable by anything running in it, including agents started in
permissive mode. Prefer a PAT scoped to the one project you're working on, with
a short expiry, over a broad token or a full `az login` to a production tenant.
