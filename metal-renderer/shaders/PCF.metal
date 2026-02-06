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

constant float2 poissonDisk[16] = {
    float2(-0.94201624, -0.39906216),
    float2( 0.94558609, -0.76890725),
    float2(-0.094184101, -0.92938870),
    float2( 0.34495938,  0.29387760),
    float2(-0.91588581,  0.45771432),
    float2(-0.81544232, -0.87912464),
    float2(-0.38277543,  0.27676845),
    float2( 0.97484398,  0.75648379),
    float2( 0.44323325, -0.97511554),
    float2( 0.53742981, -0.47373420),
    float2(-0.26496911, -0.41893023),
    float2( 0.79197514,  0.19090188),
    float2(-0.24188840,  0.99706507),
    float2(-0.81409955,  0.91437590),
    float2( 0.19984126,  0.78641367),
    float2( 0.14383161, -0.14100790)
};

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
            float sampled = sampleCubeTexture(nd, shadowAtlas).r;
            sum += (receiverDepth - (bias + slopeBias) <= sampled) ? 1.0 : 0.0;
        }
    }
    float taps = (float)((2 * k + 1) * (2 * k + 1));
    return sum / taps;
}

static inline float2x2 diskRotation(float angle){
    return float2x2(
                    float2(sin(angle), cos(angle)),
                    float2(cos(angle),  sin(angle))
                    );
}

static inline float random_value(const float4 seed4)
{
    const float dot_product = dot(seed4, float4(12.9898,78.233,45.164,94.673));
    return fract(sin(dot_product) * 43758.5453);
}

static inline float PCFCubePoisson(texturecube_array<float, access :: read> shadowAtlas,
              sampler shadowSampler,
              float3 dir,
              float receiverDepth,
              float3 normal,
              uint layer = 0)
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
    
    // random rotation between  -2Pi and 2Pi
    float angle = random_value(float4(dir, 1.0)) * 2 * M_PI_F;
    // 2x2 rotation matrix
    float2x2 rotation = diskRotation(angle);

    for (int i = 0; i <= 16; i++) {
        float2 poissonSample = rotation * poissonDisk[i];
        float3 sampleDir = dir + (poissonSample.x * delta) * a + (poissonSample.y * delta) * b;
        float3 nd = normalize(sampleDir);
        float slopeBias = (1 - saturate(dot(normal, -nd))) * 0.01;
        float sampled = sampleCubeTexture(nd, shadowAtlas).r;
        sum += (receiverDepth - (bias + slopeBias) <= sampled) ? 1.0 : 0.0;
    }
    return sum / 16;
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
