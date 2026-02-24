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

float beckmann(float alpha, float3 n, float3 m){
    float nm = dot(n, m);
    return (positiveCharacteristic(nm) / (M_PI_F * alpha * pow(nm, 4))) * exp((pow(nm, 2) - 1)/(alpha*pow(nm, 2)));
}

float GGX(float alpha, float3 N, float3 H) {
    float a2 = alpha * alpha;
    float NdH = saturate(dot(N, H));
    float NdH2 = pow(NdH, 2.0);
    float denom = (1 + NdH2 * (a2 - 1));
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

float lambda_GGX(float3 N, float3 S, float alpha){
    float NdS = saturate(dot(N, S));
    float NdS2 = pow(NdS, 2.0);
    float a = NdS / (alpha * sqrt(1 - NdS2));
    float a2 = pow(a, 2.0);
    
    return (-1 + sqrt(1 + (1/a2)))/2;
}

float smith_G1(float3 M, float3 V, float lambdaV){
    float MdV = saturate(dot(M, V));
    return positiveCharacteristic(MdV) / (1 + lambdaV);
}

float smith_G2(float3 L, float3 V, float3 M, float lambdaV, float lambdaL){
    float MdV = saturate(dot(M, V));
    float MdL = saturate(dot(M, L));
    return (positiveCharacteristic(MdV) * positiveCharacteristic(MdL))/( 1 + lambdaV + lambdaL);
}

float separated_G2(float3 L, float3 V, float3 M, float lambdaV, float lambdaL){
    return smith_G1(M, V, lambdaV) * smith_G1(M, L, lambdaL);
}

float3 cookTorrence(float3 F, float alpha, float3 N, float3 L, float3 V){
    float3 H = normalize(L + V);
    float NdV = saturate(dot(N, V));
    float NdL = saturate(dot(N, L));
    if(NdL <= 0) {
        return float3(0.0);
    }

    float lambdaV = lambda_GGX(N, V, alpha);
    float lambdaL = lambda_GGX(N, L, alpha);
    float G = separated_G2(L, V, H, lambdaV, lambdaL);

    float D = GGX(alpha, N, H);

    return (D * F * G) / 4.0 * NdL * NdV;
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
                                 texturecube_array<float> envMap [[texture(TextureIndexEnvironmentMap)]],
                                 texture2d<float> envBrdfLUT [[texture(TextureIndexLUT)]],
                                 constant DebugData& debug [[buffer(BufferIndexDebug)]]) {
    constexpr sampler linearSampler (mip_filter::linear,
                                     mag_filter::linear,
                                     min_filter::linear);
    
    float3 ambient = 0;
    float3 diffuse = float3(0);
    float3 specular = float3(0);
    float3 N = normalize(in.normal);
    if(debug.normal == 1){
        return float4(N, 1.0);
    }
    float3 V = normalize(-in.viewPos);
    float3 F0 = pow((material.Ni - 1)/(material.Ni + 1), 2.0);

    {
        // Map roughness to array index (0 to arrayLength-1)
        int arrayLength = envMap.get_array_size();  // Divide by 6 since cube maps have 6 faces per array element
        float roughnessIndexFloat = material.roughness * material.roughness * float(arrayLength - 1);
        int roughnessIndex = int(round(roughnessIndexFloat));
        roughnessIndex = clamp(roughnessIndex, 0, arrayLength - 1);
        
        float3 N = normalize(in.worldNormal);
        float3 V = normalize(uniforms.cameraPosition.xyz - in.worldPos);

        float3 I = -V;
        
        float3 R = normalize(reflect(I, N));
        float NdV = saturate(dot(N,V));
        
        // Sample the cube texture array at the appropriate roughness index
        float3 prefilteredColor = envMap.sample(shadowSampler, R, roughnessIndex).xyz;
        // BRDF LUT: horizontal axis is NdV, vertical is roughness
        float4 envBRDF = envBrdfLUT.sample(shadowSampler, float2(NdV, material.roughness));
        float3 F = fresnel(F0, N, R);
        float3 H = normalize(R + V);
        diffuse = (1 - material.metallic) * (1 - F) * diffuseDisneyBRDF(material.roughness, material.baseColor.xyz, N, R, V, H);
        specular = prefilteredColor * (material.specular * envBRDF.x + envBRDF.y);
    }

    if (debug.environment == 1){
        if(debug.specular == 1){
            return float4(specular, 1.0);
        }

        if(debug.diffuse == 1){
            return float4(diffuse, 1.0);
        }
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
        float3 lightDiffuse = (1 - material.metallic) * (1 - F) * diffuseDisneyBRDF(material.roughness, material.baseColor.xyz, N, L, V, H);

        float alpha = pow(material.roughness * 0.5, 2.0);
        float3 lightSpec = cookTorrence(F, alpha, N, L, V);
        
        float3 specTerm = lightSpec;
        float3 diffuseTerm = lightDiffuse;

        diffuse += shadowFactor * lightDiffuse * lightColor;
        specular += specShadow * material.specular * lightSpec * lightColor;
        
        if(debug.specular == 1){
            return float4(specTerm, 1.0);
        }

        if(debug.diffuse == 1){
            return float4(diffuseTerm, 1.0);
        }
    }



    float3 result = ambient + diffuse + specular;
    return float4(result, 1.0);
}

