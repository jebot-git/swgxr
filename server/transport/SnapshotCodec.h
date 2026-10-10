#ifndef SWGXR_SNAPSHOT_CODEC_H
#define SWGXR_SNAPSHOT_CODEC_H
#include <string>
#include <stdexcept>
// zconf.h pulls POSIX declarations; keep those in the global namespace.
#include <unistd.h>
namespace zlib {
#include <zlib.h>
}
namespace swgxr { namespace snapshot_codec {
// Compress before SOE fragmentation, rather than compressing each tiny fragment.
// Negotiated only by our native child; legacy clients still receive plain JSON.
constexpr size_t max_bytes = 4 * 1024 * 1024;
inline std::string encode(const std::string& plain) {
    if (plain.size() < 1024 || plain.size() > max_bytes) return plain;
    zlib::uLongf length = zlib::compressBound(plain.size());
    std::string compressed(length, '\0');
    if (zlib::compress2(reinterpret_cast<zlib::Bytef*>(&compressed[0]), &length,
            reinterpret_cast<const zlib::Bytef*>(plain.data()), plain.size(), 1) != Z_OK) return plain;
    std::string out = "z1:" + std::to_string(plain.size()) + ":";
    if (out.size() + length * 2 >= plain.size()) return plain;
    static const char hex[] = "0123456789abcdef";
    out.reserve(out.size() + length * 2);
    for (size_t i = 0; i < length; ++i) {
        auto b = static_cast<unsigned char>(compressed[i]);
        out += hex[b >> 4]; out += hex[b & 15];
    }
    return out;
}
inline std::string decode(const std::string& wire) {
    if (wire.size() > max_bytes) throw std::runtime_error("native_snapshot_size_limit");
    if (wire.compare(0, 3, "z1:") != 0) return wire;
    auto end = wire.find(':', 3);
    if (end == std::string::npos || end <= 3 || end > 10) throw std::runtime_error("native_snapshot_codec_invalid");
    size_t expected = 0;
    for (size_t i = 3; i < end; ++i) {
        if (wire[i] < '0' || wire[i] > '9') throw std::runtime_error("native_snapshot_codec_invalid");
        expected = expected * 10 + wire[i] - '0';
    }
    auto size = wire.size() - end - 1;
    if (!expected || expected > max_bytes || !size || size % 2) throw std::runtime_error("native_snapshot_codec_invalid");
    auto nibble = [](char c) -> unsigned char {
        if (c >= '0' && c <= '9') return c - '0';
        if (c >= 'a' && c <= 'f') return c - 'a' + 10;
        throw std::runtime_error("native_snapshot_codec_invalid");
    };
    std::string compressed(size / 2, '\0'), plain(expected, '\0');
    for (size_t i = 0; i < size / 2; ++i)
        compressed[i] = (nibble(wire[end + 1 + i * 2]) << 4) | nibble(wire[end + 2 + i * 2]);
    zlib::uLongf length = expected;
    if (zlib::uncompress(reinterpret_cast<zlib::Bytef*>(&plain[0]), &length,
            reinterpret_cast<const zlib::Bytef*>(compressed.data()), compressed.size()) != Z_OK || length != expected)
        throw std::runtime_error("native_snapshot_codec_invalid");
    return plain;
}
}}
#endif
