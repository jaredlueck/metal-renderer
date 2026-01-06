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
    var cameraPos: simd_float4 = SIMD4<Float>(0, 2, 5, 1)
}

struct PointLight {
    var position: simd_float4
    var color: simd_float4
    var radius: simd_float1
}

struct LightData {
    var pointLights: [PointLight] = []
    var pontLightShadowAtlas: MTLTexture
    var lightCount: Int = 0
}

struct SharedResources {
    var lightData: LightData
    var frameUniforms: FrameUniforms
    var outlineMask: MTLTexture?
    var renderables: [InstancedRenderable] = []
    var selectedRenderableInstance: Instance? = nil
    var colorBuffer: MTLTexture
    var depthBuffer: MTLTexture
    var skyBoxTexture: MTLTexture
    var depthStencilStateDisabled: MTLDepthStencilState
    var depthStencilStateEnabled: MTLDepthStencilState
    var sampler: MTLSamplerState
    var shadowSampler: MTLSamplerState
    var view: MTKView
}

var f: Float = 0.0
var clear_color: SIMD3<Float> = .init(x: 0.28, y: 0.36, z: 0.5)
var counter: Int = 0

class Renderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    
    let view: MTKView
    
    var sharedResources: SharedResources
    
    let depthTextureDescriptor: MTLTextureDescriptor
    let colorTextureDescriptor: MTLTextureDescriptor
    let maskTextureDescriptor: MTLTextureDescriptor
    
    @MainActor
    init?(metalKitView: MTKView) {
        metalKitView.framebufferOnly = false
        self.device = metalKitView.device!
        self.commandQueue = self.device.makeCommandQueue()!
        self.view = metalKitView
        
        let size = view.drawableSize   // CGSize in pixels
        let width = Int(size.width)
        let height = Int(size.height)
        
        metalKitView.colorPixelFormat = MTLPixelFormat.bgra8Unorm_srgb
        
        let textureLoader = MTKTextureLoader(device: device)
        
        guard let url = Bundle.main.url(forResource: "vertical" , withExtension: "png") else {
            fatalError("Couldn't find skybox texture")
        }
        let skyboxTexture = try! textureLoader.newTexture(URL: url, options: [.cubeLayout: MTKTextureLoader.CubeLayout.vertical])
        
        self.depthTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float,
                                                            width: width,
                                                            height: height,
                                                            mipmapped: false)
        self.depthTextureDescriptor.storageMode = .private
        self.depthTextureDescriptor.usage = [.renderTarget]
        self.depthTextureDescriptor.textureType = .type2D
        let depthTexture = device.makeTexture(descriptor: self.depthTextureDescriptor)!
        
        let depthAttachmentDescriptor = MTLRenderPassDepthAttachmentDescriptor()
        depthAttachmentDescriptor.texture = depthTexture
        
        let sphereModel = Model(device: self.device, resourceName: "sphere")
        let sphereRenderable = InstancedRenderable(device: device, model: sphereModel)
        sphereRenderable.addInstance(transform: matrix4x4_translation(-4, 1, 0))
        sphereRenderable.addInstance(transform: matrix4x4_translation(4, 1, 0))
        sphereRenderable.addInstance(transform: matrix4x4_translation(0, 1, -4))
        
        let planeModel = Model(device: self.device, resourceName: "plane")
        let planeRenderable = InstancedRenderable(device: device, model: planeModel)
        planeRenderable.addInstance(transform: matrix4x4_scale(scaleX: 100, scaleY: 100, scaleZ: 100))
        planeRenderable.castsShadows = false
        planeRenderable.selectable = false
        
        let shadowAtlasDesc = MTLTextureDescriptor()
        shadowAtlasDesc.textureType = .typeCubeArray
        shadowAtlasDesc.pixelFormat = .r32Float
        shadowAtlasDesc.width = width
        shadowAtlasDesc.height = height
        shadowAtlasDesc.arrayLength = 6
        shadowAtlasDesc.mipmapLevelCount = 1
        shadowAtlasDesc.sampleCount = 1
        shadowAtlasDesc.usage = [.renderTarget, .shaderRead]
        
        let shadowAtlas = device.makeTexture(descriptor: shadowAtlasDesc)!
        
        self.colorTextureDescriptor = MTLTextureDescriptor()
        self.colorTextureDescriptor.textureType = .type2D
        self.colorTextureDescriptor.pixelFormat = view.colorPixelFormat
        self.colorTextureDescriptor.width = width
        self.colorTextureDescriptor.height = height
        self.colorTextureDescriptor.mipmapLevelCount = 1
        self.colorTextureDescriptor.usage = [.renderTarget, .shaderRead]
        
        let colorBuffer = device.makeTexture(descriptor: self.colorTextureDescriptor)!
        
        self.maskTextureDescriptor = MTLTextureDescriptor()
        self.maskTextureDescriptor.textureType = .type2D
        self.maskTextureDescriptor.pixelFormat = .r32Float
        self.maskTextureDescriptor.height = height
        self.maskTextureDescriptor.width = width
        self.maskTextureDescriptor.usage = [.renderTarget, .shaderRead]
        
        let outlineMask = device.makeTexture(descriptor: self.maskTextureDescriptor)
        
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.mipFilter = .linear
        guard let sampler = device.makeSamplerState(descriptor: samplerDescriptor) else {
            fatalError("Failed to create sampler state")
        }
        
        let shadowSamplerDesc = MTLSamplerDescriptor()
        shadowSamplerDesc.minFilter = .linear
        shadowSamplerDesc.magFilter = .linear
        shadowSamplerDesc.mipFilter = .notMipmapped // depth maps often no mipmaps
        shadowSamplerDesc.sAddressMode = .clampToEdge
        shadowSamplerDesc.tAddressMode = .clampToEdge
        shadowSamplerDesc.rAddressMode = .clampToEdge
        shadowSamplerDesc.normalizedCoordinates = true

        guard let shadowSampler = device.makeSamplerState(descriptor: shadowSamplerDesc) else {
            fatalError("Failed to create shadow comparison sampler")
        }
        
        let depthStencilStateDesabledDesc = MTLDepthStencilDescriptor()
        depthStencilStateDesabledDesc.isDepthWriteEnabled = false
        depthStencilStateDesabledDesc.depthCompareFunction = .always
        
        guard let depthStencilStateDisabled = device.makeDepthStencilState(descriptor: depthStencilStateDesabledDesc) else {
            fatalError("Failed to create depth stencil state")
        }
        
        let depthStencilStateEnabledDesc = MTLDepthStencilDescriptor()
        depthStencilStateEnabledDesc.isDepthWriteEnabled = true
        depthStencilStateEnabledDesc.depthCompareFunction = .lessEqual
        
        
        guard let depthStencilStateEnabled = device.makeDepthStencilState(descriptor: depthStencilStateEnabledDesc) else {
            fatalError("Failed to create depth stencil state")
        }
        
        let pointLight = PointLight(position: SIMD4<Float>(0, 1, 0, 0), color: SIMD4<Float>(1, 1, 1, 1),
                                    radius: 10)
        let lightData = LightData(pointLights: [pointLight], pontLightShadowAtlas: shadowAtlas, lightCount: 1)
        
        sharedResources = SharedResources( lightData: lightData, frameUniforms: FrameUniforms(), outlineMask: outlineMask, renderables: [sphereRenderable, planeRenderable], colorBuffer: colorBuffer, depthBuffer: depthTexture,  skyBoxTexture: skyboxTexture, depthStencilStateDisabled: depthStencilStateDisabled, depthStencilStateEnabled: depthStencilStateEnabled, sampler: sampler, shadowSampler: shadowSampler, view: self.view)
        sharedResources.selectedRenderableInstance = sphereRenderable.instances[0]
        
        super.init()
        
        _ = ImGuiCreateContext(nil)
        ImGuiStyleColorsDark(nil)
        ImGui_ImplMetal_Init(device)
    }
    
    private func updateGameState() {
        let cameraPos = self.sharedResources.frameUniforms.cameraPos
        let eye = SIMD3<Float>(cameraPos.x, cameraPos.y, cameraPos.z)
        self.sharedResources.frameUniforms.view = matrix_lookAt(eye: eye, target: SIMD3<Float>(0, 0, 0), up: SIMD3<Float>(0, 1, 0))
    }
    
    func draw(in view: MTKView) {
        // Convert drawableSize (CGSize) to Ints for comparison
        let expectedW = Int(view.drawableSize.width)
        let expectedH = Int(view.drawableSize.height)

        guard let drawable = view.currentDrawable else {
            return // No drawable this frame
        }
        let tex = drawable.texture

        if tex.width != expectedW || tex.height != expectedH {
            return
        }

        var show_demo_window: Bool = false
        let io = ImGuiGetIO()!

        io.pointee.DisplaySize.x = Float(view.bounds.size.width)
        io.pointee.DisplaySize.y = Float(view.bounds.size.height)

        let frameBufferScale = Float(view.window?.screen?.backingScaleFactor ?? NSScreen.main!.backingScaleFactor)

        io.pointee.DisplayFramebufferScale = ImVec2(x: frameBufferScale, y: frameBufferScale)
        io.pointee.DeltaTime = 1.0 / Float(view.preferredFramesPerSecond)

        let commandBuffer = commandQueue.makeCommandBuffer()!
        
        self.updateGameState()
        
        guard let mtkDescriptor = view.currentRenderPassDescriptor else {
            fatalError()
        }
        
        // create shadow atlas for point lights
        let shadowPass = ShadowPass(device: device, colorTexture: sharedResources.lightData.pontLightShadowAtlas)
        shadowPass.encode(commandBuffer: commandBuffer, sharedResources: &sharedResources)
        
        // render meshes
        let colorPass = ColorPassx(device: device, depthTexture: sharedResources.depthBuffer, colorTexture: sharedResources.colorBuffer)
        colorPass.encode(commandBuffer: commandBuffer, sharedResources: &sharedResources)
        
        // Render Editor layers
        let maskPass = MaskPass(device: device)
        maskPass.encode(commandBuffer: commandBuffer, sharedResources: &sharedResources)
                
        let outlinePass = OutlinePass(device: device, colorTexture: sharedResources.colorBuffer, depthTexture: sharedResources.depthBuffer)
        outlinePass.encode(commandBuffer: commandBuffer, sharedResources: &sharedResources)
        
        mtkDescriptor.colorAttachments[0].texture = sharedResources.colorBuffer
        mtkDescriptor.colorAttachments[0].loadAction = .load
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor:  mtkDescriptor) else {
            fatalError("Failed to create render command encoder")
        }

                
        ImGui_ImplMetal_NewFrame(mtkDescriptor)
        ImGui_ImplOSX_NewFrame(view)
        ImGuiNewFrame()
//        ImGuiShowDemoWindow(&show_demo_window)
        // Create a window called "Hello, world!" and append into it.
        ImGuiBegin("Begin", &show_demo_window, 0)

        // Display some text (you can use a format strings too)
        ImGuiTextV("This is some useful text.")

        // Edit bools storing our window open/close state
        ImGuiSliderFloat("Float Slider", &f, 0.0, 1.0, nil, 1) // Edit 1 float using a slider from 0.0f to 1.0f

        ImGuiColorEdit3("clear color", &clear_color, 0) // Edit 3 floats representing a color

        if ImGuiButton("Button", ImVec2(x: 100, y: 20)) { // Buttons return true when clicked (most widgets return true when edited/activated)
            counter += 1
        }

        // SameLine(offset_from_start_x: 0, spacing: 0)

        ImGuiSameLine(0, 2)
        ImGuiTextV(String(format: "counter = %d", counter))

        let avg: Float = (1000.0 / io.pointee.Framerate)
        let fps = io.pointee.Framerate

        ImGuiTextV(String(format: "Application average %.3f ms/frame (%.1f FPS)", avg, fps))

        ImGuiEnd()
        
        ImGuiRender()
        let drawData = ImGuiGetDrawData()!

        ImGui_ImplMetal_RenderDrawData(drawData.pointee, commandBuffer, encoder)
        encoder.endEncoding()
        
        let blitEncoder = commandBuffer.makeBlitCommandEncoder()!
        
        blitEncoder.copy(from: sharedResources.colorBuffer, to: drawable.texture)
        blitEncoder.endEncoding()
        
        commandBuffer.present(drawable)
        

        commandBuffer.commit()
    }
    
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        let aspect = Float(size.width) / Float(size.height)
        
        let width = Int(size.width)
        let height = Int(size.height)
        self.sharedResources.frameUniforms.projection = matrix_perspective_right_hand(fovyRadians: radians_from_degrees(65), aspectRatio:aspect, nearZ: 0.01, farZ: 100.0)
        
        self.depthTextureDescriptor.height = height
        self.depthTextureDescriptor.width = width
        self.sharedResources.depthBuffer = device.makeTexture(descriptor: self.depthTextureDescriptor)!
        
        self.maskTextureDescriptor.height = height
        self.maskTextureDescriptor.width = width
        device.makeTexture(descriptor: self.maskTextureDescriptor)
        self.sharedResources.outlineMask = device.makeTexture(descriptor: self.maskTextureDescriptor)
        
        self.colorTextureDescriptor.height = height
        self.colorTextureDescriptor.width = width
        self.sharedResources.colorBuffer = device.makeTexture(descriptor: self.colorTextureDescriptor)!
    }
    
    func AABBintersect(px: Float, py: Float){
        let size = view.drawableSize
        // Convert CGFloat to Float explicitly for SIMD Float math
        let width = Float(size.width)
        let height = Float(size.height)

        let xNDC: Float = (px - 0.5 * width) / (0.5 * width)
        let yNDC: Float = (py - 0.5 * height) / (0.5 * height)

        let rayStart = SIMD3<Float>(xNDC, yNDC, 0.0)
        let rayEnd = SIMD3<Float>(xNDC-0.001, yNDC, 1.0) // make it slightly not parallel
                
        let viewProjection = self.sharedResources.frameUniforms.projection * self.sharedResources.frameUniforms.view
        let inverseViewProjection = simd_inverse(viewProjection)
        
        var worldStart = inverseViewProjection * SIMD4<Float>(rayStart, 1.0)
        var worldEnd = inverseViewProjection *  SIMD4<Float>(rayEnd, 1.0)
        
        worldStart /= worldStart.w
        worldEnd /= worldEnd.w
        
        let d = normalize(worldEnd - worldStart)
        let r = worldStart
        
        // parametric equation of line p(t) = r + dt
        
        let minDist = Float.greatestFiniteMagnitude
        var selected: Instance? = nil
        
        for renderable in sharedResources.renderables {
            if !renderable.selectable { continue }
            let bb = renderable.model.asset.boundingBox
            for instance in renderable.instances {
                let transform = instance.transform
                let lWorld = transform * SIMD4<Float>(bb.minBounds, 1.0)
                let rWorld = transform * SIMD4<Float>(bb.maxBounds, 1.0)
                
                // parametric equation of line: p(t) = r + dt
                // parametric equation of the plane orthogonal to x-axis containing l: p(u, v) = l + (0, 0, 1)u + (0, 1, 0)v
                // r_x + d_xt = l_x
                let txLower: Float = (lWorld.x - r.x)/d.x
                let txHigher: Float = (rWorld.x - r.x)/d.x
                
                let txClose = min(txLower, txHigher)
                let txFar = max(txLower, txHigher)
                
                // intersection of plane orthogonal to y-axis
                let tyLower = (lWorld.y - r.y) / d.y
                let tyHigher = (rWorld.y - r.y) / d.y
                
                let tyClose = min(tyLower, tyHigher)
                let tyFar = max(tyLower, tyHigher)

                let tzLower: Float = (lWorld.z - r.z) / d.z
                let tzHigher: Float = (rWorld.z - r.z) / d.z
                
                let tzClose = min(tzLower, tzHigher)
                let tzFar = max(tzLower, tzHigher)
                
                let tclose = max(txClose, tyClose, tzClose)
                let tfar = min(txFar, tyFar, tzFar)
                
                if tclose <= tfar {
                    // ray intersects
                    if tclose < minDist {
                        selected = instance
                    }
                }
            }
        }
        self.sharedResources.selectedRenderableInstance = selected
    }
}

func gaussianKernel1D(size: Int, sigma: Float) -> [Float] {
    precondition(size > 0 && size % 2 == 1, "Kernel size should be a positive odd number")
    var kernel = Array(repeating: Float(0), count: size)
    let half = size / 2

    let twoSigma2 = 2.0 * sigma * sigma
    let norm: Float = 1.0 / sqrtf(2.0 * Float.pi * sigma * sigma)
    var sum: Float = 0

    for i in 0..<size {
        let x = Float(i - half)
        let exponent = -((x * x) / Float(twoSigma2))
        let value = norm * expf(exponent)
        kernel[i] = value
        sum += value
    }

    if sum != 0 {
        for i in 0..<size {
            kernel[i] /= sum
        }
    }
    return kernel
}

func guassianKernel(size: Int, sigma: Float) -> [Float] {
    return gaussianKernel1D(size: size, sigma: sigma)
}

// Generic matrix math utility functions
func matrix4x4_rotation(radians: Float, axis: SIMD3<Float>) -> matrix_float4x4 {
    let unitAxis = normalize(axis)
    let ct = cosf(radians)
    let st = sinf(radians)
    let ci = 1 - ct
    let x = unitAxis.x, y = unitAxis.y, z = unitAxis.z
    return matrix_float4x4.init(columns:(vector_float4(    ct + x * x * ci, y * x * ci + z * st, z * x * ci - y * st, 0),
                                         vector_float4(x * y * ci - z * st,     ct + y * y * ci, z * y * ci + x * st, 0),
                                         vector_float4(x * z * ci + y * st, y * z * ci - x * st,     ct + z * z * ci, 0),
                                         vector_float4(                  0,                   0,                   0, 1)))
}

func matrix4x4_translation(_ translationX: Float, _ translationY: Float, _ translationZ: Float) -> matrix_float4x4 {
    return matrix_float4x4.init(columns:(vector_float4(1, 0, 0, 0),
                                         vector_float4(0, 1, 0, 0),
                                         vector_float4(0, 0, 1, 0),
                                         vector_float4(translationX, translationY, translationZ, 1)))
}

func matrix4x4_scale(scaleX: Float, scaleY: Float, scaleZ: Float) -> matrix_float4x4 {
    return matrix_float4x4.init(columns:(vector_float4(scaleX, 0, 0, 0),
                                         vector_float4(0, scaleY, 0, 0),
                                         vector_float4(0, 0, scaleZ, 0),
                                         vector_float4(0, 0, 0, 1)))
}

func matrix_perspective_right_hand(fovyRadians fovy: Float, aspectRatio: Float, nearZ: Float, farZ: Float) -> matrix_float4x4 {
    let ys = 1 / tanf(fovy * 0.5)
    let xs = ys / aspectRatio
    let zs = farZ / (nearZ - farZ)
    return matrix_float4x4.init(columns:(vector_float4(xs,  0, 0,   0),
                                         vector_float4( 0, ys, 0,   0),
                                         vector_float4( 0,  0, zs, -1),
                                         vector_float4( 0,  0, zs * nearZ, 0)))
}

func matrix_orthographic_right_hand(left: Float, right: Float, bottom: Float, top: Float, nearZ: Float, farZ: Float) -> matrix_float4x4 {
    // nearZ and farZ are positive distances; camera looks down -Z.
    // This directly maps Z to [0, 1] for Metal.
    let rml = right - left
    let tmb = top - bottom
    let fn = farZ - nearZ

    let sx = 2.0 / rml
    let sy = 2.0 / tmb
    let sz = -1.0 / fn  // maps depth to [0,1] for Metal in RH

    let tx = -(right + left) / rml
    let ty = -(top + bottom) / tmb
    let tz = -nearZ / fn      // 0 at near, 1 at far

    return matrix_float4x4(columns: (
        SIMD4<Float>( sx,  0,  0, 0),
        SIMD4<Float>(  0, sy,  0, 0),
        SIMD4<Float>(  0,  0, sz, 0),
        SIMD4<Float>( tx, ty, tz, 1)
    ))
}

func matrix_lookAt(eye: SIMD3<Float>, target: SIMD3<Float>, up: SIMD3<Float>) -> matrix_float4x4 {
    // basis vectors
    let zAxis = normalize(eye-target)
    let xAxis = normalize(cross(up, zAxis))
    let yAxis = cross(zAxis, xAxis)
    let translation = matrix4x4_translation(-eye.x, -eye.y, -eye.z)
    var result: matrix_float4x4 = matrix_identity_float4x4
    // orthonormal basis A^-1 = A^T
    result.columns.0 = SIMD4<Float>(xAxis.x, yAxis.x, zAxis.x, 0)
    result.columns.1 = SIMD4<Float>(xAxis.y, yAxis.y, zAxis.y, 0)
    result.columns.2 = SIMD4<Float>(xAxis.z, yAxis.z, zAxis.z, 0)
    return simd_mul(result, translation);
}

func radians_from_degrees(_ degrees: Float) -> Float {
    return (degrees / 180) * .pi
}

