import os
import sys

sys.path.insert(0, os.environ.get("WOW_ADDON_SIM", "D:/l/wow-addon-sim"))
pytest_plugins = ["wowaddonsim.pytest_plugin"]
