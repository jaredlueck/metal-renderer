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
    let outlinePass: Editor
            
    @MainActor
    init?(metalKitView: MTKView, scene: Scene, editor: Editor, assetManager: AssetManager) {
        metalKitView.framebufferOnly = false
        self.device = metalKitView.device!
        self.commandQueue = self.device.makeCommandQueue()!
        self.view = metalKitView

        metalKitView.colorPixelFormat = MTLPixelFormat.bgra8Unorm_srgb

        let eye = SIMD3<Float>(0, 1, 5)
        let viewMatrix = matrix_lookAt(eye: eye, target: SIMD3<Float>(0, 0, 0), up: SIMD3<Float>(0, 1, 0))

        sharedResources = SharedResources( device: device, view: self.view)
        sharedResources.viewMatrix = viewMatrix
        sharedResources.cameraPos = SIMD4<Float>(eye, 1.0)

        self.scene = scene
        self.assetManager = assetManager
        
        colorPass = ColorPass(device: device)
        colorPass.setColorAttachment(colorTexture: sharedResources.colorBuffer)
        colorPass.setDepthAttachment(depthTexture: sharedResources.depthBuffer)
        maskPass = MaskPass(device: device)
        shadowPass = ShadowPass(device: device)
        outlinePass = editor
 
        self.assetManager.loadAssets()
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

        self.sharedResources.viewMatrix = outlinePass.editorView
        self.sharedResources.projectionMatrix = outlinePass.editorProjection
        self.sharedResources.cameraPos = SIMD4<Float>(outlinePass.editorCameraPosition, 1.0)
        
        let commandBuffer = commandQueue.makeCommandBuffer()!
        
        if shadowCasterInstances.count > 0 {
            shadowPass.encode(commandBuffer: commandBuffer, lights: data.pointLights, cubeTextureArray: sharedResources.pointLightShadowAtlas, shadowCasters: shadowCasterInstances )
        }
        colorPass.encode(commandBuffer: commandBuffer, pointLights: data.pointLights, renderables: renderables  ,sharedResources: &sharedResources)
        outlinePass.renderHUD(commandBuffer: commandBuffer, sharedResources: &sharedResources)
        outlinePass.renderUI(commandBuffer: commandBuffer, sharedResources: &sharedResources)

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
        self.outlinePass.editorProjection = self.sharedResources.projectionMatrix
        
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
