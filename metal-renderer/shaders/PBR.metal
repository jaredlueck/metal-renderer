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

float GGX(float roughness, float3 N, float3 H) {
    float alpha = roughness * roughness;     // perceptual roughness -> microfacet alpha
    float a2 = alpha * alpha;
    float NdH = saturate(dot(N, H));
    float denom = NdH * NdH * (a2 - 1.0) + 1.0;
    return a2 / (M_PI_F * denom * denom);
}

float3 diffuseDisneyBRDF(float roughness, float3 albedo, float3 N, float3 L, float3 V, float3 H){
    float LdH = saturate(dot(L, H));
    float NdL = saturate(dot(N, L));
    float NdV = saturate(dot(N, V));
    
    float F90 = 0.5 + 2.0 * roughness * LdH * LdH;
    float oneMinusNdL5 = pow(1.0 - NdL, 5.0);
    float oneMinusNdV5 = pow(1.0 - NdV, 5.0);
    
    return (albedo / M_PI_F) * (1.0 + (F90 - 1.0) * oneMinusNdL5) * (1.0 + (F90 - 1.0) * oneMinusNdV5);
}

// compute fresnel color using schlick approximation
float3 fresnel(float3 F0, float3 n, float3 l){
    return F0 + (1.0f - F0) * pow(1.0f - clamp(dot(n, l), 0.0f, 1.0f), 5.0f);
}

float3 cookTorrence(float3 F, float roughness, float3 N, float3 L, float3 V){
    float3 H = normalize(L + V);
    float3 M = H;
    float NdV = saturate(dot(V, N));
    float NdL = saturate(dot(N, L));
    float G = GGX(roughness, N, H);
    float sigma = max(1e-4, roughness * roughness);
    float D = beckmann(sigma, N, M);
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

float3 calculatePointLightColor1(PointLight light, float3 fragmentPosition) {
    float r = abs(length(fragmentPosition - light.position.xyz));
    return light.color.xyz * max(((1-pow((r/light.radius),2.0))),0.0);
}

fragment float4 pbrFragment(VertexOut in [[stage_in]],
                                 sampler shadowSampler [[sampler(SamplerIndexCube)]],
                                 constant FrameData& uniforms [[buffer(BufferIndexFrameData)]],
                                 constant PointLight* pointLights [[buffer(BufferIndexLightData)]],
                                 constant uint& lightCount [[buffer(BufferIndexPointLightCount)]],
                                 texturecube_array<float, access :: read> shadowAtlas [[texture(TextureIndexShadow)]],
                                 constant InstanceData& material [[buffer(BufferIndexInstanceData)]],
                            texturecube<float> envMap [[texture(TextureIndexEnvironmentMap)]],
                                 constant DebugData& debug [[buffer(BufferIndexDebug)]]) {
    constexpr sampler linearSampler (mip_filter::linear,
                                     mag_filter::linear,
                                     min_filter::linear);
    
    float3 ambient = 0;
    float3 diffuse = float3(0);
    float3 specular = float3(0);
    float3 N = normalize(in.normal);
    float3 V = normalize(-in.viewPos);
    float3 F0 = pow((material.Ni - 1)/(material.Ni + 2), 2.0);

    {
        float3 N = normalize(in.worldNormal);
        float3 V = normalize(uniforms.cameraPosition.xyz - in.worldPos);
        if(debug.normal == 1){
            return float4(N, 1.0);
        }
        float3 I = -V;
        
        float3 R = normalize(reflect(I, N));
        
        float3 radiance = envMap.sample(shadowSampler, R).xyz;
        float3 F = fresnel(F0, N, R);
        
        float alpha = material.roughness;
        float3 lightSpec = material.specular * max(cookTorrence(F, alpha, N, R, V), 0);
        
        float3 H = normalize(R + V);
        
        // Lambertian diffuse for global illumination
        diffuse = (1 - F) * diffuseDisneyBRDF(material.roughness, material.baseColor.xyz, N, R, V, H);
        specular = radiance * lightSpec * material.specular;
    }

    if (debug.environment == 1){
        return float4(ambient + diffuse + specular, 1.0);
    }

    for(int i = 0 ; i < int(lightCount); i++){
        PointLight light = pointLights[i];
        
        float3 lightPosView = (uniforms.view * float4(light.position.xyz, 1.0)).xyz;
        float3 L = normalize(lightPosView - in.viewPos); // direction from fragment to light in view space
        float3 H = normalize(L + V);

        // distance from light to fragment
        float receiverDepth = distance(in.worldPos,  light.position.xyz) / light.radius;
        float3 shadowDir = normalize(in.worldPos - light.position.xyz);

        float specShadow = PCFCube(shadowAtlas, linearSampler, shadowDir, receiverDepth, in.worldNormal, i, 0);
        float shadowFactor = PCFCubePoisson(shadowAtlas, linearSampler, shadowDir, receiverDepth, in.worldNormal, i);

        // incident light color with attenuation
        float3 lightColor = calculatePointLightColor1(light, in.worldPos);

        float3 F = fresnel(F0, N, L);

        float3 lightDiffuse = (1 - F) * diffuseDisneyBRDF(material.roughness, material.baseColor.xyz, N, L, V, H);
        float alpha = material.roughness;
        float3 lightSpec = max(cookTorrence(F, alpha, N, L, V), 0);

        diffuse += shadowFactor * lightDiffuse * lightColor;
        specular +=  material.specular * specShadow * lightSpec * lightColor;
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

