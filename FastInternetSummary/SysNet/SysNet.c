#include "SysNet.h"

#include <ifaddrs.h>
#include <net/if.h>
#include <net/if_media.h>
#include <net/if_var.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <unistd.h>

bool IIInterfaceBytes(const char *name, uint64_t *ibytes, uint64_t *obytes) {
    if (name == NULL || ibytes == NULL || obytes == NULL) {
        return false;
    }

    struct ifaddrs *addrs = NULL;
    if (getifaddrs(&addrs) != 0) {
        return false;
    }

    bool found = false;
    for (struct ifaddrs *cursor = addrs; cursor != NULL; cursor = cursor->ifa_next) {
        if (cursor->ifa_addr == NULL || cursor->ifa_addr->sa_family != AF_LINK) {
            continue;
        }
        if (strcmp(cursor->ifa_name, name) != 0) {
            continue;
        }
        if (cursor->ifa_data == NULL) {
            continue;
        }

        struct if_data *data = (struct if_data *)cursor->ifa_data;
        *ibytes = data->ifi_ibytes;
        *obytes = data->ifi_obytes;
        found = true;
        break;
    }

    freeifaddrs(addrs);
    return found;
}

static bool copy_ifmedia(const char *name, struct ifmediareq *request) {
    int sock = socket(AF_INET, SOCK_DGRAM, 0);
    if (sock < 0) {
        return false;
    }

    memset(request, 0, sizeof(*request));
    strlcpy(request->ifm_name, name, sizeof(request->ifm_name));
    int rc = ioctl(sock, SIOCGIFMEDIA, request);
    close(sock);
    return rc == 0;
}

bool IIInterfaceIsUp(const char *name) {
    if (name == NULL) {
        return false;
    }

    struct ifaddrs *addrs = NULL;
    if (getifaddrs(&addrs) != 0) {
        return false;
    }

    bool up = false;
    for (struct ifaddrs *cursor = addrs; cursor != NULL; cursor = cursor->ifa_next) {
        if (strcmp(cursor->ifa_name, name) != 0) {
            continue;
        }
        up = (cursor->ifa_flags & IFF_UP) && (cursor->ifa_flags & IFF_RUNNING);
        break;
    }

    freeifaddrs(addrs);
    if (!up) {
        return false;
    }

    // ifconfig's "status: inactive" — IFF_RUNNING stays set with the cable out.
    struct ifmediareq request;
    if (copy_ifmedia(name, &request) && (request.ifm_status & IFM_AVALID)) {
        return (request.ifm_status & IFM_ACTIVE) != 0;
    }

    return true;
}

static int mbps_for_subtype(int subtype) {
    switch (subtype) {
    case IFM_10_T:
    case IFM_10_2:
    case IFM_10_5:
    case IFM_10_STP:
    case IFM_10_FL:
        return 10;
    case IFM_100_TX:
    case IFM_100_FX:
    case IFM_100_T4:
    case IFM_100_VG:
    case IFM_100_T2:
    case IFM_100_T:
    case IFM_100_SGMII:
        return 100;
    case IFM_1000_SX:
    case IFM_1000_LX:
    case IFM_1000_CX:
    case IFM_1000_T:
    case IFM_1000_CX_SGMII:
    case IFM_1000_KX:
    case IFM_1000_SGMII:
        return 1000;
    case IFM_2500_T:
    case IFM_2500_SX:
    case IFM_2500_KX:
    case IFM_2500_X:
        return 2500;
    case IFM_5000_T:
    case IFM_5000_KR:
    case IFM_5000_KR_S:
    case IFM_5000_KR1:
        return 5000;
    case IFM_10G_SR:
    case IFM_10G_LR:
    case IFM_10G_CX4:
    case IFM_10G_T:
    case IFM_10G_KX4:
    case IFM_10G_KR:
    case IFM_10G_CR1:
    case IFM_10G_ER:
    case IFM_10G_TWINAX:
    case IFM_10G_TWINAX_LONG:
    case IFM_10G_LRM:
    case IFM_10G_SFI:
    case IFM_10G_AOC:
        return 10000;
    default:
        return -1;
    }
}

int IIEthernetLinkSpeedMbps(const char *name) {
    if (name == NULL) {
        return -1;
    }

    struct ifmediareq request;
    if (!copy_ifmedia(name, &request)) {
        return -1;
    }
    if ((request.ifm_status & IFM_AVALID) && !(request.ifm_status & IFM_ACTIVE)) {
        return -1;
    }

    int word = request.ifm_active != 0 ? request.ifm_active : request.ifm_current;
    if (IFM_TYPE(word) != IFM_ETHER) {
        return -1;
    }
    return mbps_for_subtype(IFM_SUBTYPE(word));
}
