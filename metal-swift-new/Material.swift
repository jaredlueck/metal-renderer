//
//  Meterial.swift
//  metal-swift-new
//
//  Created by Jared Lueck on 2026-01-04.
//
//  Note: Renamed to PBRMaterial to avoid invalid redeclaration conflicts with any existing `Material` type.
//

import simd

/// A simple physically based material description suitable for Metal shaders.
/// Stores common PBR parameters and optional texture references by index.
public final class PBRMaterial: Sendable {
    // MARK: - Scalar parameters
    /// Base/albedo color in linear space.
    public var baseColor: simd_float3
    /// Emissive color (linear). Use zero for no emission.
    public var emissiveColor: simd_float3
    /// Perceptual roughness in [0, 1]. 0 = mirror, 1 = fully rough.
    public var roughness: Float
    /// Metallic in [0, 1]. 0 = dielectric, 1 = metal.
    public var metallic: Float
    /// Specular intensity in [0, 1]. Typically ~0.5 for dielectrics.
    public var specular: Float
    /// Ambient occlusion in [0, 1]. 1 = unoccluded.
    public var ambientOcclusion: Float

    // MARK: - Texture bindings (indices into a texture array/atlas or -1 if unused)
    /// Index of a base color (albedo) texture, or -1 if none.
    public var baseColorTextureIndex: Int
    /// Index of a normal map texture, or -1 if none.
    public var normalTextureIndex: Int
    /// Index of a metallic-roughness texture (G: roughness, B: metallic) or -1 if none.
    public var metallicRoughnessTextureIndex: Int
    /// Index of an occlusion texture, or -1 if none.
    public var occlusionTextureIndex: Int
    /// Index of an emissive texture, or -1 if none.
    public var emissiveTextureIndex: Int

    // MARK: - Initializers
    public init(
        baseColor: simd_float3 = simd_float3(1, 1, 1),
        emissiveColor: simd_float3 = simd_float3(0, 0, 0),
        roughness: Float = 0.5,
        metallic: Float = 0.0,
        specular: Float = 0.5,
        ambientOcclusion: Float = 1.0,
        baseColorTextureIndex: Int = -1,
        normalTextureIndex: Int = -1,
        metallicRoughnessTextureIndex: Int = -1,
        occlusionTextureIndex: Int = -1,
        emissiveTextureIndex: Int = -1
    ) {
        self.baseColor = baseColor
        self.emissiveColor = emissiveColor
        self.roughness = clamp01(roughness)
        self.metallic = clamp01(metallic)
        self.specular = clamp01(specular)
        self.ambientOcclusion = clamp01(ambientOcclusion)
        self.baseColorTextureIndex = baseColorTextureIndex
        self.normalTextureIndex = normalTextureIndex
        self.metallicRoughnessTextureIndex = metallicRoughnessTextureIndex
        self.occlusionTextureIndex = occlusionTextureIndex
        self.emissiveTextureIndex = emissiveTextureIndex
    }

    // MARK: - Utilities
    /// Packs the scalar parameters into a vector useful for GPU buffers.
    public var scalarsPacked: simd_float4 {
        simd_float4(roughness, metallic, specular, ambientOcclusion)
    }
}

// MARK: - Helpers
@inline(__always)
private func clamp01(_ v: Float) -> Float { max(0, min(1, v)) }
