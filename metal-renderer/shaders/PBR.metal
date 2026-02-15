//
//  NDF.metal
//  metal-renderer
//
//  Created by Jared Lueck on 2026-01-31.
//

#include <metal_stdlib>
#include <metal_simdgroup_matrix>
#include "PCF.metal"
#include "Types.h"

struct VertexOut {
    float4 position [[position]];
    float3 viewPos;
    float3 normal;
    float2 texCoord;
    float3 worldPos;
    float3 worldNormal;
};

using namespace metal;

namespace NDF {
    float positiveCharacteristic(float x){
        if( x > 0) return 1;
        return 0;
    }

    float blinnPhong(float3 n, float3 m, float roughness){
        float nm = dot(n, m);
        return positiveCharacteristic(nm) * ((roughness + 2)/2*M_PI_F) * pow(nm, roughness);
    }
    
    float beckmann(float roughness, float3 n, float3 m){
        float nm = dot(n, m);
        return (positiveCharacteristic(nm) / (M_PI_F * pow(roughness, 2) * pow(nm, 4))) * exp((pow(nm, 2) - 1)/(pow(roughness, 2.0)*pow(nm, 2)));
    }
    
    float GGX(float roughness, float3 N, float3 M){
        float alpha = roughness * roughness;
        float NdM = dot(N, M);
        return positiveCharacteristic(NdM) * alpha / (M_PI_F * (1 + pow(NdM, 2.0) * (alpha - 1)));
    }
}

namespace Mask {
    
}

namespace BRDF {
    // compute fresnel color using schlick approximation
    float fresnel(float F0, float3 n, float3 l){
        return F0 + (1.0f - F0) * pow(1.0f - clamp(dot(n, l), 0.0f, 1.0f), 5.0f);
    }

    float3 cookTorrence(float3 F, float roughness, float3 N, float3 L, float3 V){
        float3 H = normalize(L + V);
        float3 M = H;
        float NdH = saturate(dot(H, N));
        float NdV = saturate(dot(V, N));
        float VdH = saturate(dot(V, H));
        float NdL = saturate(dot(N, L));
        float G = min(1.0, min((2*NdH*NdV)/VdH,(2*NdH*NdL)/VdH));
        float D = NDF::GGX(roughness, N, M);
        return (F / M_PI_F) * ((D * G)/((NdL * NdV)));
    }

    float3 orenNayer(float3 albedo, float roughness, float3 N, float3 L, float3 V){
        float sigma2 = roughness * roughness;
        
        float NdL = dot(N, L);
        float NdV = dot(N, V);
        float3 lp = normalize(L - N * NdL);
        float3 vp = normalize(V - N * NdV);
        // relative azimuth
        float cosRelativeAzimuth = dot(lp, vp);
        float sinThetaI = sqrt(max(0.0, 1 - NdL*NdL));
        float sinThetaO = sqrt(max(0.0, 1 - NdV*NdV));
        
        float alphaSin = max(sinThetaI, sinThetaO);
        float eps = 1e-4;
        float betaTan = min(sinThetaI/max(eps, NdL), sinThetaO/max(eps, NdV));
        
        float A = 1.0 - 0.5 * (sigma2 / (sigma2 + 0.33));
        float B = 0.45 * (sigma2 / (sigma2 + 0.09));
        return (albedo / M_PI_F) * (A + B * max(0.0, cosRelativeAzimuth)) * alphaSin * betaTan;
    }
}

float3 calculatePointLightColor1(PointLight light, float3 fragmentPosition) {
    float r = abs(length(fragmentPosition - light.position.xyz));
    return light.color.xyz * max(((1-pow((r/light.radius),2.0))),0.0);
}

fragment float4 pbrFragment(VertexOut in [[stage_in]],
                                 sampler s [[sampler(SamplerIndexDefault)]],
                                 sampler shadowSampler [[sampler(SamplerIndexCube)]],
                                 constant FrameData& uniforms [[buffer(BufferIndexFrameData)]],
                                 constant PointLight* pointLights [[buffer(BufferIndexLightData)]],
                                 constant uint& lightCount [[buffer(BufferIndexPointLightCount)]],
                            texturecube_array<float, access :: read> shadowAtlas [[texture(TextureIndexShadow)]],
                                 constant InstanceData& material [[buffer(BufferIndexInstanceData)]],
                                 constant DebugData& debug [[buffer(BufferIndexDebug)]]) {
    constexpr sampler linearSampler (mip_filter::linear,
                                     mag_filter::linear,
                                     min_filter::linear);
    
    // Compute normalized view vector from surface to camera in world space
    float3 N = normalize(in.normal);
    if(debug.normal == 1){
        return float4(N, 1.0);
    }
    float3 V = normalize(-in.viewPos);
        
    float3 ambient = 0.2 * material.baseColor.xyz;
    float3 diffuse = float3(0);
    float3 specular = float3(0);
    
    for(int i = 0 ; i < int(lightCount) ; i++){
        PointLight light = pointLights[i];
        
        float3 lightPosView = (uniforms.view * float4(light.position.xyz, 1.0)).xyz;
        float3 L = normalize(lightPosView - in.viewPos); // direction from fragment to light in view space
        
        // distance from light to fragment
        float receiverDepth = distance(in.worldPos,  light.position.xyz) / light.radius;
        float3 shadowDir = normalize(in.worldPos - light.position.xyz);
        
        float specShadow = PCFCube(shadowAtlas, linearSampler, shadowDir, receiverDepth, in.worldNormal, i, 0);
        float shadowFactor = PCFCubePoisson(shadowAtlas, linearSampler, shadowDir, receiverDepth, in.worldNormal, i);
        
        // incident light color with attenuation
        float3 lightColor = calculatePointLightColor1(light, in.worldPos);
        
        float F = BRDF::fresnel(material.specular, N, L);
        
        float3 lightDiffuse = clamp(dot(N, L), 0.0, 1.0) * BRDF::orenNayer(material.baseColor.xyz, material.roughness, N, L, V);
        float alpha = material.roughness * material.roughness;
        float3 lightSpec = max(BRDF::cookTorrence(F, alpha, N, L, V), 0);
        
        diffuse += (1 - F) * shadowFactor * lightDiffuse *  lightColor;
        specular += specShadow * lightSpec * lightColor;
    }
    if(debug.specular == 1){
        return float4(specular, 1.0);
    }
    if(debug.diffuse == 1){
        return float4(diffuse, 1.0);
    }

    float3 result = ambient + diffuse + specular;
    return float4(result, 1.0);
}

