//
//  TransformGizmo.swift
//  metal-renderer
//
//  Created by Jared Lueck on 2026-01-25.
//

import Metal
import simd
import ImGui
import MetalKit

public class TransformGizmo {
    let xAxis: ArrowGizmo
    let yAxis: ArrowGizmo
    let zAxis: ArrowGizmo
    
    let xAxisColor = SIMD3<Float>(1,0,0)
    let yAxisColor = SIMD3<Float>(0,1,0)
    let zAxisColor = SIMD3<Float>(0,0,1)
    
    var transformMode: TransformMode = .translate
    
    var xAxisSelected: Bool = false
    var yAxisSelected: Bool = false
    var zAxisSelected: Bool = false
    
    var moveToolTexture: MTLTexture
    var rotateToolTexture: MTLTexture
    var scaleToolTexture: MTLTexture
    
    init(device: MTLDevice){
        self.xAxis = ArrowGizmo(device: device, rotation: matrix4x4_rotation(radians: radians_from_degrees(90), axis: SIMD3<Float>(0,1,0)), color: xAxisColor)
        self.yAxis = ArrowGizmo(device: device, rotation: matrix4x4_rotation(radians: radians_from_degrees(-90), axis: SIMD3<Float>(1,0,0)), color: yAxisColor)
        self.zAxis = ArrowGizmo(device: device, rotation: matrix_identity_float4x4, color: zAxisColor)
        
        let textureLoader = MTKTextureLoader(device: device)
        
//        let pointlightIconTextureUrl = Bundle.main.url(forResource: "pointlight", withExtension: "png")!
//        spotLightTexture = try! textureLoader.newTexture(URL: pointlightIconTextureUrl)

        let moveToolTextureUrl = Bundle.main.url(forResource: "movetool", withExtension: "png")!
        moveToolTexture = try! textureLoader.newTexture(URL: moveToolTextureUrl)

        let rotateToolTextureUrl = Bundle.main.url(forResource: "rotatetool", withExtension: "png")!
        rotateToolTexture = try! textureLoader.newTexture(URL: rotateToolTextureUrl)

        let scaleToolTextureUrl = Bundle.main.url(forResource: "scaletool", withExtension: "png")!
        scaleToolTexture = try! textureLoader.newTexture(URL: scaleToolTextureUrl)
        
        var error: NSError? = nil
        textureLoader.newTextures(URLs: [moveToolTextureUrl, rotateToolTextureUrl, scaleToolTextureUrl], error: &error)
    }
    
    func encode(encoder: MTLRenderCommandEncoder, mouseX: Float, mouseY: Float, editorCamera: Camera, position: SIMD3<Float>){
        let xAxisHovered = xAxis.testArrowSelected(position: position, mouseX: mouseX, mouseY: mouseY, editorCamera: editorCamera)
        xAxis.encode(encoder: encoder, position: position, editorCamera: editorCamera, selected: xAxisHovered, transformMode: transformMode)
    
        let yAxisHovered  = yAxis.testArrowSelected(position: position, mouseX: mouseX, mouseY: mouseY, editorCamera: editorCamera)
        yAxis.encode(encoder: encoder, position: position, editorCamera: editorCamera, selected: yAxisHovered, transformMode: transformMode)

        let zAxisHovered  = zAxis.testArrowSelected(position: position, mouseX: mouseX, mouseY: mouseY, editorCamera: editorCamera)
        zAxis.encode(encoder: encoder, position: position, editorCamera: editorCamera, selected: zAxisHovered, transformMode: transformMode)
        
        ImGuiSetNextWindowPos(ImVec2(x: 10, y: 200), 0, ImVec2(x: 0, y: 0))
        var show = true
        ImGuiBegin("gizmos", &show, Int32(ImGuiWindowFlags_NoTitleBar.rawValue))
        withUnsafePointer(to: &moveToolTexture) { ptr in
            let raw = UnsafeMutableRawPointer(mutating: ptr)
            if ImGuiImageButton("Move Tool", raw, ImVec2(x: 15, y: 15), ImVec2(x: 0.1, y: 0.1), ImVec2(x: 0.9, y: 0.9), ImVec4(x: 0, y: 0, z: 0, w: 0), ImVec4(x: 1, y: 1, z: 1, w: 1)) {
                transformMode = .translate
            }
            if ImGuiIsItemHovered(0) {
                ImGuiBeginTooltip()
                ImGuiTextV("Move Tool")
                ImGuiEndTooltip()
            }
        }
        
        withUnsafePointer(to: &rotateToolTexture) { ptr in
            let raw = UnsafeMutableRawPointer(mutating: ptr)
            if ImGuiImageButton("Rotate Tool", raw, ImVec2(x: 15, y: 15), ImVec2(x: 0.1, y: 0.1), ImVec2(x: 0.9, y: 0.9), ImVec4(x: 0, y: 0, z: 0, w: 0), ImVec4(x: 1, y: 1, z: 1, w: 1)) {
                transformMode = .rotate
            }
            if ImGuiIsItemHovered(0) {
                ImGuiBeginTooltip()
                ImGuiTextV("Rotate Tool")
                ImGuiEndTooltip()
            }
        }

        withUnsafePointer(to: &scaleToolTexture) { ptr in
            let raw = UnsafeMutableRawPointer(mutating: ptr)
            if ImGuiImageButton("Scale Tool", raw, ImVec2(x: 15, y: 15), ImVec2(x: 0.1, y: 0.1), ImVec2(x: 0.9, y: 0.9), ImVec4(x: 0, y: 0, z: 0, w: 0), ImVec4(x: 1, y: 1, z: 1, w: 1)) {
                transformMode = .scale
            }
            if ImGuiIsItemHovered(0) {
                ImGuiBeginTooltip()
                ImGuiTextV("Scale Tool")
                ImGuiEndTooltip()
            }
        }
        ImGuiEnd()
    }
    
    func setSelectedAxis(mouseX: Float, mouseY: Float, editorCamera: Camera, position: SIMD3<Float>){
        if xAxisSelected || yAxisSelected || zAxisSelected {return}
        if xAxis.testArrowSelected(position: position, mouseX: mouseX, mouseY: mouseY, editorCamera: editorCamera){
            xAxisSelected = true
        } else if yAxis.testArrowSelected(position: position, mouseX: mouseX, mouseY: mouseY, editorCamera: editorCamera){
            yAxisSelected = true
        } else if zAxis.testArrowSelected(position: position, mouseX: mouseX, mouseY: mouseY, editorCamera: editorCamera){
            zAxisSelected = true
        }
    }
    
    func clearSelection(){
        xAxisSelected = false
        yAxisSelected = false
        zAxisSelected = false
    }
    
    func invoke(deltaX: Float, deltaY: Float, editorCamera: Camera, selectedEntity: inout Node){
        if !xAxisSelected && !yAxisSelected && !zAxisSelected{
            return
        }
        // update the object position in the xy plane relative to the camera
        let screenDirection = SIMD4<Float>(deltaX, deltaY, 0.0, 0.0)
        
        let width = editorCamera.viewportSize.x
        let height = editorCamera.viewportSize.y
        // convert pixel deltas to deltas in NDC space
        let dxNDC = (2.0 / width) * deltaX
        let dyNDC = (2.0 / height) * deltaY
        
        let view = editorCamera.lookAtMatrix()
        let projection = editorCamera.projectionMatrix
        
        let inverseView = view.inverse
        let inverseProjection = projection.inverse
        
        let selectedObj = selectedEntity
        
        // get object depth in clip space
        let objPositionWorld = SIMD4(selectedObj.transform.position, 1.0)
        let objClip = projection * view * objPositionWorld
        let wClip = objClip.w
        // add NDC offsets scaled by w
        let objOffset = SIMD4<Float>(objClip.x + dxNDC * wClip, objClip.y + dyNDC * wClip, objClip.z, wClip)

        // project back to world space and calculate difference in position
        let objWorldOffset = inverseView * inverseProjection * objOffset

        let diff = objWorldOffset - objPositionWorld
        var proj = SIMD3<Float>(0.0, 0.0, 0.0)

        if xAxisSelected {
            proj.x = diff.x
        }
        else if yAxisSelected {
            proj.y = diff.y
        }
        else if zAxisSelected {
            proj.z = diff.z
        }
        // update the transform with translation
        if transformMode == .translate {
            selectedObj.transform.position = selectedObj.transform.position + proj
        } else {
            selectedObj.transform.scale = selectedObj.transform.scale + proj
        }
    }
    
    func setTransformMode(_ mode: TransformMode){
        self.transformMode = mode
    }
}
