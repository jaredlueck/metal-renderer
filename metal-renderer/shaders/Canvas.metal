//
//  gpu_3D_canvas_texture.metal
//  metal-swift-new
//
//  Created by Jared Lueck on 2026-01-17.
//

#include <metal_stdlib>
#include "Types.h"
using namespace metal;

struct VertexIn {
    float3 position [[attribute(0)]];
    float3 normal [[attribute(1)]];
    float2 textureCoordinate [[attribute(2)]];
    
};

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
    float3 center [[flat]];
};

vertex VertexOut canvasVertex(uint vertex_id [[vertex_id]],
                             VertexIn vertexData [[stage_in]],
                             constant float4x4* instanceData [[buffer(BufferIndexInstanceData)]],
                             constant FrameData& uniforms [[buffer(BufferIndexFrameData)]]) {
    
    VertexOut o;
    float4 localPos = float4(vertexData.position, 1.0);
    float4x4 mvp = uniforms.projection * uniforms.view;
    o.position = mvp * localPos;
    o.texCoord = vertexData.textureCoordinate;
    return o;
}

fragment float4 canvasFragment(VertexOut in [[stage_in]],
                               texture2d<float> texture [[texture(TextureIndexAlbedo)]],
                               sampler s [[sampler(SamplerIndexDefault)]]){
    float4 color = texture.sample(s, in.texCoord);
    if( color.x <= 0.05 && color.y <= 0.05 && color.z <= 0.05 ){
        discard_fragment();
        return float4(0.0);
    }
    color.w = 0.4;
    return color;
}

struct CircleUniforms {
    float radius;
    float thickness;
    float3 color;
    float2 center;
};

fragment float4 circleFragment(VertexOut in [[stage_in]],
                               constant CircleUniforms& uniforms [[buffer(BufferIndexPipeline)]]){
    float2 pixel = in.position.xy;
    float dist = distance(uniforms.center, pixel);
    if(abs(dist - uniforms.radius) < uniforms.thickness){
        return float4(uniforms.color, 0.5);
    }
    discard_fragment();
    return float4();
}
