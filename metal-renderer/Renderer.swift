//
//  Renderer.swift
//  metal-swift-new
//
//  Created by Jared Lueck on 2025-12-08.
//

// Our platform independent renderer class

import Metal
import MetalKit
import simd
import ImGui

struct FrameUniforms {
    var view: simd_float4x4 =  matrix_identity_float4x4
    var projection: simd_float4x4 =  matrix_identity_float4x4
    var inverseView: simd_float4x4 =  matrix_identity_float4x4
    var inverseProjection: simd_float4x4  = matrix_identity_float4x4
    var cameraPos: simd_float4 = SIMD4<Float>(0, -1, 5.1, 1)
    var viewportSize: simd_float2 = .init(1, 1)
}

public struct PointLight {
    var position: simd_float4
    var color: simd_float4
    var radius: simd_float1
}

var f: Float = 0.0
var clear_color: SIMD3<Float> = .init(x: 0.28, y: 0.36, z: 0.5)
var counter: Int = 0

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
    SIMD3<Float>(0,  0,  -1),
    SIMD3<Float>(0, -1,  0),
    SIMD3<Float>(0, -1,  0)
]

class Renderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let view: MTKView
    
    let assetManager: AssetManager
    let scene: Scene
    
    var sharedResources: SharedResources
    let shadowPass: ShadowPass
    let maskPass: MaskPass
    let colorPass: ColorPass
    let editor: Editor
    let library: MTLLibrary
    
    let colorPixelFormat: MTLPixelFormat
    let depthPixelFormat: MTLPixelFormat
    
    let shadowMap: MTLTexture
    
    lazy var forwardPassDescriptor: MTLRenderPassDescriptor = {
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].storeAction = .store
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.depthAttachment.storeAction = .store
        return descriptor
    }()

    lazy var shadowPassDescriptor: MTLRenderPassDescriptor = {
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].storeAction = .store
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
        return descriptor
    }()

    @MainActor
    init?(metalKitView: MTKView, scene: Scene, editor: Editor, assetManager: AssetManager) {
        metalKitView.framebufferOnly = false
        self.device = metalKitView.device!
        self.commandQueue = self.device.makeCommandQueue()!
        self.view = metalKitView

        metalKitView.colorPixelFormat = MTLPixelFormat.bgra8Unorm_srgb
        metalKitView.depthStencilPixelFormat = MTLPixelFormat.depth32Float

        let eye = SIMD3<Float>(0, 1, 5)
        let viewMatrix = matrix_lookAt(eye: eye, target: SIMD3<Float>(0, 0, 0), up: SIMD3<Float>(0, 1, 0))

        sharedResources = SharedResources( device: device, view: self.view)
        sharedResources.viewMatrix = viewMatrix
        sharedResources.cameraPos = SIMD4<Float>(eye, 1.0)
        
        let width = Int(view.drawableSize.width)
        let height = Int(view.drawableSize.height)

        self.scene = scene
        self.assetManager = assetManager
        
        colorPass = ColorPass(device: device)
        colorPass.setColorAttachment(colorTexture: sharedResources.colorBuffer)
        colorPass.setDepthAttachment(depthTexture: sharedResources.depthBuffer)
        maskPass = MaskPass(device: device)
        shadowPass = ShadowPass(device: device)
        self.editor = editor
        colorPixelFormat = view.colorPixelFormat
        depthPixelFormat = view.depthStencilPixelFormat
        
 
        self.assetManager.loadAssets()
        self.library = try! device.makeDefaultLibrary(bundle: Bundle.main)
        
        let shadowMapDesc = MTLTextureDescriptor()
        shadowMapDesc.textureType = .typeCubeArray
        shadowMapDesc.pixelFormat = .r32Float
        shadowMapDesc.width = width
        shadowMapDesc.height = height
        shadowMapDesc.arrayLength = 6
        shadowMapDesc.mipmapLevelCount = 1
        shadowMapDesc.sampleCount = 1
        shadowMapDesc.usage = [.renderTarget, .shaderRead]
        
        shadowMap = device.makeTexture(descriptor: shadowMapDesc)!
        super.init()
        
        _ = ImGuiCreateContext(nil)
        ImGuiStyleColorsDark(nil)
        ImGui_ImplMetal_Init(device)
    }
    
    func draw(in view: MTKView) {
        let expectedW = Int(view.drawableSize.width)
        let expectedH = Int(view.drawableSize.height)

        view.preferredFramesPerSecond = 30

        guard let drawable = view.currentDrawable else {
            return
        }
        let tex = drawable.texture

        if tex.width != expectedW || tex.height != expectedH {
            return
        }

        let data = self.scene.getSceneData()

        var renderables: [InstancedRenderable] = []
        var shadowCasterInstances: [InstancedRenderable] = []

        data.renderables.keys.forEach {
            let instances = self.scene.getSceneData().renderables[$0]!
            let instancedRenderable = InstancedRenderable(device: device, model: assetManager.assetMap[$0]!)
            let shadowCastingInstances = InstancedRenderable(device: device, model: assetManager.assetMap[$0]!)
            for instance in instances {
                instancedRenderable.addInstance(transform: instance.transform )
                if instance.castsShadows{
                    shadowCastingInstances.addInstance(transform: instance.transform)
                }
            }
            renderables.append(instancedRenderable)
            if shadowCastingInstances.instances.count > 0 {
                shadowCasterInstances.append(shadowCastingInstances)
            }
        }
        
        let commandBuffer = commandQueue.makeCommandBuffer()!
        forwardPassDescriptor.colorAttachments[0].texture = drawable.texture
        forwardPassDescriptor.depthAttachment.texture = view.depthStencilTexture
                        
        encodeShadowPass(into: commandBuffer)
        encodePass(into: commandBuffer, using: forwardPassDescriptor , label: "Forward Pass" ){ encoder in
            encodeForwardStage(using: encoder)
        }
        
        editor.encode(commandBuffer: commandBuffer)

        commandBuffer.present(view.currentDrawable!)
        commandBuffer.commit()
    }

    func encodePass(into: MTLCommandBuffer,
                    using: MTLRenderPassDescriptor,
                    label: String,
                    _ encodingBlock: (MTLRenderCommandEncoder) -> Void){
        guard let renderEncoder = into.makeRenderCommandEncoder(descriptor: using) else {
            fatalError("fatal error")
        }
        renderEncoder.label = label
        encodingBlock(renderEncoder)
        renderEncoder.endEncoding()
    }
    
    func encodeStage(using renderEncoder: MTLRenderCommandEncoder,
                     label: String,
                     _ encodingBlock: () -> Void){
        renderEncoder.pushDebugGroup(label)
        encodingBlock()
        renderEncoder.popDebugGroup()
    }
    
    func encodeShadowPass(into commandBuffer: MTLCommandBuffer){
        let data = self.scene.getSceneData()

        var shadowCastingRenderables: [InstancedRenderable] = []

        data.renderables.keys.forEach {
            let instances = self.scene.getSceneData().renderables[$0]!
            let shadowCastingInstances = InstancedRenderable(device: device, model: assetManager.assetMap[$0]!)
            for instance in instances {
                if instance.castsShadows{
                    shadowCastingInstances.addInstance(transform: instance.transform)
                }
            }
            if shadowCastingInstances.instances.count > 0 {
                shadowCastingRenderables.append(shadowCastingInstances)
            }
        }
        let pointLights = data.pointLights
        for i in 0..<pointLights.count {
            let light = pointLights[i]
            for face in 0..<6{
                let slice = i * 6 + face
                let faceTexture = shadowMap.makeTextureView(
                    pixelFormat: .r32Float, textureType: MTLTextureType.type2D, levels: 0..<1, slices: slice..<(slice+1))
                shadowPassDescriptor.colorAttachments[0].texture = faceTexture
                encodePass(into: commandBuffer, using: shadowPassDescriptor, label: "shadow pass"){ renderEncoder in
                    encodeStage(using: renderEncoder, label: "shadow pass stage"){
                        renderEncoder.setRenderPipelineState(pointLightShadow)
                        let eyePos = SIMD3<Float>(light.position.x, light.position.y, light.position.z)
                        let forward = faceDirections[face]
                        let up = faceUps[face]
                        let view = matrix_lookAt(eye: eyePos, target: eyePos + forward, up: up)
                        let projection = matrix_perspective_right_hand(fovyRadians: radians_from_degrees(90), aspectRatio: 1, nearZ: 1, farZ: light.radius)
                        var uniforms = ShadowUniforms(view: view, projection: projection, position: light.position, radius: light.radius)
                        withUnsafeBytes(of: &uniforms){
                            rawBuffer in
                            renderEncoder.setVertexBytes(rawBuffer.baseAddress!, length: MemoryLayout<ShadowUniforms>.stride, index: Int(BufferIndexPipeline.rawValue))
                            renderEncoder.setFragmentBytes(rawBuffer.baseAddress!, length: MemoryLayout<ShadowUniforms>.stride, index: Int(BufferIndexPipeline.rawValue))
                        }
                        
                        renderEncoder.setCullMode(MTLCullMode.front)
                        
                        for i in 0..<shadowCastingRenderables.count {
                            let renderable = shadowCastingRenderables[i]
                            renderable.draw(renderEncoder: renderEncoder, instanceId: nil)
                        }
                    }
                }
            }
        }
    }

    func encodeForwardStage(using renderEncoder: MTLRenderCommandEncoder){
        encodeStage(using: renderEncoder, label: "forward stage"){
            renderEncoder.setRenderPipelineState(forwardBlinnPhong)
            
            let frameData = editor.getFrameData()
            let sceneData = scene.getSceneData()
            let lights = sceneData.pointLights
            let sceneRenderables = sceneData.renderables

            // Set common uniforms
            withUnsafeBytes(of: frameData) { rawBuffer in
                renderEncoder.setFragmentBytes(rawBuffer.baseAddress!,
                                               length: MemoryLayout<FrameData>.stride,
                                         index: Int(BufferIndexFrameData.rawValue))
                renderEncoder.setVertexBytes(rawBuffer.baseAddress!,
                                               length: MemoryLayout<FrameData>.stride,
                                       index: Int(BufferIndexFrameData.rawValue))
            }
            
            renderEncoder.setFragmentSamplerState(sharedResources.sampler, index: Int(SamplerIndexDefault.rawValue))
            renderEncoder.setFragmentSamplerState(sharedResources.shadowSampler, index: Int(SamplerIndexCube.rawValue))
                    
            renderEncoder.pushDebugGroup("render meshes")
            renderEncoder.setDepthStencilState(sharedResources.depthStencilStateEnabled)
            
            let lightBuffer = lights.withUnsafeBufferPointer { bufferPtr in
                 return device.makeBuffer(bytes: bufferPtr.baseAddress!, length: MemoryLayout<PointLight>.stride * max(lights.count, 1))
            }
            
            renderEncoder.setFragmentBuffer(lightBuffer, offset: 0, index: Int(BufferIndexLightData.rawValue))
            
            var lightCount = lights.count
            renderEncoder.setFragmentBytes(&lightCount, length: MemoryLayout<UInt>.self.stride, index: Int(BufferIndexPointLightCount.rawValue))
                        
            renderEncoder.setFragmentBuffer(lightBuffer, offset: 0, index: Int(BufferIndexLightData.rawValue))
            renderEncoder.setFragmentTexture(shadowMap, index: Int(TextureIndexShadow.rawValue))
            
            sceneRenderables.keys.forEach {
                let instances = sceneRenderables[$0]!
                let instancedRenderable = InstancedRenderable(device: device, model: assetManager.assetMap[$0]!)
                for instance in instances {
                    instancedRenderable.addInstance(transform: instance.transform )
                }
                instancedRenderable.draw(renderEncoder: renderEncoder, instanceId: nil)
            }
        }
    }
    
    func makeRenderPipelineState(label: String,
                                 block: (MTLRenderPipelineDescriptor) -> Void) -> MTLRenderPipelineState {
        let descriptor = MTLRenderPipelineDescriptor()
        block(descriptor)
        descriptor.label = label
        do {
            return try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            fatalError(error.localizedDescription)
        }
    }

    lazy var forwardBlinnPhong = makeRenderPipelineState(label: "forward blinn phong") { descriptor in
        descriptor.vertexFunction = library.makeFunction(name: "phongVertex")!
        descriptor.fragmentFunction = library.makeFunction(name: "phongFragment")!
        descriptor.vertexDescriptor = VertexDescriptors.mtl()
        descriptor.colorAttachments[0].pixelFormat = colorPixelFormat
        descriptor.depthAttachmentPixelFormat = depthPixelFormat
    }
    
    lazy var pointLightShadow = makeRenderPipelineState(label: "point light shadow") { descriptor in
        descriptor.vertexFunction = library.makeFunction(name: "cubeShadowMapVertex")!
        descriptor.fragmentFunction = library.makeFunction(name: "cubeShadowMapFragment")!
        descriptor.vertexDescriptor = VertexDescriptors.mtl()
        
        descriptor.colorAttachments[0].pixelFormat = .r32Float
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        let aspect = Float(size.width) / Float(size.height)
        
        let width = Int(size.width)
        let height = Int(size.height)
        self.sharedResources.projectionMatrix = matrix_perspective_right_hand(fovyRadians: radians_from_degrees(65), aspectRatio:aspect, nearZ: 0.01, farZ: 100.0)
        self.editor.updateTextures(size: size)
        self.editor.editorCamera.updateProjection(drawableSize: size)
        editor.editorCamera.viewportSize = SIMD2<Float>(Float(width), Float(height))
        
        sharedResources.depthTextureDescriptor.height = height
        sharedResources.depthTextureDescriptor.width = width
        sharedResources.depthBuffer = device.makeTexture(descriptor: sharedResources.depthTextureDescriptor)!
                
        sharedResources.maskTextureDescriptor.height = height
        sharedResources.maskTextureDescriptor.width = width
        device.makeTexture(descriptor: sharedResources.maskTextureDescriptor)
        sharedResources.outlineMask = device.makeTexture(descriptor: sharedResources.maskTextureDescriptor)
        
        sharedResources.colorTextureDescriptor.height = height
        sharedResources.colorTextureDescriptor.width = width
        sharedResources.colorBuffer = device.makeTexture(descriptor: sharedResources.colorTextureDescriptor)!
    }
}
