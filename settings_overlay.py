import os
import configparser
from importlib import import_module

original_django_settings = os.environ["DJANGO_SETTINGS_MODULE"]

# import everything from the original django settings
original_settings = import_module(original_django_settings)
globals().update(original_settings.__dict__)

# Overriden settings
PODMAN_DJANGO_DEBUG = os.environ["PODMAN_DJANGO_DEBUG"] == "1"
settings = configparser.ConfigParser()
settings.read("settings.ini")

if PODMAN_DJANGO_DEBUG:
    overlay_apps = settings.get("additional_django_settings", "INSTALLED_APPS").split(",")

    for app in overlay_apps:
        if app not in original_settings.INSTALLED_APPS:
            print("[podman_django_debug] overlaying django app: ", app)
            original_settings.INSTALLED_APPS.append(app)

    original_installed_apps_set = set(original_settings.INSTALLED_APPS)

    INSTALLED_APPS = list(original_installed_apps_set.union(overlay_apps))

# Change the settings variable to overlay settings
os.environ["DJANGO_SETTINGS_MODULE"] = original_django_settings
