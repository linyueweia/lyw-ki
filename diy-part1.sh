#!/bin/bash
# diy-part1: KICKPI K1 板级注入（在 feeds update 之前执行）
#   1. vermagic 修复（与官方软件源内核模块 hash 一致，官方源 kmod 可装）
#   2. 注入 K1 DTS + 内核 Maxio MAE0621A PHY 驱动（双千兆命门）
#   3. legacy.mk 追加 K1 设备定义（官方原生 Device/Legacy/rk3568 模板）

set -e

echo ">>> diy-part1: pwd=$(pwd)"

# ============ 1. vermagic ============
hash_value=""
Releases_version=""
if [ -f include/version.mk ]; then
    Releases_version=$(sed -n 's|.*openwrt.org/releases/\([0-9.]*\).*|\1|p' include/version.mk | head -1)
fi
if [ -z "$Releases_version" ]; then
    Releases_version=$(cat package/base-files/image-config.in 2>/dev/null | sed -n 's|.*releases/\([^\"]*\)".*|\1|p')
fi
echo ">>> diy-part1: OpenWrt releases 版本 = ${Releases_version:-未知}"

if [ -n "$Releases_version" ]; then
    for base_url in \
        "https://downloads.openwrt.org/releases/${Releases_version}/targets/rockchip/armv8/kmods/" \
        "https://mirrors.tuna.tsinghua.edu.cn/openwrt/releases/${Releases_version}/targets/rockchip/armv8/kmods/" \
        "https://mirrors.ustc.edu.cn/openwrt/releases/${Releases_version}/targets/rockchip/armv8/kmods/" \
        "https://mirrors.cernet.edu.cn/openwrt/releases/${Releases_version}/targets/rockchip/armv8/kmods/" \
        "https://archive.openwrt.org/releases/${Releases_version}/targets/rockchip/armv8/kmods/" ; do
        http_value=$(wget -qO- --timeout=20 "$base_url" 2>/dev/null || true)
        hash_value=$(echo "$http_value" | sed -n 's/.*-\([0-9a-f]\{32\}\)\/.*/\1/p' | head -1)
        if [ -n "$hash_value" ]; then
            echo ">>> diy-part1: 从 $base_url 抓到官方 kmod hash = $hash_value"
            break
        fi
    done
fi

if [ -n "$hash_value" ] && [[ "$hash_value" =~ ^[0-9a-f]{32}$ ]] && [ -f include/version.mk ]; then
    echo "$hash_value" > .vermagic
    echo ">>> diy-part1: 已写入 .vermagic = $hash_value"
else
    echo ">>> diy-part1: 未抓到官方 kmod hash, 按本机 .config 计算 vermagic"
fi

# ============ 2. K1 DTS ============
mkdir -p target/linux/rockchip/dts/rk3568
cp -f "$GITHUB_WORKSPACE/dts/rk3568-kickpi-k1.dts" target/linux/rockchip/dts/rk3568/rk3568-kickpi-k1.dts
echo ">>> diy-part1: K1 DTS 已就位"
for marker in '"KICKPI K1"' 'fan53555-reg' 'tx_delay = <0x21>' 'rx_delay = <0x3c>' \
              'tx_delay = <0x2f>' 'rx_delay = <0x39>' 'RK_PD3' 'RK_PA7' 'post-power-on-delay-ms = <1000>' \
              'gpio = <&gpio0 RK_PD4 GPIO_ACTIVE_HIGH>' 'pcie3-power-en' 'pcie30-avdd0v9' 'pcie30-avdd1v8'; do
    if grep -qF "$marker" target/linux/rockchip/dts/rk3568/rk3568-kickpi-k1.dts; then
        echo "    marker OK: $marker"
    else
        echo "!!! marker NOT FOUND: $marker"; exit 1
    fi
done
# 反向门禁：pcie30phy 绝不能再出现 data-lanes（KK 实机定案：写了必 lock failed）
if grep -qE 'pcie30phy *\{' target/linux/rockchip/dts/rk3568/rk3568-kickpi-k1.dts; then
    if sed -n '/&pcie30phy *{/,/};/p' target/linux/rockchip/dts/rk3568/rk3568-kickpi-k1.dts | grep -qE '^[[:space:]]*data-lanes'; then
        echo "!!! &pcie30phy 里出现了 data-lanes —— 实机定案会 lock failed，必须删掉"; exit 1
    fi
    echo "    marker OK: &pcie30phy 无 data-lanes（反向门禁）"
fi

# ============ 3. Maxio MAE0621A PHY 驱动（双千兆命门）============
# 3a. 驱动源码 -> target/linux/rockchip/files/（OpenWrt 自动 overlay 进内核树）
mkdir -p target/linux/rockchip/files/drivers/net/phy
cp -f "$GITHUB_WORKSPACE/kernel/maxio.c" target/linux/rockchip/files/drivers/net/phy/maxio.c
# 3b. Makefile/Kconfig 补丁 -> patches-6.12（quilt 自动应用）
mkdir -p target/linux/rockchip/patches-6.12
cp -f "$GITHUB_WORKSPACE/kernel/100-net-phy-add-maxio-mae0621a.patch" \
      target/linux/rockchip/patches-6.12/100-net-phy-add-maxio-mae0621a.patch
# 3c. 内核配置打开 CONFIG_MAXIO_PHY=y（编进内核，非模块）
echo "CONFIG_MAXIO_PHY=y" >> target/linux/rockchip/armv8/config-6.12
echo ">>> diy-part1: Maxio PHY 驱动已注入（files + patch + config）"
grep -n "MAXIO" target/linux/rockchip/armv8/config-6.12

# ============ 4. legacy.mk 追加 K1 设备定义 ============
cat >> target/linux/rockchip/image/legacy.mk <<'DEVEOF'

# KICKPI K1 (RK3568B2, 双 Maxio MAE0621A GbE) —— 非官方列表设备，本仓库新增
define Device/kickpi_k1
$(call Device/Legacy/rk3568,$(1))
  DEVICE_VENDOR := KICKPI
  DEVICE_MODEL := K1
  DEVICE_DTS := rk3568/rk3568-kickpi-k1
  DEVICE_PACKAGES += kmod-nvme kmod-ata-ahci-dwc
endef
TARGET_DEVICES += kickpi_k1
DEVEOF
echo ">>> diy-part1: legacy.mk 设备定义已追加"
tail -12 target/linux/rockchip/image/legacy.mk

echo ">>> diy-part1: 全部完成"
