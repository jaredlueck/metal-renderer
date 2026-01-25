//
//  gpu_pcf.metal
//  metal-swift-new
//
//  Created by Jared Lueck on 2026-01-17.
//

#include <metal_stdlib>

using namespace metal;

// Perform PCF sampling from a cube map by offsetting the direction vector
// and sampling around a particular radius
static inline float PCFCube(texturecube_array<float> shadowAtlas,
              sampler shadowSampler,
              float3 dir,
              float receiverDepth,
              float3 normal,
              uint layer = 0,
              uint kernelSize = 3)
{
    dir = normalize(dir);
    dir.y = -dir.y;

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
    int k = 5;

    for (int dx = -k; dx <= k; ++dx) {
        for (int dy = -k; dy <= k; ++dy) {
            float3 sampleDir = dir + (dx * delta) * a + (dy * delta) * b;
            float3 nd = normalize(sampleDir);
            float slopeBias = (1 - saturate(dot(normal, -nd)))*0.01;
            float sampled = shadowAtlas.sample(shadowSampler, nd, layer).r;
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
