//
//  mirror.metal
//  metal
//
//  Created by Jared Lueck on 2025-12-08.
//

#include <metal_stdlib>
using namespace metal;

struct Uniforms {
    float4x4 model;
    float4x4 view;
    float4x4 projection;
    float4x4 inverseView;
};

struct VertexIn {
    float3 position [[attribute(0)]];
    float3 normal [[attribute(1)]];
};

struct VertexOut {
    float4 position [[position]];
    float3 normal;
    float3 worldPos;
    float3 eyePos;
};

vertex VertexOut mirrorVertex(uint vertex_id [[vertex_id]],
                               VertexIn vertexData [[stage_in]],
                               constant Uniforms& uniforms [[buffer(0)]]) {

    VertexOut o;
    float4 localPos = float4(vertexData.position, 1.0);
    o.worldPos = (uniforms.model * localPos).xyz;
    float4x4 mv = uniforms.view * uniforms.model;
    float4x4 mvp = uniforms.projection * mv;
    float3x3 normalMatrix = float3x3(mv[0].xyz, mv[1].xyz, mv[2].xyz);
    o.position = mvp * localPos;
    o.normal = normalize(normalMatrix * vertexData.normal);
    o.eyePos = (uniforms.inverseView * float4(0,0,0,1)).xyz;
    return o;
}

fragment float4 mirrorFragment(VertexOut in [[stage_in]],
                              texturecube<float> skyTex [[texture(0)]],
                              sampler samp [[sampler(0)]]) {
    float3 I = normalize(in.eyePos - in.worldPos);
    float3 N = normalize(in.normal);
    float3 R = reflect(I, N);
    float4 color = skyTex.sample(samp, R);
    return float4(color.rgb, 1.0);
}
