{
  pkgs,
  lib,
  ...
}:
let
  inherit (pkgs.stdenv) isLinux;

  claude-podman = pkgs.writeShellScriptBin "claude-podman" ''
    # claude-podman - Launch Claude Code in rootless Podman containers
    # Supports: interactive, auto (--dangerously-skip-permissions), multi-agent
    #
    # Usage:
    #   claude-podman                     # Interactive mode
    #   claude-podman --auto              # Auto mode (skip permissions)
    #   claude-podman --auto --agents 3   # Multi-agent parallel (3 containers)
    #   claude-podman --shell             # Shell only (no claude start)
    #   claude-podman --build             # Force rebuild image
    #   claude-podman --list              # List running containers
    #   claude-podman --stop              # Stop all claude containers
    #   claude-podman --attach <name>     # Attach to running container

    set -euo pipefail

    # Config
    IMAGE_NAME="claude-code-podman"
    CONTAINER_PREFIX="claude"
    DEVCONTAINER_DIR="''${HOME}/.config/claude-podman"
    CLAUDE_CONFIG_DIR="''${HOME}/.claude"
    WORKSPACE_DIR="''${PWD}"

    # Colors
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    CYAN='\033[0;36m'
    NC='\033[0m'

    info()  { echo -e "''${GREEN}[INFO]''${NC} $*"; }
    warn()  { echo -e "''${YELLOW}[WARN]''${NC} $*"; }
    error() { echo -e "''${RED}[ERROR]''${NC} $*" >&2; }

    # Parse args
    MODE="interactive"
    AGENTS=1
    FORCE_BUILD=false
    FIREWALL=true
    AGENT_NAME=""
    CLAUDE_ARGS=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --auto)        MODE="auto"; shift ;;
            --shell)       MODE="shell"; shift ;;
            --agents)      AGENTS="''${2:?'--agents requires a number'}"; shift 2 ;;
            --build)       FORCE_BUILD=true; shift ;;
            --no-firewall) FIREWALL=false; shift ;;
            --list)        MODE="list"; shift ;;
            --stop)        MODE="stop"; shift ;;
            --attach)      MODE="attach"; AGENT_NAME="''${2:?'--attach requires a name'}"; shift 2 ;;
            --name)        AGENT_NAME="''${2:?'--name requires a name'}"; shift 2 ;;
            --)            shift; CLAUDE_ARGS="$*"; break ;;
            -*)            error "Unknown option: $1"; exit 1 ;;
            *)             CLAUDE_ARGS="$*"; break ;;
        esac
    done

    # Commands
    cmd_list() {
        info "Running Claude containers:"
        ${pkgs.podman}/bin/podman ps --filter "label=app=claude-code" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    }

    cmd_stop() {
        info "Stopping all Claude containers..."
        local containers
        containers=$(${pkgs.podman}/bin/podman ps -q --filter "label=app=claude-code")
        if [[ -n "$containers" ]]; then
            echo "$containers" | xargs ${pkgs.podman}/bin/podman stop
            echo "$containers" | xargs ${pkgs.podman}/bin/podman rm -f 2>/dev/null || true
            info "All Claude containers stopped"
        else
            info "No running Claude containers found"
        fi
    }

    cmd_attach() {
        local name="''${CONTAINER_PREFIX}-''${AGENT_NAME}"
        if ${pkgs.podman}/bin/podman ps --format '{{.Names}}' | grep -q "^''${name}$"; then
            info "Attaching to ''${name}..."
            ${pkgs.podman}/bin/podman exec -it "$name" /bin/zsh
        else
            error "Container \"''${name}\" not found. Use --list to see running containers."
            exit 1
        fi
    }

    build_image() {
        if [[ "$FORCE_BUILD" == true ]] || ! ${pkgs.podman}/bin/podman image exists "$IMAGE_NAME"; then
            info "Building image: ''${IMAGE_NAME}..."
            ${pkgs.podman}/bin/podman build \
                -t "$IMAGE_NAME" \
                -f "''${DEVCONTAINER_DIR}/Containerfile" \
                "''${DEVCONTAINER_DIR}"
            info "Image built successfully"
        else
            info "Image \"''${IMAGE_NAME}\" already exists (use --build to rebuild)"
        fi
    }

    launch_container() {
        local name="$1"
        local mode="$2"
        local workspace="$3"

        # Container run args
        local run_args=(
            --name "$name"
            --label "app=claude-code"
            --hostname "$name"
            --userns keep-id
            # Mounts
            -v "''${workspace}:/workspace:Z"
            -v "''${CLAUDE_CONFIG_DIR}:/home/node/.claude:Z"
            -v "claude-bash-history-''${name}:/commandhistory:Z"
            # Environment
            -e "NODE_OPTIONS=--max-old-space-size=4096"
            -e "CLAUDE_CONFIG_DIR=/home/node/.claude"
            -e "TERM=xterm-256color"
        )

        # Add ANTHROPIC_API_KEY if set
        if [[ -n "''${ANTHROPIC_API_KEY:-}" ]]; then
            run_args+=(-e "ANTHROPIC_API_KEY=''${ANTHROPIC_API_KEY}")
        fi

        # Firewall needs NET_ADMIN + NET_RAW
        if [[ "$FIREWALL" == true ]]; then
            run_args+=(--cap-add=NET_ADMIN --cap-add=NET_RAW)
        fi

        # Remove existing container with same name
        ${pkgs.podman}/bin/podman rm -f "$name" 2>/dev/null || true

        case "$mode" in
            interactive)
                info "Starting interactive session: ''${name}"
                run_args+=(-it --rm)
                ${pkgs.podman}/bin/podman run "''${run_args[@]}" "$IMAGE_NAME" /bin/bash -c '
                    sudo /usr/local/bin/init-firewall.sh 2>/dev/null || true
                    exec claude '"''${CLAUDE_ARGS}"'
                '
                ;;
            auto)
                info "Starting auto session: ''${name} (--dangerously-skip-permissions)"
                run_args+=(-it --rm)
                ${pkgs.podman}/bin/podman run "''${run_args[@]}" "$IMAGE_NAME" /bin/bash -c '
                    sudo /usr/local/bin/init-firewall.sh 2>/dev/null || true
                    exec claude --dangerously-skip-permissions '"''${CLAUDE_ARGS}"'
                '
                ;;
            auto-detached)
                info "Starting detached auto session: ''${name}"
                run_args+=(-d)
                ${pkgs.podman}/bin/podman run "''${run_args[@]}" "$IMAGE_NAME" /bin/bash -c '
                    sudo /usr/local/bin/init-firewall.sh 2>/dev/null || true
                    claude --dangerously-skip-permissions '"''${CLAUDE_ARGS}"'
                    sleep infinity
                '
                ;;
            shell)
                info "Starting shell: ''${name}"
                run_args+=(-it --rm)
                ${pkgs.podman}/bin/podman run "''${run_args[@]}" "$IMAGE_NAME" /bin/bash -c '
                    sudo /usr/local/bin/init-firewall.sh 2>/dev/null || true
                    exec /bin/zsh
                '
                ;;
        esac
    }

    # Main
    case "$MODE" in
        list)
            cmd_list
            exit 0
            ;;
        stop)
            cmd_stop
            exit 0
            ;;
        attach)
            cmd_attach
            exit 0
            ;;
    esac

    # Ensure config dir exists
    mkdir -p "$CLAUDE_CONFIG_DIR"

    # Build image
    build_image

    if [[ "$AGENTS" -gt 1 ]]; then
        # Multi-agent mode
        info "Launching ''${AGENTS} agents in parallel..."
        echo ""

        for i in $(seq 1 "$AGENTS"); do
            agent_name="''${CONTAINER_PREFIX}-agent-''${i}"
            launch_container "$agent_name" "auto-detached" "$WORKSPACE_DIR"
        done

        echo ""
        info "All agents launched! Commands:"
        echo "  claude-podman --list              # Show running agents"
        echo "  claude-podman --attach agent-1    # Attach to agent 1"
        echo "  claude-podman --stop              # Stop all agents"
    else
        # Single agent mode
        name="''${CONTAINER_PREFIX}-''${AGENT_NAME:-main}"
        launch_container "$name" "$MODE" "$WORKSPACE_DIR"
    fi
  '';
in
{
  # Linux-only packages
  home.packages = lib.mkIf isLinux [
    claude-podman
    pkgs.podman
    pkgs.slirp4netns
  ];

  # Containerfile and init-firewall.sh (Linux only)
  home.file = lib.mkIf isLinux {
    ".config/claude-podman/Containerfile".source = ./claude-podman/Containerfile;
    ".config/claude-podman/init-firewall.sh" = {
      source = ./claude-podman/init-firewall.sh;
      executable = true;
    };
  };
}
