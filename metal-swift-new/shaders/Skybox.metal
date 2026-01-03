//
//  Skybox.metal
//  metal-swift
//
//  Created by Jared Lueck on 2025-12-08.
//

#include <metal_stdlib>
using namespace metal;

struct VSOut {
    float4 position [[position]];
    float2 ndc;
};

struct Uniforms {
    float4x4 view;
    float4x4 projection;
    float4x4 inverseView;
    float4x4 inverseProjection;
};

vertex VSOut skyboxVertex(uint vid [[vertex_id]]) {
    float2 verts[3] = {
        float2(-1.0, -3.0),
        float2(-1.0,  1.0),
        float2( 3.0,  1.0)
    };
    VSOut out;
    out.position = float4(verts[vid], 0.0, 1.0);
    out.ndc = verts[vid];
    return out;
}

fragment float4 skyboxFragment(VSOut in [[stage_in]],
                              texturecube<float> skyTex [[texture(0)]],
                              sampler samp [[sampler(0)]],
                              constant Uniforms& uniforms [[buffer(0)]]) {
    float4 clip = float4(in.ndc, 1.0, 1.0);
    float3 viewPos = normalize((uniforms.inverseProjection * clip).xyz);
    float4 worldDir = normalize((uniforms.inverseView) * float4(viewPos, 0.0));
    float4 color = skyTex.sample(samp, worldDir.xyz);
    return color;
}
