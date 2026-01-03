//
//  Mesh.swift
//  metal-swift-new
//
//  Created by Jared Lueck on 2025-12-09.
//
import ModelIO
import Metal
import MetalKit

class Mesh {

    let vertexBuffer: MTLBuffer
    let texture: MTLTexture
    let sampler: MTLSamplerState
    let submeshes: [MTKSubmesh]
    public var transform: simd_float4x4 = matrix_identity_float4x4

    init(device: MTLDevice, resourceName: String, ext: String = "obj") {
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: ext) else {
            fatalError("Couldn't find skybox texture")
        }
        
        let allocator = MTKMeshBufferAllocator(device: device)
        let asset = MDLAsset(url: url, vertexDescriptor: nil, bufferAllocator: allocator)
        let meshes: [MTKMesh]
        do {
            (_, meshes) = try MTKMesh.newMeshes(asset: asset, device: device)
        } catch {
            fatalError("Failed to create MTKMesh from asset: \(error)")
        }
        submeshes = meshes[0].submeshes;
        vertexBuffer = meshes[0].vertexBuffers[0].buffer
        let textureLoader = MTKTextureLoader(device: device)
        guard let url = Bundle.main.url(forResource: "brick", withExtension: "jpg") else {
            fatalError("Couldn't find skybox texture")
        }
        do {
            texture = try textureLoader.newTexture(URL: url)
        } catch {
            fatalError("Failed to load texture: \(error)")
        }
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.mipFilter = .linear
        guard let sampler = device.makeSamplerState(descriptor: samplerDescriptor) else {
            fatalError("Failed to create sampler state")
        }
        self.sampler = sampler
    }
    func bind(renderEncoder: MTLRenderCommandEncoder) {
        renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 1)
        renderEncoder.setFragmentTexture(texture, index: 0)
        renderEncoder.setFragmentSamplerState(sampler, index: 0)

    }
    
}
