//
//  ShadowCube.metal
//  metal-swift-new
//
//  Created by Jared Lueck on 2025-12-28.
//
#include <simd/simd.h>
#include <metal_stdlib>
#include "Types.h"
using namespace metal;

struct VertexIn {
    float3 position [[attribute(0)]];
};

struct VertexOut {
    float4 position [[position]];
    float3 worldPos;
};

vertex VertexOut maskVertex(uint vertex_id [[vertex_id]],
                            uint instance_id [[instance_id]],
                            VertexIn vertexData [[stage_in]],
                            constant FrameData& uniforms [[buffer(BufferIndexFrameData)]],
                            constant InstanceData* instanceData [[buffer(BufferIndexInstanceData)]]) {

    VertexOut o;
    InstanceData instance = instanceData[instance_id];
    float4x4 model = instance.model;
    float4 localPos = float4(vertexData.position, 1.0);
    o.worldPos = (model * localPos).xyz;
    float4x4 mvp = uniforms.projection * uniforms.view * model;
    o.position = mvp * localPos;
    return o;
}

fragment float maskFragment(VertexOut in [[stage_in]]) {
    return 1.0;
}
