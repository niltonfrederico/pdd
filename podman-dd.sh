#!/bin/bash
set -e

# Define script location for volume mount
SCRIPTS_DIR="${HOME}/.pydebug/"
PYTHON_SCRIPT="/pydebug/entrypoint.py"
PYDEBUG_PODMAN_FOLDER="/pydebug"
VOLUME_MOUNT="${SCRIPTS_DIR}:${PYDEBUG_PODMAN_FOLDER}"

# Help function
function show_help() {
  echo "podman pydebug - Run containers with an injected Python script"
  echo ""
  echo "Usage:"
  echo "  podman pydebug [service] [podman-options...] [command]"
  echo ""
  echo "Examples:"
  echo "  podman pydebug my-container bash"
  echo "  podman pydebug compose_service --service-ports bash"
  echo "  podman pydebug compose_service --build --service-ports bash"
  echo "  podman pydebug compose_service -e FOO=BAR bash"
  echo ""
}

# Check for help
if [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
  show_help
  exit 0
fi

# Check if at least one argument is provided
if [ $# -lt 1 ]; then
  echo "Error: Missing service name" >&2
  show_help
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

function is_compose_context() {
  [ -f "docker-compose.yml" ] || [ -f "docker-compose.yaml" ] || [ -f "podman-compose.yml" ] || [ -f "podman-compose.yaml" ]
}

function build_bash_command() {
  local base_cmd
  base_cmd="python ${PYTHON_SCRIPT} || true"
  
  if [ ${#RUN_COMMAND[@]} -ge 1 ]; then
    echo "${base_cmd} && python -c 'import site; print(site.getsitepackages()[0])' && exec ${RUN_COMMAND[*]}"
  else
    echo "${base_cmd} && ${RUN_COMMAND[*]}"
  fi
}

function run_podman() {
  local bash_cmd
  bash_cmd=$(build_bash_command "$@")
  
  if is_compose_context; then
    echo "Running compose service '$SERVICE' with Python script injection..."
    echo "Podman options: ${PODMAN_OPTS[*]}"
    echo "Final command: ${RUN_COMMAND[*]}"
    echo "Bash command: ${bash_cmd}"
    podman compose run -e PODMAN_PYDEBUG=1 -e PODMAN_PYDEBUG_FOLDER="${PYDEBUG_PODMAN_FOLDER}" --rm -v "${VOLUME_MOUNT}" "${PODMAN_OPTS[@]}" "$SERVICE"  bash -c "$bash_cmd"
  else
    echo "Running container '$SERVICE' with Python script injection..."
    echo "Podman options: ${PODMAN_OPTS[*]}"
    echo "Final command: ${RUN_COMMAND[*]}"
    echo "Bash command: ${bash_cmd}"
    podman run -e PODMAN_PYDEBUG=1 -e PODMAN_PYDEBUG_FOLDER="${PYDEBUG_PODMAN_FOLDER}" --rm -v "${VOLUME_MOUNT}" "${PODMAN_OPTS[@]}" "$SERVICE"  bash -c "$bash_cmd"
  fi
}


run_podman "$@"
