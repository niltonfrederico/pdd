import os
import configparser
from pathlib import Path

if os.environ["PODMAN_DD_INSTALLED"] == "1":
    exit(0)

# Get backup settings file
original_django_settings = "scripts/podman_dd/settings.original.py"

# Get current settings file
current_django_settings = os.environ["DJANGO_SETTINGS_MODULE"]

app, _settings = current_django_settings.split(".")
current_django_settings = Path("/app") / Path(app) / (_settings + ".py")


# Overriden settings
PODMAN_DD = os.environ["PODMAN_DD"] == "1"
settings = configparser.ConfigParser()
settings.read(f"{os.environ['PODMAN_DD_PATH']}/settings.ini")

if not PODMAN_DD:
    exit(0)

lines_to_write = []

with open(original_django_settings, "r") as f:
    lines = f.read()

additional_apps = settings["podman_dd"]["additional_django_apps"]
additional_settings = dict(settings["podman_dd.django_settings"])

lines_to_write.append("\n")

if additional_apps:
    lines_to_write.append(f"INSTALLED_APPS += {additional_apps}\n")

if additional_settings:
    for setting, value in additional_settings.items():
        lines_to_write.append(f"{setting.upper()} = {value}\n")

with open(current_django_settings, "a") as f:
    f.writelines(lines_to_write)
