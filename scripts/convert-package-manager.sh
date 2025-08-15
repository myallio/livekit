#!/bin/bash

set -e

# Configuration
# GITHUB_BASE_URL="https://raw.githubusercontent.com/livekit/livekit-cli/refs/heads/main/pkg/agentfs/examples/"
# Temporary until this is merged: https://github.com/livekit/livekit-cli/pull/644
GITHUB_BASE_URL="https://raw.githubusercontent.com/livekit/livekit-cli/05790019cc1977abcc6452890811bda07f2e74b1/pkg/agentfs/examples"
PROGRAM_MAIN="src/agent.py"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Get the target package manager from command line
TARGET_PM="$1"

if [ -z "$TARGET_PM" ]; then
    echo -e "${RED}Error: No package manager specified${NC}"
    echo "Usage: $0 {pip|poetry|pipenv|pdm|hatch|uv}"
    exit 1
fi

# Source the detection script
source "$(dirname "$0")/detect-package-manager.sh"

# Detect current package manager
CURRENT_PM=$(detect_current_pm)

echo -e "${GREEN}✔${NC} Detected current package manager: ${YELLOW}$CURRENT_PM${NC}"

# Create backup directory
BACKUP_DIR=".backup.$CURRENT_PM"
if [ "$CURRENT_PM" = "unknown" ]; then
    BACKUP_DIR=".backup.original"
fi

echo "  Creating backup: $BACKUP_DIR/"

# Create backup
mkdir -p "$BACKUP_DIR"

# Backup existing files
[ -f "Dockerfile" ] && cp "Dockerfile" "$BACKUP_DIR/"
[ -f ".dockerignore" ] && cp ".dockerignore" "$BACKUP_DIR/"
[ -f "pyproject.toml" ] && cp "pyproject.toml" "$BACKUP_DIR/"
[ -f "requirements.txt" ] && cp "requirements.txt" "$BACKUP_DIR/"
[ -f "Pipfile" ] && cp "Pipfile" "$BACKUP_DIR/"
[ -f "Pipfile.lock" ] && cp "Pipfile.lock" "$BACKUP_DIR/"
[ -f "poetry.lock" ] && cp "poetry.lock" "$BACKUP_DIR/"
[ -f "pdm.lock" ] && cp "pdm.lock" "$BACKUP_DIR/"
[ -f "uv.lock" ] && cp "uv.lock" "$BACKUP_DIR/"

echo ""
echo -e "${GREEN}✔${NC} Fetching $TARGET_PM templates from GitHub"

# Download Dockerfile and dockerignore
DOCKERFILE_URL="$GITHUB_BASE_URL/python.$TARGET_PM.Dockerfile"
DOCKERIGNORE_URL="$GITHUB_BASE_URL/python.$TARGET_PM.dockerignore"

curl -sL "$DOCKERFILE_URL" -o Dockerfile.tmp
if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to download Dockerfile${NC}"
    exit 1
fi

curl -sL "$DOCKERIGNORE_URL" -o .dockerignore
if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to download .dockerignore${NC}"
    exit 1
fi

# Replace template variable in Dockerfile
sed "s|{{\.ProgramMain}}|$PROGRAM_MAIN|g" Dockerfile.tmp > Dockerfile
rm Dockerfile.tmp

echo "  Downloaded: Dockerfile (from LiveKit template)"
echo "  Downloaded: .dockerignore (from LiveKit template)"
echo ""
echo -e "${YELLOW}⚠️  Note: Dockerfile has been reset to LiveKit template version${NC}"
echo "    Any custom modifications have been backed up"

# Generate package manager specific files
echo ""
echo -e "${GREEN}✔${NC} Generating $TARGET_PM configuration"

case "$TARGET_PM" in
    pip)
        # Generate requirements.txt from pyproject.toml
        if [ -f "pyproject.toml" ]; then
            python3 -c "
import sys
try:
    import tomllib
except ImportError:
    try:
        import tomli as tomllib
    except ImportError:
        # Fallback to basic parsing
        import re
        with open('pyproject.toml', 'r') as f:
            content = f.read()
            # Extract dependencies with regex
            deps_match = re.search(r'dependencies = \[(.*?)\]', content, re.DOTALL)
            if deps_match:
                deps_str = deps_match.group(1)
                deps = re.findall(r'\"([^\"]+)\"', deps_str)
                for dep in deps:
                    print(dep)
            sys.exit(0)

with open('pyproject.toml', 'rb') as f:
    data = tomllib.load(f)

deps = data.get('project', {}).get('dependencies', [])
for dep in deps:
    print(dep)

# Also include dev dependencies as comments
dev_groups = data.get('dependency-groups', {})
if dev_groups:
    print('\n# Development dependencies:')
    for group, deps in dev_groups.items():
        print(f'# [{group}]')
        for dep in deps:
            print(f'# {dep}')
" > requirements.txt
            echo "  Generated: requirements.txt"
        else
            echo -e "${YELLOW}Warning: No pyproject.toml found to convert${NC}"
        fi
        ;;

    poetry)
        # Poetry can work with existing pyproject.toml
        if [ -f "pyproject.toml" ]; then
            echo "  Note: Poetry will use existing pyproject.toml"
            echo "  You may need to run 'poetry init' to add Poetry-specific metadata"
        else
            echo -e "${YELLOW}Warning: No pyproject.toml found${NC}"
        fi
        echo "  Using: pyproject.toml"
        ;;

    pipenv)
        # Generate Pipfile from pyproject.toml
        if [ -f "pyproject.toml" ]; then
            # Create a basic Pipfile
            cat > Pipfile << 'EOF'
[[source]]
url = "https://pypi.org/simple"
verify_ssl = true
name = "pypi"

[packages]
livekit-agents = {extras = ["openai", "turn-detector", "silero", "cartesia", "deepgram"], version = "~=1.2"}
livekit-plugins-noise-cancellation = "~=0.2"
python-dotenv = "*"

[dev-packages]
pytest = "*"
pytest-asyncio = "*"
ruff = "*"

[requires]
python_version = "3.9"
EOF
            echo "  Generated: Pipfile"
        else
            echo -e "${YELLOW}Warning: Creating basic Pipfile${NC}"
            cat > Pipfile << 'EOF'
[[source]]
url = "https://pypi.org/simple"
verify_ssl = true
name = "pypi"

[packages]

[dev-packages]

[requires]
python_version = "3.9"
EOF
            echo "  Generated: Pipfile (basic template)"
        fi
        ;;

    pdm|hatch|uv)
        # These use pyproject.toml, just ensure it exists
        if [ ! -f "pyproject.toml" ]; then
            echo -e "${YELLOW}Warning: No pyproject.toml found${NC}"
        else
            echo "  Using existing: pyproject.toml"
        fi
        ;;
esac

echo "  Entry point: $PROGRAM_MAIN"

# Display instructions based on package manager
echo ""
echo "Next steps:"
echo "  › Install $TARGET_PM:"

case "$TARGET_PM" in
    pip)
        echo "    # pip is usually pre-installed with Python"
        echo ""
        echo "  › Install dependencies:"
        echo "    pip install -r requirements.txt"
        echo ""
        echo "  › For reproducible builds, generate lock file:"
        echo "    pip freeze > requirements.lock"
        ;;
    poetry)
        echo "    curl -sSL https://install.python-poetry.org | python3 -"
        echo ""
        echo "  › Generate lock file:"
        echo "    poetry lock"
        echo ""
        echo "  › Install dependencies:"
        echo "    poetry install"
        ;;
    pipenv)
        echo "    pip install pipenv"
        echo ""
        echo "  › Generate lock file:"
        echo "    pipenv lock"
        echo ""
        echo "  › Install dependencies:"
        echo "    pipenv install"
        ;;
    pdm)
        echo "    pip install pdm"
        echo ""
        echo "  › Generate lock file:"
        echo "    pdm lock"
        echo ""
        echo "  › Install dependencies:"
        echo "    pdm install"
        ;;
    hatch)
        echo "    pip install hatch"
        echo ""
        echo "  › Create environment:"
        echo "    hatch env create"
        echo ""
        echo "  › Install dependencies:"
        echo "    hatch env run pip install -e ."
        ;;
    uv)
        echo "    curl -LsSf https://astral.sh/uv/install.sh | sh"
        echo ""
        echo "  › Generate lock file:"
        echo "    uv lock"
        echo ""
        echo "  › Install dependencies:"
        echo "    uv sync"
        ;;
esac

echo ""
echo "  › Test locally:"
echo "    python $PROGRAM_MAIN dev"
echo ""
echo "  › Build Docker image:"
echo "    docker build -t my-agent ."
echo ""
echo "To rollback: make rollback"

# List existing backups
BACKUP_COUNT=$(ls -d .backup.* 2>/dev/null | wc -l)
if [ $BACKUP_COUNT -gt 0 ]; then
    echo "Existing backups: $(ls -d .backup.* | tr '\n' ' ')"
fi