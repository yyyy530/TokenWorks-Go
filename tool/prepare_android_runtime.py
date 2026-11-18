"""Stage the Linux components from the pinned, official ARM64 dsh-Go release."""

import argparse
import hashlib
import json
import shutil
import tempfile
from pathlib import Path
from zipfile import ZipFile


UPSTREAM = "ccch1mneyyy/dsh-Go v1.1.0 ARM64"
APK_SHA256 = "ec7d9ffbfb6cf3d5d8b0c19cd34a5933df00b9290cfe9d6dbdc05337308b3037"
ROOTFS_SHA256 = "dc3cd9cb9c88935139118621be469c073ce46c808732fb9f1eda8ff253df06ca"
ROOTFS_NAME = "rootfs-arm64-v8a.tar.xz"
ROOTFS_BYTES = 159570076
ABI = "arm64-v8a"
RUNTIME_DIR = Path(__file__).resolve().parents[1] / "app/android/runtime-bundle"
LIBRARIES = ("libproot.so", "libproot-loader.so", "libtalloc.so", "libandroid-shmem.so")
LICENSES = ("proot-COPYING.txt", "libtalloc-notice.txt", "libandroid-shmem-copyright.txt")


def digest(path: Path) -> str:
    with path.open("rb") as contents:
        return hashlib.file_digest(contents, "sha256").hexdigest()


def copy_member(apk: ZipFile, name: str, target: Path) -> None:
    target.parent.mkdir(parents=True, exist_ok=True)
    with apk.open(name) as source, target.open("wb") as destination:
        shutil.copyfileobj(source, destination, length=1024 * 1024)


def prepare(apk_path: Path) -> None:
    if digest(apk_path) != APK_SHA256:
        raise ValueError(f"APK SHA-256 does not match {UPSTREAM}")

    with ZipFile(apk_path) as apk, tempfile.TemporaryDirectory(dir=RUNTIME_DIR.parent) as temp:
        source = json.loads(apk.read("assets/runtime/manifest.json"))
        expected = (ABI, ROOTFS_NAME, ROOTFS_SHA256, ROOTFS_BYTES)
        actual = tuple(source[key] for key in ("abi", "rootfs", "rootfsSha256", "rootfsBytes"))
        if actual != expected:
            raise ValueError("Upstream runtime manifest does not match the pinned release")

        bundle = Path(temp) / "bundle"
        assets = bundle / "assets/tokenworks/runtime"
        rootfs = assets / ROOTFS_NAME
        copy_member(apk, f"assets/runtime/{ROOTFS_NAME}", rootfs)
        if rootfs.stat().st_size != ROOTFS_BYTES or digest(rootfs) != ROOTFS_SHA256:
            raise ValueError("The embedded rootfs did not pass verification")
        for library in LIBRARIES:
            copy_member(apk, f"lib/{ABI}/{library}", bundle / f"jniLibs/{ABI}/{library}")
        for notice in LICENSES:
            copy_member(apk, f"assets/runtime/licenses/{notice}", assets / "licenses" / notice)
        manifest = {key: source[key] for key in (
            "abi", "runtimeVersion", "rootfs", "rootfsSha256", "rootfsBytes",
            "uncompressedBytes", "dshVersion", "nodeVersion", "ubuntuVersion",
        )}
        (assets / "manifest.json").write_text(
            json.dumps(manifest, indent=2) + "\n", encoding="utf-8",
        )

        if RUNTIME_DIR.exists():
            actual_files = {item.relative_to(RUNTIME_DIR) for item in RUNTIME_DIR.rglob("*") if item.is_file()}
            expected_files = {item.relative_to(bundle) for item in bundle.rglob("*") if item.is_file()}
            if actual_files != expected_files or any(
                digest(RUNTIME_DIR / item) != digest(bundle / item) for item in expected_files
            ):
                raise ValueError(f"An existing bundle differs from the verified input at {RUNTIME_DIR}")
        else:
            bundle.rename(RUNTIME_DIR)
    print(f"Verified {UPSTREAM} runtime at {RUNTIME_DIR}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("apk", type=Path, help="Path to the official dsh-go-1.1.0-arm64.apk")
    prepare(parser.parse_args().apk)
