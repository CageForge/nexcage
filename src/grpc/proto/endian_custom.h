#ifndef ENDIAN_CUSTOM_H
#define ENDIAN_CUSTOM_H

#include <cstdint>

namespace google {
namespace protobuf {
namespace internal {

inline uint16_t FromHost(uint16_t value) {
#if defined(__LITTLE_ENDIAN__)
    return value;
#else
    return __builtin_bswap16(value);
#endif
}

inline uint32_t FromHost(uint32_t value) {
#if defined(__LITTLE_ENDIAN__)
    return value;
#else
    return __builtin_bswap32(value);
#endif
}

inline uint64_t FromHost(uint64_t value) {
#if defined(__LITTLE_ENDIAN__)
    return value;
#else
    return __builtin_bswap64(value);
#endif
}

inline uint16_t ToHost(uint16_t value) {
    return FromHost(value);
}

inline uint32_t ToHost(uint32_t value) {
    return FromHost(value);
}

inline uint64_t ToHost(uint64_t value) {
    return FromHost(value);
}

}  // namespace internal
}  // namespace protobuf
}  // namespace google

#endif  // ENDIAN_CUSTOM_H 