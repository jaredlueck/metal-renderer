//
//  GameViewController.swift
//  metal-swift-new
//
//  Created by Jared Lueck on 2025-12-08.
//

import Cocoa
import MetalKit

// Our macOS specific view controller
class GameViewController: NSViewController {

    var renderer: Renderer!
    var mtkView: MTKView!
    var dragging = true
    
    override func viewDidLoad() {
        super.viewDidLoad()
                        
        // Select the device to render with.  We choose the default device
        guard let defaultDevice = MTLCreateSystemDefaultDevice() else {
            print("Metal is not supported on this device")
            return
        }
        
        let bounds = self.view.bounds

        let mtkView = MTKView(frame: bounds, device: defaultDevice)
        mtkView.autoresizingMask = [.width, .height]

        self.mtkView = mtkView
        self.view = mtkView


        guard let newRenderer = Renderer(metalKitView: mtkView) else {
            print("Renderer cannot be initialized")
            return
        }
        renderer = newRenderer

        renderer.mtkView(mtkView, drawableSizeWillChange: mtkView.drawableSize)
        
        let trackingArea = NSTrackingArea(rect: .zero,
                                          options: [.mouseMoved, .inVisibleRect, .activeAlways],
                                          owner: self,
                                          userInfo: nil)
        view.addTrackingArea(trackingArea)

        mtkView.delegate = renderer
        
        ImGui_ImplOSX_Init(view)

    }

    override func mouseUp(with event: NSEvent){
        print("MOUSEUP")
        ImGui_ImplOSX_HandleEvent(event, view)
        guard let mtkView = self.mtkView else { return }
        let windowPoint = event.locationInWindow
        let viewPoint = mtkView.convert(windowPoint, from: nil)

        let scale = mtkView.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1.0
        let pixelPoint = CGPoint(x: viewPoint.x * scale, y: viewPoint.y * scale)

        let px = Float(pixelPoint.x)
        let py = Float(pixelPoint.y)

        renderer.AABBintersect(px: px, py: py)
    }
    
    override func mouseDown(with event: NSEvent) {
        print("MOUSEDOWN")

        ImGui_ImplOSX_HandleEvent(event, view)
    }
    
    override func mouseMoved(with event: NSEvent) {
        ImGui_ImplOSX_HandleEvent(event, view)
    }
        
    override func mouseDragged(with event: NSEvent) {
        print("DRAGGED: event.deltaX: \(event.deltaX), event.deltaY: \(event.deltaY)")
        let scale = mtkView.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1.0
        let pixelPoint = CGPoint(x: event.deltaX * scale, y: event.deltaY * scale)
        let dx = Float(pixelPoint.x)
        let dy = -Float(pixelPoint.y)
        if(renderer.sharedResources.selectedRenderableInstance != nil){
            renderer.updateSelectedObjectTransform(deltaX: dx, deltaY: dy)
        }
        ImGui_ImplOSX_HandleEvent(event, view)
        
    }
    
    override func scrollWheel(with event: NSEvent) {
        let dx = event.scrollingDeltaX * 0.01
        let dy = event.scrollingDeltaY * 0.01
        renderer.updateCameraTransform(deltaX: Float(dx), deltaY: Float(dy))
    }
    
    override func magnify(with event: NSEvent) {
        let delta = Float(event.magnification)
        let zoom = delta * 1
        renderer.updateCameraTransform(zoom: zoom)
    }
}
