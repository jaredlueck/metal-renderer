//
//  Skybox.swift
//  metal-swift
//
//  Created by Jared Lueck on 2025-12-08.
//

import Metal
import MetalKit
import ModelIO

class Skybox {
    let vertexBuffer: MTLBuffer

    let vertices: [Float] = [
        // Front face (z = 1)
        -1, -1,  1,   1, -1,  1,  1,  1,  1,
        -1, -1,  1,   1,  1,  1, -1,  1,  1,

        // Back face (z = -1)
         1, -1, -1,  -1, -1, -1,  -1,  1, -1,
         1, -1, -1,  -1,  1, -1,   1,  1, -1,

        // Left face (x = -1)
        -1, -1, -1,  -1, -1,  1,  -1,  1,  1,
        -1, -1, -1,  -1,  1,  1,  -1,  1, -1,

        // Right face (x = 1)
         1, -1,  1,   1, -1, -1,   1,  1, -1,
         1, -1,  1,   1,  1, -1,   1,  1,  1,

        // Top face (y = 1)
        -1,  1,  1,   1,  1,  1,   1,  1, -1,
        -1,  1,  1,   1,  1, -1,  -1,  1, -1,

        // Bottom face (y = -1)
        -1, -1, -1,   1, -1, -1,   1, -1,  1,
        -1, -1, -1,   1, -1,  1,  -1, -1,  1,
    ]
    
    let texture: MTLTexture
    
    let sampler: MTLSamplerState
     
    init(device: MTLDevice) {
        let length = vertices.count * MemoryLayout<Float>.size
        vertexBuffer = device.makeBuffer(bytes: vertices, length: length, options: [.storageModeShared])!
        let textureLoader = MTKTextureLoader(device: device)
        
        guard let url = Bundle.main.url(forResource: "vertical" , withExtension: "png") else {
            fatalError("Couldn't find skybox texture")
        }
        texture = try! textureLoader.newTexture(URL: url, options: [.cubeLayout: MTKTextureLoader.CubeLayout.vertical])
        
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.mipFilter = .linear
        guard let sampler = device.makeSamplerState(descriptor: samplerDescriptor) else {
            fatalError("Failed to create sampler state")
        }
        self.sampler = sampler
    }

    func bind(renderCommandEncoder: MTLRenderCommandEncoder) {
        renderCommandEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        renderCommandEncoder.setFragmentTexture(texture, index: 0)
        renderCommandEncoder.setFragmentSamplerState(sampler, index: 0)
    }
}
