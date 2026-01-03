//
//  OutlineRenderPass.swift
//  metal-swift-new
//
//  Created by Jared Lueck on 2026-01-01.
//

import Metal
import simd

import Metal

class GridPass {
    let pipeline: GridPipeline
    let device: MTLDevice
    let descriptor: MTLRenderPassDescriptor;
    
    init(device: MTLDevice){
        self.descriptor = MTLRenderPassDescriptor()
        self.pipeline = GridPipeline(device: device)
        self.device = device
    }
    
    func encode(commandBuffer: MTLCommandBuffer, sharedResources: inout SharedResources){
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: self.descriptor) else {
            fatalError("Failed to create render command encoder")
        }
        encoder.label = "grid pass"
        
        
        let outlineDesc = MTLTextureDescriptor()
        outlineDesc.textureType = .type2D
        outlineDesc.pixelFormat = .bgra8Unorm_srgb
        outlineDesc.width = sharedResources.colorBuffer?.width ?? 1024
        outlineDesc.height = sharedResources.colorBuffer?.height ?? 1014
        outlineDesc.usage = [.shaderWrite, .shaderRead]
        
        let gridUniforms = GridUniforms(view: sharedResources.viewMatrix, projection: sharedResources.projectionMatrix, gridColor: SIMD4<Float>(1.0,1.0,1.0,1.0), cameraPos: SIMD4<Float>(sharedResources.cameraPos, 1.0))
        self.pipeline.bind(encoder: encoder, uniforms: gridUniforms)
        
        encoder.drawPrimitives(type: MTLPrimitiveType.triangle, vertexStart: 0, vertexCount: 6)
                
        encoder.endEncoding()
        
    }
}

