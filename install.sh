#!/usr/bin/env bash
set -euo pipefail

# Gastown unified installer
# Builds the gt binary from src/ and installs deployment config from deploy/

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=true
  echo "🔍 DRY RUN MODE - no changes will be made"
  echo
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$REPO_ROOT/src"
DEPLOY_DIR="$REPO_ROOT/deploy"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() { echo -e "${GREEN}✓${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC} $*"; }
error() { echo -e "${RED}✗${NC} $*"; exit 1; }

# Check prerequisites
command -v go >/dev/null 2>&1 || error "Go is not installed"
command -v make >/dev/null 2>&1 || error "make is not installed"

# 1. Build the gt binary
log "Building gt binary from src/..."
if [[ "$DRY_RUN" == false ]]; then
  cd "$SRC_DIR"
  make build || error "Build failed"
  
  # Install to /usr/local/bin
  sudo cp gt /usr/local/bin/gt.new || error "Failed to copy binary"
  sudo mv /usr/local/bin/gt.new /usr/local/bin/gt || error "Failed to install binary"
  log "Installed gt to /usr/local/bin/gt"
else
  log "[DRY RUN] Would build: cd $SRC_DIR && make build"
  log "[DRY RUN] Would install: sudo cp gt /usr/local/bin/gt"
fi

# 2. Run the deployment installer
log "Running deployment config installer from deploy/..."
if [[ "$DRY_RUN" == false ]]; then
  cd "$DEPLOY_DIR"
  ./install.sh || error "Deployment installation failed"
else
  log "[DRY RUN] Would run: $DEPLOY_DIR/install.sh"
fi

log "Installation complete! 🎉"
log ""
log "Next steps:"
log "  1. Configure secrets: cp deploy/.env.example ~/.gt/.env && vim ~/.gt/.env"
log "  2. Sync hooks: gt hooks sync"
log "  3. Start Slack relay: systemctl --user start slack-relay"
