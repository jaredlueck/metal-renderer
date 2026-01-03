//
//  BlinnPhong.metal
//  metal-swift-new
//
//  Created by Jared Lueck on 2025-12-20.
//

#include <metal_stdlib>

using namespace metal;

struct Uniforms {
    float4x4 view;
    float4x4 projection;
};

struct Material {
    float3 baseColor;
};

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

struct PointLight {
    float4 position;
    float4 color;
    float  radius;
};

float PCF(depth2d<float> shadowMap, uint2 pixel, float receiverDepth, uint kernelSize);
float PCFCube(texturecube_array<float> shadowAtlas, sampler shadowSampler,float3 dir, float redeiverDepth, float3 normal, uint layer = 0, uint kernelSize = 3);
float3 calculatePointLightColor(PointLight light, float3 fragmentPosition);

vertex VertexOut phongVertex(uint vertex_id [[vertex_id]],
                             uint instance_id [[instance_id]],
                             VertexIn vertexData [[stage_in]],
                             constant float4x4* instanceData [[buffer(2)]],
                             constant Uniforms& uniforms [[buffer(0)]]) {
    
    float4x4 model = instanceData[instance_id];
    VertexOut o;
    float4 localPos = float4(vertexData.position, 1.0);
    o.worldPos = (model * localPos).xyz;
    float4x4 mv = uniforms.view * model;
    float4x4 mvp = uniforms.projection * uniforms.view * model;
    float3x3 normalMatrix = float3x3(mv[0].xyz, mv[1].xyz, mv[2].xyz);
    o.position = mvp * localPos;
    o.viewPos = (mv * localPos).xyz;
    o.texCoord = vertexData.textureCoordinate;
    o.normal = normalize(normalMatrix * vertexData.normal);
    o.worldNormal = normalize((model * float4(vertexData.normal, 1.0)).xyz);
    
    return o;
}

fragment float4 phongFragment(VertexOut in [[stage_in]],
                                 texture2d<float> texture [[texture(0)]],
                                 sampler s [[sampler(0)]],
                                 sampler shadowSampler [[sampler(1)]],
                                 constant Uniforms& uniforms [[buffer(0)]],
                                 constant PointLight* pointLights [[buffer(2)]],
                                 texturecube_array<float> pointLightShadowMaps [[texture(1)]],
                                 constant uint& pointLightCount [[buffer(3)]],
                                 constant Material& material [[buffer(4)]]) {
    // Compute normalized view vector from surface to camera in world space
    float3 N = normalize(in.normal);
    float3 V = normalize(-in.viewPos);
        
    float3 ambient = 0.2 * material.baseColor;
    float3 diffuse = float3(0);
    float3 specular = float3(0);
        
    PointLight light = pointLights[0];
    
    float3 lightPosView = (uniforms.view * float4(light.position.xyz, 1.0)).xyz;
    float3 L = normalize(lightPosView - in.viewPos); // direction from fragment to light in view space
    float3 H = normalize(L + V);
    
    // distance from light to fragment
    float receiverDepth = distance(in.worldPos,  light.position.xyz) / light.radius;

    float3 shadowDir = normalize(in.worldPos - light.position.xyz);

    // Sample normalized distance from the cube array using the NON-compare shadow sampler
    float shadowFactor = PCFCube(pointLightShadowMaps, shadowSampler, shadowDir, receiverDepth, in.normal,  0, 3);
    
    float3 lightColor = calculatePointLightColor(light, in.worldPos);
    
    float lightDiffuse = max(dot(N, L), 0.0);
    float lightSpec = pow(max(dot(N, H), 0.0), 64);
    
    diffuse += shadowFactor * lightDiffuse * material.baseColor;
    specular +=  shadowFactor * lightSpec * lightColor;

    float3 result = ambient + diffuse; // + specular if desired
    return float4(result, 1.0);
}

float3 calculatePointLightColor(PointLight light, float3 fragmentPosition) {
    float r = length(fragmentPosition - light.position.xyz);
    return light.color.xyz * pow(max(((1-pow((r/light.radius),2.0))),0.0), 2.0);
}

float PCFCube(texturecube_array<float> shadowAtlas,
              sampler shadowSampler,
              float3 dir,
              float receiverDepth,
              float3 normal,
              uint layer,
              uint kernelSize)
{
    dir = normalize(dir);

    float3 up = (abs(dir.y) > 0.99) ? float3(0.0, 0.0, 1.0) : float3(0.0, 1.0, 0.0);

    // Build orthonormal basis
    float3 a = normalize(cross(up, dir));
    float3 b = normalize(cross(a, dir));

    float width = shadowAtlas.get_width();
    float maxAxis = max(max(abs(dir.x), abs(dir.y)), abs(dir.z));

    const float filterRadius = 1.0;
    float delta = (2.0 * maxAxis) / width * filterRadius;

    float bias = 0.0001;
    float sum = 0.0;
    int k = (int)kernelSize;

    for (int dx = -k; dx <= k; ++dx) {
        for (int dy = -k; dy <= k; ++dy) {
            float3 sampleDir = dir + (dx * delta) * a + (dy * delta) * b;
            float3 nd = normalize(sampleDir);
            float slopeBias = (1 - saturate(dot(normal, -nd)))*0.01;
            float sampled = shadowAtlas.sample(shadowSampler, nd, layer).r;
            sum += (receiverDepth - (bias + slopeBias) <= sampled) ? 1.0 : 0.0;
        }
    }

    float taps = (float)((2 * k + 1) * (2 * k + 1));
    return sum / taps;
}

float PCF(depth2d<float> shadowMap, uint2 pixel, float receiverDepth, uint kernelSize){
    // Use signed ints locally to avoid ambiguous clamp overloads with uints
    int width = (int)shadowMap.get_width();
    int height = (int)shadowMap.get_height();

    // Accumulator for how many samples are lit (receiver not in shadow)
    float sum = 0.0;

    // Define half-size of the kernel; iterate from -k to +k inclusive for a square kernel
    int k = (int)kernelSize;

    for (int dx = -k; dx <= k; dx++) {
        for (int dy = -k; dy <= k; dy++) {
            int sx = (int)pixel.x + dx;
            int sy = (int)pixel.y + dy;
            
            sx = clamp(sx, 0, width-1);
            sy = clamp(sy, 0, height-1);

            float depth = shadowMap.read(uint2((uint)sx, (uint)sy));
            // If receiver depth is in front of the stored depth, it's lit (PCF style)
            if (receiverDepth <= depth) {
                sum += 1.0;
            }
        }
    }
    // Normalize by the number of samples taken: (2k + 1)^2
    float samples = (float)((2 * k + 1) * (2 * k + 1));
    return sum / samples;
}

