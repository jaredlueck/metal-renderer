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

class Editor {
    let outlineShaders: ShaderProgram
    let outlinePipeline: RenderPipeline
    
    let gridShaders: ShaderProgram
    let gridPipeline: RenderPipeline
    
    let uniformColorShader: ShaderProgram
    let uniformColorPipeline: RenderPipeline
    
    let device: MTLDevice
    let descriptor: MTLRenderPassDescriptor;
    
    let assetManager: AssetManager
    
    let view: MTKView
    
    private func makeArrowVertices(axis: SIMD3<Float>, normal: SIMD3<Float>, arrowSize: Float, arrowOffset: Float, radialSegments: Int = 6) -> [SIMD3<Float>] {
        // Build a 2D profile along the axis using the provided normal as thickness basis,
        // then sweep it around the axis by radialSegments to create a rotationally symmetric arrow.
        let ap0: SIMD3<Float> = (normal * 0.0) + (axis * 0.0)
        let ap1: SIMD3<Float> = (normal * 0.01) + (axis * 0.0)
        let ap2: SIMD3<Float> = (normal * 0.01) + (axis * arrowOffset)
        let ap3: SIMD3<Float> = (normal * 0.065) + (axis * arrowOffset)
        let ap4: SIMD3<Float> = (normal * 0.0) + (axis * (arrowOffset + arrowSize))
        let profile: [SIMD3<Float>] = [ap0, ap1, ap2, ap3, ap4]

        let tau: Float = 2.0 * .pi
        let delta: Float = tau / Float(radialSegments)
        var verts: [SIMD3<Float>] = []

        for k in 0..<radialSegments {
            let angle1: Float = Float(k) * delta
            let angle2: Float = Float(k + 1) * delta
            let rot1: simd_float4x4 = matrix4x4_rotation(radians: angle1, axis: axis)
            let rot2: simd_float4x4 = matrix4x4_rotation(radians: angle2, axis: axis)

            for i in 0..<(profile.count - 1) {
                let p0 = SIMD4<Float>(profile[i].x,     profile[i].y,     profile[i].z,     1.0)
                let p1 = SIMD4<Float>(profile[i+1].x,   profile[i+1].y,   profile[i+1].z,   1.0)

                let r10 = rot1 * p0
                let r20 = rot2 * p0
                let r11 = rot1 * p1
                let r21 = rot2 * p1

                // First triangle
                verts.append(SIMD3<Float>(r10.x, r10.y, r10.z))
                verts.append(SIMD3<Float>(r20.x, r20.y, r20.z))
                verts.append(SIMD3<Float>(r11.x, r11.y, r11.z))
                // Second triangle
                verts.append(SIMD3<Float>(r20.x, r20.y, r20.z))
                verts.append(SIMD3<Float>(r11.x, r11.y, r11.z))
                verts.append(SIMD3<Float>(r21.x, r21.y, r21.z))
            }
        }
        return verts
    }
    
    init(device: MTLDevice, view: MTKView){
        self.descriptor = MTLRenderPassDescriptor()
        self.descriptor.colorAttachments[0].loadAction = .load
        self.descriptor.colorAttachments[0].storeAction = .store
        self.descriptor.depthAttachment.loadAction = .load

        try! self.outlineShaders = ShaderProgram(device: device, descriptor: ShaderProgramDescriptor(vertexName: "outlineVertex", fragmentName: "outlineFragment"))
        self.outlinePipeline = RenderPipeline(device: device, program: self.outlineShaders, vertexDescriptor: nil, colorAttachmentPixelFormat: MTLPixelFormat.bgra8Unorm_srgb, depthAttachmentPixelFormat: MTLPixelFormat.depth32Float)
        
        try! self.gridShaders = ShaderProgram(device: device, descriptor: ShaderProgramDescriptor(vertexName: "gridVertex", fragmentName: "gridFragment"))
        self.gridPipeline = RenderPipeline(device: device, program: self.gridShaders, vertexDescriptor: nil, colorAttachmentPixelFormat: MTLPixelFormat.bgra8Unorm_srgb, depthAttachmentPixelFormat: MTLPixelFormat.depth32Float)
        
        try! self.uniformColorShader = ShaderProgram(device: device, descriptor: ShaderProgramDescriptor(vertexName: "uniformColorVertex", fragmentName: "uniformColorFragment"))
        self.uniformColorPipeline = RenderPipeline(device: device, program: self.uniformColorShader, vertexDescriptor: nil, colorAttachmentPixelFormat: MTLPixelFormat.bgra8Unorm_srgb, depthAttachmentPixelFormat: MTLPixelFormat.depth32Float)

        self.device = device
        
        self.assetManager = AssetManager(path: "/Users/jaredlueck/Documents/programming/metal-swift-new/metal-swift-new/assets")
        
        self.view = view
    }
    
    func encode(commandBuffer: MTLCommandBuffer, sharedResources: inout SharedResources){
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
        
        if let selected = sharedResources.selectedRenderableInstance {
            // Build arrows for X, Y, Z axes
            let arrowSize: Float = 0.35
            let arrowOffset: Float = 1.4

            // Define axis directions
            let xAxis = SIMD3<Float>(1, 0, 0)
            let yAxis = SIMD3<Float>(0, 1, 0)
            let zAxis = SIMD3<Float>(0, 0, 1)

            // Choose normals roughly perpendicular to each axis (not necessarily orthonormal; only used to define profile thickness)
            let xNormal = SIMD3<Float>(0, 1, 0)
            let yNormal = SIMD3<Float>(0, 0, 1)
            let zNormal = SIMD3<Float>(1, 0, 0)

            let xVerts = makeArrowVertices(axis: xAxis, normal: xNormal, arrowSize: arrowSize, arrowOffset: arrowOffset)
            let yVerts = makeArrowVertices(axis: yAxis, normal: yNormal, arrowSize: arrowSize, arrowOffset: arrowOffset)
            let zVerts = makeArrowVertices(axis: zAxis, normal: zNormal, arrowSize: arrowSize, arrowOffset: arrowOffset)

            self.uniformColorPipeline.bind(encoder: encoder)

            let selectedPosition = selected.transform.columns.3

            func drawArrow(verts: [SIMD3<Float>], color: SIMD3<Float>, extraTransform: simd_float4x4) {
                guard verts.count > 0 else { return }
                guard let vbuf = device.makeBuffer(length: MemoryLayout<SIMD3<Float>>.stride * verts.count, options: .storageModeShared) else { return }
                let vptr = vbuf.contents().bindMemory(to: SIMD3<Float>.self, capacity: verts.count)
                for i in 0..<verts.count { vptr[i] = verts[i] }
                encoder.setVertexBuffer(vbuf, offset: 0, index: Bindings.vertexBuffer)

                guard let ibuf = device.makeBuffer(length: MemoryLayout<matrix_float4x4>.stride, options: .storageModeShared) else { return }
                let iptr = ibuf.contents().bindMemory(to: matrix_float4x4.self, capacity: 1)
                let translate = matrix4x4_translation(selectedPosition.x, selectedPosition.y, selectedPosition.z)
                iptr[0] = translate * extraTransform
                encoder.setVertexBuffer(ibuf, offset: 0, index: Bindings.instanceData)

                var c = color
                encoder.setFragmentBytes(&c, length: MemoryLayout<SIMD3<Float>>.stride, index: Bindings.pipelineUniforms)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: verts.count)
            }

            let identity = matrix_identity_float4x4
            drawArrow(verts: xVerts, color: SIMD3<Float>(1, 0, 0), extraTransform: identity)
            drawArrow(verts: yVerts, color: SIMD3<Float>(0, 1, 0), extraTransform: identity)
            drawArrow(verts: zVerts, color: SIMD3<Float>(0, 0, 1), extraTransform: identity)
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
        
        // Example data and selection state (store these where appropriate in your type)

        var selectedIndex: Int32 = 0

        // Inside your ImGui window:
        if ImGuiBeginListBox("Fruits", ImVec2(x: 150, y: 100)) {
            for i in 0..<assetManager.assetURLs.count {
                let item = assetManager.assetURLs[i]
                var isSelected: Bool = (Int32(i) == selectedIndex)

                if ImGuiSelectable(item.lastPathComponent, &isSelected, 0, ImVec2(x: 0, y: 0) ) {
                    selectedIndex = Int32(i)
                }

                if ImGuiBeginDragDropSource(0) {
                    // Optional: show preview text while dragging
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
        
        ImGuiRender()
        let drawData = ImGuiGetDrawData()!

        ImGui_ImplMetal_RenderDrawData(drawData.pointee, commandBuffer, encoder)
    }
}

