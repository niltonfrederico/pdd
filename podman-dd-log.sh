#!/bin/bash
set -e

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
#######################################
error() {
    local message="$1"
    local should_exit="$2"
    echo -e "${DD_CYAN}[podman_dd]${DD_NC} ${DD_RED}Error: $message${DD_NC}" >&2
    if [ "$should_exit" = "true" ]; then
        exit 1
    fi
}


#######################################
# Print info message
# Arguments:
#   Info message
#######################################
info() {
    echo -e "${DD_CYAN}[podman_dd]${DD_NC} ${DD_GREEN}Info:${DD_NC} $1" >&2
}

#######################################
# Print warning message
# Arguments:
#   Warning message
#######################################
warn() {
    echo -e "${DD_CYAN}[podman_dd]${DD_NC} ${DD_YELLOW}Warning:${DD_NC} $1" >&2
}

# Print test message for the functions if called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    info "This is a test message"
    warn "This is a warning message"
    error "This script should be sourced" true
else
    # Export the functions
    export -f error
    export -f info
    export -f warn
    # Export the colors
    export DD_RED
    export DD_GREEN
    export DD_YELLOW
    export DD_CYAN
    export DD_BLUE
    export DD_NC
fi  