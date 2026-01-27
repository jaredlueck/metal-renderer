//
//  Editor.swift
//  metal-swift-new
//
//  Created by Jared Lueck on 2026-01-01.
//

import Metal
import simd
import ImGui
import MetalKit

enum TransformMode {
    case translate
    case scale
    case rotate
}

struct CircleUniforms {
    var radius: simd_float1
    var thickness: simd_float1
    var color: SIMD3<Float>;
    var center: SIMD2<Float>
}

class Editor {

    let outlineShaders: ShaderProgram
    let outlinePipeline: RenderPipeline
    
    let gridShaders: ShaderProgram
    let gridPipeline: RenderPipeline
    
    let uniformColorShader: ShaderProgram
    let uniformColorPipeline: RenderPipeline
    
    let maskShaders: ShaderProgram
    let maskPipeline: RenderPipeline
    
    let canvasShader: ShaderProgram
    let canvasPipeline: RenderPipeline
    
    let circleShader: ShaderProgram
    let circlePipeline: RenderPipeline
    
    let device: MTLDevice
    let descriptor: MTLRenderPassDescriptor;
    
    let hudRenderPassDescriptor: MTLRenderPassDescriptor
        
    let view: MTKView
    
    let scene: Scene
    let assetManager: AssetManager
    
    var selectedEntity: Node? = nil
    var transformMode: TransformMode = .translate
    
    var mouseX: Float = 0.0
    var mouseY: Float = 0.0
        
    let spotLightTexture: MTLTexture
    
    let sampler: MTLSamplerState
    
    var hoveringSceneWindow = false
    
    var xAxisSelected = false
    var yAxisSelected = false
    var zAxisSelected = false
    
    var dragging = false
    
    let transformGizmo: TransformGizmo
    
    var editorCamera: Camera
    
    var assetsWindow: AssetsWindow
    
    init(device: MTLDevice, view: MTKView, scene: Scene, assetManager: AssetManager){
        self.descriptor = MTLRenderPassDescriptor()
        self.descriptor.colorAttachments[0].loadAction = .load
        self.descriptor.colorAttachments[0].storeAction = .store
        self.descriptor.depthAttachment.loadAction = .load
        
        self.hudRenderPassDescriptor = MTLRenderPassDescriptor()
        self.hudRenderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor.init(red: 0, green: 0, blue: 0, alpha: 1)
        self.hudRenderPassDescriptor.colorAttachments[0].loadAction = .clear
        self.hudRenderPassDescriptor.colorAttachments[0].storeAction = .store
                
        try! self.maskShaders = ShaderProgram(device: device, descriptor: ShaderProgramDescriptor(vertexName: "maskVertex", fragmentName: "maskFragment"))
        self.maskPipeline = RenderPipeline(device: device, program: self.maskShaders, colorAttachmentPixelFormat: .r32Float)

        try! self.outlineShaders = ShaderProgram(device: device, descriptor: ShaderProgramDescriptor(vertexName: "outlineVertex", fragmentName: "outlineFragment"))
        self.outlinePipeline = RenderPipeline(device: device, program: self.outlineShaders, vertexDescriptor: nil, colorAttachmentPixelFormat: MTLPixelFormat.bgra8Unorm_srgb, depthAttachmentPixelFormat: MTLPixelFormat.depth32Float)
        
        try! self.gridShaders = ShaderProgram(device: device, descriptor: ShaderProgramDescriptor(vertexName: "gridVertex", fragmentName: "gridFragment"))
        self.gridPipeline = RenderPipeline(device: device, program: self.gridShaders, vertexDescriptor: nil, colorAttachmentPixelFormat: MTLPixelFormat.bgra8Unorm_srgb, depthAttachmentPixelFormat: MTLPixelFormat.depth32Float)
        
        try! self.uniformColorShader = ShaderProgram(device: device, descriptor: ShaderProgramDescriptor(vertexName: "uniformColorVertex", fragmentName: "uniformColorFragment"))
        self.uniformColorPipeline = RenderPipeline(device: device, program: self.uniformColorShader, vertexDescriptor: nil, colorAttachmentPixelFormat: MTLPixelFormat.bgra8Unorm_srgb, depthAttachmentPixelFormat: MTLPixelFormat.depth32Float)
        
        try! self.canvasShader = ShaderProgram(device: device, descriptor: ShaderProgramDescriptor(vertexName: "canvasVertex", fragmentName: "canvasFragment"))
        self.canvasPipeline = RenderPipeline(device: device, program: self.canvasShader, colorAttachmentPixelFormat: MTLPixelFormat.bgra8Unorm_srgb, depthAttachmentPixelFormat: MTLPixelFormat.depth32Float)
        
        try! self.circleShader = ShaderProgram(device: device, descriptor: ShaderProgramDescriptor(vertexName: "outlineVertex", fragmentName: "circleFragment"))
        self.circlePipeline = RenderPipeline(device: device, program: self.circleShader, vertexDescriptor: nil, colorAttachmentPixelFormat: MTLPixelFormat.bgra8Unorm_srgb, depthAttachmentPixelFormat: MTLPixelFormat.depth32Float)
        self.device = device
        
        assetsWindow = AssetsWindow(scene: scene)
        assetsWindow.loadAssetsFolder()
        
        self.view = view
        self.scene = scene
        self.assetManager = assetManager
        let size = view.bounds.size
        let width = Int(size.width)
        let height = Int(size.height)

        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.mipFilter = .linear
        guard let sampler = device.makeSamplerState(descriptor: samplerDescriptor) else {
            fatalError("Failed to create sampler state")
        }
        self.sampler = sampler
        
        self.transformGizmo = TransformGizmo(device: device)
        self.editorCamera = Camera(position: SIMD3<Float>(0, 1, 5), viewportSize: SIMD2<Float>(Float(width), Float(height)))
        let textureLoader = MTKTextureLoader(device: device)
        let pointlightIconTextureUrl = Bundle.main.url(forResource: "pointlight", withExtension: "png")!
        spotLightTexture = try! textureLoader.newTexture(URL: pointlightIconTextureUrl)
    }
    
    func NDCToScreenSpace(ndc: SIMD3<Float>) -> SIMD2<Float> {
        let width = Float(view.drawableSize.width)
        let height = Float(view.drawableSize.height)
        let xPixel = (ndc.x + 1) * (width/2)
        let yPixel = height - (ndc.y + 1) * (height/2)
        return SIMD2(xPixel, yPixel)
    }
    
    func SceenSpaceToNDC(pixel: SIMD2<Float>, depth: Float) -> SIMD3<Float> {
        let width = Float(view.drawableSize.width)
        let height = Float(view.drawableSize.height)
        let x = (2.0 * pixel.x) / width - 1.0
        let y = (-2.0 * pixel.y) / height + 1.0
        return SIMD3(x, y, depth)
    }
    
    func ScreenSpaceToWorld(pixel: SIMD2<Float>, depth: Float) -> SIMD3<Float> {
        let ndc = SceenSpaceToNDC(pixel: pixel, depth: depth)
        var viewPos = editorCamera.projectionMatrix.inverse * SIMD4<Float>(ndc, 1.0)
        viewPos /= viewPos.w
        let worldPos = editorCamera.lookAtMatrix().inverse * SIMD4<Float>(viewPos)
        return worldPos[SIMD3(0, 1, 2)]
    }
    
    // draw a light icon and a ring in screen space showing the radius
    func drawLightIcon(encoder: MTLRenderCommandEncoder, light: PointLight){
        let editorView = editorCamera.lookAtMatrix()
        let editorProjection = editorCamera.projectionMatrix
        encoder.pushDebugGroup("Pointlight canvas")
        let position = light.position[SIMD3(0, 1, 2)]
        canvasPipeline.bind(encoder: encoder)
        let iconSize = 100
        // project position into pixel space
        let viewPos = editorView * SIMD4<Float>(position, 1.0)
        let clipPos = editorProjection * viewPos
        let ndc = clipPos / clipPos.w
        // not visible so nothing to draw
        if ndc.x < -1.0 || ndc.x > 1.0 || ndc.y < -1.0 || ndc.y > 1.0 {
            return
        }
        let pixelCoords = NDCToScreenSpace(ndc: ndc[SIMD3(0, 1, 2)])

        let tl = SIMD2(pixelCoords.x - Float(iconSize/2), pixelCoords.y - Float(iconSize/2))
        let tr = SIMD2(pixelCoords.x + Float(iconSize/2), pixelCoords.y - Float(iconSize/2))
        let br = SIMD2(pixelCoords.x + Float(iconSize/2), pixelCoords.y + Float(iconSize/2))
        let bl = SIMD2(pixelCoords.x - Float(iconSize/2), pixelCoords.y + Float(iconSize/2))

        let uvs: [SIMD2<Float>] = [SIMD2(0, 0), SIMD2(1, 0), SIMD2(1, 1), SIMD2(0, 1)]

        let tlWorld = ScreenSpaceToWorld(pixel: tl, depth: ndc.z)
        let trWorld = ScreenSpaceToWorld(pixel: tr, depth: ndc.z)
        let brWorld = ScreenSpaceToWorld(pixel: br, depth: ndc.z)
        let blWorld = ScreenSpaceToWorld(pixel: bl, depth: ndc.z)
        let v1: [Float] = [tlWorld.x, tlWorld.y, tlWorld.z, 1.0, 1.0, 1.0, uvs[0].x, uvs[0].y]
        let v2: [Float] = [trWorld.x, trWorld.y, trWorld.z, 1.0, 1.0, 1.0, uvs[1].x, uvs[1].y]
        let v3: [Float] = [brWorld.x, brWorld.y, brWorld.z, 1.0, 1.0, 1.0, uvs[2].x, uvs[2].y]
        let v4: [Float] = [blWorld.x, blWorld.y, blWorld.z, 1.0, 1.0, 1.0, uvs[3].x, uvs[3].y]

        let vertices = v1 + v2 + v3 + v4

        encoder.setFragmentTexture(spotLightTexture, index: Bindings.baseTexture)
        encoder.setFragmentSamplerState(sampler, index: Bindings.sampler)

        guard let vertexBuffer = device.makeBuffer(length: MemoryLayout<Float>.stride * vertices.count) else { fatalError() }
        let vP = vertexBuffer.contents().bindMemory(to: Float.self, capacity: vertices.count)
        vP.update(from: vertices, count: vertices.count)

        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        
        let indices: [UInt16] = [0, 1, 3, 3, 1, 2]

        guard let indexBuffer = device.makeBuffer(length: MemoryLayout<UInt16>.stride * 6) else { fatalError()}
        let iP = indexBuffer.contents().bindMemory(to: UInt16.self, capacity: 6)
        iP.update(from: indices, count: 6)

        encoder.drawIndexedPrimitives(type: .triangle, indexCount: indices.count, indexType: MTLIndexType.uint16, indexBuffer: indexBuffer, indexBufferOffset: 0)

        encoder.popDebugGroup()
    }
    
    func drawLightRadius(encoder: MTLRenderCommandEncoder, position: SIMD3<Float>, radius: Float){
        uniformColorPipeline.bind(encoder: encoder)
        var color = SIMD3<Float>(1.0, 1.0, 1.0)
        encoder.setFragmentBytes(&color, length: MemoryLayout<SIMD3<Float>>.stride, index: Bindings.pipelineUniforms)
        drawRadius(encoder: encoder, origin: position, radius: radius)
    }

    func renderHUD(commandBuffer: MTLCommandBuffer, sharedResources: inout SharedResources) {
        self.hudRenderPassDescriptor.colorAttachments[0].texture = sharedResources.outlineMask
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: self.hudRenderPassDescriptor) else {
            fatalError("Failed to create render command encoder")
        }
        withUnsafeBytes(of: sharedResources.makeFrameUniforms()) { rawBuffer in
            encoder.setVertexBytes(rawBuffer.baseAddress!,
                                           length: MemoryLayout<FrameUniforms>.stride,
                                     index: Bindings.frameUniforms)
        }
        
        if let selected = selectedEntity {
            if selected.nodeType == .model {
                self.maskPipeline.bind(encoder: encoder)
                
                let model = assetManager.getAssetById(selected.assetId!)!
                
                let instance = InstancedRenderable(device: device, model:model)
                instance.addInstance(transform: selected.transform)
                instance.draw(renderEncoder: encoder, instanceId: nil)
            }
        }
        
        encoder.endEncoding()
    }

    func renderUI(commandBuffer: MTLCommandBuffer, sharedResources: inout SharedResources){
        self.descriptor.colorAttachments[0].texture = sharedResources.colorBuffer
        self.descriptor.depthAttachment.texture = sharedResources.depthBuffer
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: self.descriptor) else {
            fatalError("Failed to create render command encoder")
        }
        encoder.label = "ImGui UI render encoder"
        
        encoder.setDepthStencilState(sharedResources.depthStencilStateDisabled)
        
        withUnsafeBytes(of: sharedResources.makeFrameUniforms()) { rawBuffer in
            encoder.setVertexBytes(rawBuffer.baseAddress!,
                                           length: MemoryLayout<FrameUniforms>.stride,
                                     index: Bindings.frameUniforms)
        }
                
        encoder.setFragmentTexture(sharedResources.outlineMask, index: 0)

        var outlineColor = SIMD4<Float>(1, 0.5, 0.0, 1)
        encoder.setFragmentBytes(&outlineColor, length: MemoryLayout<SIMD4<Float>>.stride, index: Bindings.pipelineUniforms)
        
        self.outlinePipeline.bind(encoder: encoder)
        
        encoder.setDepthStencilState(sharedResources.depthStencilStateEnabled)
        
        encoder.drawPrimitives(type: MTLPrimitiveType.triangle, vertexStart: 0, vertexCount: 6)
        
        var gridColor = SIMD4<Float>(0.5, 0.5, 0.5, 0.5)
        encoder.setFragmentBytes(&gridColor, length: MemoryLayout<SIMD4<Float>>.stride, index: Bindings.pipelineUniforms)
        
        self.gridPipeline.bind(encoder: encoder)
        
        encoder.drawPrimitives(type: MTLPrimitiveType.triangle, vertexStart: 0, vertexCount: 6)
        
        encoder.setDepthStencilState(sharedResources.depthStencilStateDisabled)

        let sceneLights = scene.getLights()

        for light in sceneLights {
            drawLightIcon(encoder: encoder, light: light)
        }
        
        if let node = selectedEntity,
           let radius = node.lightData?.radius {
            drawLightRadius(encoder: encoder, position: node.transform.position, radius: radius)
        }

        encoder.setDepthStencilState(sharedResources.depthStencilStateEnabled)
        imGui(view: view, commandBuffer: commandBuffer, encoder: encoder, sharedResources: &sharedResources)
        encoder.endEncoding()
    }
    
    @objc func saveScene(_ sender: Any?) {
        let encoder = JSONEncoder()
        let data = try! encoder.encode(self.scene)
        if let jsonString = String(data: data, encoding: .utf8) {
            print(jsonString)
        }
        let url = URL(filePath: "/Users/jaredlueck/Documents/programming/metal-swift-new/metal-renderer/persistance")
        let fileURL = url.appendingPathComponent("scene.json")
        
        try! data.write(to: fileURL)
        
        assetManager.writeAssetMapToFile()
    }
    
    func imGui(view: MTKView, commandBuffer: MTLCommandBuffer, encoder: MTLRenderCommandEncoder, sharedResources: inout SharedResources){
        let io = ImGuiGetIO()!
        io.pointee.IniFilename = nil
        let viewWidth = Float(view.bounds.size.width)
        let viewHeight = Float(view.bounds.size.height)
        
        io.pointee.DisplaySize.x = Float(view.bounds.size.width)
        io.pointee.DisplaySize.y = Float(view.bounds.size.height)

        let frameBufferScale = Float(view.window?.screen?.backingScaleFactor ?? NSScreen.main!.backingScaleFactor)

        io.pointee.DisplayFramebufferScale = ImVec2(x: frameBufferScale, y: frameBufferScale)
        io.pointee.DeltaTime = 1.0 / Float(view.preferredFramesPerSecond)

        ImGui_ImplMetal_NewFrame(self.descriptor)
        ImGui_ImplOSX_NewFrame(view)
        ImGuiNewFrame()
        ImGuiSetNextWindowPos(ImVec2(x: 10, y: 10), 1 << 1, ImVec2(x: 0, y: 0))
        var show_demo_window = true
        
        assetsWindow.encode()
        
        encoder.setDepthStencilState(sharedResources.depthStencilStateDisabled)
        
        if let selected = selectedEntity {
            self.uniformColorPipeline.bind(encoder: encoder)
            transformGizmo.encode(encoder: encoder, mouseX: mouseX, mouseY: mouseY, editorCamera: editorCamera, position: selected.transform.position)
        }
        
        encoder.setDepthStencilState(sharedResources.depthStencilStateDisabled)
        
        ImGuiSetNextWindowPos(ImVec2(x: viewWidth - 10, y: 10), 1 << 1, ImVec2(x: 1, y: 0))
        ImGuiBegin("Scene Hierarchy", &show_demo_window, 0)
        ImGuiEnd()

        ImGuiSetNextWindowPos(ImVec2(x: 0, y: 0), 1 << 1, ImVec2(x: 0, y: 0))
        ImGuiSetNextWindowSize(ImVec2(x: viewWidth, y: viewHeight), 0)
        
        let sceneFlags = ImGuiWindowFlags(
            ImGuiWindowFlags_NoTitleBar.rawValue |
            ImGuiWindowFlags_NoBackground.rawValue |
            ImGuiWindowFlags_NoBringToFrontOnFocus.rawValue |
            ImGuiWindowFlags_NoNavFocus.rawValue |
            ImGuiWindowFlags_NoMove.rawValue |
            ImGuiWindowFlags_NoResize.rawValue
        )
        
        ImGuiBegin("Scene area", &show_demo_window,sceneFlags )
        
        var size = ImVec2()
        ImGuiGetContentRegionAvail(&size)
        ImGuiInvisibleButton("SceneDropZone", size, 0);
        
        hoveringSceneWindow = ImGuiIsItemHovered(0)

        if ImGuiBeginDragDropTarget() {
            if let payload = ImGuiAcceptDragDropPayload("ASSET_URL", 0) {
                let rawPtr = payload.pointee.Data
                let size = Int(payload.pointee.DataSize)

                let buffer = UnsafeRawBufferPointer(start: rawPtr, count: size)
                let filename = String(decoding: buffer, as: UTF8.self)

                let assetId = self.assetManager.loadAssetAtPath(filename)
                scene.add(Node(nodeType: .model, transform: Transform(), assetId: assetId))
            }
            if let payload = ImGuiAcceptDragDropPayload("LIGHT_SOURCE", 0) {
                let rawPtr = payload.pointee.Data
                let size = Int(payload.pointee.DataSize)
                
                let buffer = UnsafeRawBufferPointer(start: rawPtr, count: size)

                scene.addLight(position: SIMD3<Float>(0.0, 1.0, 0.0), color: SIMD3<Float>(1.0, 1.0, 1.0), radius: 10.0)
            }
            ImGuiEndDragDropTarget()
        }
        ImGuiEnd()
        ImGuiRender()
        let drawData = ImGuiGetDrawData()!

        ImGui_ImplMetal_RenderDrawData(drawData.pointee, commandBuffer, encoder)
    }
    
    func drawRadius(encoder: MTLRenderCommandEncoder, origin: SIMD3<Float>, radius: Float){
        let square: [SIMD2<Float>] = [SIMD2<Float>(radius, radius), SIMD2<Float>(-radius, radius), SIMD2<Float>(-radius, -radius), SIMD2<Float>(radius, -radius)]
        let circle = subdivideClosedPolygon(polygon: square, count: 10)
        
        var xyCircle = circle.map { vert2d in SIMD3<Float>(origin.x + vert2d.x, origin.y + vert2d.y, origin.z) }
        xyCircle.append(xyCircle[0])
        
        var yzCircle = circle.map { vert2d in SIMD3<Float>(origin.x, origin.y + vert2d.y, origin.z + vert2d.x) }
        yzCircle.append(yzCircle[0])
        
        var xzCircle = circle.map { vert2d in SIMD3<Float>(origin.x + vert2d.x, origin.y, origin.z + vert2d.y) }
        xzCircle.append(xzCircle[0])
        
        var transform = matrix_identity_float4x4
        encoder.setVertexBytes(&transform, length: MemoryLayout<simd_float4x4>.stride , index: Bindings.instanceData)
        
        let xyBuffer = device.makeBuffer(length: MemoryLayout<SIMD3<Float>>.stride * xyCircle.count)
        let xyPtr = xyBuffer?.contents().bindMemory(to: SIMD3<Float>.self, capacity: xyCircle.count)
        xyPtr?.update(from: xyCircle, count: xyCircle.count)
        encoder.setVertexBuffer(xyBuffer, offset: 0, index: Bindings.vertexBuffer)
        encoder.drawPrimitives(type: .lineStrip, vertexStart: 0, vertexCount: xyCircle.count)

        let yzBuffer = device.makeBuffer(length: MemoryLayout<SIMD3<Float>>.stride * yzCircle.count)
        let yzPtr = yzBuffer?.contents().bindMemory(to: SIMD3<Float>.self, capacity: yzCircle.count)
        yzPtr?.update(from: yzCircle, count: yzCircle.count)
        encoder.setVertexBuffer(yzBuffer, offset: 0, index: Bindings.vertexBuffer)
        encoder.drawPrimitives(type: .lineStrip, vertexStart: 0, vertexCount: yzCircle.count)
        
        let xzBuffer = device.makeBuffer(length: MemoryLayout<SIMD3<Float>>.stride * xzCircle.count)
        let xzPtr = xzBuffer?.contents().bindMemory(to: SIMD3<Float>.self, capacity: xzCircle.count)
        xzPtr?.update(from: xzCircle, count: xzCircle.count)
        encoder.setVertexBuffer(xzBuffer, offset: 0, index: Bindings.vertexBuffer)
        encoder.drawPrimitives(type: .lineStrip, vertexStart: 0, vertexCount: xzCircle.count)
    }
    
    func subdivideClosedPolygon(polygon: [SIMD2<Float>], count: Int) -> [SIMD2<Float>]{
        if count == 0{
            return polygon
        }
        var newVerts: [SIMD2<Float>] = Array(repeating: SIMD2<Float>(repeating: 0.0), count: 2 * polygon.count)
        newVerts.replaceSubrange(0..<polygon.count, with: polygon)
        for i in 0..<polygon.count{
            newVerts[2*i] = 0.75 * polygon[i] + 0.25 * polygon[(i + 1) % polygon.count]
            newVerts[2*i+1] = 0.25 * polygon[i] + 0.75 * polygon[(i + 1) % polygon.count]
        }
        return subdivideClosedPolygon(polygon: newVerts, count: count - 1)
    }
    
    struct Ray {
        var origin: SIMD3<Float>
        var direction: SIMD3<Float>
    }
    
    func computeRayFromPixels(px: Float, py: Float, width: Float, height: Float) -> Ray {
        let editorProjection = self.editorCamera.projectionMatrix
        let editorView = self.editorCamera.lookAtMatrix()
        let xNDC: Float = (px - 0.5 * width) / (0.5 * width)
        let yNDC: Float = (py - 0.5 * height) / (0.5 * height)

        let rayStart = SIMD3<Float>(xNDC, yNDC, 0.0)
        let rayEnd = SIMD3<Float>(xNDC-0.001, yNDC, 1.0) // make it slightly not parallel
                
        let viewProjection = editorProjection * editorView
        let inverseViewProjection = simd_inverse(viewProjection)
        
        var worldStart = inverseViewProjection * SIMD4<Float>(rayStart, 1.0)
        var worldEnd = inverseViewProjection *  SIMD4<Float>(rayEnd, 1.0)

        worldStart /= worldStart.w
        worldEnd /= worldEnd.w
        
        let origin = SIMD3<Float>(worldStart.x, worldStart.y, worldStart.z)
        let direction = normalize(worldEnd - worldStart)[SIMD3<Int>(0, 1, 2)]
        
        return Ray(origin: origin, direction: direction)
    }

    func hover(px: Float, py: Float){
        self.mouseX = px
        self.mouseY = py
    }

    // TODO: convert to use a BVH tree
    // Cast a ray from the camera mouse click position into the screen and calculate
    // if it intersects with any objects in the scene.
    func AABBintersect(px: Float, py: Float){
        let io = ImGuiGetIO()!
        let wantsCaptureMouse = io.pointee.WantCaptureMouse
        if wantsCaptureMouse && !hoveringSceneWindow {
            return
        }
        if dragging {
            dragging = false
            return
        }
        let size = view.drawableSize
        let width = Float(size.width)
        let height = Float(size.height)

        let ray = computeRayFromPixels(px: px, py: py, width: width, height: height)

        let d = ray.direction
        let r = ray.origin
        
        // parametric equation of line p(t) = r + dt
        let minDist = Float.greatestFiniteMagnitude
        var selected: Node? = nil
        
        let nodes = scene.getNodes()
        
        for node in nodes {
            var bb: MDLAxisAlignedBoundingBox

            if node.nodeType == .model {
                let asset = assetManager.getAssetById(node.assetId!)
                bb = asset!.asset.boundingBox
            } else {
                bb = MDLAxisAlignedBoundingBox(maxBounds: SIMD3<Float>(-0.5, -0.5, -0.5), minBounds: SIMD3<Float>(0.5, 0.5, 0.5))
            }
            
            let transform = node.transform.getMatrix()
            let lWorld = transform * SIMD4<Float>(bb.minBounds, 1.0)
            let rWorld = transform * SIMD4<Float>(bb.maxBounds, 1.0)
            
            // parametric equation of line: p(t) = r + dt
            // parametric equation of the slab orthogonal to x-axis containing l: p(u, v) = l + (0, 0, 1)u + (0, 1, 0)v
            // r_x + d_xt = l_x
            let txLower: Float = (lWorld.x - r.x)/d.x
            let txHigher: Float = (rWorld.x - r.x)/d.x
            
            let txClose = min(txLower, txHigher)
            let txFar = max(txLower, txHigher)
            
            // intersection of slab orthogonal to y-axis
            let tyLower = (lWorld.y - r.y) / d.y
            let tyHigher = (rWorld.y - r.y) / d.y
            
            let tyClose = min(tyLower, tyHigher)
            let tyFar = max(tyLower, tyHigher)
            
            // intersection of slab orthogonal to z-axis
            let tzLower: Float = (lWorld.z - r.z) / d.z
            let tzHigher: Float = (rWorld.z - r.z) / d.z
            
            let tzClose = min(tzLower, tzHigher)
            let tzFar = max(tzLower, tzHigher)
            
            let tclose = max(txClose, tyClose, tzClose)
            let tfar = min(txFar, tyFar, tzFar)
            
            if tclose <= tfar {
                // ray intersects
                if tclose < minDist {
                    selected = node
                }
            }
        }
        self.selectedEntity = selected
    }
    
    func updateCameraTransform(deltaX: Float, deltaY: Float){
        // get x axis and y axis relative to camera in world space
        let cameraPos =  SIMD4<Float>(editorCamera.position, 1.0)
        let xAxis = SIMD4<Float>(1, 0, 0, 0)
        let yAxis = SIMD4<Float>(0, 1, 0, 0)
        let inverseView = self.editorCamera.lookAtMatrix().inverse
        
        let xWorld = inverseView * xAxis
        let yWorld = inverseView * yAxis
        
        let rotationX = matrix4x4_rotation(radians: radians_from_degrees(-deltaY), axis: SIMD3<Float>(xWorld.x, xWorld.y, xWorld.z))
        let rotationY = matrix4x4_rotation(radians: radians_from_degrees(-deltaX), axis: SIMD3<Float>(yWorld.x, yWorld.y, yWorld.z))
        let newCameraPos = rotationX * rotationY * cameraPos
        self.editorCamera.position = newCameraPos[SIMD3<Int>(0, 1, 2)]
    }
    
    func updateCameraTransform(zoom: Float){
        // translate along the forward vector relative to the camera in view space
        let editorCameraPosition = self.editorCamera.position
        let forward = normalize(-editorCameraPosition)
        let dist = zoom * forward
        let translation = matrix4x4_translation(dist.x, dist.y, dist.z)
        
        let pos = translation * SIMD4<Float>(editorCameraPosition, 1.0)
        self.editorCamera.position = pos[SIMD3<Int>(0, 1, 2)]
    }
    
    func mouseDragged(dx: Float, dy: Float){
        let io = ImGuiGetIO()!
        dragging = true
        let wantsCaptureMouse = io.pointee.WantCaptureMouse
        if wantsCaptureMouse && !hoveringSceneWindow {
            return
        }
        if(selectedEntity != nil){
            transformGizmo.invoke(deltaX: dx, deltaY: dy, editorCamera: self.editorCamera, selectedEntity: &selectedEntity!)
        }
    }
    
    func mouseDown(px: Float, py: Float){
        if let selected = selectedEntity {
            transformGizmo.setSelectedAxis(mouseX: mouseX, mouseY: mouseY, editorCamera: editorCamera, position: selected.transform.position)
        }
    }
}

