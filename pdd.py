#!/usr/bin/env python3
import os
import site
import sys
from pathlib import Path
import configparser
import subprocess
import ast
import pip._internal
import shutil


class PDD:
    RED: str = "\033[0;31m"
    GREEN: str = "\033[0;32m"
    YELLOW: str = "\033[1;33m"
    CYAN: str = "\033[0;36m"
    BLUE: str = "\033[0;34m"
    NC: str = "\033[0m"
    IS_INSTALLED: bool
    IS_DEBUG: bool = False

    DJANGO_SETTINGS_MODULE: str
    DJANGO_SETTINGS_FILE: Path
    PROJECT_PATH: Path

    PDD_PATH: Path
    PYTHONVERBOSE: int

    settings: configparser.ConfigParser
    pdd_settings: configparser.SectionProxy

    def __init__(self, pdd_path: Path) -> None:
        self.IS_DEBUG = os.environ.get("PDD_DEBUG", "0") == "1"
        self.PDD_PATH = pdd_path
        self.IS_INSTALLED = os.environ.get("PDD_IS_INSTALLED", "0") == "1"
        self.PYTHONVERBOSE = 1 if self.IS_DEBUG else 0

        self.debug(f"PDD_PATH: {self.PDD_PATH}")

        if not os.isatty(sys.stdout.fileno()):
            self.RED = ""
            self.GREEN = ""
            self.YELLOW = ""
            self.CYAN = ""
            self.BLUE = ""
            self.NC = ""

        self.DJANGO_SETTINGS_MODULE = os.environ["DJANGO_SETTINGS_MODULE"]
        self.DJANGO_SETTINGS_FILE = self.get_original_settings_file()
        self.PROJECT_PATH = self.DJANGO_SETTINGS_FILE.parent
        self.backup_original_settings()

        # Get .ini settinges
        self.settings = configparser.ConfigParser()
        self.settings.read(self.PDD_PATH / "settings.ini")
        self.pdd_settings = self.settings["pdd"]

        self.pip_packages = ast.literal_eval(str(self.pdd_settings["pip_packages"]))
        self.debug(f"Pip packages: {self.pip_packages}")
        self.debian_packages = ast.literal_eval(
            str(self.pdd_settings["debian_packages"])
        )
        self.debug(f"Debian packages: {self.debian_packages}")

        self.pdd_django_apps = ast.literal_eval(str(self.pdd_settings["django_apps"]))
        self.pdd_django_settings = dict(self.settings["pdd.django_settings"])

    def get_original_settings_file(self) -> Path:
        app, _settings = self.DJANGO_SETTINGS_MODULE.split(".")
        return Path(app) / (_settings + ".py")

    def backup_original_settings(self) -> None:
        shutil.copy(
            self.DJANGO_SETTINGS_FILE,
            self.DJANGO_SETTINGS_FILE.with_suffix(".original.py"),
        )

    def info(self, message: str) -> None:
        print(f"{self.CYAN}[pdd]{self.NC} {message}")

    def warn(self, message: str) -> None:
        print(f"{self.YELLOW}[pdd]{self.NC} {message}")

    def error(self, message: str) -> None:
        print(f"{self.RED}[pdd]{self.NC} {message}")

    def debug(self, message: str) -> None:
        if self.IS_DEBUG:
            print(f"{self.BLUE}[pdd]{self.NC} {message}")

    def install_pip_packages(self) -> None:
        if not self.pip_packages:
            self.debug("No pip packages to install")
            return

        self.info(f"Installing pip packages: {self.pip_packages}")
        pip._internal.main(["install", *self.pip_packages])

    def install_debian_packages(self) -> None:
        if not self.debian_packages:
            self.debug("No debian packages to install")
            return

        self.info(f"Installing debian packages: {self.debian_packages}")
        subprocess.run(["apt", "update"], check=True, capture_output=True)
        subprocess.run(["apt", "install", "-y", *self.debian_packages], check=True)

    def prepare_django_apps_append(self) -> list[str]:
        return [f"INSTALLED_APPS += {app}" for app in self.pdd_django_apps]

    def prepare_django_settings_append(self) -> list[str]:
        return [
            f"{setting} = {value}"
            for setting, value in self.pdd_django_settings.items()
        ]

    def overwrite_django_settings(self) -> None:
        with open(self.DJANGO_SETTINGS_FILE, "a") as f:
            f.writelines(["\n"])
            f.writelines(["### PDD INJECTION ###"])
            f.writelines(["\n"])
            f.writelines(self.prepare_django_apps_append())
            f.writelines(self.prepare_django_settings_append())
            f.writelines(["\n"])

    def install(self) -> None:
        self.info("Starting to install pip packages")
        self.install_pip_packages()
        self.info("Starting to install debian packages")
        self.install_debian_packages()
        self.info("Starting to overwrite django settings")
        self.overwrite_django_settings()


if __name__ == "__main__":
    # Get first argument as PDD_PATH
    print(f"sys.argv: {sys.argv}")
    PDD_PATH = Path(sys.argv[1])
    pdd = PDD(PDD_PATH)
    pdd.info(f"PDD_PATH: {PDD_PATH}")
    pdd.info("Starting to install PDD on container")
    pdd.install()
