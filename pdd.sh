#!/bin/bash
set -e

################################################################################
# Global variables
# Feel free to tweak to your liking
################################################################################
PDD_DEBUG=${PDD_DEBUG:-0}
PDD_INSTALLATION_PATH="${HOME}/Chronopolis/prometheus/repos/pdd"
PDD_SCRIPTS_PATH="/scripts/.pdd"
PDD_CONTAINER_PATH="/app${PDD_SCRIPTS_PATH}"

################################################################################
# Global variables
# Do not change below this line unless you know what you are doing
################################################################################
PDD_ENTRYPOINT="${PDD_CONTAINER_PATH}/pdd.py"
PDD_SETTINGS_INI_PATH="${PDD_CONTAINER_PATH}/settings.ini"
PDD_ENV_VARS_PATH="${PDD_CONTAINER_PATH}/env_vars.sh"
PDD_IS_CONTAINER=false

################################################################################
# Check if is called from inside a container
################################################################################
if [ -f /.dockerenv ] || [ -f /run/.containerenv ]; then
  PDD_IS_CONTAINER=true
else
  PDD_IS_CONTAINER=false
fi

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
    local should_exit="$2"
    if [ "$PDD_DEBUG" = true ] || [ "$PDD_DEBUG" = 1 ]; then
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
# Prepare volume mount
################################################################################
SETTINGS_PY=$(find . -maxdepth 2 -name "settings.py" -not -path "*/.*" -not -path "*/venv*")
info "Settings.py path: $SETTINGS_PY"
APP_NAME=$(basename "$(dirname "${SETTINGS_PY}")")
info "App name: $APP_NAME"
if [ "$PDD_IS_CONTAINER" = false ]; then
    info "Preparing volume mount"
    PDD_VOLUME_MOUNT="${PDD_INSTALLATION_PATH}"

    # Create a temporary directory with all files from pdd installation path
    PDD_TEMP_DIR=$(mktemp -d)
    cp -r "${PDD_INSTALLATION_PATH}/" "${PDD_TEMP_DIR}"

    # Use the temporary directory as PDD_VOLUME_MOUNT
    PDD_VOLUME_MOUNT="${PDD_TEMP_DIR}:${PDD_CONTAINER_PATH}"
fi

################################################################################
# Environment variables and .init functions
################################################################################

#######################################
# Validate input parameters
# Arguments:
#   $1 - INI file path
#   $2 - Section name
#######################################
dd_validate_input() {
    local ini_file="$1"
    local section="$2"

    if [[ -z "$ini_file" ]]; then
        error "INI file path is required" 1
    fi
    
    if [[ ! -f "$ini_file" ]]; then
        error "INI file does not exist: $ini_file" 1
    fi
    
    if [[ ! -r "$ini_file" ]]; then
        error "Cannot read INI file: $ini_file" 1
    fi
    
    # Check if section is provided
    if [[ -z "$section" ]]; then
        error "Section name is required" 1
    fi
}

#######################################
# Check if line is a comment or empty
# Arguments:
#   $1 - Line content
# Returns:
#   0 if line should be skipped, 1 otherwise
#######################################
dd_should_skip_line() {
    local line="$1"
    [[ -z "$line" || "$line" =~ ^[[:space:]]*[#\;] ]]
}

#######################################
# Check if line is a section header
# Arguments:
#   $1 - Line content
# Returns:
#   0 if line is a section header, 1 otherwise
#######################################
dd_is_section_header() {
    local line="$1"
    [[ "$line" =~ ^\[([^\]]+)\]$ ]]
}

#######################################
# Extract section name from section header
# Arguments:
#   $1 - Section header line
# Returns:
#   Section name
#######################################
dd_extract_section_name() {
    local line="$1"
    if [[ "$line" =~ ^\[([^\]]+)\]$ ]]; then
        echo "${BASH_REMATCH[1]}"
    fi
}

#######################################
# Clean and trim whitespace from string
# Arguments:
#   $1 - String to clean
# Returns:
#   Cleaned string
#######################################
dd_trim_whitespace() {
    local input="$1"
    echo "$input" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

#######################################
# Remove surrounding quotes from value
# Arguments:
#   $1 - Value string
# Returns:
#   Value without surrounding quotes
#######################################
dd_remove_quotes() {
    local value="$1"
    echo "$value" | sed 's/^"//;s/"$//'
}

#######################################
# Convert section and key to environment variable name
# Arguments:
#   $1 - Key name
# Returns:
#   Environment variable name in UPPER_CASE format
#######################################
dd_create_env_var_name() {
    local key="$1"
    echo "${key}" | tr '[:lower:]' '[:upper:]'
}

#######################################
# Write the header of the output script
# Arguments:
#   $1 - Output file path
#   $2 - Source INI file path
#######################################
dd_write_script_header() {
    local output_file="$1"
    local source_ini="$2"
    local section="$3"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    cat > "$output_file" << EOF
#!/bin/bash
# Auto-generated environment variables script
# Source INI file: $source_ini
# Section: $section
# Generated on: $timestamp
# 
# Usage: source $output_file

EOF
}

#######################################
# Generate environment variables script from INI file
# Arguments:
#   $1 - INI file path (required)
#   $2 - Section name (required)
#   $3 - Output file path (optional, defaults to env_vars.sh)
#######################################
dd_generate_env_script() {
    local ini_file="$1"
    local section="$2"
    local output_file="${3:-$PDD_ENV_VARS_PATH}"
    local current_section=""
    local line_number=0

    debug "INI file path: $ini_file"
    debug "Section name: $section"
    debug "Output file path: $output_file"
    debug "Current section: $current_section"
    debug "Line number: $line_number"
    
    # Validate inputs
    dd_validate_input "$ini_file" "$section"
    
    # Create output script with header
    dd_write_script_header "$output_file" "$ini_file" "$section"
    
    info "Processing INI file: $ini_file"
    info "Processing section: $section"
    
    # Process each line of the INI file
    while IFS='=' read -r raw_key raw_value; do
        line_number=$((line_number+1))
        
        # Skip empty lines and comments
        if dd_should_skip_line "$raw_key"; then
            debug "Skipping line #$line_number: $raw_key=$raw_value"
            continue
        fi
        
        # Handle section headers
        if dd_is_section_header "$raw_key"; then
            current_section=$(dd_extract_section_name "$raw_key")
            if [[ -n "$section" && "$current_section" != "$section" ]]; then
                debug "Skipping section header #$line_number: $raw_key=$raw_value"
                # Skip section headers outside of section
                continue
            fi
            echo "# Section: $current_section" >> "$output_file"
            continue
        fi
        
        # Skip key-value pairs outside of sections
        if [[ -n "$section" && "$current_section" != "$section" ]]; then
            debug "Current section: $current_section"
            debug "Section: $section"
            debug "Skipping key-value pair #$line_number: $raw_key=$raw_value"
            continue
        fi

        info "Adding key-value pair to output file: $raw_key = $raw_value"
        
        # Process key-value pairs
        local clean_key clean_value env_var_name
        clean_key=$(dd_trim_whitespace "$raw_key")
        clean_value=$(dd_trim_whitespace "$raw_value")
        clean_value=$(dd_remove_quotes "$clean_value")
        
        # Skip malformed lines
        if [[ -z "$clean_key" ]]; then
            warn "Empty key on line $line_number, skipping"
            continue
        fi
        
        # Create environment variable
        env_var_name=$(dd_create_env_var_name "$clean_key")
        echo "export $env_var_name=\"$clean_value\"" >> "$output_file"
        
    done < "$ini_file"
    
    # Make the output script executable
    chmod +x "$output_file"
    
    info "Generated environment script: $output_file"
    info "To use: source $output_file"
}

#######################################
# dd_environment wrapper to be used
#######################################
dd_environment() {    
    # Check minimum arguments
    if [[ $# -lt 1 ]]; then
        show_usage
        error "INI file path is required" 1
    fi

    debug "INI file path: $1"
    debug "Section name: $2"
    
    # Generate the environment script
    dd_generate_env_script "$@"
}

################################################################################
# Container functions
################################################################################
function pdd_cleanup() {
  warn "Cleaning up"
  # find settings.original.py in PDD_VOLUME_MOUNT, looking only in subdirectories
  SETTINGS_ORIGINAL_PY="$PWD/$APP_NAME/settings.original.py"

  warn "Moving $SETTINGS_ORIGINAL_PY to settings.py"
  mv "${SETTINGS_ORIGINAL_PY}" "${SETTINGS_ORIGINAL_PY%.original.py}.py"
  warn "Removed injected settings.py"
}

function pdd_install() {
  # Set dd internal environment variables
  info "Set dd internal environment variables"
  # shellcheck source=/dev/null
  dd_environment "${PDD_SETTINGS_INI_PATH}" "pdd.pre_install_environment"
  info "Source environment variables"
  # shellcheck source=/dev/null
  source "${PDD_ENV_VARS_PATH}"
  info "End source environment variables"

  # Install PDD
  info "Install PDD"
  python "${PDD_ENTRYPOINT}" "${PDD_CONTAINER_PATH}"

  # Set user custom environment variables
  info "Set user custom environment variables"
  # shellcheck source=/dev/null
  dd_environment "${PDD_SETTINGS_INI_PATH}" "pdd.user_environment"
  # shellcheck source=/dev/null
  source "${PDD_ENV_VARS_PATH}"

  # Set post install environment variables
  info "Set post install environment variables"
  # shellcheck source=/dev/null
  dd_environment "${PDD_SETTINGS_INI_PATH}" "pdd.post_install_environment"
  # shellcheck source=/dev/null
  source "${PDD_ENV_VARS_PATH}"

  info "End set post install environment variables"
}

################################################################################
# Run command functions
################################################################################
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

function run_docker_exec() {
  local service="$1"
  local opts="$2"
  local run_command="$3"

  local BASH_CMD="bash -c 'PDD_DEBUG=$PDD_DEBUG $PDD_CONTAINER_PATH/pdd.sh && $run_command'"
  local DOCKER_BIN="docker-compose" # Podman have a docker alias, so we use docker as default

  warn "Volume mount: ${PDD_VOLUME_MOUNT}"
  warn "Container options: ${opts[*]}"
  warn "Container service: $service"
  warn "Shell command: ${BASH_CMD}"

  info "Running compose service '$service' with Python script injection..."
  local cmd="${DOCKER_BIN} run --rm -v ${PDD_VOLUME_MOUNT} ${opts[*]} ${service} ${BASH_CMD}"
  debug "Running command: ${cmd}"
  eval "${cmd}"
}

################################################################################
# Arguments handling
################################################################################
# Check for help
if [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
  show_usage
  exit 0
fi

function validate_and_get_service() {
  local service="$1"
  if [ ! -f "docker-compose.yml" ] && [ ! -f "docker-compose.yaml" ]; then
    error "No docker-compose.yml or docker-compose.yaml file found" 1
  fi

  # Check if at least one argument is provided
  if [ $# -lt 1 ]; then
    show_usage
    error "Provide a service name" 1
  fi

  # Check service is provided
  if [ -z "$service" ]; then
    show_usage
    error "Service name is required" 1
  fi

  echo "$service"
}

function get_opts() {
    # opts are all arguments except the last one
    if [ $# -eq 1 ]; then
        echo ""
    else
        echo "${*:1:$((${#}-1))}"
    fi
}

function get_run_command() {
    # run command is the last argument
    if [ $# -eq 1 ]; then
        echo "$1"
    else
        echo "${*: -1}"
    fi
}

################################################################################
# Arguments aliases
################################################################################
PDD_OPTS="${PDD_OPTS//--sp/--service-ports}"
PDD_OPTS="${PDD_OPTS//--ro/--remove-orphans}"

################################################################################
# Main execution
################################################################################
debug "PDD_DEBUG: $PDD_DEBUG"
debug "PDD_IS_CONTAINER: $PDD_IS_CONTAINER"

if [ "$PDD_IS_CONTAINER" = true ]; then
  info "Installing podman-dd inside the container"
  trap pdd_cleanup EXIT SIGINT SIGTERM
  pdd_install
else
  info "Executing the run command"

  PDD_SERVICE=$(validate_and_get_service "$1")
  PDD_OPTS=$(get_opts "${@:1:$((${#}-1))}")
  PDD_RUN_COMMAND=$(get_run_command "${@: -1}")

  run_docker_exec "$PDD_SERVICE" "$PDD_OPTS" "$PDD_RUN_COMMAND"
fi
