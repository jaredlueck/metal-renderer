//
//  Types.h
//  metal-renderer
//
//  Created by Jared Lueck on 2026-01-04.
//

#include <simd/simd.h>

enum BufferIndices : int {
    BufferIndexVertex = 0,
    BufferIndexFrameData = 1,
    BufferIndexInstanceData = 2,
    BufferIndexLightData = 3,
    BufferIndexPointLightCount = 4,
    BufferIndexPipeline = 5
};

enum TextureIndices {
    TextureIndexAlbedo = 0,
    TextureIndexShadow = 1,
};

enum SamplerIndices {
    SamplerIndexDefault = 0,
    SamplerIndexCube = 1
};

struct PointLight {
    simd_float4 position;
    simd_float4 color;
    float radius;
};

struct FrameData {
    matrix_float4x4 view;
    matrix_float4x4 projection;
    matrix_float4x4 inverseView;
    matrix_float4x4 inverseProjection;
    simd_float4 cameraPosition;
    simd_float2 viewportSize;
};

struct InstanceData {
    matrix_float4x4 model;
    matrix_float3x3 normalMatrix;
    
    // Material
    simd_float4 baseColor;
};
