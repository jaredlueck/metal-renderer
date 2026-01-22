//
//  RenderPass.swift
//  metal-swift-new
//
//  Created by Jared Lueck on 2026-01-04.
//

import Metal
import simd

class ColorPass {
    let descriptor: MTLRenderPassDescriptor;
    let device: MTLDevice
    
    let colorAttachmentPixelFormat = MTLPixelFormat.bgra8Unorm_srgb
    let depthAttachmentPixelFormat = MTLPixelFormat.depth32Float
    
    let blinnPhongShaders: ShaderProgram
    let blinnPhongPipeline: RenderPipeline
    
    let sampler: MTLSamplerState
    
    init(device: MTLDevice) {
        self.descriptor = MTLRenderPassDescriptor();
        self.descriptor.depthAttachment.storeAction = .store
        self.descriptor.depthAttachment.clearDepth = 1.0
        self.descriptor.colorAttachments[0].loadAction = .clear
                
        self.device = device

        self.blinnPhongShaders = try! ShaderProgram(device: self.device, descriptor: ShaderProgramDescriptor(vertexName: "phongVertex", fragmentName: "phongFragment"))
        self.blinnPhongPipeline = RenderPipeline(device: self.device, program: self.blinnPhongShaders, colorAttachmentPixelFormat: colorAttachmentPixelFormat, depthAttachmentPixelFormat: depthAttachmentPixelFormat)
        
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.mipFilter = .linear
        guard let sampler = device.makeSamplerState(descriptor: samplerDescriptor) else {
            fatalError("Failed to create sampler state")
        }
        self.sampler = sampler
    }
    
    func setColorAttachment(colorTexture: MTLTexture) {
        self.descriptor.colorAttachments[0].texture = colorTexture
    }
    
    func setDepthAttachment(depthTexture: MTLTexture) {
        self.descriptor.depthAttachment.texture = depthTexture
    }
    
    func encode(commandBuffer: MTLCommandBuffer,  pointLights: [PointLight], renderables: [InstancedRenderable], sharedResources: inout SharedResources){
        self.descriptor.depthAttachment.texture = sharedResources.depthBuffer
        self.descriptor.colorAttachments[0].texture = sharedResources.colorBuffer
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: self.descriptor) else {
            fatalError("failed to create encoder")
        }
        encoder.label = "Color pass encoder"
        
        // Set common uniforms
        withUnsafeBytes(of: sharedResources.makeFrameUniforms()) { rawBuffer in
            encoder.setFragmentBytes(rawBuffer.baseAddress!,
                                           length: MemoryLayout<FrameUniforms>.stride,
                                     index: Bindings.frameUniforms)
            encoder.setVertexBytes(rawBuffer.baseAddress!,
                                           length: MemoryLayout<FrameUniforms>.stride,
                                     index: Bindings.frameUniforms)
        }
        
        encoder.setFragmentSamplerState(sharedResources.sampler, index: Bindings.sampler)
        encoder.setFragmentSamplerState(sharedResources.shadowSampler, index: Bindings.shadowSampler)
                
        encoder.pushDebugGroup("render meshes")
        encoder.setDepthStencilState(sharedResources.depthStencilStateEnabled)
                        
        let lightBuffer = pointLights.withUnsafeBufferPointer { bufferPtr in
             return device.makeBuffer(bytes: bufferPtr.baseAddress!, length: MemoryLayout<PointLight>.stride * pointLights.count)
        }
        
        encoder.setFragmentBuffer(lightBuffer, offset: 0, index: Bindings.lightData)
        
        var lightCount = pointLights.count
        encoder.setFragmentBytes(&lightCount, length: MemoryLayout<UInt>.self.stride, index: Bindings.pointLightCount)
        
        self.blinnPhongPipeline.bind(encoder: encoder)
        
        for i in 0..<renderables.count {
            let renderable = renderables[i]
        }
        encoder.setFragmentBuffer(lightBuffer, offset: 0, index: Bindings.lightData)
        encoder.setFragmentTexture(sharedResources.pointLightShadowAtlas, index: Bindings.shadowAtas)

        self.blinnPhongPipeline.bind(encoder: encoder)
        
        for i in 0..<renderables.count {
            let renderable = renderables[i]
            renderable.draw(renderEncoder: encoder, instanceId: nil)
        }
        encoder.popDebugGroup()
        encoder.endEncoding()
    }
}

