# Gastown

A fork of [Git Town](https://github.com/steveyegge/gastown) customized for Material Lab's agent workflow with integrated deployment config.

## Quick Start

```bash
# Clone this repo
git clone git@github.com:material-lab-io/gastown.git
cd gastown

# Install (builds gt binary + deploys all config)
./install.sh

# Sync hooks to all agents
gt hooks sync

# Start the Slack relay
systemctl --user start slack-relay
```

## What's Included

### Source (`src/`)
- Custom Git Town fork with Material Lab enhancements
- Auto-creates crew agent beads on `gt crew start`
- Enriched `gt convoy list --json` with tracked issues
- Improved `gt status` agent liveness checks
- Configurable timeout for migration step commands

### Deployment (`deploy/`)

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

Secrets are stored in `~/.gt/.env` (not checked in). Required:

| Variable | Purpose |
|----------|---------|
| `SLACK_BOT_TOKEN` | Slack bot OAuth token for the relay |

Create from template:
```bash
cp deploy/.env.example ~/.gt/.env
# Edit ~/.gt/.env — fill in SLACK_BOT_TOKEN
```

## Development

Build the binary:
```bash
cd src && make build
```

Run tests:
```bash
cd src && make test
```

## Dry Run

Preview what will be installed:
```bash
./install.sh --dry-run
```

## Architecture

This repo combines two previously separate repos:
- **gastown** (Go source, forked from steveyegge/gastown)
- **gt-deploy** (deployment config and agent context)

Now maintained as a single, self-contained deployable unit.
