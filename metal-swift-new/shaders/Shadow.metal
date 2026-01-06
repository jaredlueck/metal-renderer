//
//  Shadow.metal
//  metal-swift-new
//
//  Created by Jared Lueck on 2025-12-22.
//

//
//  BlinnPhong.metal
//  metal-swift-new
//
//  Created by Jared Lueck on 2025-12-20.
//

#include <metal_stdlib>
using namespace metal;

struct Uniforms {
    float4x4 vp;
};

struct VertexIn {
    float3 position [[attribute(0)]];
};

struct VertexOut {
    float4 position [[position]];
};

vertex VertexOut shadowVertex(uint vertex_id [[vertex_id]],
                              uint instance_id [[instance_id]],
                               VertexIn vertexData [[stage_in]],
                               constant Uniforms& uniforms [[buffer(0)]],
                               constant float4x4* instanceData [[buffer(2)]]) {
    VertexOut o;
    float4x4 model = instanceData[instance_id];
    float4 localPos = float4(vertexData.position, 1.0);
    float4x4 mvp = uniforms.vp * model;
    o.position = mvp * localPos;
    return o;
}
