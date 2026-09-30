# amnezia-ru-split

[English](README.md) | [Русский](README.ru.md) | 简体中文

在 Linux 上开启 AmneziaVPN 时让俄罗斯网站直连，并避免 VPN 一连上就把网络断掉。

这不是客户端本身的插件，而是一个小型的 root 辅助脚本，配合 NetworkManager 钩子和 systemd 定时器使用。它不会修改客户端及其设置。

## 解决什么问题

1. **俄罗斯网站直连。** 选定的公网 IPv4 网段通过物理网关走直连，其余流量走 VPN。脚本会添加路由（`proto 186 metric 42760`），并在 Amnezia 的断网开关（kill switch）链 `amnvpn.110.allowNets` 中为 80/443 端口添加 `ACCEPT` 规则；没有这些规则，kill switch 会丢弃这部分流量。
2. **“一连接 VPN 网络就断了”。** AmneziaVPN 守护进程用 8 KiB 的缓冲区读取路由表。如果路由表转储更大（第 1 项中的 160 多条路由会使其变大），守护进程就找不到网关，日志里出现 `No default gateway available, skipping exclusion route`，也不会把 VPN 服务器从隧道中排除。于是 VPN 自身的 UDP 包被送进 `amn0`，握手无法完成，kill switch 又阻断所有流量。脚本会通过物理网关为服务器保留一条固定路由，这样问题就不再出现。

检查你是否受影响：运行 `tools/netlink-check.py`（无需 root），它会模拟这种读取并输出 `AFFECTED` 或 `OK`。

关于结论的可靠性：原因是通过模拟 netlink 读取并与守护进程日志比对得出的，并没有阅读守护进程的源代码。测试环境：AmneziaVPN 5.0.3.0（AmneziaWG）、Arch Linux、内核 7.2.8。

## 环境要求

Linux、AmneziaVPN、NetworkManager、systemd、iptables、iproute2、python3、curl（用于 `health`）。

## 安装

```sh
sudo install -d /etc/amnezia-ru-split
sudo install -m 644 examples/vpn-endpoints.example /etc/amnezia-ru-split/vpn-endpoints   # 填入你的服务器 IP
cp examples/routes.ru-sites.json routes.json                                             # 或使用你自己的网段列表
./amnezia-ru-split plan --routes routes.json     # 试运行：只显示计划，不做任何更改，无需 root
# 连接 VPN，然后：
sudo ./amnezia-ru-split install --routes routes.json
```

`install` 会应用路由，检查流量是否经过 `amn0`、外网 IP 是否在 `vpn-endpoints` 中，然后安装 `/usr/local/libexec/amnezia-ru-split`、NM 钩子 `90-amnezia-ru-split` 和一个 30 秒间隔的定时器。任何一步失败都会完整回滚。如果已经安装过，则拒绝覆盖。

`routes.json` 的格式与 Amnezia 分站点隧道（split tunneling）的“站点”导出格式相同：`[{"hostname": "77.88.0.0/18", "ip": ""}]`。只接受公网 IPv4，前缀不得短于 /12。

## 配置（`/etc/amnezia-ru-split/`）

| 文件 | 用途 |
| --- | --- |
| `routes.json` | 走直连的网段 |
| `vpn-endpoints` | 你的 VPN 服务器的公网 IPv4，每行一个；更换服务器时请加入新地址 |
| `health-hosts` | 可选：VPN 开启时必须通过 HTTPS 返回 200 的网站（供 `install`、`health` 使用） |

`health` 会访问 `api.ipify.org` 来获取外网 IP。

## 示例路由列表

`examples/routes.ru-sites.json` 包含作者自己配置中的 162 个网段：Yandex、VK、Mail.ru、OK、Ozon、Avito、Rutube、Gosuslugi 以及部分俄罗斯运营商的网段，另有 9 条 CDN 主机路由。这是 2026-09-30 的快照。当天，ya.ru、vk.com、mail.ru、ok.ru、ozon.ru、wildberries.ru、avito.ru、gosuslugi.ru、kinopoisk.ru、rutube.ru 和 dzen.ru 解析出的地址经由物理网卡走直连，而 2gis.ru 没有（它走了 VPN）。网站的 IP 会变化，所以请把这个文件当作起点，并持续维护你自己的列表。`examples/routes.example.json` 是仅三行的格式示例，测试会用到它。

## 检查与回滚

```sh
tests/sandbox.sh                                     # 在一次性命名空间中运行 16 项检查，不影响主机
./amnezia-ru-split health                            # VPN 开启时的实时检查
sudo /usr/local/libexec/amnezia-ru-split uninstall   # 只移除它自己创建的内容，不会断开 VPN
```

## 检查未覆盖的部分

- `install` 和 `uninstall`（会写入 `/etc` 并启用 systemd 单元）没有在沙箱中运行过。
- 与真实 Amnezia 守护进程的冷启动（重启、Wi-Fi 重连）只在一台机器上手动验证过。

## 限制

仅支持 IPv4，直连网站只处理 80/443 端口。链名 `amnvpn.110.allowNets` 来自当前版本的客户端，其他版本可能使用不同的名称。如果客户端修复了网关查找问题，脚本应当仍能正常工作（到服务器的路由只是变得多余），但这一点没有测试过。

## 许可证

[MIT](LICENSE)：任何人都可以使用、复制、修改和分发。
