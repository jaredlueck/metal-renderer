//
//  BlinnPhong.metal
//  metal-swift-new
//
//  Created by Jared Lueck on 2025-12-20.
//

#include <metal_stdlib>
#include <metal_simdgroup_matrix>
#include "gpu_pcf.metal"
#include "Bindings.h"
#include "Types.h"

using namespace metal;

struct VertexIn {
    float3 position [[attribute(0)]];
    float3 normal [[attribute(1)]];
    float2 textureCoordinate [[attribute(2)]];
};

struct VertexOut {
    float4 position [[position]];
    float3 viewPos;
    float3 normal;
    float2 texCoord;
    float3 worldPos;
    float3 worldNormal;
};
 
struct UniformsAB {
    float4x4 view;
    float4x4 projection;
};

struct PointLight {
    float4 position;
    float4 color;
    float  radius;
};

struct LightData {
    const device PointLight* pointLights; // 0, 1, 2
    texturecube_array<float> pointLightShadowMaps; // 3
    uint pointLightCount; // 4
};

float3 calculatePointLightColor(PointLight light, float3 fragmentPosition);

vertex VertexOut phongVertex(uint vertex_id [[vertex_id]],
                             uint instance_id [[instance_id]],
                             VertexIn vertexData [[stage_in]],
                             constant InstanceData* instanceData [[buffer(BindingsInstanceData)]],
                             constant FrameUniforms& uniforms [[buffer(BindingsFrameUniforms)]]) {
    InstanceData instance = instanceData[instance_id];
    float4x4 model = instance.model;
    
    VertexOut o;
    float4 localPos = float4(vertexData.position, 1.0);
    o.worldPos = (model * localPos).xyz;
    float4x4 mv = uniforms.view * model;
    float4x4 mvp = uniforms.projection * uniforms.view * model;
    // Build the upper-left 3x3 of the model-view matrix
    float3x3 mv3x3 = float3x3(mv[0].xyz, mv[1].xyz, mv[2].xyz);
    // TODO: use inverse transpose to transform normals
    float3x3 normalMatrix = mv3x3;
    o.position = mvp * localPos;
    o.viewPos = (mv * localPos).xyz;
    o.texCoord = vertexData.textureCoordinate;
    o.normal = normalize(normalMatrix * vertexData.normal);
    float3x3 model3x3 = float3x3(model[0].xyz, model[1].xyz, model[2].xyz);
    o.worldNormal = normalize(model3x3 * vertexData.normal);
    return o;
}

fragment float4 phongFragment(VertexOut in [[stage_in]],
                                 sampler s [[sampler(0)]],
                                 sampler shadowSampler [[sampler(1)]],
                                 constant FrameUniforms& uniforms [[buffer(BindingsFrameUniforms)]],
                                 constant PointLight* pointLights [[buffer(BindingsLightData)]],
                                 constant uint& lightCount [[buffer(BindingsPointLightCount)]],
                                 texturecube_array<float> shadowAtlas [[texture(BindingsShadowAtas)]],
                                 constant Material& material [[buffer(BindingsMaterialData)]]) {
    // Compute normalized view vector from surface to camera in world space
    float3 N = normalize(in.normal);
    float3 V = normalize(-in.viewPos);
        
    float3 ambient = 0.2 * material.baseColor.xyz;
    float3 diffuse = float3(0);
    float3 specular = float3(0);
    
    for(int i = 0 ; i < int(lightCount) ; i++){
        PointLight light = pointLights[i];
        
        float3 lightPosView = (uniforms.view * float4(light.position.xyz, 1.0)).xyz;
        float3 L = normalize(lightPosView - in.viewPos); // direction from fragment to light in view space
        float3 H = normalize(L + V);
        
        // distance from light to fragment
        float receiverDepth = distance(in.worldPos,  light.position.xyz) / light.radius;
        float3 shadowDir = normalize(in.worldPos - light.position.xyz);
        
        float shadowFactor = receiverDepth > 1 ? 1.0 : PCFCube(shadowAtlas, shadowSampler, shadowDir, receiverDepth, in.worldNormal, i, 3);
        
        float3 lightColor = calculatePointLightColor(light, in.worldPos);
        
        float lightDiffuse = max(dot(N, L), 0.0);
        float lightSpec = pow(max(dot(N, H), 0.0), 64);
        
        diffuse += shadowFactor * lightDiffuse * material.baseColor.xyz * lightColor;
        specular += shadowFactor * lightSpec * lightColor * lightColor;
    }

    float3 result = ambient + diffuse + specular;
    return float4(result, 1.0);
}

float3 calculatePointLightColor(PointLight light, float3 fragmentPosition) {
    float r = abs(length(fragmentPosition - light.position.xyz));
    return light.color.xyz * max(((1-pow((r/light.radius),2.0))),0.0);
}

