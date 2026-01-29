//
//  OutlineRenderPass.swift
//  metal-swift-new
//
//  Created by Jared Lueck on 2026-01-01.
//

import Metal
import simd

class MaskPass {
    let maskShaders: ShaderProgram
    let maskPipeline: RenderPipeline
    let device: MTLDevice
    let descriptor: MTLRenderPassDescriptor;
    
    init(device: MTLDevice){
        self.descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].clearColor = MTLClearColor.init(red: 0, green: 0, blue: 0, alpha: 1)
        self.descriptor.colorAttachments[0].loadAction = .clear
        self.descriptor.colorAttachments[0].storeAction = .store
        try! self.maskShaders = ShaderProgram(device: device, descriptor: ShaderProgramDescriptor(vertexName: "maskVertex", fragmentName: "maskFragment"))
        self.maskPipeline = RenderPipeline(device: device, program: self.maskShaders, colorAttachmentPixelFormat: .r32Float)
        self.device = device
    }
    
    func encode(commandBuffer: MTLCommandBuffer, sharedResources: inout SharedResources){
        self.descriptor.colorAttachments[0].texture = sharedResources.outlineMask
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: self.descriptor) else {
            fatalError("Failed to create render command encoder")
        }
        encoder.label = "Mask pass encoder"
        
        encoder.pushDebugGroup("render mask of selected object")
        
        withUnsafeBytes(of: sharedResources.makeFrameUniforms()) { rawBuffer in
            encoder.setVertexBytes(rawBuffer.baseAddress!,
                                           length: MemoryLayout<FrameUniforms>.stride,
                                   index: Int(BufferIndexInstanceData.rawValue))
        }
                
        self.maskPipeline.bind(encoder: encoder)
        
        if let selected = sharedResources.selectedRenderableInstance {
            for renderable in sharedResources.renderables {
                if let instance = renderable.instances.first(where: {$0.id == selected.id}){
                    renderable.draw(renderEncoder: encoder, instanceId: instance.id)
                }
            }
        }
        encoder.popDebugGroup()
        encoder.endEncoding()
    }
}

