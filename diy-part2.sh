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

echo ">>> diy-part2: 全部完成"
