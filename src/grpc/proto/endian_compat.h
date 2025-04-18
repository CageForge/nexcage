#ifndef ENDIAN_COMPAT_H
#define ENDIAN_COMPAT_H

#include <cstdint>

namespace google {
namespace protobuf {

template<typename T>
inline T FromHost(T value) {
    return value;
}

template<typename T>
inline T ToHost(T value) {
    return value;
}

} // namespace protobuf
} // namespace google

#endif // ENDIAN_COMPAT_H 