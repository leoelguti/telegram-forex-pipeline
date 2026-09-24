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
    os.environ["STREAMLIT_SERVER_ADDRESS"] = "0.0.0.0"
    os.environ["STREAMLIT_SERVER_PORT"] = "8501"
    subprocess.run([
        sys.executable, "-m", "streamlit", "run", path,
        "--server.address", "0.0.0.0",
        "--server.port", "8501",
        "--server.headless", "true"
    ])
