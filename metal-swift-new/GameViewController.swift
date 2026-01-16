//
//  GameViewController.swift
//  metal-swift-new
//
//  Created by Jared Lueck on 2025-12-08.
//

import Cocoa
import MetalKit

class GameViewController: NSViewController {

    var renderer: Renderer!
    var mtkView: MTKView!
    var dragging = true
    var editor: Editor!
    override var acceptsFirstResponder: Bool { true }
    
    override func viewDidLoad() {
        super.viewDidLoad()
                        
        guard let defaultDevice = MTLCreateSystemDefaultDevice() else {
            print("Metal is not supported on this device")
            return
        }
        
        let bounds = self.view.bounds

        let mtkView = MTKView(frame: bounds, device: defaultDevice)
        mtkView.autoresizingMask = [.width, .height]

        self.mtkView = mtkView
        self.view = mtkView
        let device = mtkView.device!

        let url = URL(fileURLWithPath: "/Users/jaredlueck/Documents/programming/metal-swift-new/metal-swift-new/scene.json")
        let scene = try! JSONDecoder().decode(Scene.self, from: Data(contentsOf: url))
        let assetManager = AssetManager(device: device, assetFilePath: "assets.json")
        self.editor = Editor(device: device, view: self.mtkView, scene: scene, assetManager: assetManager)
        
        guard let newRenderer = Renderer(metalKitView: mtkView, scene: scene, editor: self.editor, assetManager: assetManager) else {
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
    
    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(self)
    }

    override func mouseUp(with event: NSEvent){
        ImGui_ImplOSX_HandleEvent(event, view)
        guard let mtkView = self.mtkView else { return }
        let windowPoint = event.locationInWindow
        let viewPoint = mtkView.convert(windowPoint, from: nil)

        let scale = mtkView.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1.0
        let pixelPoint = CGPoint(x: viewPoint.x * scale, y: viewPoint.y * scale)

        let px = Float(pixelPoint.x)
        let py = Float(pixelPoint.y)
        
        self.editor.AABBintersect(px: px, py: py)
    }
    
    override func mouseDown(with event: NSEvent) {
        ImGui_ImplOSX_HandleEvent(event, view)
    }
    
    override func mouseMoved(with event: NSEvent) {
        ImGui_ImplOSX_HandleEvent(event, view)
        guard let mtkView = self.mtkView else { return }
        let windowPoint = event.locationInWindow
        let viewPoint = mtkView.convert(windowPoint, from: nil)

        let scale = mtkView.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1.0
        let pixelPoint = CGPoint(x: viewPoint.x * scale, y: viewPoint.y * scale)

        let px = Float(pixelPoint.x)
        let py = Float(pixelPoint.y)
        
        editor.hover(px: px, py: py)
    }
        
    override func mouseDragged(with event: NSEvent) {
        let scale = mtkView.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1.0
        let pixelPoint = CGPoint(x: event.deltaX * scale, y: event.deltaY * scale)
        let dx = Float(pixelPoint.x)
        let dy = -Float(pixelPoint.y)
        if(editor.selectedEntity != nil){
            editor.updateSelectedObjectTransform(deltaX: dx, deltaY: dy)
        }
        ImGui_ImplOSX_HandleEvent(event, view)
    }
    
    override func scrollWheel(with event: NSEvent) {
        let dx = event.scrollingDeltaX * 0.01
        let dy = event.scrollingDeltaY * 0.01
        editor.updateCameraTransform(deltaX: Float(dx), deltaY: Float(dy))
    }
    
    override func magnify(with event: NSEvent) {
        let delta = Float(event.magnification)
        let zoom = delta * 1
        editor.updateCameraTransform(zoom: zoom)
    }
    
    override func keyDown(with event: NSEvent) {
        print("Keydown: \(event.keyCode)")
    }
}
