//
//  gpu_3D_canvas_texture.metal
//  metal-swift-new
//
//  Created by Jared Lueck on 2026-01-17.
//

#include <metal_stdlib>
#include "Types.h"
#include "Bindings.h"
using namespace metal;

struct VertexIn {
    float3 position [[attribute(0)]];
    float3 normal [[attribute(1)]];
    float2 textureCoordinate [[attribute(2)]];
};

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

vertex VertexOut canvasVertex(uint vertex_id [[vertex_id]],
                             VertexIn vertexData [[stage_in]],
                             constant float4x4* instanceData [[buffer(BindingsInstanceData)]],
                             constant FrameUniforms& uniforms [[buffer(BindingsFrameUniforms)]]) {
    
    VertexOut o;
    float4 localPos = float4(vertexData.position, 1.0);
    float4x4 mvp = uniforms.projection * uniforms.view;
    o.position = mvp * localPos;
    o.texCoord = vertexData.textureCoordinate;
    return o;
}

fragment float4 canvasFragment(VertexOut in [[stage_in]],
                               texture2d<float> texture [[texture(BindingsBaseTexture)]],
                               sampler s [[sampler(BindingsSampler)]]){
    float4 color = texture.sample(s, in.texCoord);
    if( color.x <= 0.05 && color.y <= 0.05 && color.z <= 0.05 ){
        discard_fragment();
        return float4(0.0);
    }
    color.w = 0.4;
    return color;
}
