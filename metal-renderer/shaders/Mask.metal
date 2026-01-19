//
//  ShadowCube.metal
//  metal-swift-new
//
//  Created by Jared Lueck on 2025-12-28.
//

#include <metal_stdlib>
#include "Types.h"
#include "Bindings.h"
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
                            constant FrameUniforms& uniforms [[buffer(BindingsFrameUniforms)]],
                            constant float4x4* instanceData [[buffer(BindingsInstanceData)]]) {

    VertexOut o;
    float4x4 model = instanceData[instance_id];
    float4 localPos = float4(vertexData.position, 1.0);
    o.worldPos = (model * localPos).xyz;
    float4x4 mvp = uniforms.projection * uniforms.view * model;
    o.position = mvp * localPos;
    return o;
}

fragment float maskFragment(VertexOut in [[stage_in]]) {
    return 1.0;
}
