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
    #   claude-podman --worktree          # Create worktree and run in it
    #   claude-podman --worktree <branch> # Use/create specific worktree branch
    #   claude-podman --no-devenv         # Skip nix devenv setup
    #   claude-podman --refresh-devenv    # Force regenerate devenv cache

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
    SKIP_DEVENV=false
    REFRESH_DEVENV=false
    WORKTREE=false
    WORKTREE_BRANCH=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --auto)        MODE="auto"; shift ;;
            --shell)       MODE="shell"; shift ;;
            --agents)      AGENTS="''${2:?'--agents requires a number'}"; shift 2 ;;
            --build)       FORCE_BUILD=true; shift ;;
            --no-firewall)    FIREWALL=false; shift ;;
            --no-devenv)      SKIP_DEVENV=true; shift ;;
            --refresh-devenv) REFRESH_DEVENV=true; shift ;;
            --worktree)
                WORKTREE=true
                if [[ -n "''${2:-}" ]] && [[ "$2" != --* ]]; then
                    WORKTREE_BRANCH="$2"; shift 2
                else
                    shift
                fi
                ;;
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

    # Setup nix devenv: parse .envrc, run nix print-dev-env, cache result
    DEVENV_FILE=""
    setup_devenv() {
        [[ "$SKIP_DEVENV" == true ]] && return 0

        local envrc="''${WORKSPACE_DIR}/.envrc"
        [[ -f "$envrc" ]] || return 0

        # Detect "use flake <path> [flags]"
        local flake_line
        flake_line=$(${pkgs.gnugrep}/bin/grep -m1 '^use flake ' "$envrc") || return 0
        local flake_args="''${flake_line#use flake }"
        [[ -n "$flake_args" ]] || return 0

        # Split: first word = path, rest = flags (e.g. --impure)
        local flake_path="''${flake_args%% *}"
        local flake_flags=""
        if [[ "$flake_args" == *" "* ]]; then
            flake_flags="''${flake_args#* }"
        fi

        # Resolve path: expand ~ and relative paths
        flake_path="''${flake_path/#\~/$HOME}"
        [[ "$flake_path" = /* ]] || flake_path="''${WORKSPACE_DIR}/''${flake_path}"

        # Verify flake.lock exists
        local flake_lock="''${flake_path}/flake.lock"
        if [[ ! -f "$flake_lock" ]]; then
            warn "devenv: flake.lock not found: ''${flake_lock}"
            return 0
        fi

        # Cache directory
        local cache_dir="''${HOME}/.cache/claude-podman/devenv"
        mkdir -p "$cache_dir"

        # Cache key: workspace path + flake.lock content hash
        local cache_key
        cache_key=$(echo "''${flake_path}:$(${pkgs.coreutils}/bin/sha256sum "$flake_lock" | cut -d' ' -f1)" | ${pkgs.coreutils}/bin/sha256sum | cut -d' ' -f1)
        local cache_file="''${cache_dir}/''${cache_key}.sh"

        if [[ "$REFRESH_DEVENV" == true ]] || [[ ! -f "$cache_file" ]]; then
            info "devenv: Generating environment from flake (this may take a moment)..."
            if ${pkgs.nix}/bin/nix print-dev-env $flake_flags "$flake_path" > "''${cache_file}.tmp" 2>/dev/null; then
                mv "''${cache_file}.tmp" "$cache_file"
                info "devenv: Environment cached"
            else
                rm -f "''${cache_file}.tmp"
                warn "devenv: nix print-dev-env failed, continuing without devenv"
                return 0
            fi
        else
            info "devenv: Using cached environment"
        fi

        DEVENV_FILE="$cache_file"
    }

    # Setup git worktree: create or reuse a worktree, update WORKSPACE_DIR
    setup_worktree() {
        [[ "$WORKTREE" == true ]] || return 0

        local branch="''${1:-$WORKTREE_BRANCH}"

        # Must be in a git repo
        ${pkgs.git}/bin/git -C "$WORKSPACE_DIR" rev-parse --is-inside-work-tree &>/dev/null || {
            error "Not in a git repository"; exit 1
        }

        local repo root
        root=$(${pkgs.git}/bin/git -C "$WORKSPACE_DIR" rev-parse --show-toplevel)
        repo=$(basename "$root")

        # Auto-generate branch name if not specified
        if [[ -z "$branch" ]]; then
            branch="claude-wt-$(date +%m%d-%H%M%S)-$$"
        fi

        local wtpath="''${root}/../''${repo}-''${branch}"
        local abs_wtpath

        # Reuse existing worktree if it exists
        if [[ -d "$wtpath" ]] && ${pkgs.git}/bin/git -C "$wtpath" rev-parse --is-inside-work-tree &>/dev/null; then
            abs_wtpath=$(cd "$wtpath" && pwd)
            info "worktree: Reusing ''${abs_wtpath}"
        elif [[ -d "$wtpath" ]]; then
            error "worktree: ''${wtpath} exists but is not a valid git worktree"
            exit 1
        else
            # Create new worktree
            if ${pkgs.git}/bin/git -C "$WORKSPACE_DIR" show-ref --verify --quiet "refs/heads/''${branch}"; then
                ${pkgs.git}/bin/git -C "$WORKSPACE_DIR" worktree add "$wtpath" "$branch"
            else
                ${pkgs.git}/bin/git -C "$WORKSPACE_DIR" worktree add -b "$branch" "$wtpath" HEAD
            fi
            # Copy .envrc for devenv (same as git nwt)
            [[ ! -f "''${root}/.envrc" ]] || cp "''${root}/.envrc" "$wtpath/"
            abs_wtpath=$(cd "$wtpath" && pwd)
            info "worktree: Created ''${abs_wtpath}"
        fi

        WORKSPACE_DIR="$abs_wtpath"
    }

    # Detect git worktree and mount main .git for container access
    GIT_EXTRA_MOUNTS=()
    setup_git_mounts() {
        local git_dir git_common_dir

        git_dir=$(${pkgs.git}/bin/git -C "$WORKSPACE_DIR" rev-parse --git-dir 2>/dev/null) || return 0
        git_common_dir=$(${pkgs.git}/bin/git -C "$WORKSPACE_DIR" rev-parse --git-common-dir 2>/dev/null) || return 0

        # Resolve to absolute paths
        git_dir=$(cd "$WORKSPACE_DIR" && cd "$git_dir" && pwd)
        git_common_dir=$(cd "$WORKSPACE_DIR" && cd "$git_common_dir" && pwd)

        # Not a worktree if both point to the same directory
        [[ "$git_dir" != "$git_common_dir" ]] || return 0

        # Mount main .git at its host-absolute path so gitdir references resolve
        info "git: Mounting ''${git_common_dir} for worktree support"
        GIT_EXTRA_MOUNTS+=(-v "''${git_common_dir}:''${git_common_dir}:z")
    }

    # Setup project-specific mounts from .claude-podman config file
    # Supports: use go, use ruby, mount <host>:<container>, env KEY=VALUE
    PROJECT_MOUNTS=()
    PROJECT_ENVS=()
    setup_project_mounts() {
        local config="''${WORKSPACE_DIR}/.claude-podman"
        [[ -f "$config" ]] || return 0

        info "project: Loading ''${config}"

        # Helper: ensure host dir exists and add mount
        _add_mount() {
            local host_path="''${1/#\~/$HOME}"
            local container_path="$2"
            mkdir -p "$host_path"
            PROJECT_MOUNTS+=(-v "''${host_path}:''${container_path}:z")
        }

        while IFS= read -r line || [[ -n "$line" ]]; do
            # Skip comments and empty lines
            line="''${line%%#*}"
            line="''${line#"''${line%%[![:space:]]*}"}"
            line="''${line%"''${line##*[![:space:]]}"}"
            [[ -n "$line" ]] || continue

            case "$line" in
                "use go")
                    info "project: Mounting Go caches"
                    _add_mount ~/go /home/node/go
                    _add_mount ~/.cache/go-build /home/node/.cache/go-build
                    ;;
                "use ruby")
                    info "project: Mounting Ruby caches"
                    _add_mount ~/.gem /home/node/.gem
                    _add_mount ~/.bundle /home/node/.bundle
                    ;;
                mount\ *)
                    local spec="''${line#mount }"
                    local host_part="''${spec%%:*}"
                    local container_part="''${spec#*:}"
                    _add_mount "$host_part" "$container_part"
                    info "project: Mounting ''${host_part} -> ''${container_part}"
                    ;;
                env\ *)
                    local envspec="''${line#env }"
                    PROJECT_ENVS+=(-e "$envspec")
                    ;;
                *)
                    warn "project: Unknown directive: ''${line}"
                    ;;
            esac
        done < "$config"
    }

    build_image() {
        if [[ "$FORCE_BUILD" == true ]] || ! ${pkgs.podman}/bin/podman image exists "$IMAGE_NAME"; then
            info "Building image: ''${IMAGE_NAME}..."

            # Create temp build context with resolved symlinks
            local build_dir
            build_dir=$(mktemp -d)
            trap "rm -rf ''${build_dir}" EXIT

            # Copy files, resolving symlinks (home-manager creates symlinks to nix store)
            cp -L "''${DEVCONTAINER_DIR}/Containerfile" "''${build_dir}/"
            cp -L "''${DEVCONTAINER_DIR}/init-firewall.sh" "''${build_dir}/"

            ${pkgs.podman}/bin/podman build \
                -t "$IMAGE_NAME" \
                -f "''${build_dir}/Containerfile" \
                "''${build_dir}"
            info "Image built successfully"
        else
            info "Image \"''${IMAGE_NAME}\" already exists (use --build to rebuild)"
        fi
    }

    launch_container() {
        local name="$1"
        local mode="$2"
        local workspace="$3"

        # MCP config file path (generated by mcp-proxy-hub if available)
        local MCP_CONFIG="''${DEVCONTAINER_DIR}/mcp-servers.json"

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
            -v "/nix/store:/nix/store:ro"
            -v "/nix/var/nix/profiles:/nix/var/nix/profiles:ro"
            # Environment
            -e "HOME=/home/node"
            -e "PATH=$(readlink -f ~/.nix-profile)/bin:/usr/local/bin:/usr/bin:/bin"
            -e "NODE_OPTIONS=--max-old-space-size=4096"
            -e "CLAUDE_CONFIG_DIR=/home/node/.claude"
            -e "TERM=xterm-256color"
        )

        # Override .claude.json with SSE MCP config for container
        # (host uses stdio, container uses SSE via mcp-proxy-hub)
        if [[ -f "$MCP_CONFIG" ]] && command -v ${pkgs.jq}/bin/jq &>/dev/null; then
            local container_claude_json
            container_claude_json=$(mktemp)
            ${pkgs.jq}/bin/jq --slurpfile mcp "$MCP_CONFIG" '.mcpServers = $mcp[0].mcpServers' \
                "''${CLAUDE_CONFIG_DIR}/.claude.json" > "$container_claude_json" 2>/dev/null
            if [[ -s "$container_claude_json" ]]; then
                run_args+=(-v "''${container_claude_json}:/home/node/.claude/.claude.json:Z")
                info "MCP: Using SSE transport via mcp-proxy-hub"
            else
                rm -f "$container_claude_json"
            fi
        fi

        # Add Anthropic environment variables if set
        if [[ -n "''${ANTHROPIC_API_KEY:-}" ]]; then
            run_args+=(-e "ANTHROPIC_API_KEY=''${ANTHROPIC_API_KEY}")
        fi
        if [[ -n "''${ANTHROPIC_CUSTOM_HEADERS:-}" ]]; then
            run_args+=(-e "ANTHROPIC_CUSTOM_HEADERS=''${ANTHROPIC_CUSTOM_HEADERS}")
        fi

        # Forward SSH agent if available
        if [[ -n "''${SSH_AUTH_SOCK:-}" ]]; then
            run_args+=(-v "''${SSH_AUTH_SOCK}:/ssh-agent" -e "SSH_AUTH_SOCK=/ssh-agent")
        fi

        # Mount devenv file if available
        if [[ -n "$DEVENV_FILE" ]]; then
            run_args+=(-v "''${DEVENV_FILE}:/home/node/.devenv.sh:ro,Z")
        fi

        # Git worktree mounts (main .git directory)
        if [[ ''${#GIT_EXTRA_MOUNTS[@]} -gt 0 ]]; then
            run_args+=("''${GIT_EXTRA_MOUNTS[@]}")
        fi

        # Project-specific mounts and env vars (from .claude-podman)
        if [[ ''${#PROJECT_MOUNTS[@]} -gt 0 ]]; then
            run_args+=("''${PROJECT_MOUNTS[@]}")
        fi
        if [[ ''${#PROJECT_ENVS[@]} -gt 0 ]]; then
            run_args+=("''${PROJECT_ENVS[@]}")
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
                    [ -f /home/node/.devenv.sh ] && . /home/node/.devenv.sh
                    exec claude '"''${CLAUDE_ARGS}"'
                '
                ;;
            auto)
                info "Starting auto session: ''${name} (--dangerously-skip-permissions)"
                run_args+=(-it --rm)
                ${pkgs.podman}/bin/podman run "''${run_args[@]}" "$IMAGE_NAME" /bin/bash -c '
                    sudo /usr/local/bin/init-firewall.sh 2>/dev/null || true
                    [ -f /home/node/.devenv.sh ] && . /home/node/.devenv.sh
                    exec claude --dangerously-skip-permissions '"''${CLAUDE_ARGS}"'
                '
                ;;
            auto-detached)
                info "Starting detached auto session: ''${name}"
                run_args+=(-d)
                ${pkgs.podman}/bin/podman run "''${run_args[@]}" "$IMAGE_NAME" /bin/bash -c '
                    sudo /usr/local/bin/init-firewall.sh 2>/dev/null || true
                    [ -f /home/node/.devenv.sh ] && . /home/node/.devenv.sh
                    claude --dangerously-skip-permissions '"''${CLAUDE_ARGS}"'
                    sleep infinity
                '
                ;;
            shell)
                info "Starting shell: ''${name}"
                run_args+=(-it --rm)
                ${pkgs.podman}/bin/podman run "''${run_args[@]}" "$IMAGE_NAME" /bin/bash -c '
                    sudo /usr/local/bin/init-firewall.sh 2>/dev/null || true
                    [ -f /home/node/.devenv.sh ] && . /home/node/.devenv.sh
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

        base_branch="$WORKTREE_BRANCH"
        [[ -n "$base_branch" ]] || base_branch="claude-wt-$(date +%m%d-%H%M%S)"
        base_workspace="$WORKSPACE_DIR"

        for i in $(seq 1 "$AGENTS"); do
            WORKSPACE_DIR="$base_workspace"
            GIT_EXTRA_MOUNTS=()
            PROJECT_MOUNTS=()
            PROJECT_ENVS=()
            DEVENV_FILE=""
            if [[ "$WORKTREE" == true ]]; then
                setup_worktree "''${base_branch}-agent-''${i}"
            fi
            setup_devenv
            setup_git_mounts
            setup_project_mounts
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
        setup_worktree
        setup_devenv
        setup_git_mounts
        setup_project_mounts
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

    # Podman container policy (required for rootless podman)
    ".config/containers/policy.json".text = builtins.toJSON {
      default = [ { type = "insecureAcceptAnything"; } ];
    };

    # Podman registries config
    ".config/containers/registries.conf".text = ''
      [registries.search]
      registries = ['docker.io', 'quay.io', 'ghcr.io']

      [registries.insecure]
      registries = []

      [registries.block]
      registries = []
    '';
  };
}
