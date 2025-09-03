# Podman Django Debug

A powerful debugging toolkit that enhances Python containers with debugging tools, packages, and environment customization for development workflows.

## Overview

Podman Django Debug injects a customized Python environment into containers at runtime, automatically installing debugging packages, setting up development tools, and configuring the environment for enhanced debugging capabilities. It works by mounting a volume with configuration and scripts that modify the Python site-packages during container startup.

## Features

- **Automatic Package Installation**: Installs both pip and Debian packages on container startup
- **Environment Customization**: Sets custom environment variables for debugging
- **Django Integration**: Overlay Django settings for development environments
- **Flexible Configuration**: INI-based configuration for easy customization
- **Compose Support**: Works with both standalone containers and compose services

## Installation

### 1. Clone or Download the Project

```bash
git clone <repository-url> ~/.podman-django-debug
# or download and extract to ~/.podman-django-debug or your preferred location
```

### 2. Create Symbolic Link for Global Access

Create a symbolic link to make the script accessible from anywhere in your system:

```bash
sudo ln -s ~/.podman-django-debug/podman-django-debug.sh /usr/local/bin/podman-django-debug
```

**Alternative locations** (choose one based on your system and personal preference):
```bash
# For systems where /usr/local/bin is not in PATH
sudo ln -s ~/.podman-django-debug/podman-django-debug.sh /usr/bin/podman-django-debug

# For user-only installation (ensure ~/.local/bin is in PATH)
ln -s ~/.podman-django-debug/podman-django-debug.sh ~/.local/bin/podman-django-debug
```

### 3. Make the Script Executable

```bash
chmod +x ~/.podman-django-debug/podman-django-debug.sh
```

### 4. Verify the Installation

```bash
pjd --help
```

## Configuration

### settings.ini Setup - for all the configuration options  

The `settings.ini` file controls what packages and environment variables are injected into containers. Here's the configuration format:

```ini
[podman_django_debug]
additional_debian_packages = ["neovim", "bat", "curl", "git"]
additional_pip_packages = ["django_extensions", "ipdb", "pytest", "pytest-xdist", "pytest-django"]
additional_environment = {"PYTHONBREAKPOINT": "ipdb.set_trace", "DEBUG": "True"}
additional_django_settings = ["django_extensions"]
additional_django_apps = ["django_extensions"]
```

### Configuration Options

#### `additional_debian_packages`
List of Debian/Ubuntu packages to install via `apt`:
```ini
additional_debian_packages = ["neovim", "bat", "curl", "git", "htop"]
```

#### `additional_pip_packages`  
List of Python packages to install via `pip`:
```ini
additional_pip_packages = ["ipdb", "pytest", "black", "flake8", "mypy"]
```

#### `additional_environment`
Environment variables to set:
```ini
additional_environment = {"PYTHONBREAKPOINT": "ipdb.set_trace", "DEBUG": "True", "LOG_LEVEL": "DEBUG"}
```

#### `additional_django_settings` & `additional_django_apps`
Django-specific configuration for adding development apps:
```ini
additional_django_settings = ["django_extensions", "debug_toolbar"]
additional_django_apps = ["django_extensions", "debug_toolbar"]
```

### Example Configurations

#### Minimal Python Debugging
```ini
[podman_django_debug]
additional_debian_packages = []
additional_pip_packages = ["ipdb", "pytest"]
additional_environment = {"PYTHONBREAKPOINT": "ipdb.set_trace"}
additional_django_settings = []
additional_django_apps = []
```

#### Full Development Environment
```ini
[podman_django_debug]
additional_debian_packages = ["neovim", "bat", "curl", "git", "htop", "tree"]
additional_pip_packages = ["ipdb", "pytest", "pytest-django", "django_extensions", "black", "flake8", "mypy"]
additional_environment = {"PYTHONBREAKPOINT": "ipdb.set_trace", "DEBUG": "True", "PYTHONVERBOSE": "1"}
additional_django_settings = ["django_extensions", "debug_toolbar"]
additional_django_apps = ["django_extensions", "debug_toolbar"]
```

## Usage

### Basic Usage

```bash
# Run a container with debugging tools
pjd my-python-container bash

# Run a compose service
pjd web_service bash

# Run with additional podman options
pjd web_service --service-ports bash

# Run with environment variables
pjd web_service -e DATABASE_URL=postgres://localhost bash
```

### Advanced Usage

```bash
# Build and run with debugging
pjd web_service --build --service-ports bash

# Run specific command after setup
pjd web_service "python manage.py shell"

# Multiple podman options
pjd web_service --service-ports -e DEBUG=True --rm bash
```

### Command Structure

```
pjd [service/image] [podman-options...] [command]
```

- **service/image**: Container image or compose service name
- **podman-options**: Any valid podman/podman-compose options
- **command**: Command to run inside the container (defaults to bash)

## How It Works

1. **Volume Mount**: Mounts `~/.podman-django-debug` to `/pydebug` inside the container
2. **Script Injection**: Runs `entrypoint.py` which creates a `sitecustomize.py` file
3. **Package Installation**: Installs configured Debian and pip packages
4. **Environment Setup**: Sets environment variables and Django overlays
5. **Command Execution**: Runs the specified command with the enhanced environment

## Current Issues & Limitations

### ⚠️ Debian/Ubuntu Container Requirement

**Current Limitation**: The tool currently only works with Debian-based containers (Debian, Ubuntu, etc.) because:

- Uses `apt` package manager for system packages
- Assumes Debian package naming conventions
- Relies on Debian-style filesystem layout

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
5. **Python Version**: Requires Python 3.6+ for proper site-packages detection

## Troubleshooting

### Permission Errors
```bash
# Ensure script is executable
chmod +x ~/.podman-django-debug/pjd.sh

# Check symbolic link
ls -la /usr/local/bin/pjd
```

### Package Installation Failures
- Verify container has internet access
- Check if container runs as root or has sudo privileges
- Ensure container is Debian/Ubuntu based

### Configuration Issues
- Validate JSON syntax in settings.ini arrays
- Check file paths and permissions
- Verify environment variable syntax

## Contributing

To extend support for other Linux distributions:

1. Modify the package installation logic in `entrypoint.py`
2. Add distribution detection
3. Implement package manager abstractions (apk, yum, zypper)
4. Update configuration options for different package names

## Security Considerations

- **Privileged Access**: Tool requires container privileges to install packages
- **Network Access**: Downloads packages from public repositories
- **Volume Mounts**: Mounts host directory into container
- **Package Sources**: Uses default package repositories (ensure they're trusted)

## License

Check the [LICENSE file](LICENSE) for more information.
