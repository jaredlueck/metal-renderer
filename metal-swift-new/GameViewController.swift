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
    var frame: CGRect!

    override func viewDidLoad() {
        super.viewDidLoad()
                        
        // Select the device to render with.  We choose the default device
        guard let defaultDevice = MTLCreateSystemDefaultDevice() else {
            print("Metal is not supported on this device")
            return
        }

        self.mtkView = MTKView(frame: self.frame, device: defaultDevice)

        guard let newRenderer = Renderer(metalKitView: mtkView) else {
            print("Renderer cannot be initialized")
            return
        }
        self.view = self.mtkView

        renderer = newRenderer

        renderer.mtkView(mtkView, drawableSizeWillChange: mtkView.drawableSize)

        mtkView.delegate = renderer
    }
    
    override func mouseDragged(with event: NSEvent) {
        renderer.rotationX += Float(event.deltaX) / 1000.0
    }
    
    override func mouseUp(with event: NSEvent){
        guard let mtkView = self.mtkView else { return }
        let windowPoint = event.locationInWindow
        let viewPoint = mtkView.convert(windowPoint, from: nil)

        let scale = mtkView.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1.0
        let pixelPoint = CGPoint(x: viewPoint.x * scale, y: viewPoint.y * scale)

        let size = mtkView.drawableSize

        // Convert CGFloat to Float explicitly for SIMD Float math
        let width = Float(size.width)
        let height = Float(size.height)
        let px = Float(pixelPoint.x)
        let py = Float(pixelPoint.y)

        renderer.AABBintersect(px: px, py: py)
    }
}
