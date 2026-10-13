# lyw-ki — KICKPI K1 的 iStoreOS 25.12 固件

KICKPI K1（RK3568B2，双千兆 Maxio MAE0621A）不在 iStoreOS 官方设备列表，
本仓库在官方 istoreos-25.12 源码上做最小板级注入，其余全部官方原生。

## 编译内容

- 源码：istoreos/istoreos @ istoreos-25.12（官方 25.12，内核 6.12）
- 设备：仅 kickpi_k1 单设备（不编其他设备）
- u-boot：官方 easepi-rk3568（与 T68M 同款，KK 线实机验证可引导 K1）

## 相对官方源码的全部改动（就这 4 处）

1. **K1 DTS**（`dts/rk3568-kickpi-k1.dts` → `target/linux/rockchip/dts/rk3568/`）
   骨架 = 官方 rk3568-t68m.dts（同为 RK3568+RK809）；板级数值 = 飞牛线实机
   验证值 + 厂商原厂 DTS 取证，逐段标注来源。与 T68M 的差异：gmac rgmii +
   MAC 侧 tx/rx_delay（0x21/0x3c、0x2f/0x39）、reset = eth1 **gpio2 PD3** / eth0 gpio3 PA7、LED/风扇
   gpio0 PD5/PD6、vdd_cpu = fan53555、按键 SARADC 1800000/1750、WiFi pwrseq
   1000ms、仅 pcie3x2 NVMe。
2. **Maxio MAE0621A PHY 驱动**（`kernel/maxio.c` + `kernel/100-*.patch`）
   双千兆命门。主线 6.12 无此驱动，注入 unifreq/linux-6.18.y 的 maxio.c；
   **EEE 关闭改用 6.12 API**（`phy_disable_eee_mode()` 在 6.12 已被 phylib 移除，
   照抄会 implicit declaration 让整发内核编译失败；改为 `linkmode_zero(advertising_eee)`
   + `eee_enabled=false` + `eee_cfg.eee_enabled=false`，与驱动里那笔 MMD 写
   `MDIO_AN_EEE_ADV=0` 双保险）。Kconfig/Makefile 锚在 iStoreOS 未改动的 motorcomm 行，
   CONFIG_MAXIO_PHY=y 编进内核。
3. **legacy.mk 设备定义**（diy-part1 追加）
   官方原生 `Device/Legacy/rk3568` 模板，`DEVICE_PACKAGES += kmod-nvme
   kmod-ata-ahci-dwc`。
4. **board.d 网络脚本**（diy-part2 写入 `03_kickpi-k1`）
   独立脚本走官方 board.d 标准机制（不覆盖官方 02_network）：
   eth0=WAN、eth1=LAN（nanopi-r5c 同款惯例）。

另：vermagic 修复（照抄 lyw，官方源 kmod 可装）。

## 已修的两个"只在实机/CI 才炸"的坑（2026-10-14）

1. **第二口 PHY 复位脚写错**：原写 `<&gpio3 RK_PB3>`（gpio3 pin 11），实机定案应为
   **GPIO2_D3**（`/pinctrl/gpio@fe750000` = gpio2，pin 0x1b = 27）——铁证是与
   **同板双口可用的飞牛线 DTB** 逐属性对照：`ethernet@fe2a0000` 只有这一处不同。
   写错的后果不是"网口性能差"，而是 PHY 被一直按在复位里 → MDIO 地址 0/1/2 全无应答 →
   `Cannot attach to PHY (error: -19)` 整口不可用。
2. **maxio.c 用了 6.12 已删除的 API**：`phy_disable_eee_mode()` 在 6.12 无声明 →
   内核编译 `implicit declaration` 直接失败（CI 首跑即挂）。
两条都已加进 workflow 的**板级静态门禁**（编译前断言 DTS 复位脚取值 + maxio.c 的 6.12 EEE 做法）。

## 已知限制（第一版）

- **无 WiFi**：K1 的 SWT6621S 是 SDIO WiFi，主线 6.12/iStoreOS 均无驱动。
  有线软路由/NAS 场景不受影响。
- HDMI 显示输出未验证（官方 dtsi 打底，理论可用）。
- fan53555 与 PWM 调速：风扇是 GPIO 直驱恒转（与实机一致），非 PWM 调速。

## 固件

Release 里 `istoreos-rockchip-armv8-kickpi_k1-squashfs-sysupgrade.img.gz`，
官方 sysupgrade 流程写入 TF 卡 / eMMC 均可。

## 定时编译

每天 18:30 UTC 检查上游 istoreos-25.12，有更新才重编（force_build 可强制）。
