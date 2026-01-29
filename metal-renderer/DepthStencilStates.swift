//
//  DepthStencilStates.swift
//  metal-renderer
//
//  Created by Jared Lueck on 2026-01-26.
//

import Metal

struct DepthStencilStates {
    
    lazy var shadowGeneration = makeDepthStencilState(label: "Shadow Generation Stage") { descriptor in
        descriptor.isDepthWriteEnabled = true
        descriptor.depthCompareFunction = .lessEqual
    }
    
    lazy var forwardPass = makeDepthStencilState(label: "Forward Pass") { descriptor in
        descriptor.isDepthWriteEnabled = true
        descriptor.depthCompareFunction = .lessEqual
    }

    let device: MTLDevice
    
    init(device: MTLDevice) {
        self.device = device
    }
    
    func makeDepthStencilState(label: String,
                               block: (MTLDepthStencilDescriptor) -> Void) -> MTLDepthStencilState {
        let descriptor = MTLDepthStencilDescriptor()
        block(descriptor)
        descriptor.label = label
        if let depthStencilState = device.makeDepthStencilState(descriptor: descriptor) {
            return depthStencilState
        } else {
            fatalError("Failed to create depth-stencil state.")
        }
    }
}
