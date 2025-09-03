#!/bin/bash
set -e

PODMAN_DD_HOST_PATH="${HOME}/.podman-dd"
CONTAINER_APP_PATH="/app"
PODMAN_DD_PATH="${CONTAINER_APP_PATH}/scripts/podman_dd"
VOLUME_MOUNT="${PODMAN_DD_HOST_PATH}:${PODMAN_DD_PATH}"

# Import log functions and environment functions
# shellcheck source=/dev/null
source "${PODMAN_DD_HOST_PATH}/podman-dd-log.sh"

# Define script location for volume mount
PODMAN_DD_ENTRYPOINT="${PODMAN_DD_PATH}/entrypoint.py"

function is_compose_context() {
  [ -f "docker-compose.yml" ] || [ -f "docker-compose.yaml" ] || [ -f "podman-compose.yml" ] || [ -f "podman-compose.yaml" ]
}

# Help function
function show_usage() {
echo -e "${DD_BLUE}podman-dd - Run containers with an injected Python script${DD_NC}"
echo -e "${DD_BLUE}Usage:${DD_NC}"
echo -e "  ${DD_CYAN}podman-dd${DD_NC} [service] [podman-options...] [command]"
echo -e ""
echo -e "${DD_BLUE}Examples:${DD_NC}"
  echo -e "  ${DD_CYAN}podman-dd${DD_NC} my-container bash"
  echo -e "  ${DD_CYAN}podman-dd${DD_NC} compose_service --service-ports bash"
  echo -e "  ${DD_CYAN}podman-dd${DD_NC} compose_service --build --service-ports bash"
  echo -e "  ${DD_CYAN}podman-dd${DD_NC} compose_service -e FOO=BAR bash"
echo -e ""
}

# Check for help
if [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
  show_usage
  exit 0
fi

# Check if at least one argument is provided
if [ $# -lt 1 ]; then
  show_usage
  error "Provide a service name"
  exit 1
fi

SERVICE="$1"
shift

# PODMAN_OPTS are all arguments except the last one
# RUN_COMMAND is the last argument
# Simple split: everything until first non-option is OPTS, rest is COMMAND
# Parse arguments: everything except the last is options, last is command
if [ $# -eq 1 ]; then
  # Only command, no options
  PODMAN_OPTS=""
  RUN_COMMAND="$1"
else
  # Multiple arguments: all except last are options, last is command
  PODMAN_OPTS="${*:1:$((${#}-1))}"
  RUN_COMMAND="${*: -1}"
fi

PODMAN_OPTS="${PODMAN_OPTS//--sp/--service-ports}"
PODMAN_OPTS="${PODMAN_OPTS//--ro/--remove-orphans}"

function build_bash_command() {
  local _dd_cmd
  local _cleanup_command
  local _cleanup_trap

  _dd_cmd="export PODMAN_DD_INSTALLED=0"
  _dd_cmd="${_dd_cmd} && source ${PODMAN_DD_PATH}/podman-dd-log.sh"
  _dd_cmd="${_dd_cmd} && source ${PODMAN_DD_PATH}/podman-dd-environment.sh"

  # Cleanup trap
  _dd_cmd="${_dd_cmd} && ${_cleanup_trap}"

  # Add the dd environment command
  _dd_cmd="${_dd_cmd} && dd_environment ${PODMAN_DD_PATH}/settings.ini podman_dd_environment"
  _dd_cmd="${_dd_cmd} && source ${CONTAINER_APP_PATH}/env_vars.sh"
  # Add python script
  _dd_cmd="${_dd_cmd} && python ${PODMAN_DD_ENTRYPOINT} || true"
  # Add post command to ensure installtion
  _dd_cmd="${_dd_cmd} && python scripts/podman_dd/settings_overlay.py"
  # Add dd custom environment command
  _dd_cmd="${_dd_cmd} && dd_environment ${PODMAN_DD_PATH}/settings.ini podman_dd_custom_environment"
  _dd_cmd="${_dd_cmd} && source ${CONTAINER_APP_PATH}/env_vars.sh"
  # Add post install environment command
  _dd_cmd="${_dd_cmd} && dd_environment ${PODMAN_DD_PATH}/settings.ini podman_dd_post_install_environment"
  _dd_cmd="${_dd_cmd} && source ${CONTAINER_APP_PATH}/env_vars.sh"
  
  if [ ${#RUN_COMMAND[@]} -ge 1 ]; then
    _dd_cmd="${_dd_cmd} && exec ${RUN_COMMAND[*]}"
  else
    _dd_cmd="${_dd_cmd} && ${RUN_COMMAND[*]}"
  fi

  echo "${_dd_cmd}"
}

function run_podman() {
  local bash_cmd
  bash_cmd=$(build_bash_command "$@")

  if is_compose_context; then
    info "Running compose service '$SERVICE' with Python script injection..."
    info "Podman options: ${PODMAN_OPTS[*]}"
    info "Final command: ${RUN_COMMAND[*]}"
    info "Bash command: ${bash_cmd}"
    podman compose run -e PODMAN_DD=1 -e PODMAN_DD_PATH="${PODMAN_DD_PATH}" --rm -v "${VOLUME_MOUNT}" "${PODMAN_OPTS[@]}" "$SERVICE"  bash -c "$bash_cmd"
  else
    info "Running container '$SERVICE' with Python script injection..."
    info "Podman options: ${PODMAN_OPTS[*]}"
    info "Final command: ${RUN_COMMAND[*]}"
    info "Bash command: ${bash_cmd}"
    podman run -e PODMAN_DD=1 -e PODMAN_DD_PATH="${PODMAN_DD_PATH}" --rm -v "${VOLUME_MOUNT}" "${PODMAN_OPTS[@]}" "$SERVICE"  bash -c "$bash_cmd"
  fi
}

run_podman "$@"
