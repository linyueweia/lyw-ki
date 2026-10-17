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
   ~~EEE 关闭改用 6.12 API~~ → **2026-10-17 起 maxio.c 里不再关 EEE**（驱动侧只保留 PHY 初始化）；
   EEE 1G 改在 **DT 层**用 `eee-broken-1000t` 关闭（见下条与 README 的网口段），100M EEE 保持默认。
   **GPIO2_D3**（`/pinctrl/gpio@fe750000` = gpio2，pin 0x1b = 27）——铁证是与
   **同板双口可用的飞牛线 DTB** 逐属性对照：`ethernet@fe2a0000` 只有这一处不同。
   写错的后果不是"网口性能差"，而是 PHY 被一直按在复位里 → MDIO 地址 0/1/2 全无应答 →
   `Cannot attach to PHY (error: -19)` 整口不可用。
2. **EEE 1G 的处理位置（2026-10-17 定案）**：DTS 的两个 PHY 节点写 `eee-broken-1000t`，
   由内核 `of_set_phy_eee_broken()` 在每次自协商清掉 1000T 的 EEE 通告位；实测证据见下：
   EEE 开着时 K1 的 `irq_rx_path_in_lpi_mode_n` 涨到 1400 万、`phy_eee_wakeup_error_n` 241，
   表现为"灯亮、能发不能收"（ARP/DHCP 发得出去、收不到回应，ping 100% 丢而 carrier 不变），
   对端关 EEE + 重协商后立刻恢复 0% 丢包。maxio.c 里**不再**写任何关 EEE 的代码。
> 门禁自身的坑（已修）：第 2 条最初用裸 `grep -q 'phy_disable_eee_mode'` 判定，
> 而 maxio.c 的**注释**里正好提到这个函数名（用来解释为何改成 6.12 写法）→
> 假阳性把 CI 拦死。现在先剥掉 `//` 与 `/* */` 注释再判定：注释提及不算，
> 真实调用仍会被拦下（有正反两个用例自证）。

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
