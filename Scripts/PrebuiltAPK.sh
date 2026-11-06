
#!/bin/bash
set -euo pipefail

echo "=========================================="
echo "       Prepare Prebuilt apk"
echo "=========================================="

ARCH="aarch64_cortex-a53"

APK="./staging_dir/host/bin/apk"

BASE_REPO="https://downloads.openwrt.org/releases/25.12.6/packages/${ARCH}/base/packages.adb"

PACKAGES_REPO="https://downloads.openwrt.org/releases/25.12.6/packages/${ARCH}/packages/packages.adb"

# 官方 APK 下载目录
OUT="./bin/packages/${ARCH}/packages"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$OUT"

if [ ! -x "$APK" ]; then
    echo "ERROR: Host APK tool not found: $APK"
    exit 1
fi

# APK 仓库参数
APK_ARGS=(
    --allow-untrusted
    --arch "$ARCH"
    --repositories-file /dev/null
    --repository "$BASE_REPO"
    --repository "$PACKAGES_REPO"
)

echo "[1/4] Download Podman dependencies..."

# 先下载用户态依赖及其递归依赖
"$APK" "${APK_ARGS[@]}" fetch \
    --recursive \
    --output "$TMP" \
    conmon \
    libgpgme \
    libseccomp \
    nsenter \
    zoneinfo-simple \
    slirp4netns \
    netavark \
    aardvark-dns \
    catatonit \
    crun

echo "[2/4] Download Podman..."

# Podman 本体单独下载，不递归拉取内核模块
"$APK" "${APK_ARGS[@]}" fetch \
    --output "$TMP" \
    podman

echo "[3/4] Copy APK packages..."

# 不使用官方内核模块，保留 LibWrt 自己编译的 kmod
rm -f "$TMP"/kmod-*.apk

find "$TMP" -maxdepth 1 -type f -name '*.apk' \
    -exec cp -f {} "$OUT/" \;

# 检查 Podman 是否下载成功
if ! ls "$OUT"/podman-*.apk >/dev/null 2>&1; then
    echo "ERROR: Podman APK not found!"
    exit 1
fi

echo "[4/4] Add Podman to rootfs install list..."

# 修改 LibWrt 的 rootfs 安装流程
python3 <<'PY'
from pathlib import Path

path = Path("package/Makefile")
content = path.read_text()

marker = "\t$(call apk,$(TARGET_DIR)) add --no-cache --initdb"

if "echo podman >> $(TMP_DIR)/apk_install_list" in content:
    print("Podman install hook already exists")
elif marker in content:
    content = content.replace(
        marker,
        "\techo podman >> $(TMP_DIR)/apk_install_list\n" + marker,
        1
    )
    path.write_text(content)
    print("Podman added to rootfs install list")
else:
    raise SystemExit("ERROR: Cannot find APK rootfs install command")
PY

echo "=========================================="
echo "Prebuilt Podman preparation completed"
echo "APK count: $(find "$OUT" -maxdepth 1 -name '*.apk' | wc -l)"
echo "=========================================="
