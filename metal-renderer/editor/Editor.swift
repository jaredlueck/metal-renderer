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
    var maskTexture: MTLTexture
    
    var moveToolTexture: MTLTexture
    var scaleToolTexture: MTLTexture
    var rotateToolTexture: MTLTexture
        
    var hoveringSceneWindow = false
    
    var xAxisSelected = false
    var yAxisSelected = false
    var zAxisSelected = false
    
    var dragging = false
    
    var editorCamera: Camera
    let transformGizmo: TransformGizmo
    var assetsWindow: AssetsWindow
    let transformPanel: TransformPanel
    var sceneArea: SceneArea
    
    var depthStencilStates: DepthStencilStates
    
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
        let size = view.bounds.size
        let width = Int(size.width)
        let height = Int(size.height)
        self.transformGizmo = TransformGizmo(device: device)
        
        assetsWindow = AssetsWindow(scene: scene)
        assetsWindow.loadAssetsFolder()
        
        transformPanel = TransformPanel(device: device)

        self.view = view
        self.scene = scene
        self.assetManager = assetManager
        self.sceneArea = SceneArea(scene: scene, assetManager: assetManager, pivot: ImVec2(x: 0, y: 0), position: ImVec2(x: 0, y: 0), size: ImVec2(x: Float(width), y: Float(height)))

        
        self.editorCamera = Camera(position: SIMD3<Float>(0, 1, 5), viewportSize: SIMD2<Float>(Float(width), Float(height)))
        let textureLoader = MTKTextureLoader(device: device)
        let pointlightIconTextureUrl = Bundle.main.url(forResource: "pointlight", withExtension: "png")!
        spotLightTexture = try! textureLoader.newTexture(URL: pointlightIconTextureUrl)
        
        let colorTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r32Float, width: Int(view.bounds.width), height: Int(view.bounds.height), mipmapped: false)
        colorTextureDescriptor.usage = [.shaderRead, .renderTarget]
        
        self.maskTexture = device.makeTexture(descriptor: colorTextureDescriptor)!

        let moveToolTextureUrl = Bundle.main.url(forResource: "movetool", withExtension: "png")!
        moveToolTexture = try! textureLoader.newTexture(URL: moveToolTextureUrl)

        let rotateToolTextureUrl = Bundle.main.url(forResource: "rotatetool", withExtension: "png")!
        rotateToolTexture = try! textureLoader.newTexture(URL: rotateToolTextureUrl)

        let scaleToolTextureUrl = Bundle.main.url(forResource: "scaletool", withExtension: "png")!
        scaleToolTexture = try! textureLoader.newTexture(URL: scaleToolTextureUrl)
        
        self.depthStencilStates = DepthStencilStates(device: device)
        
        transformPanel.onMovePressed = { self.transformGizmo.transformMode = .translate }
        transformPanel.onScalePressed = { self.transformGizmo.transformMode = .scale }
        
        _ = ImGuiCreateContext(nil)
        ImGuiStyleColorsDark(nil)
        ImGui_ImplMetal_Init(device) 
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

        encoder.setFragmentTexture(spotLightTexture, index: Int(TextureIndexAlbedo.rawValue))

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
    
    lazy var maskPassDescriptor: MTLRenderPassDescriptor = {
        var descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].storeAction = .store
        return descriptor
    }()

    lazy var editorHudPassDescriptor: MTLRenderPassDescriptor = {
        var descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].loadAction = .load
        descriptor.colorAttachments[0].storeAction = .store
        descriptor.depthAttachment.storeAction = .store
        descriptor.depthAttachment.loadAction = .load
        return descriptor
    }()
    
    func getFrameData() -> FrameData {
        let view = editorCamera.lookAtMatrix()
        let projection = editorCamera.projectionMatrix
        let inverseView = view.inverse
        let inverseProjection = projection.inverse
        let viewportSize = editorCamera.viewportSize
        
        let frameData = FrameData(view: view, projection: projection, inverseView: inverseView, inverseProjection: inverseProjection, cameraPosition: SIMD4<Float>(editorCamera.position, 1.0), viewportSize: viewportSize)
        return frameData
    }

    func encode(commandBuffer: MTLCommandBuffer) {
        let frameData = getFrameData()
        
        let maskPass = maskPassDescriptor
        maskPass.colorAttachments[0].texture = maskTexture
                
        editorHudPassDescriptor.colorAttachments[0].texture = self.view.currentDrawable?.texture
        editorHudPassDescriptor.depthAttachment.texture = self.view.depthStencilTexture
        
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: editorHudPassDescriptor) else {
            fatalError("Failed to create render command encoder")
        }
        
        encoder.setDepthStencilState(depthStencilStates.forwardPass)
        
//        encodeStage(using: <#T##MTLRenderCommandEncoder#>, label: <#T##String#>, <#T##() -> Void#>)
        
        self.gridPipeline.bind(encoder: encoder)
        
        withUnsafeBytes(of: frameData) { rawBuffer in
            encoder.setVertexBytes(rawBuffer.baseAddress!,
                                       length: MemoryLayout<FrameData>.stride,
                                       index: Int(BufferIndexFrameData.rawValue))
        }
        
        encoder.drawPrimitives(type: MTLPrimitiveType.triangle, vertexStart: 0, vertexCount: 6)
        
        let sceneLights = scene.getLights()

        for light in sceneLights {
            drawLightIcon(encoder: encoder, light: light)
        }
        
        if let node = selectedEntity,
           let radius = node.lightData?.radius {
            drawRadius(encoder: encoder, origin: node.transform.position, radius: radius)
        }
        
        encoder.endEncoding()
        
        if let selected = selectedEntity {
            if selected.nodeType == .model {
                guard let maskEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: maskPassDescriptor) else {
                    fatalError("Failed to create render command encoder")
                }
                maskEncoder.label = "Mask pass render encoder"
                
                withUnsafeBytes(of: frameData) { rawBuffer in
                    maskEncoder.setVertexBytes(rawBuffer.baseAddress!,
                                               length: MemoryLayout<FrameData>.stride,
                                               index: Int(BufferIndexFrameData.rawValue))
                }
                
                maskPipeline.bind(encoder: maskEncoder)
                let model = assetManager.getAssetById(selected.assetId!)!
                
                let instance = InstancedRenderable(device: device, model:model)
                let i = Instance(transform: selected.transform, material: selected.material)
                instance.addInstance(instance: i)
                instance.draw(renderEncoder: maskEncoder, instanceId: nil)
                maskEncoder.endEncoding()
                
//                encodeStage(using: <#T##MTLRenderCommandEncoder#>, label: <#T##String#>, <#T##() -> Void#>)
                guard let outlineEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: editorHudPassDescriptor) else {
                    fatalError("Failed to create render command encoder")
                }
                outlineEncoder.label = "Outline pass render encoder"
                
                outlinePipeline.bind(encoder: outlineEncoder)
                
                withUnsafeBytes(of: frameData) { rawBuffer in
                    outlineEncoder.setVertexBytes(rawBuffer.baseAddress!,
                                               length: MemoryLayout<FrameData>.stride,
                                               index: Int(BufferIndexFrameData.rawValue))
                }
                
                outlineEncoder.setFragmentTexture(maskTexture, index: Int(TextureIndexAlbedo.rawValue))

                outlineEncoder.drawPrimitives(type: MTLPrimitiveType.triangle, vertexStart: 0, vertexCount: 6)
                
                outlineEncoder.endEncoding()
            }
            guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: editorHudPassDescriptor) else {
                fatalError("Failed to create render command encoder")
            }
            self.uniformColorPipeline.bind(encoder: encoder)
            withUnsafeBytes(of: frameData) { rawBuffer in
                encoder.setVertexBytes(rawBuffer.baseAddress!,
                                           length: MemoryLayout<FrameData>.stride,
                                           index: Int(BufferIndexFrameData.rawValue))
            }
            transformGizmo.encode(encoder: encoder, mouseX: mouseX, mouseY: mouseY, editorCamera: editorCamera, position: selected.transform.position)
            encoder.endEncoding()
        }
        imGui(view: view, commandBuffer: commandBuffer)
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
    
    func imGui(view: MTKView, commandBuffer: MTLCommandBuffer){
        let imGuiRenderPassDescriptor = MTLRenderPassDescriptor()
        imGuiRenderPassDescriptor.colorAttachments[0].texture = view.currentDrawable!.texture
        imGuiRenderPassDescriptor.colorAttachments[0].loadAction = .load
        imGuiRenderPassDescriptor.depthAttachment.loadAction = .load
        
        imGuiRenderPassDescriptor.depthAttachment.texture = view.depthStencilTexture
        let imGuiEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: imGuiRenderPassDescriptor)!
        let io = ImGuiGetIO()!
        io.pointee.IniFilename = nil
        let viewWidth = Float(view.bounds.size.width)
        let viewHeight = Float(view.bounds.size.height)
        
        io.pointee.DisplaySize.x = Float(view.bounds.size.width)
        io.pointee.DisplaySize.y = Float(view.bounds.size.height)

        let frameBufferScale = Float(view.window?.screen?.backingScaleFactor ?? NSScreen.main!.backingScaleFactor)

        io.pointee.DisplayFramebufferScale = ImVec2(x: frameBufferScale, y: frameBufferScale)
        io.pointee.DeltaTime = 1.0 / Float(view.preferredFramesPerSecond)

        ImGui_ImplMetal_NewFrame(imGuiRenderPassDescriptor)
        ImGui_ImplOSX_NewFrame(view)
        ImGuiNewFrame()
        transformPanel.encode()
        
        var show_demo_window = true
        
        imGuiEncoder.setDepthStencilState(depthStencilStates.shadowGeneration)
        if let selected = selectedEntity, selected.nodeType == .model{
            ImGuiSetNextWindowPos(ImVec2(x: viewWidth - 10, y: 10), ImGuiCond(ImGuiCond_Always.rawValue), ImVec2(x: 1, y: 0))
            ImGuiSetNextWindowSize(ImVec2(x: 300, y: 325), 0)
            ImGuiBegin("Inspector", &show_demo_window, 0)
            if ImGuiCollapsingHeader("Material", Int32(ImGuiTreeNodeFlags_DefaultOpen.rawValue)){
                ImGuiTextV("Slider")
                if ImGuiSliderFloat("roughness", &selected.material.roughness, Float(0.0), Float(1.0), nil, Int32(ImGuiSliderFlags_None.rawValue)) {
                    
                }
                var a = Float(1.0)
                if ImGuiColorPicker4("baseColor", &selected.material.baseColor, Int32(ImGuiColorEditFlags_DisplayRGB.rawValue), &a){}
                var items: [Shader] = [.blinnPhong, .pbr]
                var currentIndex: Int = items.firstIndex(of: selected.material.shader)!
                // Begin the combo box with a label and the preview value
                if ImGuiBeginCombo("Shader", selected.material.shader.rawValue, 0) {
                    for i in 0..<items.count {
                        // Determine if this item is currently selected
                        var isSelected = (i == currentIndex)

                        // Render the item as selectable
                        if ImGuiSelectable(items[i].rawValue, &isSelected, 0, ImVec2()) {
                            currentIndex = i
                            selected.material.shader = items[i]
                        }
                        

                        // Optionally set default focus on the selected item for keyboard navigation
                        if isSelected {
                            ImGuiSetItemDefaultFocus()
                        }
                    }
                    ImGuiEndCombo()
                }

            }
            
            ImGuiEnd()
        }
            
        assetsWindow.encode()
        sceneArea.encode()

        ImGuiRender()
        let drawData = ImGuiGetDrawData()!

        ImGui_ImplMetal_RenderDrawData(drawData.pointee, commandBuffer, imGuiEncoder)
        imGuiEncoder.endEncoding()
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
        encoder.setVertexBytes(&transform, length: MemoryLayout<simd_float4x4>.stride , index: Int(BufferIndexInstanceData.rawValue))
        
        let xyBuffer = device.makeBuffer(length: MemoryLayout<SIMD3<Float>>.stride * xyCircle.count)
        let xyPtr = xyBuffer?.contents().bindMemory(to: SIMD3<Float>.self, capacity: xyCircle.count)
        xyPtr?.update(from: xyCircle, count: xyCircle.count)
        encoder.setVertexBuffer(xyBuffer, offset: 0, index: Int(BufferIndexVertex.rawValue))
        encoder.drawPrimitives(type: .lineStrip, vertexStart: 0, vertexCount: xyCircle.count)

        let yzBuffer = device.makeBuffer(length: MemoryLayout<SIMD3<Float>>.stride * yzCircle.count)
        let yzPtr = yzBuffer?.contents().bindMemory(to: SIMD3<Float>.self, capacity: yzCircle.count)
        yzPtr?.update(from: yzCircle, count: yzCircle.count)
        encoder.setVertexBuffer(yzBuffer, offset: 0, index: Int(BufferIndexVertex.rawValue))
        encoder.drawPrimitives(type: .lineStrip, vertexStart: 0, vertexCount: yzCircle.count)
        
        let xzBuffer = device.makeBuffer(length: MemoryLayout<SIMD3<Float>>.stride * xzCircle.count)
        let xzPtr = xzBuffer?.contents().bindMemory(to: SIMD3<Float>.self, capacity: xzCircle.count)
        xzPtr?.update(from: xzCircle, count: xzCircle.count)
        encoder.setVertexBuffer(xzBuffer, offset: 0, index: Int(BufferIndexVertex.rawValue))
        encoder.drawPrimitives(type: .lineStrip, vertexStart: 0, vertexCount: xzCircle.count)
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
        if wantsCaptureMouse && !sceneArea.hovered {
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
        var minDist = Float.greatestFiniteMagnitude
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
                    minDist = tclose
                }
            }
        }
        self.selectedEntity = selected
    }
    
    func updateTextures(size: CGSize){
        let colorTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r32Float, width: Int(size.width), height: Int(size.height), mipmapped: false)
        colorTextureDescriptor.usage = [.shaderRead, .renderTarget]
        self.maskTexture = device.makeTexture(descriptor: colorTextureDescriptor)!
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
        if wantsCaptureMouse && !sceneArea.hovered {
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

