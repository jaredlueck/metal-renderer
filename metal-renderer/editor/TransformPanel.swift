//
//  TransformPanel.swift
//  metal-renderer
//
//  Created by Jared Lueck on 2026-01-29.
//

import ImGui
import MetalKit

public class TransformPanel {
    var windowVisible: Bool = true
    
    var onMovePressed: (() -> Void)?
    var onRotatePressed: (() -> Void)?
    var onScalePressed: (() -> Void)?
    
    var moveToolTexture: MTLTexture
    var scaleToolTexture: MTLTexture
    var rotateToolTexture: MTLTexture
    
    init(device: MTLDevice) {
        let textureLoader = MTKTextureLoader(device: device)
        let moveToolTextureUrl = Bundle.main.url(forResource: "movetool", withExtension: "png")!
        moveToolTexture = try! textureLoader.newTexture(URL: moveToolTextureUrl)

        let rotateToolTextureUrl = Bundle.main.url(forResource: "rotatetool", withExtension: "png")!
        rotateToolTexture = try! textureLoader.newTexture(URL: rotateToolTextureUrl)

        let scaleToolTextureUrl = Bundle.main.url(forResource: "scaletool", withExtension: "png")!
        scaleToolTexture = try! textureLoader.newTexture(URL: scaleToolTextureUrl)
    }
    
    func encode(){
        ImGuiSetNextWindowPos(ImVec2(x: 10, y: 200), 1 << 1, ImVec2(x: 0, y: 0))
        ImGuiBegin("gizmos", &windowVisible, Int32(ImGuiWindowFlags_NoTitleBar.rawValue))
        withUnsafePointer(to: &moveToolTexture) { ptr in
            let raw = UnsafeMutableRawPointer(mutating: ptr)
            if ImGuiImageButton("Move Tool", raw, ImVec2(x: 15, y: 15), ImVec2(x: 0.1, y: 0.1), ImVec2(x: 0.9, y: 0.9), ImVec4(x: 0, y: 0, z: 0, w: 0), ImVec4(x: 1, y: 1, z: 1, w: 1)) {
                onMovePressed!()
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
                onRotatePressed!()
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
                onScalePressed!()
            }
            if ImGuiIsItemHovered(0) {
                ImGuiBeginTooltip()
                ImGuiTextV("Scale Tool")
                ImGuiEndTooltip()
            }
        }
        ImGuiEnd()
    }
}
