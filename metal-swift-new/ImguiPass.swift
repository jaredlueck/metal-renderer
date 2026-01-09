//
//  ImguiPass.swift
//  metal-swift-new
//
//  Created by Jared Lueck on 2026-01-06.
//
import Metal
import simd
import ImGui
import MetalKit

class ImguiPass {

    let device: MTLDevice
    let descriptor: MTLRenderPassDescriptor;
    
    var show_demo_window = true
    
    init(device: MTLDevice){
        self.descriptor = MTLRenderPassDescriptor()
        self.descriptor.colorAttachments[0].loadAction = .load
        self.descriptor.colorAttachments[0].storeAction = .store
        self.device = device
    }
    
    func encode(commandBuffer: MTLCommandBuffer, sharedResources: inout SharedResources){
        self.descriptor.colorAttachments[0].texture = sharedResources.colorBuffer
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor:  self.descriptor) else {
            fatalError("Failed to create render command encoder")
        }
        
        let view = sharedResources.view
        
        let io = ImGuiGetIO()!

        io.pointee.DisplaySize.x = Float(view.bounds.size.width)
        io.pointee.DisplaySize.y = Float(view.bounds.size.height)

        let frameBufferScale = Float(view.window?.screen?.backingScaleFactor ?? NSScreen.main!.backingScaleFactor)

        io.pointee.DisplayFramebufferScale = ImVec2(x: frameBufferScale, y: frameBufferScale)
        io.pointee.DeltaTime = 1.0 / Float(view.preferredFramesPerSecond)
                
        ImGui_ImplMetal_NewFrame(self.descriptor)
        ImGui_ImplOSX_NewFrame(sharedResources.view)
        ImGuiNewFrame()
        ImGuiSetNextWindowPos(ImVec2(x: 10, y: 10), 1 << 1, ImVec2(x: 0, y: 0))
 
        ImGuiBegin("Begin", &show_demo_window, 0)

        // Display some text (you can use a format strings too)
        ImGuiTextV("This is some useful text.")

        // Edit bools storing our window open/close state
        ImGuiSliderFloat("Float Slider", &f, 0.0, 1.0, nil, 1) // Edit 1 float using a slider from 0.0f to 1.0f

        ImGuiColorEdit3("clear color", &clear_color, 0) // Edit 3 floats representing a color

        if ImGuiButton("Button", ImVec2(x: 100, y: 20)) { // Buttons return true when clicked (most widgets return true when edited/activated)
            counter += 1
        }

        ImGuiEnd()
        
        ImGuiRender()
        let drawData = ImGuiGetDrawData()!

        ImGui_ImplMetal_RenderDrawData(drawData.pointee, commandBuffer, encoder)
        encoder.endEncoding()
    }
}
