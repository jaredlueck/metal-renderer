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
    let outlineShaders: ShaderProgram
    let outlinePipeline: RenderPipeline<Any>
    
    let gridShaders: ShaderProgram
    let gridPipeline: RenderPipeline<Any>
    
    let device: MTLDevice
    let descriptor: MTLRenderPassDescriptor;
    
    init(device: MTLDevice, colorTexture: MTLTexture, depthTexture: MTLTexture){
        self.descriptor = MTLRenderPassDescriptor()
        self.descriptor.colorAttachments[0].texture = colorTexture
        self.descriptor.colorAttachments[0].loadAction = .load
        self.descriptor.colorAttachments[0].storeAction = .store
        self.descriptor.depthAttachment.texture = depthTexture
        self.descriptor.depthAttachment.loadAction = .load

        try! self.outlineShaders = ShaderProgram(device: device, descriptor: ShaderProgramDescriptor(vertexName: "outlineVertex", fragmentName: "outlineFragment"))
        self.outlinePipeline = RenderPipeline<Any>(device: device, program: self.outlineShaders, vertexDescriptor: nil, colorAttachmentPixelFormat: MTLPixelFormat.bgra8Unorm_srgb, depthAttachmentPixelFormat: MTLPixelFormat.depth32Float)
        
        try! self.gridShaders = ShaderProgram(device: device, descriptor: ShaderProgramDescriptor(vertexName: "gridVertex", fragmentName: "gridFragment"))
        self.gridPipeline = RenderPipeline<Any>(device: device, program: self.gridShaders, vertexDescriptor: nil, colorAttachmentPixelFormat: MTLPixelFormat.bgra8Unorm_srgb, depthAttachmentPixelFormat: MTLPixelFormat.depth32Float)

        self.device = device
    }
    
    func encode(commandBuffer: MTLCommandBuffer, sharedResources: inout SharedResources){
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: self.descriptor) else {
            fatalError("Failed to create render command encoder")
        }
        encoder.label = "mask outline encoder"
        
        encoder.setDepthStencilState(sharedResources.depthStencilStateDisabled)
        
        withUnsafeBytes(of: sharedResources.frameUniforms) { rawBuffer in
            encoder.setVertexBytes(rawBuffer.baseAddress!,
                                           length: MemoryLayout<FrameUniforms>.stride,
                                     index: Bindings.frameUniforms)
        }
                
        encoder.setFragmentTexture(sharedResources.outlineMask, index: 0)

        var outlineColor = SIMD4<Float>(0, 1, 0, 1)
        encoder.setFragmentBytes(&outlineColor, length: MemoryLayout<SIMD4<Float>>.stride, index: Bindings.pipelineUniforms)
        
        self.outlinePipeline.bind(encoder: encoder)
        
        encoder.setDepthStencilState(sharedResources.depthStencilStateDisabled)
        
        encoder.drawPrimitives(type: MTLPrimitiveType.triangle, vertexStart: 0, vertexCount: 6)
        
        encoder.setDepthStencilState(sharedResources.depthStencilStateEnabled)
        
        self.gridPipeline.bind(encoder: encoder)
        
        encoder.drawPrimitives(type: MTLPrimitiveType.triangle, vertexStart: 0, vertexCount: 6)
        
        encoder.endEncoding()
        
    }
}
