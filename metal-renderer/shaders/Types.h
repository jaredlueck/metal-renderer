//
//  Types.h
//  metal-swift-new
//
//  Created by Jared Lueck on 2026-01-04.
//

#include <metal_stdlib>
using namespace metal;

struct FrameUniforms {
    float4x4 view;
    float4x4 projection;
    float4x4 inverseView;
    float4x4 inverseProjection;
    float4 cameraPosition;
    float2 viewportSize;
};

struct Material {
    float4 baseColor;
};

struct InstanceData {
    float4x4 model;
    float3x3 normalMatrix;
};



