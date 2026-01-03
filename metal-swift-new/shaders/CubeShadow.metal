//
//  ShadowCube.metal
//  metal-swift-new
//
//  Created by Jared Lueck on 2025-12-28.
//

#include <metal_stdlib>
using namespace metal;

struct Uniforms {
    float4x4 vp;
    float3 lightPos;
    float radius;
};

struct VertexIn {
    float3 position [[attribute(0)]];
};

struct VertexOut {
    float4 position [[position]];
    float3 worldPos;
};

vertex VertexOut cubeShadowVertex(uint vertex_id [[vertex_id]],
                               VertexIn vertexData [[stage_in]],
                               constant Uniforms& uniforms [[buffer(0)]],
                               uint instance_id [[instance_id]],
                               constant float4x4* instanceData [[buffer(2)]]) {

    VertexOut o;
    float4x4 model = instanceData[instance_id];
    float4 localPos = float4(vertexData.position, 1.0);
    o.worldPos = (model * localPos).xyz;
    float4x4 mvp = uniforms.vp * model;
    o.position = mvp * localPos;
    return o;
}

fragment float cubeShadowFragment(VertexOut in [[stage_in]],
                                  constant Uniforms& uniforms [[buffer(0)]]) {
    float dist = distance(in.worldPos, uniforms.lightPos);
    return dist / uniforms.radius;
}
