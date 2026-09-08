#ifndef INTERNET_INFO_SYSNET_H
#define INTERNET_INFO_SYSNET_H

#include <stdbool.h>
#include <stdint.h>

/// Byte counters for `name` from getifaddrs / if_data. Returns false if missing.
bool IIInterfaceBytes(const char *name, uint64_t *ibytes, uint64_t *obytes);

/// True when the interface is up and has a live carrier.
/// IFF_UP/IFF_RUNNING stay set on macOS after you unplug Ethernet;
/// IFM_ACTIVE is what actually goes down (ifconfig's "status: inactive").
bool IIInterfaceIsUp(const char *name);

/// Negotiated Ethernet speed in Mbps via SIOCGIFMEDIA, or -1 if unknown
/// or the cable is unplugged.
int IIEthernetLinkSpeedMbps(const char *name);

#endif
