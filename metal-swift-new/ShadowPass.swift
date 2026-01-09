//
//  CubeShadowRenderPass.swift
//  metal-swift-new
//
//  Created by Jared Lueck on 2025-12-29.
//

import Metal
import simd

struct ShadowUniforms {
    var view: simd_float4x4
    var projection: simd_float4x4
    var position: simd_float4
    var radius: simd_float1
}

let faceDirections: [SIMD3<Float>] = [
    SIMD3<Float>( 1,  0,  0),
    SIMD3<Float>(-1,  0,  0),
    SIMD3<Float>( 0,  1,  0),
    SIMD3<Float>( 0, -1,  0),
    SIMD3<Float>( 0,  0,  1),
    SIMD3<Float>( 0,  0, -1)
]

let faceUps: [SIMD3<Float>] = [
    SIMD3<Float>(0, -1,  0),
    SIMD3<Float>(0, -1,  0),
    SIMD3<Float>(0,  0,  1),
    SIMD3<Float>(0,  0,  1),
    SIMD3<Float>(0, -1,  0),
    SIMD3<Float>(0, -1,  0)
]

class ShadowPass {
    let descriptor: MTLRenderPassDescriptor;
    
    let cubeShadowMapShaders: ShaderProgram
    let pipeline: RenderPipeline
    init(device: MTLDevice){
        self.descriptor = MTLRenderPassDescriptor()
        self.descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
        self.descriptor.colorAttachments[0].loadAction = .clear
        self.descriptor.colorAttachments[0].storeAction = .store
                
        try! self.cubeShadowMapShaders = ShaderProgram(device: device, descriptor: ShaderProgramDescriptor(vertexName: "cubeShadowMapVertex", fragmentName: "cubeShadowMapFragment"))

        self.pipeline = RenderPipeline(device: device, program: self.cubeShadowMapShaders, colorAttachmentPixelFormat: .r32Float, depthAttachmentPixelFormat: MTLPixelFormat.invalid)
    }
    
    func encode(commandBuffer: MTLCommandBuffer, sharedResources: inout SharedResources){
        let pointLights = sharedResources.pointLights
        let cubeTextureArray = sharedResources.pointLightShadowAtlas
        for i in 0..<pointLights.count {
            let light = pointLights[i]
            for face in 0..<6{
                let slice = i * 6 + face
                let faceTexture = cubeTextureArray.makeTextureView(
                    pixelFormat: .r32Float, textureType: MTLTextureType.type2D, levels: 0..<1, slices: slice..<(slice+1))
                self.descriptor.colorAttachments[0].texture = faceTexture
                guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: self.descriptor) else {
                    fatalError("failed to create encoder")
                }
                let eyePos = SIMD3<Float>(light.position.x, light.position.y, light.position.z)
                let forward = faceDirections[face]
                let up = faceUps[face]
                let view = matrix_lookAt(eye: eyePos, target: eyePos + forward, up: up)
                let projection = matrix_perspective_right_hand(fovyRadians: radians_from_degrees(90), aspectRatio: 1, nearZ: 1, farZ: light.radius)
                var uniforms = ShadowUniforms(view: view, projection: projection, position: light.position, radius: light.radius)
                withUnsafeBytes(of: &uniforms){
                    rawBuffer in
                    encoder.setVertexBytes(rawBuffer.baseAddress!, length: MemoryLayout<ShadowUniforms>.stride, index: Bindings.pipelineUniforms)
                    encoder.setFragmentBytes(rawBuffer.baseAddress!, length: MemoryLayout<ShadowUniforms>.stride, index: Bindings.pipelineUniforms)
                }

                pipeline.bind(encoder: encoder)
                
                for i in 0..<sharedResources.renderables.count {
                    let renderable = sharedResources.renderables[i]
                    if renderable.castsShadows {
                        renderable.draw(renderEncoder: encoder, instanceId: nil)
                    }
                }
                encoder.endEncoding()
            }
        }
    }
}

