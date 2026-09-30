# amnezia-ru-split

English | [Русский](README.ru.md) | [简体中文](README.zh-CN.md)

Keep Russian sites direct while AmneziaVPN is on (Linux), and stop the VPN from killing your internet.

This is not a plugin of the client itself: it is a small root helper script with a NetworkManager hook and a
systemd timer. It does not change the client or its settings.

## What it solves

1. **Russian sites go direct.** Selected public IPv4 prefixes are routed through the physical gateway, everything
   else goes through the VPN. The script adds the routes (`proto 186 metric 42760`) and `ACCEPT` rules for ports
   80/443 to Amnezia's kill-switch chain `amnvpn.110.allowNets`; without them the kill switch drops that traffic.
2. **"I connect and the internet dies."** The AmneziaVPN daemon reads the routing table into an 8 KiB buffer. If
   the dump is bigger (160+ routes from item 1 make it so), the daemon cannot find the gateway, logs
   `No default gateway available, skipping exclusion route`, and does not exclude the VPN server from the tunnel.
   The VPN's own UDP goes into `amn0`, the handshake never completes, and the kill switch blocks everything. The
   script keeps a permanent route to the server through the physical gateway, so this no longer matters.

Check whether you are affected: `tools/netlink-check.py` (no root) emulates that read and prints `AFFECTED` or `OK`.

A note on certainty: the cause was established by emulating the netlink read and matching it with the daemon's log;
the daemon's source was not read. Tested with AmneziaVPN 5.0.3.0 (AmneziaWG), Arch Linux, kernel 7.2.8.

## Requirements

Linux, AmneziaVPN, NetworkManager, systemd, iptables, iproute2, python3, curl (for `health`).

## Install

```sh
sudo install -d /etc/amnezia-ru-split
sudo install -m 644 examples/vpn-endpoints.example /etc/amnezia-ru-split/vpn-endpoints   # put your server's IP in it
cp examples/routes.ru-sites.json routes.json                                             # or your own prefix list
./amnezia-ru-split plan --routes routes.json     # dry run: shows what would happen, changes nothing, no root
# connect the VPN, then:
sudo ./amnezia-ru-split install --routes routes.json
```

`install` applies the routes, checks that traffic goes through `amn0` and that the external IP is listed in
`vpn-endpoints`, then installs `/usr/local/libexec/amnezia-ru-split`, the NM hook `90-amnezia-ru-split` and a
30-second timer. On any failure everything is rolled back. Installing over an existing installation is refused.

`routes.json` uses the same format as Amnezia's split-tunneling "sites" export:
`[{"hostname": "77.88.0.0/18", "ip": ""}]`. Public IPv4 only, prefix no wider than /12.

## Configuration (`/etc/amnezia-ru-split/`)

| File | Purpose |
| --- | --- |
| `routes.json` | prefixes that go direct |
| `vpn-endpoints` | public IPv4 of your VPN servers, one per line; add the new one when you switch servers |
| `health-hosts` | optional: hosts that must answer 200 over HTTPS while the VPN is on (`install`, `health`) |

`health` calls `api.ipify.org` to learn the external IP.

## Example route list

`examples/routes.ru-sites.json` has 162 prefixes taken from the author's setup: ranges of Yandex, VK, Mail.ru, OK,
Ozon, Avito, Rutube, Gosuslugi and some Russian operator networks, plus nine CDN host routes. It is a snapshot from
2026-09-30. On that day the resolved addresses of ya.ru, vk.com, mail.ru, ok.ru, ozon.ru, wildberries.ru,
avito.ru, gosuslugi.ru, kinopoisk.ru, rutube.ru and dzen.ru were routed through the physical interface, while
2gis.ru was not (it went through the VPN). Site addresses change, so treat the file as a starting point and keep your
own list up to date. `examples/routes.example.json` is a three-line format sample used by the tests.

## Checks and rollback

```sh
tests/sandbox.sh                                     # 16 checks in a throw-away namespace, the host is untouched
./amnezia-ru-split health                            # live check while the VPN is on
sudo /usr/local/libexec/amnezia-ru-split uninstall   # removes only what it created; the VPN stays connected
```

## Not covered by the checks

- `install` and `uninstall` (they write to `/etc` and enable systemd units) were not run in the sandbox.
- A cold start with the real Amnezia daemon (reboot, Wi-Fi reconnect) was checked by hand on one machine only.

## Limits

IPv4 only, and only ports 80/443 for the direct sites. The chain name `amnvpn.110.allowNets` comes from the current
client; another version may name it differently. If the client's gateway lookup gets fixed, the script should keep
working (the server route would just be redundant), but that was not tested.

## License

[MIT](LICENSE): anyone may use, copy, modify and distribute it.
