//
//  LineUniformColor.swift
//  metal-swift-new
//
//  Created by Jared Lueck on 2026-01-10.
//

#include <metal_stdlib>
#include "Types.h"
#include "Bindings.h"

using namespace metal;

struct VertexIn {
    float3 position [[attribute(0)]];
};

vertex float4 uniformColorVertex(uint vertex_id [[vertex_id]],
                                 const device float3* vertices[[buffer(BindingsVertexBuffer)]],
                                 constant float4x4& transform [[buffer(BindingsInstanceData)]],
                                 constant FrameUniforms& frameUniforms [[buffer(BindingsFrameUniforms)]]
                                 ){
    float3 pos = vertices[vertex_id];
    return frameUniforms.projection * frameUniforms.view * transform * float4(pos, 1.0);
}

fragment float4 uniformColorFragment(float4 position [[stage_in]], constant float3& color[[buffer(BindingsPipelineUniforms)]] ){
    return float4(color, 1.0);
}
