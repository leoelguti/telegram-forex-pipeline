import os
import tarfile
import sys

def create_bundle():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    root = os.path.abspath(os.path.join(script_dir, ".."))
    bundle_path = os.path.join(script_dir, "bundle_vps.tar.gz")

    EXCLUDE_DIRS = {
        '.venv', '.git', '__pycache__', 'node_modules',
        'mql5', '.cache', 'assets', 'types', '.pytest_cache'
    }
    EXCLUDE_EXTS = {
        '.log', '.zip', '.exe', '.pdf', '.tmp', '.tar.gz', '.bak'
    }
    EXCLUDE_FILES = {'logs.txt'}

    print("Empaquetando archivos del proyecto para el VPS...")
    with tarfile.open(bundle_path, "w:gz") as tar:
        for dirpath, dirnames, filenames in os.walk(root):
            # Avoid traversing excluded directories
            dirnames[:] = [d for d in dirnames if d not in EXCLUDE_DIRS]
            for f in filenames:
                ext = os.path.splitext(f)[1].lower()
                if ext in EXCLUDE_EXTS or f in EXCLUDE_FILES or "bundle_vps" in f:
                    continue
                abs_file = os.path.join(dirpath, f)
                rel_file = os.path.relpath(abs_file, root)
                tar.add(abs_file, arcname=rel_file)

    size_mb = os.path.getsize(bundle_path) / (1024 * 1024)
    print(f"Paquete listo: {bundle_path} ({size_mb:.2f} MB)")
    return bundle_path

if __name__ == "__main__":
    create_bundle()
