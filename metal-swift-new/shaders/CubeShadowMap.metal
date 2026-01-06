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

struct CubeShadowUniforms {
    float4x4 view;
    float4x4 projection;
    float4 lightPos;
    float radius;
};

struct VertexIn {
    float3 position [[attribute(0)]];
};

struct VertexOut {
    float4 position [[position]];
    float3 worldPos;
};

vertex VertexOut cubeShadowMapVertex(uint vertex_id [[vertex_id]],
                               VertexIn vertexData [[stage_in]],
                               uint instance_id [[instance_id]],
                               constant CubeShadowUniforms& uniforms [[buffer(BindingsPipelineUniforms)]],
                               constant float4x4* instanceData [[buffer(BindingsInstanceData)]]) {

    VertexOut o;
    float4x4 model = instanceData[instance_id];
    float4 localPos = float4(vertexData.position, 1.0);
    o.worldPos = (model * localPos).xyz;
    float4x4 mvp = uniforms.projection * uniforms.view* model;
    o.position = mvp * localPos;
    return o;
}

fragment float cubeShadowMapFragment(VertexOut in [[stage_in]],
                                  constant CubeShadowUniforms& uniforms [[buffer(BindingsPipelineUniforms)]]) {
    float dist = distance(in.worldPos, uniforms.lightPos.xyz);
    return dist / uniforms.radius;
}
