#!/bin/bash
# set -euo pipefail

# We will always init with debug mode
DEBUG=true

################################################################################
# Log functions
################################################################################
# Colors for output (if terminal supports it)
if [[ -t 1 ]]; then
    DD_RED='\033[0;31m'
    DD_GREEN='\033[0;32m'
    DD_YELLOW='\033[1;33m'
    DD_CYAN='\033[0;36m'
    DD_BLUE='\033[0;34m'
    DD_NC='\033[0m' # No Color
else
    DD_RED=''
    DD_GREEN=''
    DD_YELLOW=''
    DD_CYAN=''
    DD_BLUE=''
    DD_NC=''
fi

#######################################
# Print error message and exit
# Arguments:
#   Error message
#   Should exit (true/false)
#######################################
error() {
    local message="$1"
    local should_exit="$2"
    echo -e "${DD_CYAN}[pdd]${DD_NC} ${DD_RED}Error: $message${DD_NC}" >&2
    
    if [ "$should_exit" = "true" ] || [ "$should_exit" = "1" ]; then
        exit 1
    fi
}

#######################################
# Print debug message
# Arguments:
#   Debug message
#######################################
debug() {
    local message="$1"
    if [ "$DEBUG" = true ] || [ "$DEBUG" = 1 ]; then
        echo -e "${DD_CYAN}[pdd]${DD_NC} ${DD_BLUE}Debug: $message${DD_NC}" >&2
    fi
}


#######################################
# Print info message
# Arguments:
#   Info message
#######################################
info() {
    echo -e "${DD_CYAN}[pdd]${DD_NC} ${DD_GREEN}Info:${DD_NC} $1" >&2
}

#######################################
# Print warning message
# Arguments:
#   Warning message
#######################################
warn() {
    echo -e "${DD_CYAN}[pdd]${DD_NC} ${DD_YELLOW}Warning:${DD_NC} $1" >&2
}

################################################################################
# Check if is called from inside a container
################################################################################
PDD_IS_CONTAINER=$([[ -f /.dockerenv || -f /run/.containerenv ]] && echo "true" || echo "false")

info "Running in container: $PDD_IS_CONTAINER"

################################################################################
# Discover Django settings.py file and extract app name
################################################################################
# Discover Django settings.py file and extract app name
# Searches up to 2 levels deep, excluding hidden and virtual environment directories
debug "Discovering Django settings.py file and extracting app name"
SETTINGS_PY=$(find . -maxdepth 2 -name "settings.py" -not -path "*/.*" -not -path "*/venv*")
[[ -z "$SETTINGS_PY" ]] && error "Django settings.py not found in current directory tree" 1
debug "Settings.py file found: $SETTINGS_PY"

debug "Extracting app name from settings.py file"
APP_NAME=$(basename "$(dirname "${SETTINGS_PY}")")
info "Django app detected: $APP_NAME (settings: $SETTINGS_PY)"

# Validate if settings.py is found
debug "Validating if settings.py is found"
if [[ -z "$SETTINGS_PY" ]]; then
    error "Django settings.py not found in current directory tree" 1
fi

################################################################################
# Loading pdd.conf
# Feel free to tweak on your pdd.conf
################################################################################
# Check if pdd.conf exists
# Ensure defaults are set
if [ "$PDD_IS_CONTAINER" = "true" ]; then
  PDD_INSTALL_PATH="${CONTAINER_INSTALLATION_PATH:-/.pdd/}"
else
  PDD_INSTALL_PATH=$(dirname "$(realpath "$0")")
fi

PDD_INSTALL_PATH="${PDD_INSTALL_PATH:-$(dirname "$(realpath "$0")")}"
PDD_CONF_PATH="${PDD_INSTALL_PATH}/pdd.conf"

if [ ! -f "${PDD_CONF_PATH}" ]; then
    echo "${PDD_CONF_PATH} not found. Have you created it?"
    exit 1
fi

# shellcheck source=/dev/null
source "${PDD_CONF_PATH}"


################################################################################
# Dependencies
################################################################################

# Install bc if not installed
if ! command -v bc &> /dev/null; then
    warn "bc not found, installing..."
    apt update -qq || error "Failed to update package lists" 1
    apt install -qq -y bc || error "Failed to install bc" 1

    # Test if bc is installed
    if ! command -v bc &> /dev/null; then
        error "bc not installed" 1
    fi

    info "bc installed"
fi

# Python 3.11+
# Set PYTHON_VERSION if is unbound
if [ -z "${PYTHON_VERSION:-}" ]; then
    debug "PYTHON_VERSION not set, setting it..."
    PYTHON_VERSION=$(python3 --version | grep -o "3\.[0-9]\+")
    debug "PYTHON_VERSION set to $PYTHON_VERSION"
fi

IS_PYTHON_3_11_OR_HIGHER=$(echo "$PYTHON_VERSION >= 3.11" | bc -l)

debug "Python version: $PYTHON_VERSION"
debug "IS_PYTHON_3_11_OR_HIGHER: $IS_PYTHON_3_11_OR_HIGHER"

if [ "$IS_PYTHON_3_11_OR_HIGHER" = 0 ]; then
    error "Python 3.11 or higher is required" 1
fi

################################################################################
# Cleanup functions
################################################################################
function pdd_restore() {
  warn "Cleaning up pdd installation"
  local docker_cmd=$1
  local docker_compose_cmd=$2
  local service=$3
  local container_id=$4

  debug "[Cleanup] Docker command: ${docker_cmd}"
  debug "[Cleanup] Docker compose command: ${docker_compose_cmd}"
  debug "[Cleanup] Service: ${service}"
  debug "[Cleanup] Container ID: ${container_id}"

  if [ -f "${SETTINGS_PY}" ]; then
    # Remove the PDD Injection by removing the lines between ### PDD INJECTION START ### and ### PDD INJECTION END ### and themselves
    sed -i '' '/### PDD INJECTION START ###/,/### PDD INJECTION END ###/d' "${SETTINGS_PY}"
  fi

  ${docker_cmd} kill "${container_id}" >/dev/null 2>&1 || true
  ${docker_compose_cmd} down "${service}" --remove-orphans >/dev/null 2>&1 || true
}

################################################################################
# Debian/Python package functions from pdd.conf
################################################################################
debug "Defining install_debian_packages function"
function install_debian_packages() {
  info "Installing Debian packages from pdd.conf..."
  
  # Check if APT_PACKAGES array exists and has elements
  if [[ ${#APT_PACKAGES[@]} -eq 0 ]]; then
    info "No Debian packages specified in pdd.conf"
    return 0
  fi
  
  # Install packages directly from array
  info "Installing packages: ${#APT_PACKAGES[@]}"

  apt install -qq -y "${APT_PACKAGES[@]}" || error "Failed to install Debian packages: ${APT_PACKAGES[*]}" 1
  
  info "Successfully installed ${#APT_PACKAGES[@]} Debian packages"
}

debug "Defining install_python_packages function"
function install_python_packages() {
  info "Installing Python packages from pdd.conf..."
  
  # Check if PIP_PACKAGES array exists and has elements
  if [[ ${#PIP_PACKAGES[@]} -eq 0 ]]; then
    info "No Python packages specified in pdd.conf"
    return 0
  fi
  
  # Convert array to space-separated string and install all at once
  info "Installing packages: ${#PIP_PACKAGES[@]}"
  
  pip install --no-cache-dir "${PIP_PACKAGES[@]}" || error "Failed to install Python packages: ${PIP_PACKAGES[*]}" 1
  
  info "Successfully installed ${#PIP_PACKAGES[@]} Python packages"
}

debug "Defining install_django_packages function"
function install_django_packages() {
    info "Installing Django packages from pdd.conf..."
    
    # Check if DJANGO_PACKAGES array exists and has elements
    if [[ ${#DJANGO_PACKAGES[@]} -eq 0 ]]; then
        info "No Django packages specified in pdd.conf"
        return 0
    fi

    # DJANGO_PACKAGES is like this:
    # ("package=app_name", "package=app_name", ...)
    # So we need to get the packages, ignoring the app_name
    local -a packages=()
    for item in "${DJANGO_PACKAGES[@]}"; do
        # Extract package name (part before '=')
        package_name="${item%%=*}"
        packages+=("$package_name")
    done
    
    pip install "${packages[@]}" || error "Failed to install Django packages: ${packages[*]}" 1
    
    info "Successfully installed $((${#packages[@]})) Django packages"
}

################################################################################
# Injection functions
#
# The order of injection will be:
# 1. Set environment variables from pdd.conf
# 2. Install Debian packages
# 3. Install Python packages
# 4. Install Django packages using the key from DJANGO_PACKAGES
# 5. Append to INSTALLED_APPS in settings.py from the value of DJANGO_PACKAGES
# 6. Append to settings.py the value of DJANGO_SETTINGS
# 8. Set PDD_IS_INSTALLED=1 to indicate that PDD is installed inside the container
#
################################################################################
debug "Defining set_django_apps function"
function set_django_apps() {
    # Get the app_name of DJANGO_PACKAGES and write INSTALLED_APPS in settings.py
    # Remember that the value of DJANGO_PACKAGES is like this:
    # ("package=app_name", "package=app_name", ...)
    # So we need to get the app_name
    info "Injecting $((${#DJANGO_PACKAGES[@]})) app_names to INSTALLED_APPS in settings.py"
    local -a app_names=()
    for item in "${DJANGO_PACKAGES[@]}"; do
        # Extract app_name (part after '=')
        app_name="${item#*=}"
        app_names+=("$app_name")
    done
    echo "### PDD APP INJECTION ###" >> "$SETTINGS_PY"
    
    # Write one line per app_name
    for app_name in "${app_names[@]}"; do
        info "Injecting $app_name to INSTALLED_APPS in settings.py"
        echo "INSTALLED_APPS += [\"$app_name\"]" >> "$SETTINGS_PY"
    done

    echo "### END PDD APP INJECTION ###" >> "$SETTINGS_PY"
}

debug "Defining set_django_settings function"
function set_django_settings() {
    # Get the value of DJANGO_SETTINGS and write to settings.py
    info "Injecting $((${#DJANGO_SETTINGS[*]})) settings to settings.py"
    echo "### PDD DJANGO SETTINGS INJECTION ###" >> "$SETTINGS_PY"

    for settings in "${DJANGO_SETTINGS[@]}"; do
        info "Injecting $settings to settings.py"
        echo "$settings" >> "$SETTINGS_PY"
    done

    echo "### END PDD DJANGO SETTINGS INJECTION ###" >> "$SETTINGS_PY"
}

debug "Defining pdd_install function"
function pdd_install() {
    info "Installing podman-dd inside the container" 

    echo "### PDD INJECTION START ###" >> "$SETTINGS_PY"

    install_debian_packages
    install_python_packages
    install_django_packages
    set_django_apps
    set_django_settings

    echo "### PDD INJECTION END ###" >> "$SETTINGS_PY"

    export PDD_IS_INSTALLED=1
}

################################################################################
# Run command functions
################################################################################
debug "Defining show_usage function"
function show_usage() {
  echo -e "${DD_BLUE}podman-dd - Run containers with inhected environment variables, python, django and debian packages${DD_NC}"
  echo -e "${DD_BLUE}Usage:${DD_NC}"
  echo -e "  ${DD_CYAN}pdd${DD_NC} [service] [podman-options...] [command]"
  echo -e ""
  echo -e "${DD_BLUE}Examples:${DD_NC}"
    echo -e "  ${DD_CYAN}pdd${DD_NC} my-container bash"
    echo -e "  ${DD_CYAN}pdd${DD_NC} compose_service --service-ports bash"
    echo -e "  ${DD_CYAN}pdd${DD_NC} compose_service --build --service-ports bash"
    echo -e "  ${DD_CYAN}pdd${DD_NC} compose_service -e FOO=BAR bash"
  echo -e ""
}

debug "Defining run_docker_exec function"
function run_docker_exec() {
  info "Running docker exec"
  local service="$1"
  local opts="$2"
  local run_command="$3"

  debug "Service: $service"
  debug "Run command: $run_command"

  # Remove service from opts
  opts="${opts//${service}/}"

  # Aliases
  # --sp -> --service-ports
  if [[ "$opts" == *"--sp"* ]]; then
    opts="${opts//--sp/--service-ports}"
  fi

  # --ro -> --remove-orphans
  if [[ "$opts" == *"--rm"* ]]; then
    opts="${opts//--rm/--remove-orphans}"
  fi


  debug "Opts: $opts"

  # Remove trailing spaces from service
  info "Removing trailing spaces from service, opts and run_command"
  service="${service// /}"
  opts="${opts// /}"
  run_command="${run_command// /}"
  info "Getting docker and docker-compose commands"

  # Get docker/podman commands
  info "Detecting container runtime and compose tool..."

  # Detect Docker/Podman command
  if command -v docker >/dev/null 2>&1; then
      DOCKER_CMD="docker"
      info "Using Docker runtime"
  elif command -v podman >/dev/null 2>&1; then
      DOCKER_CMD="podman"
      info "Using Podman runtime"
  else
      error "Neither Docker nor Podman found. Please install one of them." 1
  fi

  # Detect Docker Compose/Podman Compose command
  if command -v docker-compose >/dev/null 2>&1; then
      DOCKER_COMPOSE_CMD="docker-compose"
      info "Using docker-compose"
  elif command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
      DOCKER_COMPOSE_CMD="docker compose"
      info "Using docker compose (built-in)"
  elif command -v podman-compose >/dev/null 2>&1; then
      DOCKER_COMPOSE_CMD="podman-compose"
      info "Using podman-compose"
  elif command -v podman >/dev/null 2>&1 && podman compose --help >/dev/null 2>&1; then
      DOCKER_COMPOSE_CMD="podman compose"
      info "Using podman compose (built-in)"
  else
      error "No compose tool found. Please install docker-compose, podman-compose, or use Docker/Podman with built-in compose support." 1
  fi

  debug "Container runtime: ${DOCKER_CMD}"
  debug "Compose tool: ${DOCKER_COMPOSE_CMD}"

  # Step 1: Start container and install PDD
  info "Step 1: Starting container and installing PDD..."

  # Start container in detached mode with a long-running command
  local container_id
  debug "Starting container with command: ${DOCKER_COMPOSE_CMD} run ${opts} -d ${service} sleep infinity"
  container_id=$(${DOCKER_COMPOSE_CMD} run ${opts} -d "${service}" sleep infinity)

  if [ -z "$container_id" ]; then
    error "Failed to start container" 1
  fi
  
  info "Container started with ID: $container_id"
  
  # Copy PDD files into the container
  info "Copying PDD files to container..."
  ${DOCKER_CMD} cp "${PDD_INSTALL_PATH}/." "${container_id}:/.pdd"
  
  info "Starting PDD Session..."
  
  subcommand="source /.pdd/pdd.sh --install && ${run_command}"
  debug "Subcommand: ${subcommand}"
  ${DOCKER_CMD} exec -it "${container_id}" bash -lc "${subcommand}"

  ${PDD_INSTALL_PATH}/pdd.sh --restore ${DOCKER_CMD} ${DOCKER_COMPOSE_CMD} ${service} ${container_id}
}

################################################################################
# Arguments handling
################################################################################
# Check if at least one argument is provided
if [ $# -eq 0 ]; then
  show_usage
  exit 1
fi

# Check for help
if [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
  show_usage
  exit 0
fi

# Install it is called using `pdd.sh --install` will be installed inside the container
if [ "$1" == "--install" ]; then
  info "Installing podman-dd inside the container"
  pdd_install
  info "Exporting environment variables ${ENVIRONMENT_VARIABLES[*]}"

  for custom_env in "${ENVIRONMENT_VARIABLES[@]}"; do
    info "Exporting $custom_env"
    export "${custom_env}"
  done
fi

# Restore it is called using `pdd.sh --restore` will be restored inside the container
if [ "$1" == "--restore" ]; then
  pdd_restore "$2" "$3" "$4" "$5"
  exit 0
fi

debug "Defining validate_and_get_service function"
function validate_and_get_service() {
  local all_args="$1"
  if [ ! -f "docker-compose.yml" ] && [ ! -f "docker-compose.yaml" ]; then
    error "No docker-compose.yml or docker-compose.yaml file found" 1
  fi

  # Check if at least one argument is provided
  if [ $# -lt 1 ]; then
    show_usage
    error "Provide a service name" 1
  fi

  # Service is the first argument found without beginning with - or --
  # All args is something like this: "--sp service command"
  set -- $all_args
  while [[ $# -gt 0 && "$1" =~ ^-+ ]]; do
    shift
  done
  service="$1"

  debug "[Get Service] All args: $all_args"
  debug "[Get Service] Service: $service"

  # Check service is provided
  if [ -z "$service" ]; then
    show_usage
    error "Service name is required" 1
  fi

  echo "$service"
}

debug "Defining get_opts function"
function get_opts() {
    # Opts are all arguments that start with - or --
    local all_args="$1"
    local opts=()

    for arg in $all_args; do
      if [[ "$arg" =~ ^-+ ]]; then
        opts+=("$arg")
      fi
    done

    echo "${opts[*]}"
}

debug "Defining get_run_command function"
function get_run_command() {
    local all_args="$1"
    
    # Run command is the last argument without beginning with - or --
    run_command="${all_args##* }"

    echo "$run_command"
}

################################################################################
# Execution of host command
################################################################################
if [ "$PDD_IS_CONTAINER" = "false" ]; then
  # Get all args passed to the script
  all_args="$@"
  debug "[All Args] All args: $all_args"

  # Pass all args to the script
  PDD_SERVICE=$(validate_and_get_service "${all_args}")
  PDD_OPTS=$(get_opts "${all_args}")
  PDD_RUN_COMMAND=$(get_run_command "${all_args}")

  debug "PDD_SERVICE: $PDD_SERVICE"
  debug "PDD_OPTS: $PDD_OPTS"
  debug "PDD_RUN_COMMAND: $PDD_RUN_COMMAND"

  run_docker_exec "$PDD_SERVICE" "$PDD_OPTS" "$PDD_RUN_COMMAND"

  exit 0
fi
