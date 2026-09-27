// DDC/CI, the protocol monitors are controlled by, for one thing: a VCP
// feature such as brightness (0x10).  Framed exactly as ddcutil (the
// reference implementation) frames it; see ddcutil's src/base/ddc_packets.c.
//
//   request on the wire:  0x51, 0x80 | n, n data bytes, checksum
//     (the checksum is an XOR over 0x6E, the monitor's address, and every
//      byte above; the address itself is set with the I2C_SLAVE ioctl,
//      so it isn't written)
//   get:   data = 0x01, feature
//   set:   data = 0x03, feature, value high, value low
//   reply: 0x6E, 0x80 | n, n data bytes, checksum
//     (checksum: 0x50 ^ 0x6E ^ the length byte ^ the data bytes)
//     get reply data: 0x02, result (0 ok, 1 unsupported), feature, type,
//                     max high, max low, current high, current low
//     a "null" reply (0x6E 0x80 0xBE) means busy: ask again
//     some monitors repeat the leading 0x6E: skip the repeat
#pragma once

#include <cstddef>
#include <cstdint>
#include <vector>

namespace ddc {

inline uint8_t checksum(const std::vector<uint8_t> &bytes, uint8_t start) {
    uint8_t c = start;
    for (uint8_t b : bytes) c ^= b;
    return c;
}

// the bytes to write for a request with these data bytes
inline std::vector<uint8_t> request(const std::vector<uint8_t> &data) {
    std::vector<uint8_t> out{ 0x51, uint8_t(0x80 | data.size()) };
    out.insert(out.end(), data.begin(), data.end());
    out.push_back(checksum(out, 0x6E));
    return out;
}
inline std::vector<uint8_t> getRequest(uint8_t feature) { return request({ 0x01, feature }); }
inline std::vector<uint8_t> setRequest(uint8_t feature, int value) {
    return request({ 0x03, feature, uint8_t((value >> 8) & 0xff), uint8_t(value & 0xff) });
}

enum class Reply { Ok, Busy, Unsupported, Bad };

// a get reply, read from the bus (len bytes): the current and maximum value
inline Reply parseGet(const uint8_t *b, size_t len, uint8_t feature, int *current, int *maximum) {
    if (len >= 2 && b[0] == 0x6E && b[1] == 0x6E) { b++; len--; }          // repeated address
    if (len < 3 || b[0] != 0x6E) return Reply::Bad;
    const int n = b[1] & 0x7f;
    if (!(b[1] & 0x80)) return Reply::Bad;
    if (n == 0) return b[2] == 0xBE ? Reply::Busy : Reply::Bad;              // null message
    if (n != 8 || len < size_t(3 + n)) return Reply::Bad;
    uint8_t c = 0x50 ^ 0x6E ^ b[1];
    for (int i = 0; i < n; ++i) c ^= b[2 + i];
    if (c != b[2 + n]) return Reply::Bad;
    const uint8_t *d = b + 2;
    if (d[0] != 0x02 || d[2] != feature) return Reply::Bad;
    if (d[1] == 0x01) return Reply::Unsupported;
    if (d[1] != 0x00) return Reply::Bad;
    *maximum = (d[4] << 8) | d[5];
    *current = (d[6] << 8) | d[7];
    return Reply::Ok;
}

} // namespace ddc
