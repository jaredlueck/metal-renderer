//
//  Grid.metal
//  metal-swift-new
//
//  Created by Jared Lueck on 2026-01-02.
//
#include <metal_stdlib>
#include "Types.h"
#include "Bindings.h"
using namespace metal;

struct GridUniforms {
    float4 baseColor;
};

struct VSOut {
    float4 position [[position]];
    float3 worldPos;
};

vertex VSOut gridVertex(uint vid [[vertex_id]], constant FrameUniforms& uniforms [[buffer(BindingsFrameUniforms)]]){
    float4 cameraPos = uniforms.cameraPosition;
    // Construct a plane on y=0 extending +/-100 around the camera's x and z
    float camX = cameraPos.x;
    float camZ = cameraPos.z;
    const float extent = 100.0;
    float4x4 view = uniforms.view;
    float4x4 projection = uniforms.projection;
    VSOut o;
    float3 vertices[6] = {
        float3(camX - extent, 0.0, camZ - extent), // BL
        float3(camX + extent, 0.0, camZ - extent), // BR
        float3(camX + extent, 0.0, camZ + extent), // TR

        float3(camX - extent, 0.0, camZ - extent), // BL
        float3(camX + extent, 0.0, camZ + extent), // TR
        float3(camX - extent, 0.0, camZ + extent)  // TL
    };
    o.worldPos = vertices[vid].xyz;
    o.position = projection * view * float4(vertices[vid], 1.0);
    
    return o;
}

fragment float4 gridFragment(VSOut in [[stage_in]], constant float4& baseColor [[buffer(BindingsPipelineUniforms)]]){
    float3 pos = in.worldPos;
    float eps = 1e-1;
    bool onGrid = fract(pos.x) < eps || fract(pos.z) < eps;
    if (!onGrid) {
        discard_fragment(); // No color or depth written
    }
    return baseColor;
}

