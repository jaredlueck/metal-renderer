//
//  OutlineRenderPass.swift
//  metal-swift-new
//
//  Created by Jared Lueck on 2026-01-01.
//

import Metal
import simd
import ImGui
import MetalKit

class AxisGizmo {
    var xbb: MDLAxisAlignedBoundingBox
    var xhovered = false
    var ybb: MDLAxisAlignedBoundingBox
    var yHovered = false
    var zbb: MDLAxisAlignedBoundingBox
    var zHovere = false
    
    init(xVerts: [SIMD3<Float>], yVerts: [SIMD3<Float>], zVerts: [SIMD3<Float>]){
        self.xbb = Editor.computeBoundingBox(vertices: xVerts)
        self.ybb = Editor.computeBoundingBox(vertices: yVerts)
        self.zbb = Editor.computeBoundingBox(vertices: zVerts)
    }
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
    
    let device: MTLDevice
    let descriptor: MTLRenderPassDescriptor;
    
    let hudRenderPassDescriptor: MTLRenderPassDescriptor
        
    let view: MTKView
    
    let scene: Scene
    let assetManager: AssetManager
    
    var editorView: simd_float4x4 = matrix_identity_float4x4
    var editorProjection: simd_float4x4 = matrix_identity_float4x4
    var editorCameraPosition = SIMD3<Float>(0.0, 4.0, 5)
    
    var selectedEntity: Node? = nil
    var axisGizmo: AxisGizmo? = nil
    
    var mouseX: Float = 0.0
    var mouseY: Float = 0.0
    
    var assetURLs: [URL]
    
    func distance(p1: SIMD2<Float>, p2: SIMD2<Float>, x: SIMD2<Float>) -> Float {
        return abs((p2[1] - p1[1])*x[0] - (p2[0] - p1[0])*x[1] + p2[0]*p1[1] - p2[1]*p1[0])/sqrt((p1[1]-p2[1])*(p1[1]-p2[1]) + (p1[0]-p2[0])*(p1[0]-p2[0]))
    }
    
    func distance(p1: SIMD2<Float>, p2: SIMD2<Float>) -> Float{
        return sqrt((p1[1]-p2[1])*(p1[1]-p2[1]) + (p1[0]-p2[0])*(p1[0]-p2[0]))
    }
    
    func testArrowSelected(transform: simd_float4x4) -> Bool {
        let size = view.drawableSize
        let width = Float(size.width)
        let height = Float(size.height)
    
        let head_center_z: Float = (0.974306 + 1.268098) / 2;
//        let head_geo_x: Float = 0.051304;
//        let stem_geo_x: Float = 0.012320;
        
        let arrowBegin = SIMD3<Float>(0, 0, 0)
        let arrowEnd = SIMD3<Float>(0, 0, 0.974306)
        
        // mouse in pixel space
        let pMouse = SIMD2<Float>(mouseX, mouseY)
        
        let arrowHead = SIMD3<Float>(0, 0, head_center_z)
        
        let mvp = editorProjection * editorView * transform
        
        var arrowHeadCenterNDC: SIMD4<Float> = mvp * SIMD4<Float>(0, 0, head_center_z, 1.0)
        arrowHeadCenterNDC /= arrowHeadCenterNDC.w
        let pArrowHeadCenter = SIMD2<Float>((arrowHeadCenterNDC[0] + 1.0) * (width/2.0), (arrowHeadCenterNDC[1] + 1.0) * (height/2.0))
        
        let arrowHeadSelectThreshold: Float = 8.0
        
        if distance(p1: pMouse, p2: pArrowHeadCenter) < arrowHeadSelectThreshold {
            return true
        }
        
        // project to pixel space
        var arrowBeginNDC = mvp  * SIMD4<Float>(arrowBegin, 1.0)
        var arrowEndNDC = mvp * SIMD4<Float>(arrowEnd, 1.0)
        var arrowHeadNDC = mvp * SIMD4<Float>(arrowHead, 1.0)
        
        arrowBeginNDC /= arrowBeginNDC.w
        arrowEndNDC /= arrowEndNDC.w
        arrowHeadNDC /= arrowHeadNDC.w
        // arrow start and end in pixel space
        let pArrowBegin = SIMD2<Float>((arrowBeginNDC[0] + 1.0) * (width/2.0), (arrowBeginNDC[1] + 1.0) * (height/2.0))
        let pArrowEnd = SIMD2<Float>((arrowEndNDC[0] + 1.0) * (width/2.0), (arrowEndNDC[1] + 1.0) * (height/2.0))
        let arrowLength = distance(p1: pArrowBegin, p2: pArrowEnd)
 
        // unit vector from the start to the end of the arrow stem
        let vArrowStem = normalize(pArrowEnd - pArrowBegin)
        // vector from the start point of the arrow to the mouse position
        let vArrowBeginMouse = SIMD2<Float>(mouseX, mouseY) - pArrowBegin
        // vector from the end point of the mouse to the mouse position
        let vArrowEndMouse = SIMD2<Float>(mouseX, mouseY) - pArrowEnd
        
        let distBegin = distance(p1: pArrowBegin, p2: pMouse)
        let distEnd = distance(p1: pArrowEnd, p2: pMouse)
        // projection of the vector from arrow start to the mouse onto the line segment
        let projBeg = dot(vArrowBeginMouse, vArrowStem)
        // projection of the vector from arrow end to the mouse onto the line segment
        let projEnd = dot(vArrowEndMouse, -vArrowStem)
        
        let stemSelectThreshold: Float = 5.0
        
        // The shortest distance from the mouse point to the stem is not on the line segment if the
        // projections from both sides of the segment are greater than the total length of the line segment
        if projBeg > arrowLength || projEnd > arrowLength{
            return min(distEnd, distBegin) < stemSelectThreshold
        }
        
        // the shortest distance is on the vector perpendicular from the mouse to the line segment
        return distance(p1: pArrowBegin, p2: pArrowEnd, x: pMouse) < stemSelectThreshold
    }

    func drawArrow(encoder: MTLRenderCommandEncoder, verts: [SIMD3<Float>], indices: [UInt16], transform: simd_float4x4, color: SIMD3<Float>) {
        let selected = testArrowSelected(transform: transform)
        let colorFactor: Float = selected ? 1.25 : 1.0
        let scale: Float = selected ? 1.1 : 1.0
        let transformWithScale = transform * matrix4x4_scale(scaleX: scale, scaleY: scale, scaleZ: scale)
        guard verts.count > 0 else { return }
        guard let vbuf = device.makeBuffer(length: MemoryLayout<SIMD3<Float>>.stride * verts.count, options: .storageModeShared) else { return }
        let vptr = vbuf.contents().bindMemory(to: SIMD3<Float>.self, capacity: verts.count)
        for i in 0..<verts.count { vptr[i] = verts[i] }
        encoder.setVertexBuffer(vbuf, offset: 0, index: Bindings.vertexBuffer)

        guard let ibuf = device.makeBuffer(length: MemoryLayout<matrix_float4x4>.stride, options: .storageModeShared) else { return }
        let iptr = ibuf.contents().bindMemory(to: matrix_float4x4.self, capacity: 1)
        iptr[0] = transformWithScale
        encoder.setVertexBuffer(ibuf, offset: 0, index: Bindings.instanceData)
        
        guard let indexBuffer = device.makeBuffer(length: MemoryLayout<UInt16>.stride * indices.count , options: .storageModeShared) else { return }
        let iptr2 = indexBuffer.contents().bindMemory(to: UInt16.self, capacity: indices.count)
        for i in 0..<indices.count { iptr2[i] = indices[i] }

        var c = color * colorFactor
        encoder.setFragmentBytes(&c, length: MemoryLayout<SIMD3<Float>>.stride, index: Bindings.pipelineUniforms)
        encoder.drawIndexedPrimitives(type: .triangle, indexCount: indices.count, indexType: MTLIndexType.uint16, indexBuffer: indexBuffer, indexBufferOffset: 0)
    }

    init(device: MTLDevice, view: MTKView, scene: Scene, assetManager: AssetManager){
        self.descriptor = MTLRenderPassDescriptor()
        self.descriptor.colorAttachments[0].loadAction = .load
        self.descriptor.colorAttachments[0].storeAction = .store
        self.descriptor.depthAttachment.loadAction = .load
        
        self.hudRenderPassDescriptor = MTLRenderPassDescriptor()
        hudRenderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor.init(red: 0, green: 0, blue: 0, alpha: 1)
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

        self.device = device
        
        let assetsURL = Bundle.main.bundleURL.appending(component: "Contents/Resources")
        
        assetURLs = Self.getAssetUrls(path: assetsURL.path)
        
        self.view = view
        self.scene = scene
        scene.addLight(position: SIMD3<Float>(0.0, 1.0, 0.0), color: SIMD3<Float>(1.0, 1.0, 1.0), radius: 10.0)
        self.assetManager = assetManager
        self.editorView = matrix_lookAt(eye: editorCameraPosition, target: SIMD3<Float>(0, 0, 0), up: SIMD3<Float>(0, 1, 0))
        let size = view.bounds.size
        let width = Int(size.width)
        let height = Int(size.height)
        let aspect = Float(width) / Float(height)
        self.editorProjection = matrix_perspective_right_hand(fovyRadians: radians_from_degrees(65), aspectRatio:aspect, nearZ: 0.01, farZ: 100.0)
    }
    
    static func getAssetUrls(path: String) -> [URL] {
        let dirURL = URL(fileURLWithPath: path)
        let filemanager = FileManager.default
        do {
            let urls = try filemanager.contentsOfDirectory(
                at: dirURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )

            let assetURLs = try urls.filter { url in
                let rv = try url.resourceValues(forKeys: [.isDirectoryKey])
                return rv.isDirectory != true
            }
            return assetURLs
        } catch {
            print("Failed to list contents of \(dirURL): \(error)")
            return []
        }
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
            self.maskPipeline.bind(encoder: encoder)
                        
            let model = assetManager.getAssetById(selected.assetId!)!
            
            let instance = InstancedRenderable(device: device, model:model)
            instance.addInstance(transform: selected.transform.value)
            
            instance.draw(renderEncoder: encoder, instanceId: nil)
        }
        encoder.endEncoding()
    }

    func renderUI(commandBuffer: MTLCommandBuffer, sharedResources: inout SharedResources){
        self.descriptor.colorAttachments[0].texture = sharedResources.colorBuffer
        self.descriptor.depthAttachment.texture = sharedResources.depthBuffer
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: self.descriptor) else {
            fatalError("Failed to create render command encoder")
        }
        encoder.label = "mask outline encoder"
        
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
        
        if let selected = selectedEntity {
            self.uniformColorPipeline.bind(encoder: encoder)

            let translation = selected.transform.value
            
            let vertices = Gizmo.verts
            let indices = Gizmo.indices
            
            let zTransform = translation * matrix_identity_float4x4
            let xTransform = translation * matrix4x4_rotation(radians: radians_from_degrees(90), axis: SIMD3(0, 1, 0))
            let yTransform = translation * matrix4x4_rotation(radians: radians_from_degrees(-90), axis: SIMD3(1, 0, 0))
            let selected = testArrowSelected(transform: xTransform)
            print(selected)
            drawArrow(encoder: encoder, verts: vertices, indices: indices, transform: xTransform, color: SIMD3<Float>(0.5, 0, 0))
            drawArrow(encoder: encoder, verts: vertices, indices: indices, transform: yTransform, color: SIMD3<Float>(0, 0.5, 0))
            drawArrow(encoder: encoder, verts: vertices, indices: indices, transform: zTransform, color: SIMD3<Float>(0, 0, 0.5))
        }

        encoder.setDepthStencilState(sharedResources.depthStencilStateEnabled)
        imGui(view: view, commandBuffer: commandBuffer, encoder: encoder)
        encoder.endEncoding()
    }
    
    func imGui(view: MTKView, commandBuffer: MTLCommandBuffer, encoder: MTLRenderCommandEncoder){
        let io = ImGuiGetIO()!

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
        ImGuiBegin("Begin", &show_demo_window, 0)
        
        var selectedIndex: Int32 = 0

        if ImGuiBeginListBox("Fruits", ImVec2(x: 150, y: 100)) {
            for i in 0..<self.assetURLs.count {
                let item = self.assetURLs[i]
                var isSelected: Bool = (Int32(i) == selectedIndex)

                if ImGuiSelectable(item.lastPathComponent, &isSelected, 0, ImVec2(x: 0, y: 0) ) {
                    selectedIndex = Int32(i)
                }
                if ImGuiBeginDragDropSource(0) {
                    ImGuiTextV("Dragging \(item.lastPathComponent)")
                    var index = Int32(i)
                    withUnsafePointer(to: &index) { ptr in
                        let rawPtr = UnsafeRawPointer(ptr)
                        ImGuiSetDragDropPayload("LIST_ITEM_INDEX", rawPtr, MemoryLayout<Int32>.size, 0)
                    }
                    ImGuiEndDragDropSource()
                }
                if isSelected {
                    ImGuiSetItemDefaultFocus()
                }
            }
            ImGuiEndListBox()
        }
        ImGuiEnd()
        
        if(selectedEntity != nil) {
            ImGuiBegin("Transform", &show_demo_window, 0)
            ImGuiSetWindowFontScale(0.3)
            ImGuiButton("translation", ImVec2(x: 30, y: 30))
            let flags = Int32(ImGuiButtonFlags_PressedOnClick.rawValue)
            ImGuiButtonEx("translation", ImVec2(x: 30, y: 30), flags)
            ImGuiButton("scale", ImVec2(x: 30, y: 30))
            ImGuiButton("rotation", ImVec2(x: 30, y: 30))
            ImGuiEnd()
        }

        ImGuiSetNextWindowPos(ImVec2(x: 150, y: 150), 1 << 1, ImVec2(x: 0, y: 0))
        ImGuiSetNextWindowSize(ImVec2(x: 100, y: 100), 0)
        
        ImGuiBegin("Scene area", &show_demo_window, 0 )
        
        var size = ImVec2()
        ImGuiGetContentRegionAvail(&size)
        ImGuiInvisibleButton("SceneDropZone", size, 0);

        if ImGuiBeginDragDropTarget() {
            if let payload = ImGuiAcceptDragDropPayload("LIST_ITEM_INDEX", 0) {
                let raw = payload.pointee.Data
                let index = raw!.bindMemory(to: Int32.self, capacity: 1).pointee
                let assetUrl = self.assetURLs[Int(index)]
                let filename = assetUrl.lastPathComponent
                let assetId = self.assetManager.loadAssetAtPath(filename)
                scene.add(Node(nodeType: .model, transform: matrix_identity_float4x4, assetId: assetId))
            }
            ImGuiEndDragDropTarget()
        }
        ImGuiEnd()
        ImGuiRender()
        let drawData = ImGuiGetDrawData()!

        ImGui_ImplMetal_RenderDrawData(drawData.pointee, commandBuffer, encoder)
    }
    
    static func computeBoundingBox(vertices: [SIMD3<Float>]) -> MDLAxisAlignedBoundingBox{
        var minx = Float.infinity
        var miny = Float.infinity
        var minz = Float.infinity
        var maxx = -Float.infinity
        var maxy = -Float.infinity
        var maxz = -Float.infinity
        
        for vertex in vertices{
            minx = min(minx, vertex.x)
            miny = min(miny, vertex.y)
            minz = min(minz, vertex.z)

            maxx = max(maxx, vertex.x)
            maxy = max(maxy, vertex.y)
            maxz = max(maxz, vertex.z)
        }
        return MDLAxisAlignedBoundingBox(maxBounds: SIMD3<Float>(maxx, maxy, maxz), minBounds: SIMD3<Float>(minx, miny, minz))
    }
    
    struct Ray {
        var origin: SIMD3<Float>
        var direction: SIMD3<Float>
    }
    
    func computeRayFromPixels(px: Float, py: Float, width: Float, height: Float) -> Ray {
        let xNDC: Float = (px - 0.5 * width) / (0.5 * width)
        let yNDC: Float = (py - 0.5 * height) / (0.5 * height)

        let rayStart = SIMD3<Float>(xNDC, yNDC, 0.0)
        let rayEnd = SIMD3<Float>(xNDC-0.001, yNDC, 1.0) // make it slightly not parallel
                
        let viewProjection = self.editorProjection * self.editorView
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
            let asset = assetManager.getAssetById(node.assetId!)
            let bb = asset!.asset.boundingBox
            
            let transform = node.transform.value
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
        let xAxis = SIMD4<Float>(1, 0, 0, 0)
        let yAxis = SIMD4<Float>(0, 1, 0, 0)
        let inverseView = self.editorView.inverse
        
        let xWorld = inverseView * xAxis
        let yWorld = inverseView * yAxis
        
        let rotationX = matrix4x4_rotation(radians: radians_from_degrees(-deltaY), axis: SIMD3<Float>(xWorld.x, xWorld.y, xWorld.z))
        let rotationY = matrix4x4_rotation(radians: radians_from_degrees(-deltaX), axis: SIMD3<Float>(yWorld.x, yWorld.y, yWorld.z))
        let pos = SIMD4<Float>(self.editorCameraPosition, 1.0)
        let newCameraPos = rotationX * rotationY * pos
        self.editorView = matrix_lookAt(eye: newCameraPos[SIMD3<Int>(0, 1, 2)], target: SIMD3<Float>(0, 0, 0), up: SIMD3<Float>(0, 1, 0))
        self.editorCameraPosition = newCameraPos[SIMD3<Int>(0, 1, 2)]
    }
    
    func updateCameraTransform(zoom: Float){
        // translate along the forward vector relative to the camera in view space
        let forward = normalize(-self.editorCameraPosition)
        let dist = zoom * forward
        let translation = matrix4x4_translation(dist.x, dist.y, dist.z)
        
        let pos = translation * SIMD4<Float>(self.editorCameraPosition, 1.0)
        self.editorView = matrix_lookAt(eye: self.editorCameraPosition, target: SIMD3<Float>(0, 0, 0), up: SIMD3<Float>(0, 1, 0))
        self.editorCameraPosition = pos[SIMD3<Int>(0, 1, 2)]
    }
    
    func updateSelectedObjectTransform(deltaX: Float, deltaY: Float){
        // update the object position in the xy plane relative to the camera
        let size = view.drawableSize
        let width = Float(size.width)
        let height = Float(size.height)
        // convert pixel deltas to deltas in NDC space
        let dxNDC = (2.0 / width) * deltaX
        let dyNDC = (2.0 / height) * deltaY
        
        let view = self.editorView
        let projection = self.editorProjection
        
        let inverseView = view.inverse
        let inverseProjection = projection.inverse
        
        let selectedObj = self.selectedEntity!
        
        // get object depth in clip space
        let objPositionWorld = selectedObj.transform.value.columns.3
        let objClip = projection * view * objPositionWorld
        let wClip = objClip.w
        // add NDC offsets scaled by w
        let objOffset = SIMD4<Float>(objClip.x + dxNDC * wClip, objClip.y + dyNDC * wClip, objClip.z, wClip)
        
        // project back to world space and calculate difference in position
        let objWorldOffset = inverseView * inverseProjection * objOffset
        
        let diff = objWorldOffset - objPositionWorld
        
        // update the transform with translation
        let transform = matrix4x4_translation(diff.x, diff.y, diff.z)
        let newTransform = transform * selectedObj.transform.value
        selectedObj.transform.value = newTransform
    }
}

