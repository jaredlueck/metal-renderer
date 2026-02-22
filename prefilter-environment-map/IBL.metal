#include <metal_stdlib>

using namespace metal;

// Radical inverse in base 2 using bit reversal (Van der Corput sequence)
inline float RadicalInverse_VdC(uint bits)
{
    bits = (bits << 16u) | (bits >> 16u);
    bits = ((bits & 0x55555555u) << 1u) | ((bits & 0xAAAAAAAAu) >> 1u);
    bits = ((bits & 0x33333333u) << 2u) | ((bits & 0xCCCCCCCCu) >> 2u);
    bits = ((bits & 0x0F0F0F0Fu) << 4u) | ((bits & 0xF0F0F0F0u) >> 4u);
    bits = ((bits & 0x00FF00FFu) << 8u) | ((bits & 0xFF00FF00u) >> 8u);
    return (float)bits * 2.3283064365386963e-10f; // 1/2^32
}

// Hammersley point set on [0,1]^2
inline float2 Hammersley(uint i, uint N)
{
    return float2((float)i / (float)N, RadicalInverse_VdC(i));
}

float3 ImportanceSampleGGX(float2 Xi, float Roughness, float3 N)
{
    float a = Roughness * Roughness;
    float Phi = 2 * M_PI_F * Xi.x;
    float CosTheta = sqrt((1 - Xi.y) / (1 + (a*a - 1) * Xi.y));
    float SinTheta = sqrt(1 - CosTheta * CosTheta);
    float3 H;
    H.x = SinTheta * cos(Phi);
    H.y = SinTheta * sin(Phi);
    H.z = CosTheta;
    float3 UpVector = abs(N.z) < 0.999 ? float3(0, 0, 1) : float3(1, 0, 0);
    float3 TangentX = normalize(cross(UpVector, N));
    float3 TangentY = cross(N, TangentX);
    return TangentX * H.x + TangentY * H.y + N * H.z;
}

float3 PrefilterEnvMap(float Roughness, float3 R, texturecube<float, access::sample> EnvMap, sampler EnvMapSampler)
{
    float3 N = R;
    float3 V = R;
    float3 PrefilteredColor = 0;
    float TotalWeight = 0.0f;
    const uint NumSamples = 1024;
    for (uint i = 0; i < NumSamples; i++) {
        float2 Xi = Hammersley(i, NumSamples);
        float3 H = ImportanceSampleGGX(Xi, Roughness, N);
        float3 L = 2 * dot(V, H) * H - V;
        float NoL = saturate(dot(N, L));
        if (NoL > 0) {
            PrefilteredColor += EnvMap.sample(EnvMapSampler, L).rgb * NoL;
            TotalWeight += NoL;
        }
    }
    return TotalWeight > 0 ? PrefilteredColor / TotalWeight : PrefilteredColor;
}

// Convert pixel UV (origin top-left) on a cube face to a world-space direction.
// Convention: right-handed, Y-up, Metal cubemap face order (0=+X,1=-X,2=+Y,3=-Y,4=+Z,5=-Z).
float3 convertUVToDirection(float u, float v, uint faceIndex)
{
    float s = 2.0f * u - 1.0f;  // [-1,1], increases rightward
    float t = 2.0f * v - 1.0f;  // [-1,1], t=-1 at top (v=0)

    float3 dir;
    switch (faceIndex)
    {
        case 0: dir = float3( 1, -t, -s); break;  // +X
        case 1: dir = float3(-1, -t,  s); break;  // -X
        case 2: dir = float3( s,  1,  t); break;  // +Y
        case 3: dir = float3( s, -1, -t); break;  // -Y
        case 4: dir = float3( s, -t,  1); break;  // +Z
        case 5: dir = float3(-s, -t, -1); break;  // -Z
        default: dir = float3(0, 0, 1);   break;
    }
    return normalize(dir);
}

// Writes one face of the prefiltered environment map to a 2D texture.
// Dispatch once per face; set `face` to 0-5 to select which cube face to compute.
kernel void prefilterEnvMap(
    uint2 gid                                          [[thread_position_in_grid]],
    constant float& roughness                          [[buffer(0)]],
    constant uint&  face                               [[buffer(1)]],
    texturecube<float, access::sample> envMap          [[texture(0)]],
    texture2d<float, access::write>    outFace         [[texture(1)]],
    sampler s                                          [[sampler(0)]])
{
    if (gid.x >= outFace.get_width() || gid.y >= outFace.get_height()) return;

    float u = (gid.x + 0.5f) / float(outFace.get_width());
    float v = (gid.y + 0.5f) / float(outFace.get_height());
    float3 R = convertUVToDirection(u, v, face);
    float3 color = PrefilterEnvMap(roughness, R, envMap, s);
    outFace.write(float4(color, 1.0f), gid);
}

inline float G_SchlickGGX(float NdotX, float k)
{
    return NdotX / (NdotX * (1.0f - k) + k);
}

inline float G_Smith(float Roughness, float NoV, float NoL)
{
    float k = (Roughness + 1.0f);
    k = (k * k) * 0.125f; // (r+1)^2 / 8
    return G_SchlickGGX(saturate(NoV), k) * G_SchlickGGX(saturate(NoL), k);
}

float2 IntegrateBRDF(float Roughness, float NoV)
{
    float3 V = float3(sqrt(1.0f - NoV * NoV), 0, NoV);
    float3 N = float3(0, 0, 1);
    float A = 0;
    float B = 0;
    const uint NumSamples = 1024;
    for (uint i = 0; i < NumSamples; i++)
    {
        float2 Xi = Hammersley(i, NumSamples);
        float3 H = ImportanceSampleGGX(Xi, Roughness, N);
        float3 L = 2 * dot(V, H) * H - V;
        float NoL = saturate(L.z);
        float NoH = saturate(H.z);
        float VoH = saturate(dot(V, H));
        if (NoL > 0)
        {
            float G = G_Smith(Roughness, NoV, NoL);
            float G_Vis = G * VoH / (NoH * NoV);
            float Fc = pow(1 - VoH, 5);
            A += (1 - Fc) * G_Vis;
            B += Fc * G_Vis;
        }
    }
    return float2(A, B) / NumSamples;
}

// BRDF integration LUT: x = NoV [0,1], y = roughness [0,1]. Output: R=scale, G=bias.
kernel void computeLUT(
    uint2 gid                              [[thread_position_in_grid]],
    texture2d<float, access::write> LUT    [[texture(0)]])
{
    if (gid.x >= LUT.get_width() || gid.y >= LUT.get_height()) return;

    float NoV       = (gid.x + 0.5f) / float(LUT.get_width());
    float roughness = (gid.y + 0.5f) / float(LUT.get_height());
    float2 brdf = IntegrateBRDF(roughness, NoV);
    LUT.write(float4(brdf, 0.0f, 1.0f), gid);
}
