//
//  ColorPass.swift
//  metal-swift-new
//
//  Created by Jared Lueck on 2025-12-29.
//

import Metal
import simd

class ColorPass {
    let descriptor: MTLRenderPassDescriptor;
    let skyboxPipeline: SkyboxPipeline
    let blinnPhongPipeline: BlinnPhongPipeline
    let device: MTLDevice
    
    init(device: MTLDevice, mtkDescriptor: MTLRenderPassDescriptor){
        self.descriptor = mtkDescriptor
        self.skyboxPipeline = SkyboxPipeline(device: device)
        self.blinnPhongPipeline = BlinnPhongPipeline(device: device)
        self.device = device
    }
    
    func encode(commandBuffer: MTLCommandBuffer, sharedResources: SharedResources){
        descriptor.depthAttachment.texture = sharedResources.depthBuffer
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: self.descriptor) else {
            fatalError("failed to create encoder")
        }
        encoder.label = "Color pass encoder"
        
        encoder.pushDebugGroup("Draw Skybox")
        
        let uniforms = Uniforms(
            view: sharedResources.viewMatrix,
            projection: sharedResources.projectionMatrix,
            inverseView: simd_inverse(sharedResources.viewMatrix),
            inverseProjection: simd_inverse(sharedResources.projectionMatrix)
        )
        
        let skyboxPipeline = SkyboxPipeline(device: self.device)
        skyboxPipeline.bind(renderCommandEncoder: encoder)
        
        withUnsafeBytes(of: uniforms) { rawBuffer in
            encoder.setFragmentBytes(rawBuffer.baseAddress!,
                                           length: MemoryLayout<Uniforms>.stride,
                                           index: 0)
        }
        
        let skybox = Skybox(device: self.device)
        skybox.bind(renderCommandEncoder: encoder)
        
        encoder.drawPrimitives(type: MTLPrimitiveType.triangle, vertexStart: 0, vertexCount: 3)
        
        encoder.popDebugGroup()
        
        
        let gridPipeline = GridPipeline(device: self.device)
        
        let gridUniforms = GridUniforms(view: sharedResources.viewMatrix, projection: sharedResources.projectionMatrix, gridColor: SIMD4<Float>(1.0,1.0,1.0,1.0), cameraPos: SIMD4<Float>(sharedResources.cameraPos, 1.0))
        gridPipeline.bind(encoder: encoder, uniforms: gridUniforms)
        
        encoder.drawPrimitives(type: MTLPrimitiveType.triangle, vertexStart: 0, vertexCount: 6)
        
        encoder.pushDebugGroup("render meshes")
        
        let blinnPhongUniforms = BlinnPhongUniforms(view: sharedResources.viewMatrix, projection: sharedResources.projectionMatrix)
        
        let phongPipeline = BlinnPhongPipeline(device: self.device)
        phongPipeline.bind(renderCommandEncoder: encoder, uniforms: blinnPhongUniforms, pointLights: sharedResources.pointLights, shadowMapAtlas: sharedResources.pointLightShadowAtlas!)
        
        for i in 0..<sharedResources.renderables.count {
            let renderable = sharedResources.renderables[i]
            renderable.draw(renderEncoder: encoder, instanceId: nil)
        }
        encoder.popDebugGroup()
        
        encoder.endEncoding()
    }
}
