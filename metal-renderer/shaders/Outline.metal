//
//  Outlinr.metal
//  metal-swift-new
//
//  Created by Jared Lueck on 2026-01-02.
//

#include <metal_stdlib>
using namespace metal;
#include "Types.h"

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
                                texture2d<float> mask [[texture(TextureIndexAlbedo)]]) {
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
                return float4(1, 0.5, 0.0, 1);
            }
        }
    }
    discard_fragment();
    return float4(0);
}
