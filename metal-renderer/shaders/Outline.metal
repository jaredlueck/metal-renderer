//
//  Outlinr.metal
//  metal-swift-new
//
//  Created by Jared Lueck on 2026-01-02.
//

#include <metal_stdlib>
using namespace metal;
#include "Types.h"
#include "Bindings.h"
struct VertexOut {
    float4 position [[position]];
    float3 worldPos;
};

vertex VertexOut outlineVertex(uint vertex_id [[vertex_id]]) {
    VertexOut o;
    
    float4 vertices[6] = {
        float4(-1.0, -1.0, 0.0, 1.0), // BL
        float4( 1.0, -1.0, 0.0, 1.0), // BR
        float4( 1.0,  1.0, 0.0, 1.0), // TR

        float4(-1.0, -1.0, 0.0, 1.0), // BL
        float4( 1.0,  1.0, 0.0, 1.0), // TR
        float4(-1.0,  1.0, 0.0, 1.0)  // TL
    };

    VertexOut out;
    out.position = vertices[vertex_id % 6];
    out.worldPos = out.position.xyz;
    return out;
    
    return o;
}

fragment float4 outlineFragment(VertexOut in [[stage_in]],
                                texture2d<float> mask [[texture(0)]],
                                constant float4& outlineColor [[buffer(BindingsPipelineUniforms)]]) {
    const int radius = 2;

    // Convert to integer pixel coordinates
    uint2 pc = uint2(in.position.xy);

    // If current pixel is in the mask, discard (drawn elsewhere)
    if (mask.read(pc).r == 1.0) {
        discard_fragment();
    }

    // Get texture size to clamp neighbor coordinates
    int w = mask.get_width();
    int h = mask.get_height();

    // Scan neighborhood for any masked pixel
    for (int dy = -radius; dy <= radius; ++dy) {
        for (int dx = -radius; dx <= radius; ++dx) {
            int nx = int(pc.x) + dx;
            int ny = int(pc.y) + dy;

            // Clamp to texture bounds
            nx = clamp(nx, 0, w - 1);
            ny = clamp(ny, 0, h - 1);

            if (mask.read(uint2(nx, ny)).r == 1.0) {
                return outlineColor;
            }
        }
    }
    discard_fragment();
}


kernel void outline(texture2d<float> mask [[texture(0)]], texture2d<float, access:: read_write> colorBuffer [[texture((1))]], texture2d<float, access:: write> output [[texture(2)]], const device float4& outlineColor [[buffer(0)]], uint2 grid [[thread_position_in_grid]]){
    int radius = 2;
    float maskVal = mask.read(grid).r;
    float4 colorVal = colorBuffer.read(grid);
    
    if(maskVal == 1.0){
        output.write(colorVal, grid);
        return;
    }
    for(int i = -radius ; i < radius ; i++){
        for(int j = -radius; j < radius; j++){
            uint xcoord = max(uint(0), grid.x + i);
            uint ycoord = max(uint(0), grid.y + j);
            maskVal = mask.read(uint2(xcoord, ycoord)).r;
            if(maskVal == 1.0){
                output.write(outlineColor, grid);
                return;
            }
        }
    }
    
    output.write(colorVal, grid);
}

//vertex VSOut skyboxVertex(uint vid [[vertex_id]]) {
//    float2 verts[3] = {
//        float2(-1.0, -3.0),
//        float2(-1.0,  1.0),
//        float2( 3.0,  1.0)
//    };
//    VSOut out;
//    out.position = float4(verts[vid], 0.0, 1.0);
//    out.ndc = verts[vid];
//    return out;
//}
//
//fragment float4 skyboxFragment(VSOut in [[stage_in]],
//                              texturecube<float> skyTex [[texture(0)]],
//                              sampler samp [[sampler(0)]],
//                              constant Uniforms& uniforms [[buffer(0)]]) {
//    float4 clip = float4(in.ndc, 1.0, 1.0);
//    float3 viewPos = normalize((uniforms.inverseProjection * clip).xyz);
//    float4 worldDir = normalize((uniforms.inverseView) * float4(viewPos, 0.0));
//    float4 color = skyTex.sample(samp, worldDir.xyz);
//    return color;
//}

