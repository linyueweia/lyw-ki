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
# K1 板级运行时修复件（与 lyw-kk 同源，改成 OpenWrt 形态：init.d + hotplug）
#   ① EEE/LPI 全关 —— 实机定案：EEE 开着会"整口间歇 Link Down/丢 IP"
#      （对端 phy_eee_wakeup_error_n=8126、LPI 进出 7800 万次；关掉掉线归零）
#   ② NVMe 开机自愈 —— pcie30 PHY 初始化早于其 0.9V/1.8V 模拟供电就绪，
#      冷启动可能 lock failed 不上盘；供电到位后重绑定 PCIe 即正常枚举
# ══════════════════════════════════════════════════════════════════════════
K1BF=target/linux/rockchip/armv8/base-files
mkdir -p "$K1BF/usr/local/sbin" "$K1BF/etc/hotplug.d/iface" "$K1BF/etc/init.d" "$K1BF/etc/rc.d"

# ①-a 关闭脚本（幂等，遍历所有真实网卡，含 USB 网卡）
cat > "$K1BF/usr/local/sbin/kickpi-k1-eee-off.sh" <<'EEEEOF'
#!/bin/sh
# KICKPI K1：关闭所有真实网卡的 EEE/LPI 省电，并把运行时电源管理钉为 on。
# 幂等：可反复执行（开机一次 + 每次接口 up 一次）。
ETHTOOL="$(command -v ethtool 2>/dev/null || echo /usr/sbin/ethtool)"
[ -x "$ETHTOOL" ] || { logger -t kickpi-eee "ethtool 缺失，EEE 未关"; exit 1; }
attempt=0
while [ "$attempt" -lt 15 ]; do
	attempt=$((attempt + 1)); pending=0
	for d in /sys/class/net/*; do
		[ -e "$d" ] || continue
		nic=${d##*/}
		case "$nic" in lo|docker*|veth*|br-*|virbr*|wg*|tailscale*|tun*|p2p*) continue ;; esac
		"$ETHTOOL" --set-eee "$nic" tx-lpi off 2>/dev/null || true
		"$ETHTOOL" --set-eee "$nic" rx-lpi off 2>/dev/null || true
		if ! "$ETHTOOL" --set-eee "$nic" eee off 2>/dev/null; then
			"$ETHTOOL" --show-eee "$nic" >/dev/null 2>&1 && pending=1
		fi
		pm="$d/device/power/control"
		[ -w "$pm" ] && echo on > "$pm" 2>/dev/null
	done
	[ "$pending" -eq 0 ] && break
	sleep 2
done
exit 0
EEEEOF
chmod +x "$K1BF/usr/local/sbin/kickpi-k1-eee-off.sh"

# ①-b 每次接口 up 之后再关一次（PHY 会在 link-up 时把 EEE 重新协商打开）
cat > "$K1BF/etc/hotplug.d/iface/99-kickpi-k1-eee-off" <<'HPEOF'
#!/bin/sh
# netifd 的 interface hotplug：ifup 之后重关 EEE（幂等）
[ "$ACTION" = "ifup" ] || exit 0
/usr/local/sbin/kickpi-k1-eee-off.sh >/dev/null 2>&1 &
exit 0
HPEOF
chmod +x "$K1BF/etc/hotplug.d/iface/99-kickpi-k1-eee-off"

# ①-c 开机执行一次
cat > "$K1BF/etc/init.d/kickpi-k1-eee-off" <<'RCEOF'
#!/bin/sh /etc/rc.common
START=99
boot() { /usr/local/sbin/kickpi-k1-eee-off.sh; }
start() { /usr/local/sbin/kickpi-k1-eee-off.sh; }
RCEOF
chmod +x "$K1BF/etc/init.d/kickpi-k1-eee-off"
ln -sf ../init.d/kickpi-k1-eee-off "$K1BF/etc/rc.d/S99kickpi-k1-eee-off"

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
for f in usr/local/sbin/kickpi-k1-eee-off.sh \
         etc/hotplug.d/iface/99-kickpi-k1-eee-off \
         etc/init.d/kickpi-k1-eee-off etc/rc.d/S99kickpi-k1-eee-off \
         usr/local/sbin/kickpi-k1-nvme-selfheal.sh \
         etc/init.d/kickpi-k1-nvme-selfheal etc/rc.d/S98kickpi-k1-nvme-selfheal; do
	[ -e "$K1BF/$f" ] || { echo "!!! diy-part2: 缺件 $f"; exit 1; }
done
grep -q -- '--set-eee' "$K1BF/usr/local/sbin/kickpi-k1-eee-off.sh" || { echo "!!! EEE 脚本内容不对"; exit 1; }
grep -q 'unbind' "$K1BF/usr/local/sbin/kickpi-k1-nvme-selfheal.sh" || { echo "!!! NVMe 自愈脚本内容不对"; exit 1; }
echo ">>> diy-part2: 板级运行时修复件（EEE 三层 + NVMe 自愈）已就位并通过自检"

echo ">>> diy-part2: 全部完成"
