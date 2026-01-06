//
//  RenderPass.swift
//  metal-swift-new
//
//  Created by Jared Lueck on 2026-01-04.
//

import Metal
import simd

class ColorPassx {
    let descriptor: MTLRenderPassDescriptor;
    let device: MTLDevice
    
    let skyboxShaders: ShaderProgram
    let skyboxPipeline: RenderPipeline<SkyBoxUniforms>
    
    let blinnPhongShaders: ShaderProgram
    let blinnPhongPipeline: RenderPipeline<Any>
    
    let sampler: MTLSamplerState
    
    init(device: MTLDevice, depthTexture: MTLTexture, colorTexture: MTLTexture) {
        self.descriptor = MTLRenderPassDescriptor();
        self.descriptor.depthAttachment.texture = depthTexture
        self.descriptor.depthAttachment.storeAction = .store
        self.descriptor.depthAttachment.clearDepth = 1.0
        self.descriptor.colorAttachments[0].texture = colorTexture
        
        self.device = device

        self.skyboxShaders = try! ShaderProgram(device: self.device, descriptor: ShaderProgramDescriptor(vertexName: "skyboxVertex", fragmentName: "skyboxFragment"))
        self.skyboxPipeline = RenderPipeline<SkyBoxUniforms>(device: self.device, program: self.skyboxShaders, vertexDescriptor: nil, colorAttachmentPixelFormat: colorTexture.pixelFormat, depthAttachmentPixelFormat: depthTexture.pixelFormat)

        self.blinnPhongShaders = try! ShaderProgram(device: self.device, descriptor: ShaderProgramDescriptor(vertexName: "phongVertex", fragmentName: "phongFragment"))
        self.blinnPhongPipeline = RenderPipeline<Any>(device: self.device, program: self.blinnPhongShaders, colorAttachmentPixelFormat: colorTexture.pixelFormat, depthAttachmentPixelFormat: depthTexture.pixelFormat)
        
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.mipFilter = .linear
        guard let sampler = device.makeSamplerState(descriptor: samplerDescriptor) else {
            fatalError("Failed to create sampler state")
        }
        self.sampler = sampler
    }
    
    func encode(commandBuffer: MTLCommandBuffer, sharedResources: inout SharedResources){
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: self.descriptor) else {
            fatalError("failed to create encoder")
        }
        encoder.label = "Color pass encoder"
        
        // Set common uniforms
        withUnsafeBytes(of: sharedResources.frameUniforms) { rawBuffer in
            encoder.setFragmentBytes(rawBuffer.baseAddress!,
                                           length: MemoryLayout<FrameUniforms>.stride,
                                     index: Bindings.frameUniforms)
            encoder.setVertexBytes(rawBuffer.baseAddress!,
                                           length: MemoryLayout<FrameUniforms>.stride,
                                     index: Bindings.frameUniforms)
        }
        
        encoder.setFragmentSamplerState(sharedResources.sampler, index: Bindings.sampler)
        
        encoder.setFragmentSamplerState(sharedResources.shadowSampler, index: Bindings.shadowSampler)
        
        encoder.pushDebugGroup("Draw Skybox")
        
        encoder.setDepthStencilState(sharedResources.depthStencilStateDisabled)
        
        encoder.setFragmentTexture(sharedResources.skyBoxTexture, index: 0)
        encoder.setFragmentSamplerState(sampler, index: Bindings.sampler)
                
        self.skyboxPipeline.bind(encoder: encoder)
        
        encoder.drawPrimitives(type: MTLPrimitiveType.triangle, vertexStart: 0, vertexCount: 3)
        
        encoder.popDebugGroup()
                
        encoder.pushDebugGroup("render meshes")
        
        encoder.setDepthStencilState(sharedResources.depthStencilStateEnabled)
        
        let pointLights = sharedResources.lightData.pointLights
                
        let lightBuffer = pointLights.withUnsafeBufferPointer { bufferPtr in
             return device.makeBuffer(bytes: bufferPtr.baseAddress!, length: MemoryLayout<PointLight>.stride * pointLights.count)
        }
        
        encoder.setFragmentBuffer(lightBuffer, offset: 0, index: Bindings.lightData)
        
        encoder.setFragmentTexture(sharedResources.lightData.pontLightShadowAtlas, index: Bindings.shadowAtas)
        
//        encoder.setFragmentBytes(&pointLightCount, length: MemoryLayout<UInt32>.stride, index: 1)
        
        self.blinnPhongPipeline.bind(encoder: encoder)
        
        for i in 0..<sharedResources.renderables.count {
            let renderable = sharedResources.renderables[i]
            renderable.draw(renderEncoder: encoder, instanceId: nil)
        }
        encoder.popDebugGroup()
        
        encoder.endEncoding()
    }
}

