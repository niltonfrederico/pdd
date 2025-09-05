# PDD (Podman Django Debug)

A powerful debugging toolkit that enhances Django containers with debugging tools, packages, and environment customization for development workflows. PDD works with both Docker and Podman containers.

⚠️ DO NOT USE THIS TOOL FOR PRODUCTION. ⚠️

## Overview

PDD injects a customized development environment into Django containers at runtime, automatically installing debugging packages, setting up development tools, and configuring the Django environment for enhanced debugging capabilities. It works by copying configuration files and scripts into the container, then executing setup commands to install packages and modify Django settings.

## Features

- **Automatic Package Installation**: Installs both pip and Debian packages on container startup
- **Environment Customization**: Sets custom environment variables for debugging
- **Django Integration**: Injects Django apps and settings for development environments
- **Flexible Configuration**: Bash-based configuration for easy customization
- **Multi-Runtime Support**: Works with both Docker and Podman
- **Compose Support**: Works with both docker-compose and podman-compose
- **Automatic Discovery**: Automatically discovers Django settings.py files

## Installation

### 1. Clone or Download the Project

```bash
git clone https://github.com/niltonfrederico/pdd.git ~/.pdd
# or download and extract to ~/.pdd or your preferred location
```

### 2. Create Symbolic Link for Global Access

Create a symbolic link to make the script accessible from anywhere in your system:

```bash
sudo ln -s ~/.pdd/pdd.sh /usr/local/bin/pdd
```

**Alternative locations** (choose one based on your system and personal preference):
```bash
# For systems where /usr/local/bin is not in PATH
sudo ln -s ~/.pdd/pdd.sh /usr/bin/pdd

# For user-only installation (ensure ~/.local/bin is in PATH)
ln -s ~/.pdd/pdd.sh ~/.local/bin/pdd
```

### 3. Make the Script Executable

```bash
chmod +x ~/.pdd/pdd.sh
```

### 4. Create Configuration File

Copy the example configuration and customize it:

```bash
cp ~/.pdd/pdd.conf.example ~/.pdd/pdd.conf
```

### 5. Verify the Installation

```bash
pdd --help
```

## Configuration

### pdd.conf Setup - Configuration Options

The `pdd.conf` file controls what packages and environment variables are injected into containers. The configuration uses bash array syntax:

```bash
# Debug mode (true/false)
DEBUG=true

# Container installation path (optional)
# CONTAINER_INSTALLATION_PATH="/.pdd/"

# Debian packages to install
APT_PACKAGES=(
    "neovim"
    "bat"
    "curl"
    "git"
)

# Python packages to install
PIP_PACKAGES=(
    "django_extensions"
    "ipdb"
    "pytest"
    "pytest-django"
)

# Environment variables to set
ENVIRONMENT_VARIABLES=(
    "PYTHONBREAKPOINT=ipdb.set_trace"
    "DEBUG=True"
)

# Django packages (format: package=app_name)
DJANGO_PACKAGES=(
    "django_extensions=django_extensions"
)

# Django settings to inject
DJANGO_SETTINGS=(
    "MY_CUSTOM_SETTING=1"
)
```

### Configuration Options

#### `APT_PACKAGES`
Array of Debian/Ubuntu packages to install via `apt`:
```bash
APT_PACKAGES=(
    "neovim"
    "bat"
    "curl"
    "git"
    "htop"
)
```

#### `PIP_PACKAGES`  
Array of Python packages to install via `pip`:
```bash
PIP_PACKAGES=(
    "ipdb"
    "pytest"
    "black"
    "flake8"
    "mypy"
)
```

#### `ENVIRONMENT_VARIABLES`
Array of environment variables to set (format: VAR=value):
```bash
ENVIRONMENT_VARIABLES=(
    "PYTHONBREAKPOINT=ipdb.set_trace"
    "DEBUG=True"
    "LOG_LEVEL=DEBUG"
)
```

#### `DJANGO_PACKAGES` & `DJANGO_SETTINGS`
Django-specific configuration:
```bash
# Django packages (format: package=app_name)
DJANGO_PACKAGES=(
    "django_extensions=django_extensions"
    "debug_toolbar=debug_toolbar"
)

# Custom Django settings to inject
DJANGO_SETTINGS=(
    "MY_DEBUG_SETTING=True"
    "CUSTOM_CONFIG=value"
    "PARSED_SETTINGS=int('1')"
)
```

### Example Configurations

#### Minimal Python Debugging
```bash
DEBUG=false
APT_PACKAGES=()
PIP_PACKAGES=(
    "ipdb"
    "pytest"
)
ENVIRONMENT_VARIABLES=(
    "PYTHONBREAKPOINT=ipdb.set_trace"
)
DJANGO_PACKAGES=()
DJANGO_SETTINGS=()
```

#### Full Development Environment
```bash
DEBUG=true
APT_PACKAGES=(
    "neovim"
    "bat"
    "curl"
    "git"
    "htop"
    "tree"
)
PIP_PACKAGES=(
    "ipdb"
    "pytest"
    "pytest-django"
    "django_extensions"
    "black"
    "flake8"
    "mypy"
)
ENVIRONMENT_VARIABLES=(
    "PYTHONBREAKPOINT=ipdb.set_trace"
    "DEBUG=True"
    "PYTHONVERBOSE=1"
)
DJANGO_PACKAGES=(
    "django_extensions=django_extensions"
)
DJANGO_SETTINGS=(
    "DEVELOPMENT_MODE=True"
)
```

## Usage

### Basic Usage

```bash
# Run a container with debugging tools
podman-dd my-python-container bash

# Run a compose service
podman-dd web_service bash

# Run with additional podman options
podman-dd web_service --service-ports bash

# Run with environment variables
podman-dd web_service -e DATABASE_URL=postgres://localhost bash
```

### Advanced Usage

```bash
# Build and run with debugging
podman-dd web_service --build --service-ports bash

# Run specific command after setup
podman-dd web_service "python manage.py shell"

# Multiple podman options
podman-dd web_service --service-ports -e DEBUG=True --rm bash
```

### Command Structure

```
podman-dd [service/image] [podman-options...] [command]
```

- **service/image**: Container image or compose service name
- **podman-options**: Any valid podman/podman-compose options
- **command**: Command to run inside the container (defaults to bash)

## How It Works

1. **Volume Mount**: Mounts `~/.podman-dd` to `/podman-dd` inside the container
2. **Script Injection**: Runs `entrypoint.py` which creates a `sitecustomize.py` file
3. **Package Installation**: Installs configured Debian and pip packages
4. **Environment Setup**: Sets environment variables and Django overlays
5. **Command Execution**: Runs the specified command with the enhanced environment

## Current Issues & Limitations

### ⚠️ Requirements and Limitations

**Current Limitations**:

1. **Django Projects Only**: Requires a Django project with settings.py file
2. **Debian/Ubuntu Container Support**: Currently only works with Debian-based containers
   - Uses `apt` package manager for system packages
   - Assumes Debian package naming conventions
3. **Compose File Required**: Requires docker-compose.yml or docker-compose.yaml file
4. **Python 3.11+**: Requires Python 3.11 or higher
5. **Container Runtime**: Requires either Docker or Podman to be installed

**Containers NOT supported**:
- Alpine Linux (uses `apk`)
- Red Hat/CentOS/Fedora (uses `yum`/`dnf`) 
- SUSE (uses `zypper`)
- Other non-Debian distributions

### Other Known Issues

1. **Root Privileges**: Container must run with sufficient privileges to install packages
2. **Network Access**: Container needs internet access for package downloads
3. **Storage Space**: Additional packages require extra container storage
4. **Startup Time**: Initial package installation adds container startup overhead

## Troubleshooting

### Permission Errors
```bash
# Ensure script is executable
chmod +x ~/.pdd/pdd.sh
# Check symbolic link
ls -la /usr/local/bin/pdd
```

### Missing Compose File
```bash
# Ensure you're in a directory with docker-compose.yml
ls -la docker-compose.y*
```

### Django Settings Not Found
```bash
# Ensure you're in a Django project directory
find . -name "settings.py" -not -path "*/.*" -not -path "*/venv*"
```

### Package Installation Failures
- Verify container has internet access
- Check if container runs as root or has sudo privileges
- Ensure container is Debian/Ubuntu based
- Check that `bc` calculator is available (auto-installed if missing)

### Configuration Issues
- Validate bash array syntax in pdd.conf
- Check file paths and permissions
- Verify environment variable syntax (VAR=value format)
- Ensure DJANGO_PACKAGES uses package=app_name format

### Runtime Detection Issues
```bash
# Check available container runtimes
which docker podman
# Check available compose tools
which docker-compose podman-compose
docker compose version  # For built-in Docker Compose
podman compose --help   # For built-in Podman Compose
```

## Contributing

To extend support for other Linux distributions:

1. Modify the package installation logic in `pdd.sh`
2. Add distribution detection in the `install_debian_packages` function
3. Implement package manager abstractions (apk, yum, zypper)
4. Update configuration options for different package names
5. Add support for non-Django Python projects

## Security Considerations

- **Privileged Access**: Tool requires container privileges to install packages
- **Network Access**: Downloads packages from public repositories
- **File Copying**: Copies host files into container (/.pdd directory)
- **Settings Modification**: Modifies Django settings.py (creates backup)
- **Package Sources**: Uses default package repositories (ensure they're trusted)
- **Environment Variables**: Injects custom environment variables into container

## License

Check the [LICENSE file](LICENSE) for more information.
