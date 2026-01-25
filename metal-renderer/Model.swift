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
    let path: String
    public let asset: MDLAsset
    init(device: MTLDevice, resourceName: String, ext: String = "obj") {
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: ext) else {
            fatalError("failed to load resourse \(resourceName).\(ext)")
        }
        let allocator = MTKMeshBufferAllocator(device: device)
        self.asset = MDLAsset(url: url, vertexDescriptor: VertexDescriptors.mdl(), bufferAllocator: allocator)
        asset.loadTextures()
        do {
            (_, self.meshes) = try MTKMesh.newMeshes(asset: asset, device: device)
        } catch {
            fatalError("Failed to create MTKMesh from asset: \(error)")
        }
        path = resourceName + ".\(ext)"
    }
    
    init(device: MTLDevice, path: String){
        let assetURL = Bundle.main.bundleURL.appending(component: "Contents/Resources").appending(component: path)
        let allocator = MTKMeshBufferAllocator(device: device)
        self.asset = MDLAsset(url: assetURL, vertexDescriptor: VertexDescriptors.mdl(), bufferAllocator: allocator)
        asset.loadTextures()
        do {
            (_, self.meshes) = try MTKMesh.newMeshes(asset: asset, device: device)
        } catch {
            fatalError("Failed to create MTKMesh from asset: \(error)")
        }
        self.path = path
    }
}
