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

struct Uniforms {
    var view: simd_float4x4
    var projection: simd_float4x4
    var inverseView: simd_float4x4
    var inverseProjection: simd_float4x4
}

struct PointLight {
    var position: simd_float4
    var color: simd_float4
    var radius: simd_float1
}

struct SharedResources {
    var pointLights: [PointLight] = []
    var pointLightShadowAtlas: MTLTexture?
    var outlineMask: MTLTexture?
    var renderables: [InstancedRenderable] = []
    var viewMatrix: simd_float4x4 = matrix_identity_float4x4
    var cameraPos: SIMD3<Float> = SIMD3<Float>(0, 4.0, 8.0)
    var projectionMatrix: simd_float4x4 = matrix_identity_float4x4
    var selectedRenderableInstance: Instance? = nil
    var colorBuffer: MTLTexture?
    var depthBuffer: MTLTexture
}

class Renderer: NSObject, MTKViewDelegate {
    
    private let maxFramesInFlight = 3
    private let inFlightSemaphore = DispatchSemaphore(value: 3)
    
    public let device: MTLDevice
    let commandQueue: MTLCommandQueue
    var depthState: MTLDepthStencilState
        
    var projectionMatrix: matrix_float4x4 = matrix_identity_float4x4
    
    var modelMatrix: matrix_float4x4 = matrix_identity_float4x4
    
    var viewMatrix: matrix_float4x4 = matrix_identity_float4x4
    
    var rotationX: Float = 0
    var rotationY: Float = 0
    
    let view: MTKView
    
    var sharedResources: SharedResources
    
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
        metalKitView.sampleCount = 1
        
        let depthStateDescriptor = MTLDepthStencilDescriptor()
        depthStateDescriptor.depthCompareFunction = MTLCompareFunction.less
        depthStateDescriptor.isDepthWriteEnabled = true
        self.depthState = device.makeDepthStencilState(descriptor: depthStateDescriptor)!
        
        let depthTexDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float,
                                                            width: width,
                                                            height: height,
                                                            mipmapped: false)
        depthTexDesc.storageMode = .private
        depthTexDesc.usage = [.renderTarget]
        depthTexDesc.textureType = .type2D
        depthTexDesc.sampleCount = 1
        let depthTexture = device.makeTexture(descriptor: depthTexDesc)!
        
        let depthAttachmentDescriptor = MTLRenderPassDepthAttachmentDescriptor()
        depthAttachmentDescriptor.texture = depthTexture
        
        self.view.currentRenderPassDescriptor?.depthAttachment = depthAttachmentDescriptor;
        
        let axisModel = Model(device: self.device, resourceName: "axis", ext: "obj")
        let axisRenderable = InstancedRenderable(device: device, model: axisModel)
        axisRenderable.addInstance(transform: matrix4x4_rotation(radians: radians_from_degrees(90), axis: SIMD3<Float>(0,1,0)))
        axisRenderable.castsShadows = false
        axisRenderable.selectable = false
        
        let sphereModel = Model(device: self.device, resourceName: "sphere")
        let sphereRenderable = InstancedRenderable(device: device, model: sphereModel)
        sphereRenderable.addInstance(transform: modelMatrix * matrix4x4_translation(-4, 1, 0))
        sphereRenderable.addInstance(transform: modelMatrix * matrix4x4_translation(4, 1, 0))
        sphereRenderable.addInstance(transform: modelMatrix * matrix4x4_translation(0, 1, -4))
        
        let planeModel = Model(device: self.device, resourceName: "plane")
        let planeRenderable = InstancedRenderable(device: device, model: planeModel)
        planeRenderable.addInstance(transform: modelMatrix * matrix4x4_scale(scaleX: 100, scaleY: 100, scaleZ: 100))
        planeRenderable.castsShadows = false
        planeRenderable.selectable = false
        
        let desc = MTLTextureDescriptor()
        desc.textureType = .typeCubeArray
        desc.pixelFormat = .r32Float
        desc.width = 1024
        desc.height = 1024
        desc.arrayLength = 6
        desc.mipmapLevelCount = 1
        desc.sampleCount = 1
        desc.usage = [.renderTarget, .shaderRead]
        
        let shadowAtlas = device.makeTexture(descriptor: desc)!
        
        let maskTextureDesc = MTLTextureDescriptor()
        maskTextureDesc.textureType = .type2D
        maskTextureDesc.pixelFormat = .r32Float
        maskTextureDesc.height = height
        maskTextureDesc.width = width
        maskTextureDesc.usage = [.renderTarget, .shaderRead]
        let outlineMask = device.makeTexture(descriptor: maskTextureDesc)
        let pointLight = PointLight(position: SIMD4<Float>(0, 1, 0, 0), color: SIMD4<Float>(1, 1, 1, 1),
                                    radius: 10 )
        sharedResources = SharedResources( pointLights: [pointLight], pointLightShadowAtlas: shadowAtlas, outlineMask: outlineMask, renderables: [axisRenderable, sphereRenderable, planeRenderable], viewMatrix: self.viewMatrix, projectionMatrix: self.projectionMatrix, depthBuffer: depthTexture)
        sharedResources.selectedRenderableInstance = sphereRenderable.instances[0]
        super.init()
    }
    
    private func updateGameState() {
        self.modelMatrix = matrix4x4_rotation(
            radians: rotationX,
            axis: SIMD3<Float>(0, 1, 0)) *
        matrix4x4_rotation(radians: rotationY, axis: SIMD3<Float>(1, 0, 0))
        self.sharedResources.viewMatrix = matrix_lookAt(eye: self.sharedResources.cameraPos, target: SIMD3<Float>(0, 0, 0), up: SIMD3<Float>(0, 1, 0))
    }
    
    func draw(in view: MTKView) {
        _ = inFlightSemaphore.wait(timeout: DispatchTime.distantFuture)

        let commandBuffer = commandQueue.makeCommandBuffer()!
        let semaphore = inFlightSemaphore
        commandBuffer.addCompletedHandler { (_ commandBuffer) -> Swift.Void in
            semaphore.signal()
            
        }
        
        self.updateGameState()
        
        let maskPass = MaskPass(device: device)
        maskPass.encode(commandBuffer: commandBuffer, sharedResources: &sharedResources)
        
        let shadowPass = PointLightShadowPass(device: device)
        
        shadowPass.encode(commandBuffer: commandBuffer, sharedResources: &sharedResources)
        
        let colorPass = ColorPass(device: device, mtkDescriptor: view.currentRenderPassDescriptor!)
        colorPass.encode(commandBuffer: commandBuffer, sharedResources: sharedResources)
        
        sharedResources.colorBuffer = view.currentRenderPassDescriptor?.colorAttachments[0].texture!
        
        let outlinePass = OutlinePass(device: device)
        outlinePass.encode(commandBuffer: commandBuffer, sharedResources: &sharedResources)
        
        guard let blit = commandBuffer.makeBlitCommandEncoder() else {
            fatalError()
        }
        guard let colorBuffer: MTLTexture = sharedResources.colorBuffer else {
            return;
        }
        guard let viewText: MTLTexture = view.currentDrawable?.texture else {
            return;
        }
        blit.copy(from: colorBuffer,
                  sourceSlice: 0,
                  sourceLevel: 0,
                  sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: sharedResources.colorBuffer!.width,
                                      height: sharedResources.colorBuffer!.height,
                                      depth: 1),
                  to: viewText,
                  destinationSlice: 0,
                  destinationLevel: 0,
                  destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        blit.endEncoding()

        if let drawable = view.currentDrawable {
            commandBuffer.present(drawable)
        }
        commandBuffer.commit()
    }
    
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        /// Respond to drawable size or orientation changes here
        let aspect = Float(size.width) / Float(size.height)
        self.sharedResources.projectionMatrix = matrix_perspective_right_hand(fovyRadians: radians_from_degrees(65), aspectRatio:aspect, nearZ: 0.01, farZ: 100.0)
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
                
        let viewProjection = self.sharedResources.projectionMatrix * self.sharedResources.viewMatrix
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

// Backwards-compatibility shim: keep the original misspelled name but return 1D
// If callers expect 2D, they should update to their own separable usage.
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

