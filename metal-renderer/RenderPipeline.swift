//
//  RenderPipeline.swift
//  metal-swift-new
//
//  Created by Jared Lueck on 2026-01-04.
//

import Metal

class RenderPipeline{
    public let vertexFunction: MTLFunction
    public let fragmentFunction: MTLFunction
    let pipelineState: MTLRenderPipelineState
    
    init(device: MTLDevice, program: ShaderProgram, vertexDescriptor: MTLVertexDescriptor? = VertexDescriptors.mtl(), colorAttachmentPixelFormat: MTLPixelFormat = .invalid, depthAttachmentPixelFormat: MTLPixelFormat = .invalid){
        self.vertexFunction = program.vertex
        self.fragmentFunction = program.fragment
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = colorAttachmentPixelFormat
        // Enable alpha blending
        let attachment = pipelineDescriptor.colorAttachments[0]
        attachment?.isBlendingEnabled = true
        attachment?.rgbBlendOperation = .add
        attachment?.alphaBlendOperation = .add
        attachment?.sourceRGBBlendFactor = .sourceAlpha
        attachment?.destinationRGBBlendFactor = .oneMinusSourceAlpha
        attachment?.sourceAlphaBlendFactor = .sourceAlpha
        attachment?.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        pipelineDescriptor.depthAttachmentPixelFormat = depthAttachmentPixelFormat

        if let vertexDescriptor = vertexDescriptor {
            pipelineDescriptor.vertexDescriptor = vertexDescriptor
        }
        
        do {
            self.pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            fatalError("Failed to create render pipeline state: \(error)")
        }
    }
    
    func bind(encoder: MTLRenderCommandEncoder) {
        encoder.setRenderPipelineState(pipelineState)
    }
}
