//
//  Model.swift
//  metal-swift-new
//
//  Created by Jared Lueck on 2025-12-31.
//

import Metal
import MetalKit

class Model {
    let meshes: [MTKMesh]
    public let asset: MDLAsset
    init(device: MTLDevice, resourceName: String, ext: String = "obj") {
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: ext) else {
            fatalError("Couldn't find skybox texture")
        }
        let allocator = MTKMeshBufferAllocator(device: device)
        self.asset = MDLAsset(url: url, vertexDescriptor: VertexDescriptors.mdl(), bufferAllocator: allocator)
        asset.loadTextures()
        do {
            (_, self.meshes) = try MTKMesh.newMeshes(asset: asset, device: device)
        } catch {
            fatalError("Failed to create MTKMesh from asset: \(error)")
        }
    }
}
