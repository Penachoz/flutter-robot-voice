#include <opencv2/opencv.hpp>

#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <unistd.h>

#include <atomic>
#include <chrono>
#include <cstring>
#include <iostream>
#include <mutex>
#include <string>
#include <thread>
#include <vector>
#include <array>

constexpr int SUB_PORT    = 5007;
constexpr int CMD_PORT    = 5005;
constexpr uint32_t MJPG_MAGIC  = 0x4D4A5047;
constexpr size_t MAX_PAYLOAD   = 1300;

// Ajustes de video (720p)
constexpr int FRAME_WIDTH   = 640;
constexpr int FRAME_HEIGHT  = 480;
constexpr int FPS = 60;
constexpr int JPEG_QUALITY = 90;
struct ClientInfo {
    std::string ip;
    int port;
};

std::mutex g_clientMutex;
bool g_hasClient = false;
ClientInfo g_client;

std::mutex g_cmdMutex;
std::string g_currentCmd = "STOP";

// ---- utilidades cliente ----
void setClient(const std::string& ip, int port) {
    std::lock_guard<std::mutex> lock(g_clientMutex);
    g_client.ip = ip;
    g_client.port = port;
    g_hasClient = true;
    std::cout << "[CLIENT] Destino vídeo: " << ip << ":" << port << std::endl;
}

bool getClient(ClientInfo& out) {
    std::lock_guard<std::mutex> lock(g_clientMutex);
    if (!g_hasClient) return false;
    out = g_client;
    return true;
}

// ---- header MJPEG ----
void build_header(std::array<uint8_t, 24>& hdr,
                  uint32_t seq,
                  uint32_t frameLen,
                  uint16_t fragIdx,
                  uint16_t fragCnt) {
    using namespace std::chrono;
    uint64_t ts_ms =
        duration_cast<milliseconds>(steady_clock::now().time_since_epoch()).count();

    uint32_t ts_hi = static_cast<uint32_t>((ts_ms >> 32) & 0xffffffff);
    uint32_t ts_lo = static_cast<uint32_t>( ts_ms        & 0xffffffff);

    auto put32 = [&](int off, uint32_t v) {
        hdr[off]     = static_cast<uint8_t>((v >> 24) & 0xff);
        hdr[off + 1] = static_cast<uint8_t>((v >> 16) & 0xff);
        hdr[off + 2] = static_cast<uint8_t>((v >> 8)  & 0xff);
        hdr[off + 3] = static_cast<uint8_t>( v        & 0xff);
    };
    auto put16 = [&](int off, uint16_t v) {
        hdr[off]     = static_cast<uint8_t>((v >> 8) & 0xff);
        hdr[off + 1] = static_cast<uint8_t>( v       & 0xff);
    };

    put32(0,  MJPG_MAGIC);
    put32(4,  seq);
    put32(8,  ts_hi);
    put32(12, ts_lo);
    put32(16, frameLen);
    put16(20, fragIdx);
    put16(22, fragCnt);
}

// ---- parsing super simple de JSON ----
int parse_video_port(const std::string& s, int def = 5600) {
    auto pos = s.find("video_port");
    if (pos == std::string::npos) return def;
    pos = s.find(':', pos);
    if (pos == std::string::npos) return def;
    try {
        return std::stoi(s.substr(pos + 1));
    } catch (...) {
        return def;
    }
}

std::string parse_cmd_value(const std::string& s) {
    auto pos = s.find("\"value\"");
    if (pos == std::string::npos) return "";
    pos = s.find(':', pos);
    if (pos == std::string::npos) return "";
    pos = s.find('"', pos);
    if (pos == std::string::npos) return "";
    auto end = s.find('"', pos + 1);
    if (end == std::string::npos) return "";
    return s.substr(pos + 1, end - pos - 1);
}

// ---- 1. Loop de suscripción ----
void sub_loop() {
    int sockfd = socket(AF_INET, SOCK_DGRAM, 0);
    if (sockfd < 0) {
        perror("[SUB] socket");
        return;
    }

    sockaddr_in addr{};
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = INADDR_ANY;
    addr.sin_port = htons(SUB_PORT);

    if (bind(sockfd, reinterpret_cast<sockaddr*>(&addr), sizeof(addr)) < 0) {
        perror("[SUB] bind");
        close(sockfd);
        return;
    }

    std::cout << "[SUB] Escuchando suscripciones en UDP " << SUB_PORT << std::endl;

    char buf[2048];
    while (true) {
        sockaddr_in src{};
        socklen_t slen = sizeof(src);
        ssize_t n = recvfrom(sockfd, buf, sizeof(buf) - 1, 0,
                             reinterpret_cast<sockaddr*>(&src), &slen);
        if (n <= 0) continue;
        buf[n] = '\0';

        std::string s(buf);
        char ipstr[INET_ADDRSTRLEN];
        inet_ntop(AF_INET, &src.sin_addr, ipstr, sizeof(ipstr));
        std::cout << "[SUB] Datagrama desde " << ipstr << ": " << s << std::endl;

        if (s.find("\"subscribe\"") != std::string::npos) {
            int video_port = parse_video_port(s, 5600);
            setClient(ipstr, video_port);
            std::cout << "[SUB] Nuevo cliente vídeo: "
                      << ipstr << ":" << video_port << std::endl;
        }
    }
}

// ---- 2. Loop de comandos ----
void handle_command(const std::string& cmd) {
    std::lock_guard<std::mutex> lock(g_cmdMutex);
    g_currentCmd = cmd;
    std::cout << "[CMD] Comando recibido: " << cmd << std::endl;
    // TODO: aquí conectas tus gaits / motores
}

void cmd_loop() {
    int sockfd = socket(AF_INET, SOCK_DGRAM, 0);
    if (sockfd < 0) {
        perror("[CMD] socket");
        return;
    }

    sockaddr_in addr{};
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = INADDR_ANY;
    addr.sin_port = htons(CMD_PORT);

    if (bind(sockfd, reinterpret_cast<sockaddr*>(&addr), sizeof(addr)) < 0) {
        perror("[CMD] bind");
        close(sockfd);
        return;
    }

    std::cout << "[CMD] Escuchando comandos en UDP " << CMD_PORT << std::endl;

    char buf[2048];
    while (true) {
        sockaddr_in src{};
        socklen_t slen = sizeof(src);
        ssize_t n = recvfrom(sockfd, buf, sizeof(buf) - 1, 0,
                             reinterpret_cast<sockaddr*>(&src), &slen);
        if (n <= 0) continue;
        buf[n] = '\0';

        std::string s(buf);
        char ipstr[INET_ADDRSTRLEN];
        inet_ntop(AF_INET, &src.sin_addr, ipstr, sizeof(ipstr));

        // fallback: si no hay cliente de vídeo, usa IP del que manda el comando
        if (!g_hasClient) {
            setClient(ipstr, 5600);
            std::cout << "[CMD] No había cliente vídeo; usando "
                      << ipstr << ":5600 como destino" << std::endl;
        }

        if (s.find("\"cmd\"") != std::string::npos) {
            auto value = parse_cmd_value(s);
            if (!value.empty()) {
                handle_command(value);
            }
        }
    }
}

// ---- 3. Loop de vídeo ----
void video_loop() {
    // Backend explícito V4L2
    cv::VideoCapture cap(0, cv::CAP_V4L2);
    if (!cap.isOpened()) {
        std::cerr << "[VIDEO] No se pudo abrir la cámara USB (CAP_V4L2)" << std::endl;
        return;
    }

    // IMPORTANTE: quitar MJPG, dejamos formato por defecto (YUYV, etc.)
    // cap.set(cv::CAP_PROP_FOURCC, cv::VideoWriter::fourcc('M','J','P','G'));

    cap.set(cv::CAP_PROP_FRAME_WIDTH,  FRAME_WIDTH);   // 1280
    cap.set(cv::CAP_PROP_FRAME_HEIGHT, FRAME_HEIGHT);  // 720
    cap.set(cv::CAP_PROP_FPS, FPS);                    // 30 (si la cam lo soporta)

    double w = cap.get(cv::CAP_PROP_FRAME_WIDTH);
    double h = cap.get(cv::CAP_PROP_FRAME_HEIGHT);
    double f = cap.get(cv::CAP_PROP_FPS);
    std::cout << "[VIDEO] Cámara abierta: " << w << "x" << h << " @ " << f << " FPS" << std::endl;

    int sockfd = socket(AF_INET, SOCK_DGRAM, 0);
    if (sockfd < 0) {
        perror("[VIDEO] socket");
        return;
    }

    std::cout << "[VIDEO] Iniciando envío de video" << std::endl;

    std::vector<int> params = {
        cv::IMWRITE_JPEG_QUALITY, JPEG_QUALITY   // 90
    };

    uint32_t seq = 0;
    using clock = std::chrono::steady_clock;
    auto target_period = std::chrono::duration<double>(1.0 / FPS);
    auto last_t = clock::now();

    // Warmup
    {
        cv::Mat warm;
        for (int i = 0; i < 10; ++i) {
            cap >> warm;
            std::this_thread::sleep_for(std::chrono::milliseconds(30));
        }
    }

    while (true) {
        ClientInfo client;
        if (!getClient(client)) {
            std::this_thread::sleep_for(std::chrono::milliseconds(100));
            continue;
        }

        cv::Mat frame;
        cap >> frame;
        if (frame.empty()) {
            std::cerr << "[VIDEO] Frame vacío" << std::endl;
            std::this_thread::sleep_for(std::chrono::milliseconds(10));
            continue;
        }

        std::vector<uchar> buf;
        if (!cv::imencode(".jpg", frame, buf, params)) {
            std::cerr << "[VIDEO] imencode falló" << std::endl;
            continue;
        }

        size_t frameLen = buf.size();
        uint16_t fragCnt = static_cast<uint16_t>(
            (frameLen + MAX_PAYLOAD - 1) / MAX_PAYLOAD
        );

        sockaddr_in dst{};
        dst.sin_family = AF_INET;
        dst.sin_port = htons(client.port);
        inet_pton(AF_INET, client.ip.c_str(), &dst.sin_addr);

        for (uint16_t fragIdx = 0; fragIdx < fragCnt; ++fragIdx) {
            size_t start = fragIdx * MAX_PAYLOAD;
            size_t end   = std::min(start + MAX_PAYLOAD, frameLen);
            size_t fragSize = end - start;

            std::array<uint8_t, 24> hdr{};
            build_header(hdr, seq, static_cast<uint32_t>(frameLen),
                         fragIdx, fragCnt);

            std::vector<uint8_t> packet(24 + fragSize);
            std::memcpy(packet.data(), hdr.data(), 24);
            std::memcpy(packet.data() + 24, buf.data() + start, fragSize);

            sendto(sockfd,
                   packet.data(),
                   packet.size(),
                   0,
                   reinterpret_cast<sockaddr*>(&dst),
                   sizeof(dst));
        }

        if (seq % 60 == 0) {  // menos spam de logs
            std::cout << "[VIDEO] Enviado frame " << seq
                      << " a " << client.ip << ":" << client.port
                      << " (len=" << frameLen
                      << ", frags=" << fragCnt << ")" << std::endl;
        }

        seq++;

        auto now = clock::now();
        auto elapsed = now - last_t;
        if (elapsed < target_period) {
            std::this_thread::sleep_for(target_period - elapsed);
        }
        last_t = clock::now();
    }
}

int main() {
    std::thread t_sub(sub_loop);
    std::thread t_cmd(cmd_loop);

    // loop de vídeo es bloqueante
    video_loop();

    t_sub.join();
    t_cmd.join();
    return 0;
}
