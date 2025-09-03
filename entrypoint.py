#!/usr/bin/env python3

import os
import site
import sys
import inspect

# Find the site-packages directory
site_packages = site.getsitepackages()[0]
sitecustomize_path = os.path.join(site_packages, "sitecustomize.py")

# Colors for output if terminal supports it
if os.isatty(sys.stdout.fileno()):
    colors = {
        "red": "\033[0;31m",
        "green": "\033[0;32m",
        "yellow": "\033[1;33m",
        "cyan": "\033[0;36m",
        "blue": "\033[0;34m",
        "nc": "\033[0m",
    }
else:
    colors = {
        "red": "",
        "green": "",
        "yellow": "",
        "cyan": "",
        "blue": "",
        "nc": "",
    }


def info(message):
    print(f"{colors['cyan']}[podman_dd]{colors['nc']} {message}")


def warn(message):
    print(f"{colors['yellow']}[podman_dd]{colors['nc']} {message}")


def error(message):
    print(f"{colors['red']}[podman_dd]{colors['nc']} {message}")


info(f"Site-packages directory: {site_packages}")
info(f"Creating/updating sitecustomize.py at: {sitecustomize_path}")

# Check if we have write permission to the directory
if not os.access(os.path.dirname(sitecustomize_path), os.W_OK):
    error(f"You don't have write permission to {site_packages}")
    error("Try running the script with sudo or as an administrator")
    sys.exit(1)


def entrypoint():
    import configparser
    import os
    import subprocess
    import sys
    import ast
    import pip._internal
    import shutil

    from importlib import metadata
    from pathlib import Path

    if os.isatty(sys.stdout.fileno()):
        colors = {
            "red": "\033[0;31m",
            "green": "\033[0;32m",
            "yellow": "\033[1;33m",
            "cyan": "\033[0;36m",
            "blue": "\033[0;34m",
            "nc": "\033[0m",
        }
    else:
        colors = {
            "red": "",
            "green": "",
            "yellow": "",
            "cyan": "",
            "blue": "",
            "nc": "",
        }

    def info(message):
        print(f"{colors['cyan']}[podman_dd]{colors['nc']} {message}")

    def warn(message):
        print(f"{colors['yellow']}[podman_dd]{colors['nc']} {message}")

    if os.environ.get("PODMAN_DD_INSTALLED", "0") == "1":
        warn("Podman DD is already installed")
        return

    os.environ["PYTHONVERBOSE"] = "1"

    # Copy original settings.py to the podman dd path
    original_settings_file = os.environ["DJANGO_SETTINGS_MODULE"]
    app, _settings = original_settings_file.split(".")

    original_settings_file = Path(app) / (_settings + ".py")
    backup_settings_file = Path(os.environ["PODMAN_DD_PATH"]) / (
        _settings + ".original.py"
    )

    shutil.copy(original_settings_file, backup_settings_file)

    podman_dd_path = os.environ["PODMAN_DD_PATH"]
    settings_file = os.path.join(podman_dd_path, "settings.ini")
    settings = configparser.ConfigParser()
    settings.read(settings_file)

    podman_dd = settings["podman_dd"]
    pip_packages = ast.literal_eval(podman_dd["additional_pip_packages"])
    debian_packages = ast.literal_eval(podman_dd["additional_debian_packages"])
    additional_environment = ast.literal_eval(podman_dd["additional_environment"])

    pip_packages_to_install = []
    if pip_packages:
        for package in pip_packages:
            try:
                metadata.version(package)
            except metadata.PackageNotFoundError:
                info(f"Will install pip package: {package}")
                pip_packages_to_install.append(package)

    if pip_packages_to_install:
        info(f"Installing pip packages: {pip_packages_to_install}")
        pip._internal.main(["install", *pip_packages_to_install])

    if additional_environment:
        for environment, value in additional_environment.items():
            info(
                f"[podman_dd] Setting additional system environment: {environment}={value}"
            )
            os.putenv(environment, value)

    if debian_packages:
        info(f"Installing debian packages: {debian_packages}")
        subprocess.run(["apt", "update"], check=True, capture_output=True)
        subprocess.run(["apt", "install", "-y", *debian_packages], check=True)

    os.environ["PYTHONVERBOSE"] = "0"


source_code = inspect.getsource(entrypoint)
sitecustomize_content = f"""
{source_code}
entrypoint()
"""

# Write the content to the file
try:
    with open(sitecustomize_path, "w") as f:
        f.write(sitecustomize_content)
    info(f"Successfully wrote sitecustomize.py to {sitecustomize_path}")
except Exception as e:
    error(f"Error writing sitecustomize.py to {sitecustomize_path}: {e}")
    sys.exit(1)
