#!/usr/bin/env python3

import os
import site
import sys
import inspect

# Find the site-packages directory
site_packages = site.getsitepackages()[0]
sitecustomize_path = os.path.join(site_packages, "sitecustomize.py")

print(f"[podman_dd] Site-packages directory: {site_packages}")
print(f"[podman_dd] Creating/updating sitecustomize.py at: {sitecustomize_path}")

# Check if we have write permission to the directory
if not os.access(os.path.dirname(sitecustomize_path), os.W_OK):
    print(f"[podman_dd] You don't have write permission to {site_packages}")
    print("[podman_dd] Try running the script with sudo or as an administrator")
    sys.exit(1)


def entrypoint():
    import configparser
    import os
    import subprocess
    import ast
    import pip._internal

    from importlib import metadata

    if os.environ.get("PODMAN_DD_INSTALLED", "0") == "1":
        print("[podman_dd] Podman DD is already installed")
        return

    os.environ["PYTHONVERBOSE"] = "1"

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
                print("[podman_dd] Will install pip package: ", package)
                pip_packages_to_install.append(package)

    if pip_packages_to_install:
        print("[podman_dd] Installing pip packages: ", pip_packages_to_install)
        pip._internal.main(["install", *pip_packages_to_install])

    if additional_environment:
        for environment, value in additional_environment.items():
            print(
                "[podman_dd] Setting additional system environment: ",
                environment,
                "=",
                value,
            )
            os.putenv(environment, value)

    if debian_packages:
        print("[podman_dd] Installing debian packages: ", debian_packages)
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
    print(f"[podman_dd] Successfully wrote sitecustomize.py to {sitecustomize_path}")
except Exception as e:
    print(f"[podman_dd] Error writing sitecustomize.py to {sitecustomize_path}: {e}")
    sys.exit(1)
