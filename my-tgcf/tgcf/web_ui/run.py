import os
import subprocess
import sys

from tgcf.config import CONFIG

package_dir = os.path.dirname(os.path.abspath(__file__))

def main():
    print(package_dir)
    path = os.path.join(package_dir, "0_👋_Hello.py")
    os.environ["STREAMLIT_THEME_BASE"] = CONFIG.theme
    os.environ["STREAMLIT_BROWSER_GATHER_USAGE_STATS"] = "false"
    os.environ["STREAMLIT_SERVER_HEADLESS"] = "true"
    subprocess.run([sys.executable, "-m", "streamlit", "run", path])
