# gt-deploy

Deployment config for Gas Town — hooks, scripts, systemd units, and agent context.

The Gas Town Go source lives at [steveyegge/gastown](https://github.com/steveyegge/gastown) (separate repo).

## Quick Start

```bash
# 1. Clone this repo
git clone git@github.com:material-lab-io/gt-deploy.git
cd gt-deploy

# 2. Build the gt binary (separate repo)
git clone https://github.com/steveyegge/gastown.git ~/material-town/gastown
cd ~/material-town/gastown && make build
sudo cp gt /usr/local/bin/gt.new && sudo mv gt.new /usr/local/bin/gt

# 3. Set up secrets
cp .env.example ~/.gt/.env
# Edit ~/.gt/.env — fill in SLACK_BOT_TOKEN

# 4. Install (symlinks everything into place)
./install.sh

# 5. Sync hooks to all agents
gt hooks sync

# 6. Start the Slack relay
systemctl --user start slack-relay
```

## What's Included

| Directory | Contents |
|-----------|----------|
| `hooks/` | Claude Code hooks config (`hooks-base.json`) |
| `scripts/` | Slack relay, reaper, janitor, notification scripts |
| `systemd/` | User-level systemd services and timers |
| `town/` | Town-level config (CLAUDE.md, town.json, rigs.json, etc.) |
| `mayor/` | Mayor agent config and slash commands |
| `setup-hooks/` | Polecat setup hooks (crew memory linking) |
| `agent-context/` | Agent context docs (AGENTS.md, HEARTBEAT.md, TOOLS.md) |

## Secrets

Secrets are stored in `~/.gt/.env` (not checked in). Required variables:

| Variable | Purpose |
|----------|---------|
| `SLACK_BOT_TOKEN` | Slack bot OAuth token for the relay |

## Dry Run

```bash
./install.sh --dry-run
```

Shows what would be symlinked/installed without making changes.
