#!/bin/bash
# diy-part2: KICKPI K1 收尾（在 feeds install 之后执行）
#   board.d 追加独立网络脚本（官方标准机制，不覆盖官方 02_network）

set -e

echo ">>> diy-part2: pwd=$(pwd)"

# K1 双 GMAC：eth0=WAN、eth1=LAN（nanopi-r5c 同款惯例）
mkdir -p target/linux/rockchip/armv8/base-files/etc/board.d
cat > target/linux/rockchip/armv8/base-files/etc/board.d/03_kickpi-k1 <<'NETEOF'
#!/bin/sh
# KICKPI K1 (kickpi,k1) 双千兆网络划分
. /lib/functions/uci-defaults.sh
. /lib/functions/system.sh

board_config_update

case "$(board_name)" in
kickpi,k1)
	ucidef_set_interfaces_lan_wan 'eth1' 'eth0'
	;;
esac

board_config_flush
NETEOF
chmod +x target/linux/rockchip/armv8/base-files/etc/board.d/03_kickpi-k1
echo ">>> diy-part2: board.d/03_kickpi-k1 已写入:"
cat target/linux/rockchip/armv8/base-files/etc/board.d/03_kickpi-k1

# ══════════════════════════════════════════════════════════════════════════
# K1 板级运行时修复件（与 lyw-kk 同源，改成 OpenWrt 形态：init.d）
#   EEE/LPI：**不再关闭**（2026-10-17 改判：当初"EEE 开着 = 整口间歇掉线"的判据在 T68M 主路由上
#            被日志推翻 —— EEE 本就关闭时掉线仍发生，且每次都伴随对端重启；现按官方默认保持开启，
#            镜像里不得有任何 EEE 关闭件，CI 反向断言）
#   NVMe 开机自愈 —— pcie30 PHY 初始化早于其 0.9V/1.8V 模拟供电就绪，
#      冷启动可能 lock failed 不上盘；供电到位后重绑定 PCIe 即正常枚举
# ══════════════════════════════════════════════════════════════════════════
K1BF=target/linux/rockchip/armv8/base-files
mkdir -p "$K1BF/usr/local/sbin" "$K1BF/etc/init.d" "$K1BF/etc/rc.d"

# ②-a NVMe 自愈脚本（驱动目录动态探测：6.12 的 PCIe 驱动名与 6.1 不同也能用）
cat > "$K1BF/usr/local/sbin/kickpi-k1-nvme-selfheal.sh" <<'NVEOF'
#!/bin/sh
# KICKPI K1：pcie30 PHY 初始化可能早于其模拟供电就绪 → 冷启动 NVMe 不上盘。
# 供电到位后重绑定 PCIe 控制器即可正常枚举。快路径：已出盘则直接退出（零开销）。
[ -e /dev/nvme0 ] && exit 0
DEV=3c0800000.pcie
for d in /sys/bus/platform/drivers/*/; do
	[ -e "$d/$DEV" ] || continue
	DRV=${d%/}; DRV=${DRV##*/}
	i=1
	while [ "$i" -le 5 ]; do
		echo "$DEV" > "/sys/bus/platform/drivers/$DRV/unbind" 2>/dev/null
		sleep 1
		echo "$DEV" > "/sys/bus/platform/drivers/$DRV/bind" 2>/dev/null
		sleep 4
		if [ -e /dev/nvme0 ]; then
			logger -t kickpi-nvme "self-heal OK via $DRV (attempt $i)"
			exit 0
		fi
		i=$((i + 1))
	done
done
logger -t kickpi-nvme "self-heal failed after retries"
exit 1
NVEOF
chmod +x "$K1BF/usr/local/sbin/kickpi-k1-nvme-selfheal.sh"

# ②-b 开机执行
cat > "$K1BF/etc/init.d/kickpi-k1-nvme-selfheal" <<'RCEOF'
#!/bin/sh /etc/rc.common
START=98
boot() { /usr/local/sbin/kickpi-k1-nvme-selfheal.sh; }
start() { /usr/local/sbin/kickpi-k1-nvme-selfheal.sh; }
RCEOF
chmod +x "$K1BF/etc/init.d/kickpi-k1-nvme-selfheal"
ln -sf ../init.d/kickpi-k1-nvme-selfheal "$K1BF/etc/rc.d/S98kickpi-k1-nvme-selfheal"

# 自检：上面每一件都必须真就位（缺件直接让构建失败，不留"以为修了其实没有"）
for f in usr/local/sbin/kickpi-k1-nvme-selfheal.sh \
         etc/init.d/kickpi-k1-nvme-selfheal etc/rc.d/S98kickpi-k1-nvme-selfheal; do
	[ -e "$K1BF/$f" ] || { echo "!!! diy-part2: 缺件 $f"; exit 1; }
done
grep -q 'unbind' "$K1BF/usr/local/sbin/kickpi-k1-nvme-selfheal.sh" || { echo "!!! NVMe 自愈脚本内容不对"; exit 1; }
echo ">>> diy-part2: 板级运行时修复件（NVMe 自愈）已就位并通过自检"

echo ">>> diy-part2: 全部完成"
