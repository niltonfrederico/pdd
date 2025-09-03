#!/bin/bash
# podman-environment.sh - Convert INI configuration to environment variables
# This script parses an INI file and generates a sourceable bash script
# that exports all configuration values as environment variables.

set -e

SCRIPT_PATH="podman_dd"

# Constants
readonly DEFAULT_OUTPUT_FILE="env_vars.sh"
SCRIPT_NAME="${SCRIPT_PATH}/podman-dd-environment.sh"

echo "Script path: $SCRIPT_PATH"
echo "Script name: $SCRIPT_NAME"

# Import log functions
# shellcheck source=/dev/null
source "${SCRIPT_PATH}/podman-dd-log.sh"

# Check if log functions are available
if ! command -v info &> /dev/null; then
    echo "Error: podman-dd-log.sh is not available"
    exit 1
fi

#######################################
# Print usage information
# Globals:
#   SCRIPT_NAME
# Arguments:
#   None
#######################################
show_usage() {
    cat << EOF
${DD_BLUE}Usage:${DD_NC} $SCRIPT_NAME <ini_file> [output_file]

Convert INI configuration file to environment variables script.

${DD_BLUE}Arguments:${DD_NC}
    ${DD_CYAN}ini_file${DD_NC}     Path to the INI configuration file to parse
    ${DD_CYAN}output_file${DD_NC}  Output script file (default: $DEFAULT_OUTPUT_FILE)

${DD_BLUE}Example:${DD_NC}
    ${DD_CYAN}$SCRIPT_NAME settings.ini my_env.sh${DD_NC}
    ${DD_CYAN}source my_env.sh${DD_NC}
EOF
}

#######################################
# Validate input parameters
# Arguments:
#   $1 - INI file path
#   $2 - Section name
#######################################
validate_input() {
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
should_skip_line() {
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
is_section_header() {
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
extract_section_name() {
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
trim_whitespace() {
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
remove_quotes() {
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
create_env_var_name() {
    local key="$1"
    echo "${key}" | tr '[:lower:]' '[:upper:]'
}

#######################################
# Write the header of the output script
# Arguments:
#   $1 - Output file path
#   $2 - Source INI file path
#######################################
write_script_header() {
    local output_file="$1"
    local source_ini="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    cat > "$output_file" << EOF
#!/bin/bash
# Auto-generated environment variables script
# Source INI file: $source_ini
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
generate_env_script() {
    local ini_file="$1"
    local section="$2"
    local output_file="${3:-$DEFAULT_OUTPUT_FILE}"
    local current_section=""
    local line_number=0
    
    # Validate inputs
    validate_input "$ini_file" "$section"
    
    # Create output script with header
    write_script_header "$output_file" "$ini_file"
    
    info "Processing INI file: $ini_file"
    info "Processing section: $section"
    
    # Process each line of the INI file
    while IFS='=' read -r raw_key raw_value; do
        ((line_number++))
        
        # Skip empty lines and comments
        if should_skip_line "$raw_key"; then
            continue
        fi
        
        # Handle section headers
        if is_section_header "$raw_key"; then
            current_section=$(extract_section_name "$raw_key")
            if [[ -n "$section" && "$current_section" != "$section" ]]; then
                # Skip section headers outside of section
                continue
            fi
            echo "# Section: $current_section" >> "$output_file"
            continue
        fi
        
        # Skip key-value pairs outside of sections
        if [[ -n "$section" && "$current_section" != "$section" ]]; then
            continue
        fi

        info "Adding key-value pair to output file: $raw_key = $raw_value"
        
        # Process key-value pairs
        local clean_key clean_value env_var_name
        clean_key=$(trim_whitespace "$raw_key")
        clean_value=$(trim_whitespace "$raw_value")
        clean_value=$(remove_quotes "$clean_value")
        
        # Skip malformed lines
        if [[ -z "$clean_key" ]]; then
            warn "Empty key on line $line_number, skipping"
            continue
        fi
        
        # Create environment variable
        env_var_name=$(create_env_var_name "$clean_key")
        echo "export $env_var_name=\"$clean_value\"" >> "$output_file"
        
    done < "$ini_file"
    
    # Make the output script executable
    chmod +x "$output_file"
    
    info "Generated environment script: $output_file"
    info "To use: source $output_file"
}

#######################################
# Main execution
#######################################
dd_environment() {
    # Check for help flag
    if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
        show_usage
        exit 0
    fi
    
    # Check minimum arguments
    if [[ $# -lt 1 ]]; then
        show_usage
        error "INI file path is required" 1
    fi
    
    # Generate the environment script
    generate_env_script "$@"
}

# Only run main if script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    dd_environment "$@"
fi

# Export the function
export -f dd_environment