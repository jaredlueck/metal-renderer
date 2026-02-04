//
//  gpu_pcf.metal
//  metal-swift-new
//
//  Created by Jared Lueck on 2026-01-17.
//

#include <metal_stdlib>

using namespace metal;

static inline float4 sampleCubeTexture(float3 dir, texturecube_array<float, access :: read> texture, bool debugFaces = false){
    float x = dir.x;
    float y = dir.y;
    float z = dir.z;

    int width = (int)texture.get_width();
    int height = (int)texture.get_height();

    float absX = abs(x);
    float absY = abs(y);
    float absZ = abs(z);

    int isXPositive = x > 0 ? 1 : 0;
    int isYPositive = y > 0 ? 1 : 0;
    int isZPositive = z > 0 ? 1 : 0;
    int index = 2;
    float maxAxis, uc, vc;
    float u, v;

    // Positive X
    if (isXPositive && absX >= absY && absX >= absZ) {
      maxAxis = absX;
      uc = z;
      vc = y;
      index = 0;
    }
    // Negative X
    if (!isXPositive && absX >= absY && absX >= absZ) {
      maxAxis = absX;
      uc = -z;
      vc = y;
      index = 1;
    }
    // Positive Y
    if (isYPositive && absY >= absX && absY >= absZ) {
      maxAxis = absY;
      uc = -x;
      vc = z;
      index = 2;
    }
    // Negative Y
    if (!isYPositive && absY >= absX && absY >= absZ) {
      maxAxis = absY;
      uc = -x;
      vc = z;
      index = 3;
    }
    // Positive Z
    if (isZPositive && absZ >= absX && absZ >= absY) {
      maxAxis = absZ;
      uc = -x;
      vc = y;
      index = 4;
    }
    // Negative Z
    if (!isZPositive && absZ >= absX && absZ >= absY) {
      maxAxis = absZ;
      uc = x;
      vc = y;
      index = 5;
    }

    // Convert range from −1 to 1 to 0 to 1
    u = 0.5f * (uc / maxAxis + 1.0f);
    v = 1 - (0.5f * (vc / maxAxis + 1.0f));
    
    uint px = min((uint)(u * (float)width),  (uint)width  - 1);
    uint py = min((uint)(v * (float)height), (uint)height - 1);

    if (debugFaces) {
        // Distinct debug colors per face: 0:+X, 1:-X, 2:+Y, 3:-Y, 4:+Z, 5:-Z
        float3 faceColor = float3(0.0);
        switch (index) {
            case 0: faceColor = float3(1.0, 0.0, 0.0); break; // +X -> Red
            case 1: faceColor = float3(0.0, 1.0, 0.0); break; // -X -> Green
            case 2: faceColor = float3(0.0, 0.0, 1.0); break; // +Y -> Blue
            case 3: faceColor = float3(1.0, 1.0, 0.0); break; // -Y -> Yellow
            case 4: faceColor = float3(1.0, 0.0, 1.0); break; // +Z -> Magenta
            case 5: faceColor = float3(0.0, 1.0, 1.0); break; // -Z -> Cyan
            default: faceColor = float3(1.0); break;
        }
        return float4(faceColor, 1.0);
    }

    return texture.read(uint2(px, py), (uint)index, /*level*/ 0, /*layer*/ 0);
}

// Perform PCF sampling from a cube map by offsetting the direction vector
// and sampling around a particular radius
static inline float PCFCube(texturecube_array<float, access :: read> shadowAtlas,
              sampler shadowSampler,
              float3 dir,
              float receiverDepth,
              float3 normal,
              uint layer = 0,
              uint kernelSize = 3)
{
    dir = normalize(dir);

    float3 up = (abs(dir.y) > 0.99) ? float3(0.0, 0.0, 1.0) : float3(0.0, 1.0, 0.0);

    // Build orthonormal basis
    float3 a = normalize(cross(up, dir));
    float3 b = normalize(cross(a, dir));

    float width = shadowAtlas.get_width();
    float maxAxis = max(max(abs(dir.x), abs(dir.y)), abs(dir.z));

    const float filterRadius = 5.0;
    float delta = (2.0 * maxAxis) / width * filterRadius;

    float bias = 0.0001;
    float sum = 0.0;
    int k = kernelSize;
    
    for (int dx = -k; dx <= k; ++dx) {
        for (int dy = -k; dy <= k; ++dy) {
            float3 sampleDir = dir + (dx * delta) * a + (dy * delta) * b;
            float3 nd = normalize(sampleDir);
            float slopeBias = (1 - saturate(dot(normal, -nd)))*0.01;
//            float sampled = sampleCubeTexture(dir, shadowAtlas).r;
            float sampled = sampleCubeTexture(nd, shadowAtlas).r;
            sum += (receiverDepth - (bias + slopeBias) <= sampled) ? 1.0 : 0.0;
        }
    }
    float taps = (float)((2 * k + 1) * (2 * k + 1));
    return sum / taps;
}

// PCF from a 2d shadow map by sampling a radius arounf the pixel
static inline float PCF(depth2d<float> shadowMap, uint2 pixel, float receiverDepth, uint kernelSize){
    int width = (int)shadowMap.get_width();
    int height = (int)shadowMap.get_height();

    float sum = 0.0;

    int k = (int)kernelSize;

    for (int dx = -k; dx <= k; dx++) {
        for (int dy = -k; dy <= k; dy++) {
            int sx = (int)pixel.x + dx;
            int sy = (int)pixel.y + dy;
            
            sx = clamp(sx, 0, width-1);
            sy = clamp(sy, 0, height-1);

            float depth = shadowMap.read(uint2((uint)sx, (uint)sy));
            if (receiverDepth <= depth) {
                sum += 1.0;
            }
        }
    }
    float samples = (float)((2 * k + 1) * (2 * k + 1));
    return sum / samples;
}

