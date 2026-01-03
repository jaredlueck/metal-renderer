//
//  OutlineRenderPass.swift
//  metal-swift-new
//
//  Created by Jared Lueck on 2026-01-01.
//

import Metal
import simd

import Metal

class OutlinePass {
    let pipeline: OutlinePipeline
    let device: MTLDevice
    let descriptor: MTLComputePassDescriptor;
    
    init(device: MTLDevice){
        self.descriptor = MTLComputePassDescriptor()
        self.pipeline = OutlinePipeline(device: device)
        self.device = device
    }
    
    func encode(commandBuffer: MTLCommandBuffer, sharedResources: inout SharedResources){
        guard let encoder = commandBuffer.makeComputeCommandEncoder(descriptor: self.descriptor) else {
            fatalError("Failed to create render command encoder")
        }
        encoder.label = "mask outline compute pass encoder"
                
        encoder.setTexture(sharedResources.outlineMask, index: 0)
        
        encoder.setTexture(sharedResources.colorBuffer, index: 1)
        
        let outlineDesc = MTLTextureDescriptor()
        outlineDesc.textureType = .type2D
        outlineDesc.pixelFormat = .bgra8Unorm_srgb
        outlineDesc.width = sharedResources.colorBuffer?.width ?? 1024
        outlineDesc.height = sharedResources.colorBuffer?.height ?? 1014
        outlineDesc.usage = [.shaderWrite, .shaderRead]
        
        let outlineTex = device.makeTexture(descriptor: outlineDesc)
        
        encoder.setTexture(outlineTex, index: 2)
        var outlineColor = SIMD4<Float>(0, 1, 0, 1)
        encoder.setBytes(&outlineColor, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
        
        self.pipeline.bind(encoder: encoder)
        
        let threadsPerThreadgroup = MTLSize(width: 1, height: 1, depth: 1)

        let threadsPerGrid = MTLSize(width: outlineDesc.width,
                                     height: outlineDesc.height,
                                     depth: 1)
        
        sharedResources.colorBuffer = outlineTex
        
        encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        encoder.endEncoding()
        
    }
}
