//
//  Renderer.swift
//  metal-swift-new
//
//  Created by Jared Lueck on 2025-12-08.
//

// Our platform independent renderer class

import Metal
import MetalKit
import MetalPerformanceShaders
import simd
import ImGui

struct ShadowUniforms {
    var view: simd_float4x4
    var projection: simd_float4x4
    var position: simd_float4
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
    SIMD3<Float>(0, 1,  0),
    SIMD3<Float>(0, 1,  0),
    SIMD3<Float>(0,  0,  -1),
    SIMD3<Float>(0,  0,   1),
    SIMD3<Float>(0, 1,  0),
    SIMD3<Float>(0, 1,  0)
]

class Renderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let view: MTKView
    
    let assetManager: AssetManager
    let scene: Scene
    
    let editor: Editor
    let library: MTLLibrary
    
    let colorPixelFormat: MTLPixelFormat
    let depthPixelFormat: MTLPixelFormat
    
    let sampler: MTLSamplerState
    let shadowMap: MTLTexture
    let skyboxTexture: MTLTexture
    let envMapTexture: MTLTexture
    let envBRDFLUT: MTLTexture
    var depthStencilStates: DepthStencilStates
    
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
        
        let width = Int(view.drawableSize.width)
        let height = Int(view.drawableSize.height)

        self.scene = scene
        self.assetManager = assetManager
        self.assetManager.loadAssets()
        
        self.editor = editor
        colorPixelFormat = view.colorPixelFormat
        depthPixelFormat = view.depthStencilPixelFormat
        
        self.library = try! device.makeDefaultLibrary(bundle: Bundle.main)
        
        let shadowMapDesc = MTLTextureDescriptor()
        shadowMapDesc.textureType = .typeCubeArray
        shadowMapDesc.pixelFormat = .r32Float
        shadowMapDesc.width = width
        shadowMapDesc.height = height
        shadowMapDesc.arrayLength = 6
        shadowMapDesc.mipmapLevelCount = 8
        shadowMapDesc.sampleCount = 1
        shadowMapDesc.usage = [.renderTarget, .shaderRead]
        
        shadowMap = device.makeTexture(descriptor: shadowMapDesc)!
        self.depthStencilStates = DepthStencilStates(device: device)
        
        let textureLoader = MTKTextureLoader(device: device)
        let skyboxTextureUrl = Bundle.main.url(forResource: "space", withExtension: "png")!
        self.skyboxTexture = try! textureLoader.newTexture(URL: skyboxTextureUrl, options: [
              MTKTextureLoader.Option.cubeLayout: MTKTextureLoader.CubeLayout.vertical,
              MTKTextureLoader.Option.SRGB: true
        ])
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.mipFilter = .linear  // Linear is fine now since we're using texture arrays
        self.sampler = device.makeSamplerState(descriptor: samplerDescriptor)!
        
        // Initialize environment map synchronously
        self.envMapTexture = try! Self.initEnvironmentMapSync(device: device, commandQueue: commandQueue, baseName: "space")
        let lutURL = Bundle.main.url(forResource: "brdf_lut", withExtension: "png")!
        self.envBRDFLUT = try! textureLoader.newTexture(URL: lutURL)
        super.init()
    }
    
    
    static func initEnvironmentMapSync(device: MTLDevice, commandQueue: MTLCommandQueue, baseName: String) throws -> MTLTexture {
        let textureLoader = MTKTextureLoader(device: device)

        // Discover roughness level files: <baseName>_1.png, <baseName>_2.png, ...
        var urls: [URL] = []
        var level = 1
        while let url = Bundle.main.url(forResource: "\(baseName)_\(level)", withExtension: "png") {
            urls.append(url)
            level += 1
        }

        guard !urls.isEmpty else {
            throw NSError(domain: "RendererError", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "No environment map textures found for '\(baseName)'"])
        }

        // Load all roughness level textures
        var textures: [MTLTexture] = []
        for url in urls {
            let texture = try textureLoader.newTexture(URL: url, options: [
                .cubeLayout: MTKTextureLoader.CubeLayout.vertical,
                .SRGB: false,
                .textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue)
            ])
            textures.append(texture)
        }

        let baseTexture = textures[0]
        
        // Create a cube texture array where each array slice represents a different roughness level
        let envMapDescriptor = MTLTextureDescriptor()
        envMapDescriptor.textureType = .typeCubeArray
        envMapDescriptor.pixelFormat = baseTexture.pixelFormat
        envMapDescriptor.width = baseTexture.width
        envMapDescriptor.height = baseTexture.height
        envMapDescriptor.arrayLength = textures.count  // One array slice per roughness level
        envMapDescriptor.usage = [.shaderRead]
        envMapDescriptor.storageMode = .private
        
        guard let envMapTexture = device.makeTexture(descriptor: envMapDescriptor) else {
            throw NSError(domain: "RendererError", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to create environment map texture array"])
        }
        
        let commandBuffer = commandQueue.makeCommandBuffer()!
        let blitEncoder = commandBuffer.makeBlitCommandEncoder()!
        
        // Copy each source texture into its corresponding array slice
        for (arrayIndex, sourceTexture) in textures.enumerated() {
            // Each source texture has 6 faces (cube map)
            for face in 0..<6 {
                // Calculate the destination slice: arrayIndex * 6 + face
                let destSlice = arrayIndex * 6 + face
                
                blitEncoder.copy(
                    from: sourceTexture,
                    sourceSlice: face,
                    sourceLevel: 0,
                    sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                    sourceSize: MTLSize(width: sourceTexture.width, height: sourceTexture.height, depth: 1),
                    to: envMapTexture,
                    destinationSlice: destSlice,
                    destinationLevel: 0,
                    destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
                )
            }
        }
        
        blitEncoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        return envMapTexture
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
        let data = self.scene.getRenderSceneData()

        let shadowCastingInstances = data.shadowCasters
        var shadowCastingRenderables: [InstancedRenderable] = []

        shadowCastingInstances.keys.forEach {
            let instances = self.scene.getRenderSceneData().shadowCasters[$0]!
            let renderable = InstancedRenderable(device: device, model: assetManager.assetMap[$0]!, instances: instances)
            shadowCastingRenderables.append(renderable)
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
                        let projection = matrix_perspective_right_hand(fovyRadians: radians_from_degrees(90), aspectRatio: 1, nearZ: 0.01, farZ: light.radius)
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
        var debugData = editor.getDebugValues()
        let frameData = editor.getFrameData()
        withUnsafeBytes(of: &debugData){ rawBuffer in
            renderEncoder.setFragmentBytes(rawBuffer.baseAddress!,
                                           length: MemoryLayout<DebugData>.stride,
                                           index: Int(BufferIndexDebug.rawValue))
        }
        withUnsafeBytes(of: frameData) { rawBuffer in
            renderEncoder.setFragmentBytes(rawBuffer.baseAddress!,
                                           length: MemoryLayout<FrameData>.stride,
                                     index: Int(BufferIndexFrameData.rawValue))
            renderEncoder.setVertexBytes(rawBuffer.baseAddress!,
                                           length: MemoryLayout<FrameData>.stride,
                                   index: Int(BufferIndexFrameData.rawValue))
        }
        
        renderEncoder.setFragmentTexture(envMapTexture, index: Int(TextureIndexEnvironmentMap.rawValue))
        renderEncoder.setFragmentTexture(envBRDFLUT, index: Int(TextureIndexLUT.rawValue))
        renderEncoder.setFragmentSamplerState(sampler, index: Int(SamplerIndexCube.rawValue))
        
                
        encodeStage(using: renderEncoder, label: "skybox"){
            
            renderEncoder.setRenderPipelineState(skybox)
            renderEncoder.setDepthStencilState(depthStencilStates.skybox)
            renderEncoder.setFragmentTexture(skyboxTexture, index: Int(TextureIndexSkybox.rawValue))
            renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        }
        encodeStage(using: renderEncoder, label: "pbr"){
            renderEncoder.setRenderPipelineState(forwardPbr)
            
            
            let sceneData = scene.getRenderSceneData()
            let lights = sceneData.pointLights
            let sceneRenderables = sceneData.renderables[.pbr]!

            // Set common uniforms
            withUnsafeBytes(of: frameData) { rawBuffer in
                renderEncoder.setFragmentBytes(rawBuffer.baseAddress!,
                                               length: MemoryLayout<FrameData>.stride,
                                         index: Int(BufferIndexFrameData.rawValue))
                renderEncoder.setVertexBytes(rawBuffer.baseAddress!,
                                               length: MemoryLayout<FrameData>.stride,
                                       index: Int(BufferIndexFrameData.rawValue))
            }
                    
            renderEncoder.pushDebugGroup("render meshes")
            renderEncoder.setDepthStencilState(depthStencilStates.forwardPass)
            
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
                    let i = Instance(transform: instance.transform, material: instance.material)
                    instancedRenderable.addInstance(instance: i)
                }
                instancedRenderable.draw(renderEncoder: renderEncoder, instanceId: nil)
            }
        }
        encodeStage(using: renderEncoder, label: "blinnphong"){
            renderEncoder.setRenderPipelineState(forwardBlinnPhong)
            
            let frameData = editor.getFrameData()
            let sceneData = scene.getRenderSceneData()
            let lights = sceneData.pointLights
            let sceneRenderables = sceneData.renderables[.blinnPhong]!

            // Set common uniforms
            withUnsafeBytes(of: frameData) { rawBuffer in
                renderEncoder.setFragmentBytes(rawBuffer.baseAddress!,
                                               length: MemoryLayout<FrameData>.stride,
                                         index: Int(BufferIndexFrameData.rawValue))
                renderEncoder.setVertexBytes(rawBuffer.baseAddress!,
                                               length: MemoryLayout<FrameData>.stride,
                                       index: Int(BufferIndexFrameData.rawValue))
            }
                    
            renderEncoder.pushDebugGroup("render meshes")
            renderEncoder.setDepthStencilState(depthStencilStates.forwardPass)
            
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
                    let i = Instance(transform: instance.transform, material: instance.material)
                    instancedRenderable.addInstance(instance: i)
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
    
    lazy var skybox = makeRenderPipelineState(label: "skybox") { descriptor in
        descriptor.vertexFunction = library.makeFunction(name: "full_screen_triangle_vertex")!
        descriptor.fragmentFunction = library.makeFunction(name: "skyboxFragment")!
        descriptor.vertexDescriptor = nil
        descriptor.colorAttachments[0].pixelFormat = colorPixelFormat
        descriptor.depthAttachmentPixelFormat = depthPixelFormat
    }

    lazy var forwardBlinnPhong = makeRenderPipelineState(label: "forward blinn phong") { descriptor in
        descriptor.vertexFunction = library.makeFunction(name: "phongVertex")!
        descriptor.fragmentFunction = library.makeFunction(name: "phongFragment")!
        descriptor.vertexDescriptor = VertexDescriptors.mtl()
        descriptor.colorAttachments[0].pixelFormat = colorPixelFormat
        descriptor.depthAttachmentPixelFormat = depthPixelFormat
    }
    
    lazy var forwardPbr = makeRenderPipelineState(label: "forward pbr") { descriptor in
        descriptor.vertexFunction = library.makeFunction(name: "phongVertex")!
        descriptor.fragmentFunction = library.makeFunction(name: "pbrFragment")!
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
        let width = Int(size.width)
        let height = Int(size.height)
        self.editor.updateTextures(size: size)
        self.editor.editorCamera.updateProjection(drawableSize: size)
        editor.editorCamera.viewportSize = SIMD2<Float>(Float(width), Float(height))
    }
}
