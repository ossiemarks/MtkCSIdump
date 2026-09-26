#include <cstring>
#include <iostream>
#include <thread>
#include <future>
#include <signal.h>
#include <sys/socket.h>
#include <fstream>
#include <unistd.h>

#include "motion_detector.h"

MotionDetector& md = MotionDetector::getInstance();
static volatile sig_atomic_t stop = 0;

void signalHandler(int)
{
    stop = 1;
}

int main(int argc, char **argv)
{
    struct sigaction sig = {};
    std::memset(&sig, 0, sizeof(sig));
    sig.sa_handler = signalHandler;

    if (sigaction(SIGINT, &sig, NULL) || sigaction(SIGTERM, &sig, NULL))
        std::cerr << "sigaction error" << std::endl;

    if (argc != 4)
    {
        std::cout << "Need 3 arguments: wifi_interface interval udp_port" << std::endl;
        return -1;
    }

    // Start UDP server
    int udpPort = std::stoi(argv[3]);
    if (md.startUdpServer(udpPort) != 0) {
        std::cerr << "Failed to start UDP server on port " << udpPort << std::endl;
        return -1;
    }

    if (md.startMonitoring(argv[1], std::stoul(argv[2])) != 0) {
        std::cerr << "Failed to start CSI capture on " << argv[1]
                  << " (does the mt76 driver expose the MediaTek CSI vendor command?)" << std::endl;
        md.stopUdpServer();
        return 1;
    }

    while (!stop)
        std::this_thread::sleep_for(std::chrono::milliseconds(200));

    md.stopMonitoring();
    md.stopUdpServer();

    return 0;
}
