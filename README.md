# Unbound Build with HTTP/2 and QUIC for Comfast CF-WR632AX

**Target**

* Comfast CF-WR632AX
* OpenWrt 25.12.5
* MediaTek Filogic
* AArch64 / musl

**Components**

| Name    | Version |
|---------|---------|
| OpenSSL | 3.5.7   |
| nghttp2 | 1.70.0  |
| nghttp3 | 1.11.0  |
| ngtcp2  | 1.15.0  |
| expat   | 2.8.2   |
| Unbound | 1.25.2  |

**Requirements**

* Docker
* Disk space ~2 GB (~440 MB Image + ~1.5 GB Volume)

**Result**

* Fully statically linked Unbound executable
* HTTP/2 support
* DNS-over-QUIC support
* OpenSSL 3.5 provides the QUIC TLS API used by ngtcp2.

**Steps**
1. Install [Docker](https://docs.docker.com/engine/install/debian) (if not already installed)
2. Install [git](https://git-scm.com/) (if not already installed)
3. Install Unbound on OpenWrt (if not already installed)
```
ssh root@192.168.1.1
apk add unbound-daemon
exit
```
4. Clone the repository
```
git clone git@github.com:nouai/unbound-docker.git
cd unbound-docker
```
5. Build the image and run the container
```
docker compose build
docker compose run
```
6. Copy `unbound-1.25.2-aarch64-static` to the target device (Comfast CF-RW632AX)
```
scp -O output/unbound-1.25.2-aarch64-static root@192.168.1.1:/tmp/unbound-doh
```
7. SSH to the target device
```
ssh root@192.168.1.1
```
8. Prepare executable
```
cd /tmp
chown root:root unbound-doh
chmod +x unbound-doh
```
9. Test Unbound with your config
```
/etc/init.d/unbound stop
./unbound-doh -c /etc/unbound/unbound.conf
```
10. Replace the Unbound executable
```
kill $(pgrep -f unbound-doh)
mv /tmp/unbound-doh /etc/unbound/unbound
/etc/init.d/unbound start
```

