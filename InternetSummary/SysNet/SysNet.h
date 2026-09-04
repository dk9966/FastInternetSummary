#ifndef INTERNET_INFO_SYSNET_H
#define INTERNET_INFO_SYSNET_H

#include <stdbool.h>
#include <stdint.h>

/// Byte counters for `name` from getifaddrs / if_data. Returns false if missing.
bool IIInterfaceBytes(const char *name, uint64_t *ibytes, uint64_t *obytes);

/// True when the interface is IFF_UP and IFF_RUNNING.
bool IIInterfaceIsUp(const char *name);

/// Negotiated Ethernet speed in Mbps via SIOCGIFMEDIA, or -1 if unknown.
int IIEthernetLinkSpeedMbps(const char *name);

#endif
