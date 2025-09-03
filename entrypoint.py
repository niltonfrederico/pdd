#!/usr/bin/env python3

import os
import site
import sys
import inspect

# Find the site-packages directory
site_packages = site.getsitepackages()[0]
sitecustomize_path = os.path.join(site_packages, "sitecustomize.py")

print(f"Site-packages directory: {site_packages}")
print(f"Creating/updating sitecustomize.py at: {sitecustomize_path}")

# Check if we have write permission to the directory
if not os.access(os.path.dirname(sitecustomize_path), os.W_OK):
    print(f"You don't have write permission to {site_packages}")
    print("Try running the script with sudo or as an administrator")
    sys.exit(1)

def entrypoint():
    import configparser
    import os
    import subprocess
    import ast
    import pip._internal

    from importlib import metadata

    os.environ["PYTHONVERBOSE"] = "1"

    pydebug_scripts_dir = os.environ["PODMAN_PYDEBUG_FOLDER"]
    settings_file = os.path.join(pydebug_scripts_dir, "settings.ini")
    settings = configparser.ConfigParser()
    settings.read(settings_file)

    podman_pydebug = settings["podman_pydebug"]
    pip_packages = ast.literal_eval(podman_pydebug["additional_pip_packages"])
    debian_packages = ast.literal_eval(podman_pydebug["additional_debian_packages"])
    additional_environment = ast.literal_eval(podman_pydebug["additional_environment"])

    pip_packages_to_install = []
    if pip_packages:
        for package in pip_packages:
            try:
                metadata.version(package)
            except metadata.PackageNotFoundError:
                print("[podman-pydebug] will install pip package: ", package)
                pip_packages_to_install.append(package)

    if pip_packages_to_install:
        print("[podman-pydebug] installing pip packages: ", pip_packages_to_install)
        pip._internal.main(["install", *pip_packages_to_install])

    if additional_environment:
        for environment, value in additional_environment.items():
            print("[podman-pydebug] setting additional environment: ", environment, "=", value)
            os.environ[environment] = value
    
    if debian_packages:
        print("[podman-pydebug] installing debian packages: ", debian_packages)
        subprocess.run(['apt', 'update'], check=True, capture_output=True)
        subprocess.run(['apt', 'install', '-y', *debian_packages], check=True)
        

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
    print(f"[podman-pydebug] Successfully wrote to {sitecustomize_path}")
except Exception as e:
    print(f"[podman-pydebug] Error writing to {sitecustomize_path}: {e}")
    sys.exit(1)

print("[podman-pydebug] Wrote sitecustomize.py!")
