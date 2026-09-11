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

**Result**

* Fully statically linked Unbound executable
* HTTP/2 support
* DNS-over-QUIC support
* OpenSSL 3.5 provides the QUIC TLS API used by ngtcp2.
