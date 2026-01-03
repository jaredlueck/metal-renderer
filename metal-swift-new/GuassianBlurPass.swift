//
//  GuassianBlurPass.swift
//  metal-swift-new
//
//  Created by Jared Lueck on 2026-01-01.
//

import Metal

class GuassianBlurPass {
    let pipeline: GuassianBlurPipeline
    let device: MTLDevice
    let descriptor: MTLComputePassDescriptor;
    
    init(device: MTLDevice){
        self.descriptor = MTLComputePassDescriptor()
        
        self.pipeline = GuassianBlurPipeline(device: device)
        self.device = device
    }
    
    func encode(commandBuffer: MTLCommandBuffer, sharedResources: inout SharedResources){
        guard let encoder = commandBuffer.makeComputeCommandEncoder(descriptor: self.descriptor) else {
            fatalError("Failed to create render command encoder")
        }
        encoder.label = "guassian blur compute pass encoder"
        
        encoder.pushDebugGroup("render selected mesh")
        
        encoder.setTexture(sharedResources.outlineMask, index: 0)
        
        let weights = guassianKernel(size: 9, sigma: 15)
        
        let blurDesc = MTLTextureDescriptor()
        blurDesc.textureType = .type2D
        blurDesc.pixelFormat = .r32Float
        blurDesc.width = sharedResources.outlineMask?.width ?? 1024
        blurDesc.height = sharedResources.outlineMask?.height ?? 1014
        blurDesc.usage = [.shaderWrite, .shaderRead]
        
        let horizontalTex = device.makeTexture(descriptor: blurDesc)
        
        encoder.setTexture(horizontalTex, index: 1)
        
        
        self.pipeline.bind(encoder: encoder, weights: weights, pass: .horizontal)
        
        let threadsPerThreadgroup = MTLSize(width: 1, height: 1, depth: 1)

        let threadsPerGrid = MTLSize(width: blurDesc.width,
                                     height: blurDesc.height,
                                     depth: 1)

        encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        
        let verticalTex = device.makeTexture(descriptor: blurDesc)
        
        encoder.setTexture(horizontalTex, index: 0)
        encoder.setTexture(verticalTex, index: 1)
        
        self.pipeline.bind(encoder: encoder, weights: weights, pass: .vertical)

        encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        
        let outlineTex = device.makeTexture(descriptor: blurDesc)
        
        encoder.setTexture(sharedResources.outlineMask, index: 0)
        encoder.setTexture(verticalTex, index: 1)
        encoder.setTexture(outlineTex, index: 2)
        
        self.pipeline.bind(encoder: encoder, weights: weights, pass: .outline)

        encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        encoder.endEncoding()
        
    }
}
