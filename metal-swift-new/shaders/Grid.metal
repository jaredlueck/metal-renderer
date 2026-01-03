//
//  Grid.metal
//  metal-swift-new
//
//  Created by Jared Lueck on 2026-01-02.
//
#include <metal_stdlib>
using namespace metal;

struct Uniforms {
    float4x4 view;
    float4x4 projection;
    float4 gridColor;
    float4 cameraPos;
};

struct VSOut {
    float4 position [[position]];
    float3 worldPos;
};

bool isWholeNumber(float x) {
    return abs(x - floor(x)) < 1e-1;
}

vertex VSOut gridVertex(uint vid [[vertex_id]], constant Uniforms& uniforms [[buffer(0)]]){
    float4 cameraPos = uniforms.cameraPos;
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

fragment float4 gridFragment(VSOut in [[stage_in]], constant Uniforms& uniforms [[buffer(0)]]){
    float3 pos = in.worldPos;
    float eps = 1e-1;
    if(fract(pos.x) < eps || fract(pos.z) < eps){
        // we are on an even number so we are on the grid
        return uniforms.gridColor;
    }
    discard_fragment();
}

