//
//  Grid.metal
//  metal-swift-new
//
//  Created by Jared Lueck on 2026-01-02.
//
#include <metal_stdlib>
#include "Types.h"
using namespace metal;

struct VSOut {
    float4 position [[position]];
    float3 worldPos;
};

vertex VSOut gridVertex(uint vid [[vertex_id]], constant FrameData& uniforms [[buffer(BufferIndexFrameData)]]){
    float4 cameraPos = uniforms.cameraPosition;
    float camX = cameraPos.x;
    float camZ = cameraPos.z;
    const float extent = 100.0;
    float4x4 view = uniforms.view;
    float4x4 projection = uniforms.projection;
    VSOut o;
    float3 vertices[6] = {
        float3(camX - extent, -0.1, camZ - extent), // BL
        float3(camX + extent, -0.1, camZ - extent), // BR
        float3(camX + extent, -0.1, camZ + extent), // TR

        float3(camX - extent, -0.1, camZ - extent), // BL
        float3(camX + extent, -0.1, camZ + extent), // TR
        float3(camX - extent, -0.1, camZ + extent)  // TL
    };
    o.worldPos = vertices[vid].xyz;
    o.position = projection * view * float4(vertices[vid], 1.0);
    return o;
}

fragment float4 gridFragment(VSOut in [[stage_in]]){
    float3 pos = in.worldPos;
    
    float dist = distance(pos, float3(0, 0, 0));
    float falloff = 1 - (dist / 30);
    float fx = fract(pos.x);
    float fz = fract(pos.z);

    float px = fwidth(fx);
    float pz = fwidth(fz);

    float lineWidth = 0.015;
    float smoothness = 1.0;

    float distLeft   = fx;
    float distRight  = 1.0 - fx;

    float distTop    = fz;
    float distBottom = 1.0 - fz;

    float halfW = 0.5 * lineWidth;

    float left   = 1.0 - smoothstep(halfW - smoothness * px, halfW + smoothness * px, distLeft);
    float right  = 1.0 - smoothstep(halfW - smoothness * px, halfW + smoothness * px, distRight);

    float top    = 1.0 - smoothstep(halfW - smoothness * pz, halfW + smoothness * pz, distTop);
    float bottom = 1.0 - smoothstep(halfW - smoothness * pz, halfW + smoothness * pz, distBottom);
    float a = max(max(left, right), max(top, bottom));
    float minDist = min(min(distLeft, distRight), min(distTop, distBottom));
    
    return float4(1.0, 1.0, 1.0, a) * falloff;
}

