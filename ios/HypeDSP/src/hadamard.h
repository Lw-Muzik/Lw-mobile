#pragma once
#include <cmath>

// In-place Hadamard transform for N=8 (butterfly pattern).
// O(N log N) = 24 operations instead of O(N^2) = 64.
// Preserves energy (unitary matrix) when normalized.
inline void hadamard8(float* data) {
    // Stage 1: stride 1 (pairs)
    for (int i = 0; i < 8; i += 2) {
        float a = data[i], b = data[i + 1];
        data[i]     = a + b;
        data[i + 1] = a - b;
    }
    // Stage 2: stride 2 (quads)
    for (int i = 0; i < 8; i += 4) {
        float a = data[i],     b = data[i + 2];
        float c = data[i + 1], d = data[i + 3];
        data[i]     = a + b;
        data[i + 2] = a - b;
        data[i + 1] = c + d;
        data[i + 3] = c - d;
    }
    // Stage 3: stride 4 (octets)
    for (int i = 0; i < 4; i++) {
        float a = data[i], b = data[i + 4];
        data[i]     = a + b;
        data[i + 4] = a - b;
    }
    // Normalize to preserve energy
    constexpr float norm = 1.0f / 2.828427f; // 1/sqrt(8)
    for (int i = 0; i < 8; i++) {
        data[i] *= norm;
    }
}

// In-place Householder reflection: H = I - (2/N) * 1*1^T
// Subtracts twice the projection onto the all-ones vector.
// Energy-preserving unitary transformation.
template<int N>
inline void householder(float* data) {
    float sum = 0.0f;
    for (int i = 0; i < N; i++) sum += data[i];
    sum *= 2.0f / static_cast<float>(N);
    for (int i = 0; i < N; i++) data[i] -= sum;
}
