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

var f: Float = 0.0
var clear_color: SIMD3<Float> = .init(x: 0.28, y: 0.36, z: 0.5)
var counter: Int = 0

class Renderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let view: MTKView
    
    var sharedResources: SharedResources
    let shadowPass: ShadowPass
    let maskPass: MaskPass
    let colorPass: ColorPass
    let outlinePass: OutlinePass
    let imguiPass: ImguiPass
    
    @MainActor
    init?(metalKitView: MTKView) {
        metalKitView.framebufferOnly = false
        self.device = metalKitView.device!
        self.commandQueue = self.device.makeCommandQueue()!
        self.view = metalKitView
        
        metalKitView.colorPixelFormat = MTLPixelFormat.bgra8Unorm_srgb
       
        let sphereModel = Model(device: self.device, resourceName: "sphere")
        let sphereRenderable = InstancedRenderable(device: device, model: sphereModel)
        sphereRenderable.addInstance(transform: matrix4x4_translation(-4, 1, 0))
        sphereRenderable.addInstance(transform: matrix4x4_translation(4, 1, 0))
        sphereRenderable.addInstance(transform: matrix4x4_translation(0, 1, -4))
        
        let pointLight = PointLight(position: SIMD4<Float>(0, 1, 0, 0), color: SIMD4<Float>(1, 1, 1, 1),
                                    radius: 10)
        let eye = SIMD3<Float>(0, 1, 5)
        let viewMatrix = matrix_lookAt(eye: eye, target: SIMD3<Float>(0, 0, 0), up: SIMD3<Float>(0, 1, 0))
        
        sharedResources = SharedResources( device: device, view: self.view)
        sharedResources.renderables = [sphereRenderable]
        sharedResources.viewMatrix = viewMatrix
        sharedResources.selectedRenderableInstance = sphereRenderable.instances[0]
        sharedResources.addPointLight(pointLight)
        sharedResources.cameraPos = SIMD4<Float>(eye, 1.0)
        
        colorPass = ColorPass(device: device)
        colorPass.setColorAttachment(colorTexture: sharedResources.colorBuffer)
        colorPass.setDepthAttachment(depthTexture: sharedResources.depthBuffer)
        maskPass = MaskPass(device: device)
        shadowPass = ShadowPass(device: device)
        outlinePass = OutlinePass(device: device)
        imguiPass = ImguiPass(device: device)

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

        let commandBuffer = commandQueue.makeCommandBuffer()!
                
        shadowPass.encode(commandBuffer: commandBuffer, sharedResources: &sharedResources)
        colorPass.encode(commandBuffer: commandBuffer, sharedResources: &sharedResources)
        maskPass.encode(commandBuffer: commandBuffer, sharedResources: &sharedResources)
        outlinePass.encode(commandBuffer: commandBuffer, sharedResources: &sharedResources)
        imguiPass.encode(commandBuffer: commandBuffer, sharedResources: &sharedResources)
        
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
        self.sharedResources.projectionMatrix = matrix_perspective_right_hand(fovyRadians: radians_from_degrees(65), aspectRatio:aspect, nearZ: 0.01, farZ: 100.0)
        
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
    
    func AABBintersect(px: Float, py: Float){
        let size = view.drawableSize
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
    
    func updateCameraTransform(deltaX: Float, deltaY: Float){
        // get x axis and y axis relative to camera in world space
        let xAxis = SIMD4<Float>(1, 0, 0, 0)
        let yAxis = SIMD4<Float>(0, 1, 0, 0)
        let inverseView = self.sharedResources.viewMatrix.inverse
        
        let xWorld = inverseView * xAxis
        let yWorld = inverseView * yAxis
        
        let rotationX = matrix4x4_rotation(radians: radians_from_degrees(-deltaY), axis: SIMD3<Float>(xWorld.x, xWorld.y, xWorld.z))
        let rotationY = matrix4x4_rotation(radians: radians_from_degrees(-deltaX), axis: SIMD3<Float>(yWorld.x, yWorld.y, yWorld.z))
        
        self.sharedResources.cameraPos = rotationX * rotationY * self.sharedResources.cameraPos
        self.sharedResources.viewMatrix = matrix_lookAt(eye: self.sharedResources.cameraPos[SIMD3<Int>(0, 1, 2)], target: SIMD3<Float>(0, 0, 0), up: SIMD3<Float>(0, 1, 0))
    }
    
    func updateCameraTransform(zoom: Float){
        // translate along the forward vector relative to the camera in view space
        let forward = normalize(-self.sharedResources.cameraPos)
        let dist = zoom * forward
        let translation = matrix4x4_translation(dist.x, dist.y, dist.z)
        
        self.sharedResources.cameraPos = translation * self.sharedResources.cameraPos
        self.sharedResources.viewMatrix = matrix_lookAt(eye: self.sharedResources.cameraPos[SIMD3<Int>(0, 1, 2)], target: SIMD3<Float>(0, 0, 0), up: SIMD3<Float>(0, 1, 0))
    }
    
    func updateSelectedObjectTransform(deltaX: Float, deltaY: Float){
        // update the object position in the xy plane relative to the camera
        let size = view.drawableSize
        let width = Float(size.width)
        let height = Float(size.height)
        // convert pixel deltas to deltas in NDC space
        let dxNDC = (2.0 / width) * deltaX
        let dyNDC = (2.0 / height) * deltaY
        
        let view = self.sharedResources.viewMatrix
        let projection = self.sharedResources.projectionMatrix
        
        let inverseView = view.inverse
        let inverseProjection = projection.inverse
        
        let selectedObj = sharedResources.selectedRenderableInstance!
        
        // get object depth in clip space
        let objPositionWorld = selectedObj.transform.columns.3
        let objClip = projection * view * objPositionWorld
        let wClip = objClip.w
        // add NDC offsets scaled by w
        let objOffset = SIMD4<Float>(objClip.x + dxNDC * wClip, objClip.y + dyNDC * wClip, objClip.z, wClip)
        
        // project back to world space and calculate difference in position
        let objWorldOffset = inverseView * inverseProjection * objOffset
        
        let diff = objWorldOffset - objPositionWorld
        
        // update the transform with translation
        let transform = matrix4x4_translation(diff.x, diff.y, diff.z)
        if let instance = self.sharedResources.selectedRenderableInstance {
            let currentTransform = instance.transform
            let newTransform = transform * currentTransform
            instance.transform = newTransform
        }
    }
}

